// Package devapp holds the dev-App mode rules (#418 design, section 2): how a tree is
// recognised as dev-App, the four per-repo surfaces (the token mount name, the FROM, the
// extras and appPort), and the exact comparison of everything else against the template.
package devapp

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

// Markers are the raw byte strings that make a tree dev-App: the image name, the host broker's
// directory and the token mount's target. A base or default-branch tip is read for them
// leniently, as raw bytes, so a base whose syntax line was retired or whose JSON no longer
// parses never wedges the PR that repairs it.
var Markers = []string{"devcontainer-devapp", "glunk-identity", "/run/wow"}

// HasMarker reports whether b holds any of Markers.
func HasMarker(b []byte) bool {
	for _, m := range Markers {
		if bytes.Contains(b, []byte(m)) {
			return true
		}
	}
	return false
}

const (
	dockerfileRel = ".devcontainer/Dockerfile"
	devcontRel    = ".devcontainer/devcontainer.json"
	maxLenient    = 4 << 20
	// ListedRel is the sentinel fetch-consumer.sh --mode-only writes once the commit's tree
	// listing succeeded untruncated. Without it, a missing file could be a failed read.
	ListedRel = "_listed"
)

// Lenient is what a lenient read of a base or tip tree found.
type Lenient struct {
	DevApp bool
	// FromMinor is the MINOR of the first FROM line naming one of this repo's images, and
	// HasFrom whether there was one.
	FromMajor, FromMinor int
	HasFrom              bool
}

// lenientFrom finds the first FROM of one of this repo's images, without parsing the file.
var lenientFrom = regexp.MustCompile(`(?im)^[ \t]*FROM[ \t]+ghcr\.io/603-identity/devcontainer-[a-z-]+:([0-9]{1,9})\.([0-9]{1,9})@`)

// ReadLenient reads dir/.devcontainer/{Dockerfile,devcontainer.json} as raw bytes. dir is
// what fetch-consumer.sh --mode-only wrote: it writes a file only when the commit's tree
// listing (untruncated, or the fetch fails) has it as a regular file, and ListedRel once the
// listing succeeded, so with ListedRel present a missing file means absent from the commit.
// A missing ListedRel, or any I/O error, is an error, never "absent".
func ReadLenient(dir string) (Lenient, error) {
	var l Lenient
	if fi, err := os.Lstat(filepath.Join(dir, ListedRel)); err != nil || !fi.Mode().IsRegular() {
		return Lenient{}, fmt.Errorf("%s holds no %s sentinel: not a completed fetch-consumer.sh --mode-only read", dir, ListedRel)
	}
	for _, rel := range []string{dockerfileRel, devcontRel} {
		b, err := readCapped(filepath.Join(dir, filepath.FromSlash(rel)))
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return Lenient{}, err
		}
		if HasMarker(b) {
			l.DevApp = true
		}
		if rel == dockerfileRel {
			if m := lenientFrom.FindSubmatch(b); m != nil {
				l.FromMajor, _ = strconv.Atoi(string(m[1]))
				l.FromMinor, _ = strconv.Atoi(string(m[2]))
				l.HasFrom = true
			}
		}
	}
	return l, nil
}

func readCapped(p string) ([]byte, error) {
	f, err := os.Open(p)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(io.LimitReader(f, maxLenient))
}

// segment is one half of OWNER/REPO, as the host broker names its directories.
var segment = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// windowsReserved are the device names Windows refuses as a file or directory name, with or
// without an extension.
var windowsReserved = regexp.MustCompile(`(?i)^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$`)

// ValidateRepo checks the repository name the token mount must carry (github.repository, from
// the workflow, never a workflow input). An empty value is an error; a name the host broker
// cannot use as a Windows directory pair is a failure.
func ValidateRepo(repo string) error {
	if repo == "" {
		return errors.New("the repository name is empty")
	}
	owner, name, ok := strings.Cut(repo, "/")
	if !ok || strings.Contains(name, "/") {
		return check.Failf("repository %q is not OWNER/REPO", repo)
	}
	for _, s := range []string{owner, name} {
		switch {
		case !segment.MatchString(s):
			return check.Failf("repository segment %q has a character outside [A-Za-z0-9._-]", s)
		case s == "." || s == "..":
			return check.Failf("repository segment %q is a relative path", s)
		case strings.HasSuffix(s, "."):
			return check.Failf("repository segment %q ends in a dot, which Windows drops", s)
		case windowsReserved.MatchString(s):
			return check.Failf("repository segment %q is a reserved Windows name", s)
		}
	}
	return nil
}
