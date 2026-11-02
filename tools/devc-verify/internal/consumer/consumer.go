// Package consumer applies the offline file rules to a consumer checkout (or to the
// directory the gate fetched the head SHA's files into).
package consumer

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/devapp"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/devcontainer"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/dockerfile"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

const (
	dockerfileRel = ".devcontainer/Dockerfile"
	devcontRel    = ".devcontainer/devcontainer.json"
	maxFile       = 1 << 20
	// irregularRel is fetch-consumer.sh's marker: the head's .devcontainer/ holds an entry it
	// would not fetch (a symlink, a submodule, an unsafe name, or too many files).
	irregularRel = "_irregular/.devcontainer"
	maxExtras    = 64 // fetch-consumer.sh's MAX_EXTRAS: files besides the two canonical ones
)

// Options says where a check reads from. Dir is required; the rest are needed in dev-App mode.
type Options struct {
	Dir string // the head's files, as fetch-consumer.sh wrote them
	// BaseDir and TipDir are the PR base's and the default branch tip's files, as
	// fetch-consumer.sh --mode-only wrote them; "" is not read.
	BaseDir, TipDir string
	TemplateDir     string // a tree holding the template's .devcontainer/devcontainer.json
	Snapshot        []byte // the previous release's template devcontainer.json; nil if none
	Repo            string // github.repository
}

// Result is what a passing check found.
type Result struct {
	Ref    image.Ref
	DevApp bool
}

// Files checks dir/.devcontainer/Dockerfile and dir/.devcontainer/devcontainer.json and
// that no other devcontainer.json exists anywhere under dir, in the mode the head alone
// implies. It returns the base image.
func Files(dir string) (image.Ref, error) {
	r, err := Check(Options{Dir: dir})
	return r.Ref, err
}

// HeadImage parses only the head Dockerfile, for `decide`, which refuses a dev-App image
// before anything that could error.
func HeadImage(dir string) (image.Ref, error) {
	df, err := readRegular(dir, dockerfileRel)
	if err != nil {
		return image.Ref{}, err
	}
	return dockerfile.Check(df)
}

// Check applies the offline rules. The mode is dev-App when the head, the base or the tip is
// dev-App; in dev-App mode the head must itself be dev-App, with its FROM and its token mount
// agreeing, and is then compared with the template. Otherwise plain mode's allowlist applies.
func Check(o Options) (Result, error) {
	if err := noOtherDevcontainerJSON(o.Dir); err != nil {
		return Result{}, err
	}
	df, err := readRegular(o.Dir, dockerfileRel)
	if err != nil {
		return Result{}, err
	}
	dj, err := readRegular(o.Dir, devcontRel)
	if err != nil {
		return Result{}, err
	}
	if err := devcontainer.Check(dj); err != nil {
		return Result{}, err
	}
	parsed, err := dockerfile.Parse(df)
	if err != nil {
		return Result{}, err
	}
	ref := parsed.Ref

	// The head's files are read for the markers the same way as a base or a tip (raw bytes,
	// comments included), so a head that passes as plain can never make the next PR's base
	// dev-App. A dev-App FROM always carries one; a plain FROM must have none in either file.
	if !ref.DevApp() && (devapp.HasMarker(df) || devapp.HasMarker(dj)) {
		return Result{}, check.Failf("FROM %q is not a dev-App image, but its Dockerfile or devcontainer.json names a dev-App marker (%q); a plain repo carries none, comments included", ref.Raw, devapp.Markers)
	}

	var base devapp.Lenient
	mode, why := ref.DevApp(), "the head"
	for _, side := range []struct{ dir, name string }{{o.BaseDir, "the PR base"}, {o.TipDir, "the default branch"}} {
		if side.dir == "" {
			continue
		}
		l, err := devapp.ReadLenient(side.dir)
		if err != nil {
			return Result{}, err
		}
		if side.dir == o.BaseDir {
			base = l
		}
		if l.DevApp && !mode {
			mode, why = true, side.name
		}
	}

	if !mode {
		if err := devcontainer.CheckPlain(dj); err != nil {
			return Result{}, err
		}
		return Result{Ref: ref}, nil
	}
	if !ref.DevApp() {
		return Result{}, check.Failf("%s is dev-App, so the head must be too: FROM %q is not a dev-App image", why, ref.Raw)
	}
	if o.Repo == "" || o.TemplateDir == "" {
		return Result{}, errors.New("dev-App mode needs --repo and --template-dir")
	}
	if err := devapp.CheckMinor(ref, base); err != nil {
		return Result{}, err
	}
	files, err := extras(o.Dir)
	if err != nil {
		return Result{}, err
	}
	if err := devapp.CheckDockerfile(parsed, files); err != nil {
		return Result{}, err
	}
	tmpl, err := os.ReadFile(filepath.Join(o.TemplateDir, filepath.FromSlash(devcontRel)))
	if err != nil {
		return Result{}, fmt.Errorf("reading the template: %w", err)
	}
	cands := []devapp.Candidate{
		{Name: "the template at this pin", Data: tmpl},
		{Name: "the previous release's snapshot", Data: o.Snapshot},
	}
	if err := devapp.CompareJSON(dj, o.Repo, cands); err != nil {
		return Result{}, err
	}
	return Result{Ref: ref, DevApp: true}, nil
}

