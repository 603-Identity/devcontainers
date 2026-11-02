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
	rules           string // the rules/branches response; "" fails the call
	err             error
	calls           int
	rulesCalls      int
}

func (f *fake) Run(_ context.Context, _ string, args ...string) ([]byte, error) {
	f.calls++
	if f.err != nil {
		return nil, f.err
	}
	switch {
	case args[0] == "api" && strings.Contains(strings.Join(args, " "), "/rules/branches/"):
		f.rulesCalls++
		if f.rules == "" {
			return nil, errors.New("HTTP 403")
		}
		return []byte(f.rules), nil
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
	for name, content := range map[string]string{"Dockerfile": df, "devcontainer.json": fixture(t, "legacy.devcontainer.json")} {
		if err := os.WriteFile(filepath.Join(dir, ".devcontainer", name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

// verifyArgs is a plain-mode verify of dir with every flag the workflow passes: an empty base and
// tip (fetch-consumer.sh --mode-only found no devcontainer files there).
func listedDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "_listed"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func verifyArgs(t *testing.T, dir string) []string {
	return []string{"verify", "--consumer-dir", dir, "--base-dir", listedDir(t), "--tip-dir", listedDir(t),
		"--template-dir", filepath.Join("testdata", "devapp", "template"), "--repo", "glunk-works/app", "--default-branch", "main"}
}

// decideArgs is decide on dir with patch, with every flag decide-bump.sh passes.
func decideArgs(t *testing.T, dir, patch string) []string {
	return []string{"decide", "--consumer-dir", dir, "--patch", patch, "--template-dir", filepath.Join("testdata", "devapp", "template"), "--repo", "glunk-works/app"}
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
	want := `{"image":"ghcr.io/603-identity/devcontainer-node","major":4,"minor":144,"digest":"` + digest + `","mode":"plain"}` + "\n"
	if code != 0 || out != want {
		t.Fatalf("code %d, stdout %q, stderr %q", code, out, errOut)
	}
}

func TestVerifyAndAttest(t *testing.T) {
	f := newFake(t)
	if code, out, e := invoke(f, verifyArgs(t, consumerDir(t, "144"))...); code != 0 || out != "" {
		t.Fatalf("verify: code %d stdout %q stderr %q", code, out, e)
	}
	if code, _, e := invoke(newFake(t), "attest", "--image", "ghcr.io/603-identity/devcontainer-node:4.144@"+digest); code != 0 {
		t.Fatalf("attest: code %d stderr %q", code, e)
	}
}

func TestDecide(t *testing.T) {
	old := "FROM ghcr.io/603-identity/devcontainer-node:4.100@" + oldDig
	patch := "@@ -2,3 +2,3 @@ x\n-" + old + "\n+FROM ghcr.io/603-identity/devcontainer-node:4.144@" + digest + "\n USER 1000:1000\n"
	if code, _, e := invoke(newFake(t), decideArgs(t, consumerDir(t, "144"), patchFile(t, patch))...); code != 0 {
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
		"MAJOR bump":              {args: decideArgs(t, consumerDir(t, "144"), patchFile(t, major))},
		"downgrade":               {args: decideArgs(t, consumerDir(t, "144"), patchFile(t, downgrade))},
		"empty patch":             {args: decideArgs(t, consumerDir(t, "144"), patchFile(t, ""))},
		"wrong MINOR":             {args: verifyArgs(t, consumerDir(t, "145"))},
		"bad binding": {args: verifyArgs(t, consumerDir(t, "144")), mut: func(f *fake) {
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
	if code, _, _ := invoke(f, decideArgs(t, consumerDir(t, "144"), patchFile(t, patch))...); code != 3 || f.calls != 0 {
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
		"gh fails (network, 5xx, 403, 429)": {args: verifyArgs(t, dir), mut: func(f *fake) { f.err = errors.New("HTTP 503") }},
		"gh fails in decide":                {args: decideArgs(t, dir, goodPatch), mut: func(f *fake) { f.err = errors.New("HTTP 429") }},
		"gh fails in attest":                {args: []string{"attest", "--image", "ghcr.io/603-identity/devcontainer-node:4.144@" + digest}, mut: func(f *fake) { f.err = errors.New("dial tcp") }},
		"unparseable gh output":             {args: verifyArgs(t, dir), mut: func(f *fake) { f.prov = "<html>" }},
		"unreadable run response":           {args: verifyArgs(t, dir), mut: func(f *fake) { f.run = "<html>" }},
		"missing patch file":                {args: decideArgs(t, dir, filepath.Join(t.TempDir(), "nope"))},
		"unreadable consumer dir":           {args: []string{"files", "--consumer-dir", filepath.Join(t.TempDir(), "nope")}},
		"no subcommand":                     {args: nil},
		"unknown subcommand":                {args: []string{"frobnicate"}},
		"missing flag":                      {args: []string{"files"}},
		"missing patch flag":                {args: []string{"decide", "--consumer-dir", dir}},
		"verify without its mode flags":     {args: []string{"verify", "--consumer-dir", dir}},
		"decide without --repo":             {args: []string{"decide", "--consumer-dir", dir, "--patch", goodPatch, "--template-dir", "."}},
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

// devAppFake serves the attestation fixtures as if they were for devcontainer-devapp.
func devAppFake(t *testing.T) *fake {
	f := newFake(t)
	f.prov = strings.ReplaceAll(f.prov, "devcontainer-node", "devcontainer-devapp")
	f.sbom = strings.ReplaceAll(f.sbom, "devcontainer-node", "devcontainer-devapp")
	return f
}

const goodRules = `[{"type":"pull_request","parameters":{"required_approving_review_count":1,"require_code_owner_review":true}}]`

// devAppDir is a dev-App head built from testdata/devapp/template, for glunk-works/app.
func devAppDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, ".devcontainer"), 0o755); err != nil {
		t.Fatal(err)
	}
	df := "# syntax=" + dockerfile.CurrentSyntax + "\nFROM ghcr.io/603-identity/devcontainer-devapp:4.144@" + digest + "\nUSER 1000:1000\n"
	dj := strings.Replace(fixture(t, "devapp/template/.devcontainer/devcontainer.json"), "tokens/OWNER/REPO", "tokens/glunk-works/app", 1)
	for name, content := range map[string]string{"Dockerfile": df, "devcontainer.json": dj} {
		if err := os.WriteFile(filepath.Join(dir, ".devcontainer", name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestVerifyDevApp(t *testing.T) {
	f := devAppFake(t)
	f.rules = goodRules
	code, out, e := invoke(f, verifyArgs(t, devAppDir(t))...)
	if code != 0 || out != "" || f.rulesCalls != 1 {
		t.Fatalf("code %d stdout %q stderr %q rules calls %d", code, out, e, f.rulesCalls)
	}
	// files says which mode it found.
	code, out, _ = invoke(newFake(t), "files", "--consumer-dir", devAppDir(t), "--template-dir", filepath.Join("testdata", "devapp", "template"), "--repo", "glunk-works/app")
	if code != 0 || !strings.Contains(out, `"image":"ghcr.io/603-identity/devcontainer-devapp"`) || !strings.Contains(out, `"mode":"dev-app"`) {
		t.Fatalf("files: code %d stdout %q", code, out)
	}
	// Plain mode never reads the rules.
	f = newFake(t)
	if code, _, e := invoke(f, verifyArgs(t, consumerDir(t, "144"))...); code != 0 || f.rulesCalls != 0 {
		t.Fatalf("plain: code %d stderr %q rules calls %d", code, e, f.rulesCalls)
	}
}

func TestVerifyDevAppRules(t *testing.T) {
	// No approval rule: a plain "no".
	f := devAppFake(t)
	f.rules = `[{"type":"pull_request","parameters":{"required_approving_review_count":0,"require_code_owner_review":true}}]`
	if code, _, e := invoke(f, verifyArgs(t, devAppDir(t))...); code != 3 || !strings.Contains(e, "code-owner review") {
		t.Fatalf("no approval rule: code %d stderr %q", code, e)
	}
	// The rules cannot be read: red, never a "no".
	f = devAppFake(t)
	if code, _, e := invoke(f, verifyArgs(t, devAppDir(t))...); code == 0 || code == 3 {
		t.Fatalf("unreadable rules: code %d stderr %q", code, e)
	}
}

// decide exits 3 for any dev-App FROM, before any network call.
func TestDecideRefusesDevApp(t *testing.T) {
	f := newFake(t)
	f.rules = goodRules
	patch := "@@ -2,3 +2,3 @@ x\n-FROM ghcr.io/603-identity/devcontainer-devapp:4.100@" + oldDig + "\n+FROM ghcr.io/603-identity/devcontainer-devapp:4.144@" + digest + "\n"
	code, _, e := invoke(f, decideArgs(t, devAppDir(t), patchFile(t, patch))...)
	if code != 3 || f.calls != 0 || !strings.Contains(e, "refuses dev-App") {
		t.Fatalf("code %d calls %d stderr %q", code, f.calls, e)
	}
	// Even with a template directory that cannot be read.
	code, _, _ = invoke(f, "decide", "--consumer-dir", devAppDir(t), "--patch", patchFile(t, patch), "--template-dir", filepath.Join(t.TempDir(), "nope"), "--repo", "glunk-works/app")
	if code != 3 {
		t.Fatalf("unreadable template: code %d", code)
	}
}

func TestSnapshotIsOptional(t *testing.T) {
	b, err := snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if b != nil && !strings.Contains(string(b), "/run/wow") {
		t.Fatal("templates/previous.devcontainer.json is not a dev-App template")
	}
}
