package image

import (
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

const dig = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func TestParse(t *testing.T) {
	r, err := Parse("ghcr.io/603-identity/devcontainer-node:4.144@" + dig)
	if err != nil {
		t.Fatal(err)
	}
	if r.Name != "node" || r.Major != 4 || r.Minor != 144 || r.Digest != dig || r.Repo() != "ghcr.io/603-identity/devcontainer-node" {
		t.Fatalf("unexpected parse: %+v", r)
	}
}

func TestParseRejects(t *testing.T) {
	for _, s := range []string{
		"",
		"ghcr.io/603-identity/devcontainer-node:4.144",
		"ghcr.io/603-identity/devcontainer-other:4.144@" + dig,
		"ghcr.io/603-identity/devcontainer-node:4.144@sha256:ABCDEF",
		"ghcr.io/603-identity/devcontainer-node:4.144@" + dig + "\n",
		"ghcr.io/603-identity/devcontainer-node:latest@" + dig,
		"ghcr.io/603-identity/devcontainer-node:04.144@" + dig,
		"ghcr.io/603-identity/devcontainer-node:4.99999999999999999999@" + dig,
		"evil.io/603-identity/devcontainer-node:4.1@" + dig,
		"ghcr.io/603-identity/devcontainer-node:4.1@" + strings.Replace(dig, "sha256", "sha512", 1),
	} {
		_, err := Parse(s)
		if !check.IsFailure(err) {
			t.Errorf("Parse(%q) = %v, want a check failure", s, err)
		}
	}
}