// extras reads every file under dir/.devcontainer/, by path relative to it. Each must be a
// regular file of bounded size; fetch-consumer.sh wrote them, and marked anything it would
// not fetch.
func extras(dir string) (map[string][]byte, error) {
	if _, err := os.Lstat(filepath.Join(dir, filepath.FromSlash(irregularRel))); err == nil {
		return nil, check.Failf(".devcontainer/ holds an entry fetch-consumer.sh would not fetch (a symlink, a submodule, an unusual name, a file over 1 MiB, or more than %d files)", maxExtras)
	} else if !errors.Is(err, fs.ErrNotExist) {
		return nil, err
	}
	root := filepath.Join(dir, ".devcontainer")
	files := map[string][]byte{}
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(dir, p)
		if err != nil {
			return err
		}
		b, err := readRegular(dir, filepath.ToSlash(rel))
		if err != nil {
			return err
		}
		if len(files) == maxExtras+2 {
			return check.Failf(".devcontainer/ holds more than %d files besides Dockerfile and devcontainer.json", maxExtras)
		}
		r, _ := filepath.Rel(root, p)
		files[filepath.ToSlash(r)] = b
		return nil
	})
	return files, err
}

// readRegular reads a regular file (never a symlink) of bounded size. A missing or
// irregular file is a rule violation; any other I/O error is an error.
func readRegular(dir, rel string) ([]byte, error) {
	p := filepath.Join(dir, filepath.FromSlash(rel))
	fi, err := os.Lstat(p)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, check.Failf("%s does not exist", rel)
	}
	if err != nil {
		return nil, err
	}
	if !fi.Mode().IsRegular() {
		return nil, check.Failf("%s is not a regular file", rel)
	}
	if fi.Size() > maxFile {
		return nil, check.Failf("%s is larger than %d bytes", rel, maxFile)
	}
	return os.ReadFile(p)
}

// noOtherDevcontainerJSON walks dir (skipping dir/.git) and rejects any entry named
// devcontainer.json or .devcontainer.json other than the one canonical path. The name
// match is case-insensitive: stricter than the spec, and harmless.
func noOtherDevcontainerJSON(dir string) error {
	gitDir := filepath.Join(dir, ".git")
	return filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if p == gitDir {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if !strings.EqualFold(name, "devcontainer.json") && !strings.EqualFold(name, ".devcontainer.json") {
			return nil
		}
		rel, err := filepath.Rel(dir, p)
		if err != nil {
			return err
		}
		if filepath.ToSlash(rel) != devcontRel {
			return check.Failf("another devcontainer.json exists at %q", filepath.ToSlash(rel))
		}
		return nil
	})
}
