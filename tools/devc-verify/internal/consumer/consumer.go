// Package consumer applies the offline file rules to a consumer checkout (or to the
// directory the gate fetched the head SHA's files into).
package consumer

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/devcontainer"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/dockerfile"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

const (
	dockerfileRel = ".devcontainer/Dockerfile"
	devcontRel    = ".devcontainer/devcontainer.json"
	maxFile       = 1 << 20
)

// Files checks dir/.devcontainer/Dockerfile and dir/.devcontainer/devcontainer.json and
// that no other devcontainer.json exists anywhere under dir. It returns the base image.
func Files(dir string) (image.Ref, error) {
	if err := noOtherDevcontainerJSON(dir); err != nil {
		return image.Ref{}, err
	}
	df, err := readRegular(dir, dockerfileRel)
	if err != nil {
		return image.Ref{}, err
	}
	dj, err := readRegular(dir, devcontRel)
	if err != nil {
		return image.Ref{}, err
	}
	if err := devcontainer.Check(dj); err != nil {
		return image.Ref{}, err
	}
	return dockerfile.Check(df)
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
