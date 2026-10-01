package consumer

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/dockerfile"
)

const (
	digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	goodDF = "# syntax=" + dockerfile.CurrentSyntax + "\nFROM ghcr.io/603-identity/devcontainer-node:4.144@" + digest + "\nUSER 1000:1000\n"
	goodDJ = `{"build":{"dockerfile":"Dockerfile"}}`
)

func write(t *testing.T, dir, rel, content string) {
	t.Helper()
	p := filepath.Join(dir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func setup(t *testing.T) string {
	dir := t.TempDir()
	write(t, dir, ".devcontainer/Dockerfile", goodDF)
	write(t, dir, ".devcontainer/devcontainer.json", goodDJ)
	return dir
}

func TestFilesOK(t *testing.T) {
	dir := setup(t)
	write(t, dir, "README.md", "hi")
	write(t, dir, ".git/devcontainer.json", "{}") // inside .git: skipped
	ref, err := Files(dir)
	if err != nil {
		t.Fatal(err)
	}
	if ref.Name != "node" || ref.Major != 4 || ref.Minor != 144 {
		t.Errorf("unexpected ref %+v", ref)
	}
}

func TestFilesRejects(t *testing.T) {
	cases := map[string]func(t *testing.T, dir string){
		"second devcontainer.json in subdir": func(t *testing.T, d string) { write(t, d, "sub/.devcontainer/devcontainer.json", goodDJ) },
		"devcontainer.json at root":          func(t *testing.T, d string) { write(t, d, "devcontainer.json", goodDJ) },
		".devcontainer.json at root":         func(t *testing.T, d string) { write(t, d, ".devcontainer.json", goodDJ) },
		"deep one":                           func(t *testing.T, d string) { write(t, d, "a/b/c/devcontainer.json", "{}") },
		"nested under .devcontainer":         func(t *testing.T, d string) { write(t, d, ".devcontainer/x/devcontainer.json", goodDJ) },
		"case variant":                       func(t *testing.T, d string) { write(t, d, "sub/DevContainer.json", goodDJ) },
		".git elsewhere is not skipped":      func(t *testing.T, d string) { write(t, d, "sub/.git/devcontainer.json", "{}") },
		"missing Dockerfile":                 func(t *testing.T, d string) { _ = os.Remove(filepath.Join(d, ".devcontainer", "Dockerfile")) },
		"missing devcontainer.json":          func(t *testing.T, d string) { _ = os.Remove(filepath.Join(d, ".devcontainer", "devcontainer.json")) },
		"bad Dockerfile":                     func(t *testing.T, d string) { write(t, d, ".devcontainer/Dockerfile", "FROM alpine\n") },
		"bad devcontainer.json":              func(t *testing.T, d string) { write(t, d, ".devcontainer/devcontainer.json", `{"image":"x"}`) },
		"Dockerfile is a directory": func(t *testing.T, d string) {
			p := filepath.Join(d, ".devcontainer", "Dockerfile")
			_ = os.Remove(p)
			_ = os.Mkdir(p, 0o755)
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			dir := setup(t)
			mutate(t, dir)
			if _, err := Files(dir); !check.IsFailure(err) {
				t.Fatalf("want a check failure, got %v", err)
			}
		})
	}
}

func TestFilesSymlinkIsRejected(t *testing.T) {
	dir := setup(t)
	real := filepath.Join(dir, "real.Dockerfile")
	write(t, dir, "real.Dockerfile", goodDF)
	p := filepath.Join(dir, ".devcontainer", "Dockerfile")
	_ = os.Remove(p)
	if err := os.Symlink(real, p); err != nil {
		t.Skipf("cannot create symlinks here: %v", err)
	}
	if _, err := Files(dir); !check.IsFailure(err) {
		t.Fatalf("want a check failure, got %v", err)
	}
}

func TestFilesMissingDirIsAnError(t *testing.T) {
	_, err := Files(filepath.Join(t.TempDir(), "does-not-exist"))
	if err == nil || check.IsFailure(err) {
		t.Fatalf("an unreadable consumer dir is an error, not a failed predicate; got %v", err)
	}
}
