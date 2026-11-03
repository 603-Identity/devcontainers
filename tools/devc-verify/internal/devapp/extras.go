package devapp

import (
	"maps"
	"net/url"
	"path"
	"regexp"
	"slices"
	"strings"

	"github.com/moby/buildkit/frontend/dockerfile/instructions"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/dockerfile"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

// BaseWorkdir is the WORKDIR every shared image sets (images/base/Dockerfile), which a relative
// path in the extras resolves against until a WORKDIR of their own.
const BaseWorkdir = "/workspace"

// FinalUser is the instruction a dev-App Dockerfile must end with. Everything between FROM and
// it is the repo's extras (surface 3).
const FinalUser = "1000:1000"

// IdentityPaths are where the flavour's identity layer lives: the token directory, the
// credential helper and the real gh, the gh wrapper, the system git config that names the
// helper, the image-owned scripts and the unsigned marker, and the verified claude with its
// managed settings. /var/run is /run on Debian.
var IdentityPaths = []string{
	"/run/wow", "/var/run/wow",
	"/usr/local/libexec",
	"/usr/local/bin/gh", "/usr/local/bin/claude",
	"/etc/gitconfig", "/etc/claude-code",
	"/usr/local/share/devc",
}

// identityRE matches an identity path as a whole path component: `/usr/local/bin/gh` and
// `/usr/local/bin/gh/x`, never `/usr/local/bin/ghq`.
var identityRE = func() *regexp.Regexp {
	alts := make([]string, len(IdentityPaths))
	for i, p := range IdentityPaths {
		alts[i] = regexp.QuoteMeta(p)
	}
	return regexp.MustCompile(`(^|[^A-Za-z0-9._-])(` + strings.Join(alts, "|") + `)([^A-Za-z0-9._-]|$)`)
}()

// systemGitRE is a `git config --system` (it writes /etc/gitconfig without naming it).
var systemGitRE = regexp.MustCompile(`\bgit\b[^;&|\n]*\bconfig\b[^;&|\n]*--system\b`)

// forbiddenEnv is matched without regard to letter case. GIT_ is a prefix.
var forbiddenEnv = []string{"ANTHROPIC_BASE_URL", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"}

// CheckDockerfile applies the extras rules to a dev-App Dockerfile that passed
// dockerfile.Parse. files holds what fetch-consumer.sh fetched from .devcontainer/, by path
// relative to it. The filter catches accidents, not attacks: a repo's extras can run as root
// (after a USER 0 of their own) at build time and undo anything below; the approval rule and
// the human review hold that.
func CheckDockerfile(p dockerfile.Parsed, files map[string][]byte) error {
	if !p.Ref.DevApp() {
		return check.Failf("FROM %q is not a dev-App image", p.Ref.Raw)
	}
	cmds := p.Commands
	if n := len(cmds); n == 0 || !isFinalUser(cmds[n-1]) {
		return check.Failf("a dev-App Dockerfile must end with `USER %s`", FinalUser)
	}
	workdir := BaseWorkdir
	for _, c := range cmds[:len(cmds)-1] {
		switch c := c.(type) {
		case *instructions.EnvCommand:
			for _, kv := range c.Env {
				if err := checkEnvName(kv.Key); err != nil {
					return err
				}
			}
		case *instructions.RunCommand:
			text := c.String()
			for _, f := range c.Files {
				text += "\n" + f.Data
			}
			if err := checkText("RUN", text); err != nil {
				return err
			}
			// A bind mount of the build context runs a context file without copying it. The
			// parse path reads mounts with a nil expander, which skips every key but `from`, so
			// re-read them with a literal one first; a source holding `$` is then refused below.
			if err := c.Expand(func(w string) (string, error) { return w, nil }); err != nil {
				return check.Failf("RUN --mount does not parse with literal values (dev-App extras take no variables in mount options): %q", err.Error())
			}
			for _, m := range instructions.GetMounts(c) {
				if m.Type != instructions.MountTypeBind {
					continue
				}
				src := m.Source
				if src == "" {
					src = "."
				}
				if _, err := sourceFiles("RUN --mount", src, files); err != nil {
					return err
				}
			}
		case *instructions.WorkdirCommand:
			w, err := resolve(workdir, c.Path)
			if err != nil {
				return err
			}
			if err := checkPath("WORKDIR", w); err != nil {
				return err
			}
			workdir = w
		case *instructions.VolumeCommand:
			for _, v := range c.Volumes {
				w, err := resolve(workdir, v)
				if err != nil {
					return err
				}
				if err := checkPath("VOLUME", w); err != nil {
					return err
				}
			}
		case *instructions.CopyCommand:
			if err := checkCopy("COPY", c.SourcesAndDest, workdir, files, c.Parents); err != nil {
				return err
			}
		case *instructions.AddCommand:
			// A local ADD unpacks an archive, whose paths no check here can see: use COPY.
			for _, src := range c.SourcePaths {
				if !isRemote(src) {
					return check.Failf("ADD of the local %q is not allowed in dev-App extras: use COPY (ADD unpacks archives)", src)
				}
			}
			if err := checkCopy("ADD", c.SourcesAndDest, workdir, files, false); err != nil {
				return err
			}
		}
	}
	return nil
}

// CheckMinor is the FROM surface's one cross-commit rule: the head may not build from an
// older image than the base did. MINOR is the build run's number, so it orders images across
// names too.
func CheckMinor(head image.Ref, base Lenient) error {
	if !base.HasFrom {
		return nil
	}
	if head.Major < base.FromMajor || (head.Major == base.FromMajor && head.Minor < base.FromMinor) {
		return check.Failf("FROM %q is older than the base's %d.%d", head.Raw, base.FromMajor, base.FromMinor)
	}
	return nil
}

func isFinalUser(c instructions.Command) bool {
	u, ok := c.(*instructions.UserCommand)
	return ok && u.User == FinalUser
}

func checkEnvName(k string) error {
	if strings.Contains(k, "$") {
		return check.Failf("ENV key %q contains $", k)
	}
	if strings.HasPrefix(strings.ToUpper(k), "GIT_") || slices.ContainsFunc(forbiddenEnv, func(f string) bool { return strings.EqualFold(f, k) }) {
		return check.Failf("ENV %q is not allowed in dev-App extras: it would redirect git, the proxy or claude", k)
	}
	return nil
}

// checkText rejects text (a RUN line, a heredoc, a copied file) that names an identity path or
// writes the system git config.
func checkText(what, text string) error {
	if m := identityRE.FindStringSubmatch(text); m != nil {
		return check.Failf("%s names %q, part of the dev-App identity layer", what, m[2])
	}
	if systemGitRE.MatchString(text) {
		return check.Failf("%s runs `git config --system`, which writes the identity layer's /etc/gitconfig", what)
	}
	return nil
}

func checkPath(what, p string) error {
	if identityRE.MatchString(p) {
		return check.Failf("%s %q writes into the dev-App identity layer", what, p)
	}
	return nil
}

// resolve turns a Dockerfile path into an absolute one against the current WORKDIR. A path the
// build would expand (`$`) cannot be resolved here, so it is refused.
func resolve(workdir, p string) (string, error) {
	if strings.Contains(p, "$") {
		return "", check.Failf("path %q holds a variable; dev-App extras use literal paths", p)
	}
	if !path.IsAbs(p) {
		p = path.Join(workdir, p)
	}
	return path.Clean(p), nil
}

// checkCopy checks one COPY or ADD: its destination and every path a copied file can land on
// (into the destination as a directory, by its base name or its path under a copied directory,
// or by its whole path with --parents), its inline (heredoc) sources, and that each source is a
// regular file (or a directory of them) fetched from .devcontainer/, whose contents then pass
// checkText too. A URL (ADD only; CheckDockerfile refuses a local ADD) fetches nothing from the
// repo, so only where it lands is checked: the destination, and the destination joined with
// the URL's last path segment.
func checkCopy(what string, sd instructions.SourcesAndDest, workdir string, files map[string][]byte, parents bool) error {
	d, err := resolve(workdir, sd.DestPath)
	if err != nil {
		return err
	}
	targets := []string{d}
	for _, sc := range sd.SourceContents {
		if err := checkText(what+" heredoc", sc.Data); err != nil {
			return err
		}
		targets = append(targets, path.Join(d, sc.Path))
	}
	for _, src := range sd.SourcePaths {
		if what == "ADD" && isRemote(src) {
			if u, err := url.Parse(src); err == nil && path.Base(u.Path) != "/" && path.Base(u.Path) != "." {
				targets = append(targets, path.Join(d, path.Base(u.Path)))
			}
			continue
		}
		// With --parents, a `/./` in the source pivots where the file lands, which the targets
		// below do not model: refuse it.
		if parents && (strings.Contains("/"+src+"/", "/./")) {
			return check.Failf("%s --parents source %q holds a . segment (a ./ pivot, or a leading ./); dev-App extras copy without one", what, src)
		}
		subs, err := sourceFiles(what+" source", src, files)
		if err != nil {
			return err
		}
		for _, sub := range subs {
			targets = append(targets, path.Join(d, sub[0]))
			if parents {
				targets = append(targets, path.Join(d, sub[1]))
			}
		}
	}
	for _, t := range targets {
		if err := checkPath(what+" destination", t); err != nil {
			return err
		}
	}
	return nil
}

func isRemote(src string) bool { return strings.Contains(src, "://") || strings.HasPrefix(src, "git@") }

// sourceFiles resolves one context source to the fetched files it names, text-checking each.
// For each it returns {its path below the source (its base name for a file), its whole path}.
func sourceFiles(what, src string, files map[string][]byte) ([][2]string, error) {
	if strings.ContainsAny(src, "*?[$\\") {
		return nil, check.Failf("%s %q is not a literal path", what, src)
	}
	rel := strings.TrimPrefix(path.Clean("/"+src), "/")
	var out [][2]string
	for _, name := range slices.Sorted(maps.Keys(files)) {
		var sub string
		switch {
		case rel == "":
			sub = name
		case name == rel:
			sub = path.Base(name)
		case strings.HasPrefix(name, rel+"/"):
			sub = strings.TrimPrefix(name, rel+"/")
		default:
			continue
		}
		out = append(out, [2]string{sub, name})
		// The two files every repo has are checked by their own rules, and their comments
		// may name the identity paths.
		if name == "Dockerfile" || name == "devcontainer.json" {
			continue
		}
		if err := checkText(what+" "+name, string(files[name])); err != nil {
			return nil, err
		}
	}
	if len(out) == 0 {
		return nil, check.Failf("%s %q is not a regular file in .devcontainer/", what, src)
	}
	return out, nil
}
