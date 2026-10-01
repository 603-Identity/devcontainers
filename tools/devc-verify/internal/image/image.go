// Package image parses the one image reference form the gate accepts.
package image

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

// BasePattern is the spec's base-image regex, verbatim.
const BasePattern = `^ghcr\.io/603-identity/devcontainer-(base|tofu|node):([0-9]+)\.([0-9]+)@sha256:[0-9a-f]{64}$`

var baseRE = regexp.MustCompile(BasePattern)

// Ref is a parsed `repo:MAJOR.MINOR@sha256:digest` reference.
type Ref struct {
	Name   string // base, tofu or node
	Major  int
	Minor  int
	Digest string // "sha256:<64 hex>"
	Raw    string // the exact input, which matched BasePattern
}

// Repo is the image repository without tag or digest.
func (r Ref) Repo() string { return "ghcr.io/603-identity/devcontainer-" + r.Name }

// Parse accepts s only if it matches BasePattern exactly. Numbers must be canonical
// decimals that fit an int (no leading zeros): tag "4.0125" never exists in the registry.
func Parse(s string) (Ref, error) {
	m := baseRE.FindStringSubmatch(s)
	if m == nil {
		return Ref{}, check.Failf("image %q does not match the allowed pattern", s)
	}
	major, err := number(m[2])
	if err != nil {
		return Ref{}, check.Failf("image %q: MAJOR is not a canonical number", s)
	}
	minor, err := number(m[3])
	if err != nil {
		return Ref{}, check.Failf("image %q: MINOR is not a canonical number", s)
	}
	return Ref{
		Name:   m[1],
		Major:  major,
		Minor:  minor,
		Digest: s[strings.IndexByte(s, '@')+1:],
		Raw:    s,
	}, nil
}

func number(s string) (int, error) {
	if len(s) > 1 && s[0] == '0' {
		return 0, strconv.ErrSyntax
	}
	return strconv.Atoi(s)
}
