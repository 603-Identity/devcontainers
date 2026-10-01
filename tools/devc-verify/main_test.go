package main

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/dockerfile"
)

const (
	digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	oldDig = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
)

func fixture(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

type fake struct {
	prov, sbom, run string
	err             error
	calls           int
}

func (f *fake) Run(_ context.Context, _ string, args ...string) ([]byte, error) {
	f.calls++
	if f.err != nil {
		return nil, f.err
	}
	switch {
	case args[0] == "api":
		return []byte(f.run), nil
	case slices.Contains(args, "--predicate-type"):
		return []byte(f.sbom), nil
	}
	return []byte(f.prov), nil
}

func newFake(t *testing.T) *fake {
	return &fake{prov: fixture(t, "provenance.json"), sbom: fixture(t, "sbom.json"), run: fixture(t, "run.json")}
}

func consumerDir(t *testing.T, minor string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, ".devcontainer"), 0o755); err != nil {
		t.Fatal(err)
	}
	df := "# syntax=" + dockerfile.CurrentSyntax + "\nFROM ghcr.io/603-identity/devcontainer-node:4." + minor + "@" + digest + "\nUSER 1000:1000\n"
	for name, content := range map[string]string{"Dockerfile": df, "devcontainer.json": `{"build":{"dockerfile":"Dockerfile"}}`} {
		if err := os.WriteFile(filepath.Join(dir, ".devcontainer", name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func patchFile(t *testing.T, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "patch")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func invoke(f *fake, args ...string) (code int, stdout, stderr string) {
	var o, e bytes.Buffer
	code = run(args, &o, &e, f)
	return code, o.String(), e.String()
}

func TestFilesPrintsOneJSONLine(t *testing.T) {
	code, out, errOut := invoke(newFake(t), "files", "--consumer-dir", consumerDir(t, "144"))
	want := `{"image":"ghcr.io/603-identity/devcontainer-node","major":4,"minor":144,"digest":"` + digest + `"}` + "\n"
	if code != 0 || out != want {
		t.Fatalf("code %d, stdout %q, stderr %q", code, out, errOut)
	}
}

func TestVerifyAndAttest(t *testing.T) {
	f := newFake(t)
	if code, out, e := invoke(f, "verify", "--consumer-dir", consumerDir(t, "144")); code != 0 || out != "" {
		t.Fatalf("verify: code %d stdout %q stderr %q", code, out, e)
	}
	if code, _, e := invoke(newFake(t), "attest", "--image", "ghcr.io/603-identity/devcontainer-node:4.144@"+digest); code != 0 {
		t.Fatalf("attest: code %d stderr %q", code, e)
	}
}

func TestDecide(t *testing.T) {
	old := "FROM ghcr.io/603-identity/devcontainer-node:4.100@" + oldDig
	patch := "@@ -2,3 +2,3 @@ x\n-" + old + "\n+FROM ghcr.io/603-identity/devcontainer-node:4.144@" + digest + "\n USER 1000:1000\n"
	if code, _, e := invoke(newFake(t), "decide", "--consumer-dir", consumerDir(t, "144"), "--patch", patchFile(t, patch)); code != 0 {
		t.Fatalf("code %d, stderr %q", code, e)
	}
}

// Exit code 3 means exactly "the predicate is false".
func TestFalsePredicateExits3(t *testing.T) {
	major := "@@ -2,3 +2,3 @@ x\n-FROM ghcr.io/603-identity/devcontainer-node:3.100@" + oldDig + "\n+FROM ghcr.io/603-identity/devcontainer-node:4.144@" + digest + "\n"
	downgrade := "@@ -2,3 +2,3 @@ x\n-FROM ghcr.io/603-identity/devcontainer-node:4.200@" + oldDig + "\n+FROM ghcr.io/603-identity/devcontainer-node:4.144@" + digest + "\n"
	cases := map[string]struct {
		args []string
		mut  func(f *fake)
	}{
		"rule violation in files": {args: []string{"files", "--consumer-dir", t.TempDir()}},
		"MAJOR bump":              {args: []string{"decide", "--consumer-dir", consumerDir(t, "144"), "--patch", patchFile(t, major)}},
		"downgrade":               {args: []string{"decide", "--consumer-dir", consumerDir(t, "144"), "--patch", patchFile(t, downgrade)}},
		"empty patch":             {args: []string{"decide", "--consumer-dir", consumerDir(t, "144"), "--patch", patchFile(t, "")}},
		"wrong MINOR":             {args: []string{"verify", "--consumer-dir", consumerDir(t, "145")}},
		"bad binding": {args: []string{"verify", "--consumer-dir", consumerDir(t, "144")}, mut: func(f *fake) {
			f.prov = strings.Replace(f.prov, "/attempts/1", "/attempts/2", -1)
		}},
		"attest with an image that does not match": {args: []string{"attest", "--image", "alpine:3"}},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			if c.mut != nil {
				c.mut(f)
			}
			code, out, e := invoke(f, c.args...)
			if code != 3 || out != "" || !strings.HasPrefix(e, "devc-verify: check failed: ") {
				t.Fatalf("code %d stdout %q stderr %q", code, out, e)
			}
		})
	}
}

func TestDecideDoesNotTouchTheNetworkWhenFalse(t *testing.T) {
	f := newFake(t)
	patch := "@@ -1 +1 @@\n-FROM ghcr.io/603-identity/devcontainer-node:3.1@" + oldDig + "\n+FROM ghcr.io/603-identity/devcontainer-node:4.144@" + digest + "\n"
	if code, _, _ := invoke(f, "decide", "--consumer-dir", consumerDir(t, "144"), "--patch", patchFile(t, patch)); code != 3 || f.calls != 0 {
		t.Fatalf("code %d, gh calls %d", code, f.calls)
	}
}

// Infrastructure faults must never read as a false predicate.
func TestInfraErrorsNeverExit3(t *testing.T) {
	dir := consumerDir(t, "144")
	goodPatch := patchFile(t, "@@ -1 +1 @@\n-FROM ghcr.io/603-identity/devcontainer-node:4.100@"+oldDig+"\n+FROM ghcr.io/603-identity/devcontainer-node:4.144@"+digest+"\n")
	cases := map[string]struct {
		args []string
		mut  func(f *fake)
	}{
		"gh fails (network, 5xx, 403, 429)": {args: []string{"verify", "--consumer-dir", dir}, mut: func(f *fake) { f.err = errors.New("HTTP 503") }},
		"gh fails in decide":                {args: []string{"decide", "--consumer-dir", dir, "--patch", goodPatch}, mut: func(f *fake) { f.err = errors.New("HTTP 429") }},
		"gh fails in attest":                {args: []string{"attest", "--image", "ghcr.io/603-identity/devcontainer-node:4.144@" + digest}, mut: func(f *fake) { f.err = errors.New("dial tcp") }},
		"unparseable gh output":             {args: []string{"verify", "--consumer-dir", dir}, mut: func(f *fake) { f.prov = "<html>" }},
		"unreadable run response":           {args: []string{"verify", "--consumer-dir", dir}, mut: func(f *fake) { f.run = "<html>" }},
		"missing patch file":                {args: []string{"decide", "--consumer-dir", dir, "--patch", filepath.Join(t.TempDir(), "nope")}},
		"unreadable consumer dir":           {args: []string{"files", "--consumer-dir", filepath.Join(t.TempDir(), "nope")}},
		"no subcommand":                     {args: nil},
		"unknown subcommand":                {args: []string{"frobnicate"}},
		"missing flag":                      {args: []string{"files"}},
		"missing patch flag":                {args: []string{"decide", "--consumer-dir", dir}},
		"unknown flag":                      {args: []string{"files", "--bogus"}},
		"stray argument":                    {args: []string{"files", "--consumer-dir", dir, "extra"}},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			if c.mut != nil {
				c.mut(f)
			}
			code, out, _ := invoke(f, c.args...)
			if code == 0 || code == 3 {
				t.Fatalf("code %d: want an error code other than 0 and 3", code)
			}
			if out != "" {
				t.Errorf("stdout %q on error", out)
			}
		})
	}
}

func TestStderrReasonQuotesPRContent(t *testing.T) {
	dir := consumerDir(t, "144")
	evil := "# syntax=evil\x1b[31m\nFROM x\n"
	if err := os.WriteFile(filepath.Join(dir, ".devcontainer", "Dockerfile"), []byte(evil), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, e := invoke(newFake(t), "files", "--consumer-dir", dir)
	if code != 3 || out != "" || strings.ContainsRune(e, 0x1b) {
		t.Fatalf("code %d stdout %q stderr %q", code, out, e)
	}
}
