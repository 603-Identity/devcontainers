// Package dockerfile checks a consumer's .devcontainer/Dockerfile with BuildKit's own
// parser, never with line matching: a line-based check can be bypassed by line
// continuations, an escape directive, or an ARG that swallows the FROM (spike finding L4).
package dockerfile

import (
	"bytes"
	"strings"

	"github.com/moby/buildkit/frontend/dockerfile/instructions"
	"github.com/moby/buildkit/frontend/dockerfile/parser"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

// CurrentSyntax is the newest allowed `# syntax=` value. A test asserts it equals the first
// line of images/*/Dockerfile, and that template/.devcontainer/Dockerfile's first line is one of
// AllowedSyntax. tools/check-self-pins.sh then asserts the template's line is allowed by the
// verifier at the release the template pins, so a template bump without a tool release fails
// CI (#125). That script reads both constants with sed: keep each one a single
// `const X = "..."` line (PreviousSyntax may also be `= CurrentSyntax`).
const CurrentSyntax = "docker/dockerfile:1.28@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b"

// PreviousSyntax is the value the template carried before CurrentSyntax (dockerfile 1.27.1, the
// release cut from BuildKit v0.33.1), kept so a consumer one bump behind still verifies.
// At the next template bump, set it to the value being retired.
//
// A consumer on PreviousSyntax is parsed by the vendored (newer) BuildKit but built by the
// older frontend, so the two must agree on what Check reads (#429). That holds only while the
// vendored delta between the two releases leaves the code Check runs unchanged:
// frontend/dockerfile/{parser,instructions} and the shell, command and linter packages they
// import. For 1.27 -> 1.28 (v0.33.1 to v0.34.1) the one non-test change there was shell/lex.go,
// the shell lexer. Check never expands a variable with it (no Expand on the parse path; `$` in
// the base, `COPY --from` and `RUN --mount from=` are refused), but BuildKit's parser does lex
// heredoc words with it, on any RUN, COPY or ADD whose logical line (continuations joined)
// holds "<<", and the 1.28 lexer no longer doubles a backslash inside double quotes there. So
// Parse refuses "<<" in a Dockerfile on PreviousSyntax, in its bytes and on every parsed
// instruction's joined line (a "<" split from a "<" by a line continuation): without one the
// lexer is never reached, and both releases read the file the same. A bump runs the check in devc-verify README.md, "Releasing and maintenance"; a change
// that cannot be fenced off this way sets PreviousSyntax = CurrentSyntax instead (fail closed).
const PreviousSyntax = "docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e"

// AllowedSyntax is the allowlist of `# syntax=` values.
var AllowedSyntax = [2]string{CurrentSyntax, PreviousSyntax}

// maxSize bounds what the parser is asked to read.
const maxSize = 1 << 20

// Parsed is a Dockerfile that passed the rules: its base image and the instructions after
// FROM, unexpanded and in order. The dev-App rules (internal/devapp) read the instructions.
type Parsed struct {
	Ref      image.Ref
	Commands []instructions.Command
}

// Check applies the Dockerfile rules and returns the parsed base image. A rule violation,
// including a file BuildKit cannot parse, is a *check.Failure.
func Check(data []byte) (image.Ref, error) {
	p, err := Parse(data)
	return p.Ref, err
}

// Parse is Check that also returns the stage's instructions.
func Parse(data []byte) (Parsed, error) {
	if len(data) == 0 || len(data) > maxSize {
		return Parsed{}, check.Failf("Dockerfile size %d is outside 1..%d bytes", len(data), maxSize)
	}
	for i, b := range data {
		if b >= 0x80 || b == '\r' || b == 0 {
			return Parsed{}, check.Failf("Dockerfile byte %#02x at offset %d: only ASCII without CR or NUL is allowed", b, i)
		}
	}

	syntax, err := checkDirectives(data)
	if err != nil {
		return Parsed{}, err
	}
	// Under PreviousSyntax the build's frontend lexes heredoc words with the older shell lexer,
	// which differs from the vendored one (#429, see PreviousSyntax). BuildKit's parser reaches
	// the lexer only for an instruction whose logical line (continuations joined, comment lines
	// inside it dropped) holds "<<", so a file with none is read the same by both. The check
	// runs on the raw bytes and again on every parsed instruction's joined line, which catches
	// a "<" "\" newline "<" split. It keys on the parsed directive value, never on line 1's
	// bytes: BuildKit accepts other spellings of that line (no space, `SYNTAX`, spaces around `=`).
	fenced := PreviousSyntax != CurrentSyntax && syntax == PreviousSyntax
	heredocErr := check.Failf("a Dockerfile on the previous syntax (%q) may not contain \"<<\" (a heredoc), in a line or across a line continuation; move it to %q first", PreviousSyntax, CurrentSyntax)
	if fenced && bytes.Contains(data, []byte("<<")) {
		return Parsed{}, heredocErr
	}

	res, err := parser.Parse(bytes.NewReader(data))
	if err != nil {
		return Parsed{}, check.Failf("Dockerfile does not parse: %q", err.Error())
	}
	if res.EscapeToken != '\\' {
		return Parsed{}, check.Failf("Dockerfile escape token is %q, not a backslash", string(res.EscapeToken))
	}
	if fenced {
		for _, n := range res.AST.Children {
			if len(n.Heredocs) > 0 || strings.Contains(n.Original, "<<") {
				return Parsed{}, heredocErr
			}
		}
	}
	stages, metaArgs, err := instructions.Parse(res.AST, nil)
	if err != nil {
		return Parsed{}, check.Failf("Dockerfile instructions do not parse: %q", err.Error())
	}
	if len(metaArgs) != 0 {
		return Parsed{}, check.Failf("Dockerfile has %d ARG before FROM; none is allowed", len(metaArgs))
	}
	if len(stages) != 1 {
		return Parsed{}, check.Failf("Dockerfile has %d stages; exactly 1 is required", len(stages))
	}
	st := stages[0]
	if st.Name != "" {
		return Parsed{}, check.Failf("FROM names its stage %q; that is not allowed", st.Name)
	}
	if st.Platform != "" {
		return Parsed{}, check.Failf("FROM sets a platform %q; that is not allowed", st.Platform)
	}
	if strings.Contains(st.BaseName, "$") {
		return Parsed{}, check.Failf("base %q contains $", st.BaseName)
	}
	ref, err := image.Parse(st.BaseName)
	if err != nil {
		return Parsed{}, err
	}

	for _, c := range st.Commands {
		switch c := c.(type) {
		case *instructions.CopyCommand:
			if c.From != "" {
				return Parsed{}, check.Failf("COPY --from=%q is not allowed", c.From)
			}
		case *instructions.OnbuildCommand:
			return Parsed{}, check.Failf("ONBUILD is not allowed")
		case *instructions.RunCommand:
			for _, m := range instructions.GetMounts(c) {
				if m.From != "" {
					return Parsed{}, check.Failf("RUN --mount from=%q is not allowed", m.From)
				}
			}
		case *instructions.LabelCommand:
			if err := checkLabels(c); err != nil {
				return Parsed{}, err
			}
		}
	}
	return Parsed{Ref: ref, Commands: st.Commands}, nil
}

// metadataLabel is the label the devcontainer CLI merges into the container's configuration
// (mounts, lifecycle commands, runArgs and more), so a Dockerfile could otherwise carry what
// devcontainer.json may not. It is rejected in both modes (#418).
const metadataLabel = "devcontainer.metadata"

// checkLabels rejects the metadata label in any spelling the build could turn into it. Keys
// are read unexpanded, so quotes and backslashes are dropped before the comparison, which
// ignores letter case; a key holding `$` is rejected outright, since an ARG could expand it
// into the label.
func checkLabels(c *instructions.LabelCommand) error {
	for _, kv := range c.Labels {
		if strings.Contains(kv.Key, "$") {
			return check.Failf("LABEL key %q contains $", kv.Key)
		}
		k := strings.NewReplacer(`"`, "", `'`, "", `\`, "").Replace(kv.Key)
		if strings.EqualFold(k, metadataLabel) {
			return check.Failf("LABEL %q is not allowed: the devcontainer CLI merges it into the container's configuration", kv.Key)
		}
	}
	return nil
}

// checkDirectives requires exactly one parser directive, `syntax`, with an allowlisted
// value. The directives come from BuildKit's directive parser; BuildKit's own syntax
// detection (the one that selects the frontend) must agree. It returns the value.
func checkDirectives(data []byte) (string, error) {
	var dp parser.DirectiveParser
	ds, err := dp.ParseAll(data)
	if err != nil {
		return "", check.Failf("Dockerfile directives do not parse: %q", err.Error())
	}
	if len(ds) != 1 || ds[0].Name != "syntax" {
		names := make([]string, len(ds))
		for i, d := range ds {
			names[i] = d.Name
		}
		return "", check.Failf("Dockerfile must carry exactly one parser directive, syntax; found %q", names)
	}
	val := ds[0].Value
	if val != AllowedSyntax[0] && val != AllowedSyntax[1] {
		return "", check.Failf("# syntax=%q is not an allowed value", val)
	}
	if _, cmdline, _, ok := parser.DetectSyntax(data); !ok || cmdline != val {
		return "", check.Failf("BuildKit's syntax detection disagrees with the directive %q", val)
	}
	return val, nil
}
