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

// CurrentSyntax is the template's current `# syntax=` value. A test asserts it equals the
// first line of template/.devcontainer/Dockerfile, so a template bump without a tool
// release fails CI.
const CurrentSyntax = "docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e"

// PreviousSyntax is the value the template carried before CurrentSyntax. No earlier PINNED
// value exists yet (before 0ab872e the template used the floating `docker/dockerfile:1`,
// which is never accepted), so it duplicates CurrentSyntax: fail closed. At the next
// template bump, set it to the value being retired.
const PreviousSyntax = CurrentSyntax

// AllowedSyntax is the allowlist of `# syntax=` values.
var AllowedSyntax = [2]string{CurrentSyntax, PreviousSyntax}

// maxSize bounds what the parser is asked to read.
const maxSize = 1 << 20

// Check applies the Dockerfile rules and returns the parsed base image. A rule violation,
// including a file BuildKit cannot parse, is a *check.Failure.
func Check(data []byte) (image.Ref, error) {
	if len(data) == 0 || len(data) > maxSize {
		return image.Ref{}, check.Failf("Dockerfile size %d is outside 1..%d bytes", len(data), maxSize)
	}
	for i, b := range data {
		if b >= 0x80 || b == '\r' || b == 0 {
			return image.Ref{}, check.Failf("Dockerfile byte %#02x at offset %d: only ASCII without CR or NUL is allowed", b, i)
		}
	}

	if err := checkDirectives(data); err != nil {
		return image.Ref{}, err
	}

	res, err := parser.Parse(bytes.NewReader(data))
	if err != nil {
		return image.Ref{}, check.Failf("Dockerfile does not parse: %q", err.Error())
	}
	if res.EscapeToken != '\\' {
		return image.Ref{}, check.Failf("Dockerfile escape token is %q, not a backslash", string(res.EscapeToken))
	}
	stages, metaArgs, err := instructions.Parse(res.AST, nil)
	if err != nil {
		return image.Ref{}, check.Failf("Dockerfile instructions do not parse: %q", err.Error())
	}
	if len(metaArgs) != 0 {
		return image.Ref{}, check.Failf("Dockerfile has %d ARG before FROM; none is allowed", len(metaArgs))
	}
	if len(stages) != 1 {
		return image.Ref{}, check.Failf("Dockerfile has %d stages; exactly 1 is required", len(stages))
	}
	st := stages[0]
	if st.Name != "" {
		return image.Ref{}, check.Failf("FROM names its stage %q; that is not allowed", st.Name)
	}
	if st.Platform != "" {
		return image.Ref{}, check.Failf("FROM sets a platform %q; that is not allowed", st.Platform)
	}
	if strings.Contains(st.BaseName, "$") {
		return image.Ref{}, check.Failf("base %q contains $", st.BaseName)
	}
	ref, err := image.Parse(st.BaseName)
	if err != nil {
		return image.Ref{}, err
	}

	for _, c := range st.Commands {
		switch c := c.(type) {
		case *instructions.CopyCommand:
			if c.From != "" {
				return image.Ref{}, check.Failf("COPY --from=%q is not allowed", c.From)
			}
		case *instructions.OnbuildCommand:
			return image.Ref{}, check.Failf("ONBUILD is not allowed")
		case *instructions.RunCommand:
			for _, m := range instructions.GetMounts(c) {
				if m.From != "" {
					return image.Ref{}, check.Failf("RUN --mount from=%q is not allowed", m.From)
				}
			}
		}
	}
	return ref, nil
}

// checkDirectives requires exactly one parser directive, `syntax`, with an allowlisted
// value. The directives come from BuildKit's directive parser; BuildKit's own syntax
// detection (the one that selects the frontend) must agree.
func checkDirectives(data []byte) error {
	var dp parser.DirectiveParser
	ds, err := dp.ParseAll(data)
	if err != nil {
		return check.Failf("Dockerfile directives do not parse: %q", err.Error())
	}
	if len(ds) != 1 || ds[0].Name != "syntax" {
		names := make([]string, len(ds))
		for i, d := range ds {
			names[i] = d.Name
		}
		return check.Failf("Dockerfile must carry exactly one parser directive, syntax; found %q", names)
	}
	val := ds[0].Value
	if val != AllowedSyntax[0] && val != AllowedSyntax[1] {
		return check.Failf("# syntax=%q is not an allowed value", val)
	}
	if _, cmdline, _, ok := parser.DetectSyntax(data); !ok || cmdline != val {
		return check.Failf("BuildKit's syntax detection disagrees with the directive %q", val)
	}
	return nil
}
