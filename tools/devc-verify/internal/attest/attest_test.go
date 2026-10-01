package attest

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

const (
	digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	tag    = "ghcr.io/603-identity/devcontainer-node:4.144@" + digest
)

// fixtures are hand-built; see testdata/README.md.
func fixture(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

type call struct {
	name string
	args []string
}

type fakeRunner struct {
	prov, sbom, run string
	verifyErr       error
	apiErr          error
	calls           []call
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	f.calls = append(f.calls, call{name, args})
	switch {
	case len(args) >= 2 && args[0] == "attestation":
		if f.verifyErr != nil {
			return nil, f.verifyErr
		}
		if slices.Contains(args, "--predicate-type") {
			return []byte(f.sbom), nil
		}
		return []byte(f.prov), nil
	case len(args) >= 2 && args[0] == "api":
		if f.apiErr != nil {
			return nil, f.apiErr
		}
		return []byte(f.run), nil
	}
	return nil, errors.New("unexpected command")
}

func newFake(t *testing.T) *fakeRunner {
	return &fakeRunner{prov: fixture(t, "provenance.json"), sbom: fixture(t, "sbom.json"), run: fixture(t, "run.json")}
}

func mustRef(t *testing.T, s string) image.Ref {
	t.Helper()
	r, err := image.Parse(s)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestVerifyAcceptsAttempt1(t *testing.T) {
	f := newFake(t)
	if err := Verify(context.Background(), f, mustRef(t, tag)); err != nil {
		t.Fatal(err)
	}
	if len(f.calls) != 3 {
		t.Fatalf("want 3 gh calls, got %d", len(f.calls))
	}
	want := []string{
		"attestation", "verify", "oci://ghcr.io/603-identity/devcontainer-node@" + digest,
		"--repo", "603-Identity/devcontainers",
		"--cert-identity", "https://github.com/603-Identity/devcontainers/.github/workflows/build.yml@refs/heads/main",
		"--cert-oidc-issuer", "https://token.actions.githubusercontent.com",
		"--source-ref", "refs/heads/main",
		"--deny-self-hosted-runners",
		"--format", "json",
	}
	if !slices.Equal(f.calls[0].args, want) {
		t.Errorf("provenance args = %q, want %q", f.calls[0].args, want)
	}
	if !slices.Equal(f.calls[1].args, append(slices.Clone(want), "--predicate-type", "https://cyclonedx.org/bom")) {
		t.Errorf("sbom args = %q", f.calls[1].args)
	}
	if f.calls[2].name != "gh" || !slices.Equal(f.calls[2].args, []string{"api", "repos/603-Identity/devcontainers/actions/runs/36800000144"}) {
		t.Errorf("api call = %v", f.calls[2])
	}
}

func TestVerifyRejects(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(f *fakeRunner)
		ref    string
		want   string
	}{
		{"attempt 2 (F4)", func(f *fakeRunner) { f.prov = strings.ReplaceAll(f.prov, "/attempts/1", "/attempts/2") }, tag, "attempts/1"},
		{"attempt 10", func(f *fakeRunner) { f.prov = strings.ReplaceAll(f.prov, "/attempts/1", "/attempts/10") }, tag, "attempts/1"},
		{"wrong MINOR vs run_number", nil, "ghcr.io/603-identity/devcontainer-node:4.145@" + digest, "run_number 144"},
		{"run_number moved", func(f *fakeRunner) { f.run = strings.Replace(f.run, `"run_number": 144`, `"run_number": 7`, 1) }, tag, "run_number 7"},
		{"wrong repository_id", func(f *fakeRunner) { f.prov = strings.Replace(f.prov, "1392815879", "1", 1) }, tag, "repository_id"},
		{"wrong owner id", func(f *fakeRunner) { f.prov = strings.Replace(f.prov, "281691191", "2", 1) }, tag, "repository_owner_id"},
		{"wrong subject name", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"name": "ghcr.io/603-identity/devcontainer-node"`, `"name": "ghcr.io/603-identity/devcontainer-tofu"`, 1)
		}, tag, "no signed subject"},
		{"wrong subject digest", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"sha256": "0123`, `"sha256": "ffff`, 1)
		}, tag, "no signed subject"},
		{"pull_request event", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"event_name": "push"`, `"event_name": "pull_request"`, 1)
		}, tag, "event_name"},
		{"cert buildTrigger disagrees", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"buildTrigger": "push"`, `"buildTrigger": "schedule"`, 1)
		}, tag, "buildTrigger"},
		{"cert issuer", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"issuer": "https://token.actions.githubusercontent.com"`, `"issuer": "https://evil.example"`, 1)
		}, tag, "issuer"},
		{"workflow ref", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"ref": "refs/heads/main"`, `"ref": "refs/heads/other"`, 1)
		}, tag, "workflow is"},
		{"workflow path", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `".github/workflows/build.yml"`, `".github/workflows/evil.yml"`, 1)
		}, tag, "workflow is"},
		{"workflow repository", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"repository": "https://github.com/603-Identity/devcontainers"`, `"repository": "https://github.com/evil/devcontainers"`, 1)
		}, tag, "workflow is"},
		{"invocation from another repo", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"invocationId": "https://github.com/603-Identity/devcontainers/`, `"invocationId": "https://github.com/evil/devcontainers/`, 1)
		}, tag, "invocationId"},
		{"cert run URI disagrees", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, `"runInvocationURI": "https://github.com/603-Identity/devcontainers/actions/runs/36800000144`, `"runInvocationURI": "https://github.com/603-Identity/devcontainers/actions/runs/1`, 1)
		}, tag, "runInvocationURI"},
		{"provenance of the wrong type", func(f *fakeRunner) {
			f.prov = strings.Replace(f.prov, "https://slsa.dev/provenance/v1", "https://slsa.dev/provenance/v0.2", 1)
		}, tag, "predicate type"},
		{"sbom of another image", func(f *fakeRunner) {
			f.sbom = strings.Replace(f.sbom, "devcontainer-node", "devcontainer-base", 1)
		}, tag, "no signed subject"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newFake(t)
			if c.mutate != nil {
				c.mutate(f)
			}
			err := Verify(context.Background(), f, mustRef(t, c.ref))
			if !check.IsFailure(err) {
				t.Fatalf("want a check failure, got %v", err)
			}
			if !strings.Contains(err.Error(), c.want) {
				t.Errorf("error %q does not mention %q", err, c.want)
			}
		})
	}
}

func TestVerifyNumericRepositoryID(t *testing.T) {
	f := newFake(t)
	f.prov = strings.Replace(f.prov, `"1392815879"`, `1392815879`, 1)
	if err := Verify(context.Background(), f, mustRef(t, tag)); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyInfraErrorsAreNotFailures(t *testing.T) {
	boom := errors.New("HTTP 502")
	cases := map[string]func(f *fakeRunner){
		"gh verify fails":       func(f *fakeRunner) { f.verifyErr = boom },
		"gh api fails":          func(f *fakeRunner) { f.apiErr = boom },
		"verify output junk":    func(f *fakeRunner) { f.prov = "not json" },
		"verify output empty":   func(f *fakeRunner) { f.prov = "[]" },
		"sbom output junk":      func(f *fakeRunner) { f.sbom = "{" },
		"run has no number":     func(f *fakeRunner) { f.run = "{}" },
		"run answers for other": func(f *fakeRunner) { f.run = strings.Replace(f.run, "36800000144", "5", 1) },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			mutate(f)
			err := Verify(context.Background(), f, mustRef(t, tag))
			if err == nil || check.IsFailure(err) {
				t.Fatalf("want a non-failure error, got %v", err)
			}
		})
	}
}
