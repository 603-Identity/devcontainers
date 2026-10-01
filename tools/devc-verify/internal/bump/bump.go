// Package bump decides whether a compare-API patch of .devcontainer/Dockerfile is exactly
// one FROM line replaced by a same-image, same-MAJOR, greater-MINOR FROM line.
package bump

import (
	"regexp"
	"strings"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

var hunkRE = regexp.MustCompile(`^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@`)

// Predicate returns nil when patch changes exactly one line, a base image bump from
// the old FROM to newBase (the image `files` found at the head SHA), and a *check.Failure
// otherwise. Unchanged context lines, hunk headers and the "\ No newline" marker are
// ignored; any other changed line is a failure.
func Predicate(patch string, newBase image.Ref) error {
	var removed, added []string
	lines := strings.Split(patch, "\n")
	for i, l := range lines {
		switch {
		case l == "" && i == len(lines)-1:
			// final newline
		case hunkRE.MatchString(l):
		case strings.HasPrefix(l, `\ No newline`):
		case strings.HasPrefix(l, " "), l == "":
			// unchanged context
		case l[0] == '-':
			removed = append(removed, l[1:])
		case l[0] == '+':
			added = append(added, l[1:])
		default:
			return check.Failf("patch line %q is not a diff line", l)
		}
	}
	if len(removed) != 1 || len(added) != 1 {
		return check.Failf("patch changes %d lines and adds %d; exactly 1 and 1 are required", len(removed), len(added))
	}
	oldRef, err := parseFrom(removed[0])
	if err != nil {
		return err
	}
	newRef, err := parseFrom(added[0])
	if err != nil {
		return err
	}
	if newRef.Raw != newBase.Raw {
		return check.Failf("patch adds %q but the head Dockerfile builds from %q", newRef.Raw, newBase.Raw)
	}
	switch {
	case oldRef.Name != newRef.Name:
		return check.Failf("image changed from %q to %q", oldRef.Name, newRef.Name)
	case oldRef.Major != newRef.Major:
		return check.Failf("MAJOR changed from %d to %d", oldRef.Major, newRef.Major)
	case newRef.Minor <= oldRef.Minor:
		return check.Failf("MINOR %d is not greater than %d", newRef.Minor, oldRef.Minor)
	}
	return nil
}

// parseFrom strips the FROM keyword. `FROM --platform=...` and `FROM x AS name` fall out
// because the remainder then fails the base regex.
func parseFrom(line string) (image.Ref, error) {
	rest, ok := strings.CutPrefix(line, "FROM ")
	if !ok {
		return image.Ref{}, check.Failf("changed line %q is not a FROM line", line)
	}
	return image.Parse(rest)
}
