package consumer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/devapp"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/dockerfile"
)

// The dev-App self-test (#392, PR C) against the fixture in testdata/devapp/template. PR D adds
// the same against the real template/.
const (
	repo     = "glunk-works/app"
	devappDF = "# syntax=" + dockerfile.CurrentSyntax + "\nFROM ghcr.io/603-identity/devcontainer-devapp-tofu:4.150@" + digest + "\nUSER 0\nCOPY tools.txt /opt/tools.txt\nUSER 1000:1000\n"
)

var templateDir = filepath.Join("..", "..", "testdata", "devapp", "template")

func templateJSON(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(templateDir, ".devcontainer", "devcontainer.json"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// devAppHead is a dev-App head as fetch-consumer.sh writes it: the two files plus an extra.
func devAppHead(t *testing.T) string {
	dir := t.TempDir()
	write(t, dir, ".devcontainer/Dockerfile", devappDF)
	write(t, dir, ".devcontainer/devcontainer.json", strings.Replace(templateJSON(t), "tokens/OWNER/REPO", "tokens/"+repo, 1))
	write(t, dir, ".devcontainer/tools.txt", "jq\n")
	return dir
}

func opts(dir string) Options {
	return Options{Dir: dir, TemplateDir: templateDir, Repo: repo}
}

// side is a lenient base or tip tree holding only a Dockerfile, as fetch-consumer.sh
// --mode-only writes it (with its sentinel).
func side(t *testing.T, df string) string {
	dir := t.TempDir()
	write(t, dir, devapp.ListedRel, "")
	if df != "" {
		write(t, dir, ".devcontainer/Dockerfile", df)
	}
	return dir
}

func TestDevAppHeadPasses(t *testing.T) {
	r, err := Check(opts(devAppHead(t)))
	if err != nil {
		t.Fatal(err)
	}
	if !r.DevApp || r.Ref.Name != "devapp-tofu" || r.Ref.Minor != 150 {
		t.Fatalf("unexpected result %+v", r)
	}
	// A plain base (the cutover PR) and an older dev-App base are fine.
	o := opts(devAppHead(t))
	o.BaseDir = side(t, "FROM ghcr.io/603-identity/devcontainer-tofu:4.149@sha256:x\n")
	o.TipDir = side(t, "")
	if _, err := Check(o); err != nil {
		t.Fatalf("cutover from a plain base: %v", err)
	}
}

func TestPlainHeadInDevAppMode(t *testing.T) {
	devappBase := "# a retired syntax line\nFROM ghcr.io/603-identity/devcontainer-devapp:4.150@sha256:x\n"
	for name, o := range map[string]Options{
		"base is dev-App": {Dir: setup(t), BaseDir: side(t, devappBase), TipDir: side(t, "")},
		"tip is dev-App":  {Dir: setup(t), BaseDir: side(t, ""), TipDir: side(t, devappBase)},
	} {
		t.Run(name, func(t *testing.T) {
			o.TemplateDir, o.Repo = templateDir, repo
			_, err := Check(o)
			if !check.IsFailure(err) || !strings.Contains(err.Error(), "the head must be too") {
				t.Fatalf("want the head-must-be-dev-App failure, got %v", err)
			}
		})
	}
	// A plain head with plain sides stays in plain mode.
	if _, err := Check(Options{Dir: setup(t), BaseDir: side(t, goodDF), TipDir: side(t, goodDF)}); err != nil {
		t.Fatal(err)
	}
	// A base or tip that was not read is an error, never "absent" (plain).
	if _, err := Check(Options{Dir: setup(t), BaseDir: t.TempDir(), TipDir: side(t, "")}); err == nil || check.IsFailure(err) {
		t.Fatalf("an unread base: want an error, got %v", err)
	}
}

// A plain head is read for the markers as a base or tip is (raw bytes, comments included), so
// one that passes can never make the next PR's base dev-App and wedge it.
func TestPlainHeadWithAMarker(t *testing.T) {
	for name, mutate := range map[string]func(dir string){
		"Dockerfile comment": func(d string) {
			write(t, d, ".devcontainer/Dockerfile", strings.Replace(goodDF, "USER 1000:1000", "# TODO: devcontainer-devapp\nUSER 1000:1000", 1))
		},
		"devcontainer.json comment": func(d string) {
			write(t, d, ".devcontainer/devcontainer.json", "// planned: the glunk-identity token mount\n"+goodDJ)
		},
		"devcontainer.json value": func(d string) {
			write(t, d, ".devcontainer/devcontainer.json", strings.Replace(goodDJ, `"remoteUser": "app",`, `"remoteUser": "app", "containerEnv": {"T": "/run/wow"},`, 1))
		},
	} {
		t.Run(name, func(t *testing.T) {
			dir := setup(t)
			mutate(dir)
			_, err := Check(Options{Dir: dir})
			if !check.IsFailure(err) || !strings.Contains(err.Error(), "names a dev-App marker") {
				t.Fatalf("want the marker failure, got %v", err)
			}
		})
	}
}

func TestDevAppRejects(t *testing.T) {
	cases := map[string]func(t *testing.T, o *Options){
		"FROM dev-App, JSON plain": func(t *testing.T, o *Options) {
			write(t, o.Dir, ".devcontainer/devcontainer.json", goodDJ)
		},
		"JSON dev-App, FROM plain": func(t *testing.T, o *Options) {
			write(t, o.Dir, ".devcontainer/Dockerfile", strings.Replace(devappDF, "devcontainer-devapp-tofu", "devcontainer-tofu", 1))
		},
		"surface 1: another repo": func(t *testing.T, o *Options) { o.Repo = "glunk-works/other" },
		"surface 2: older than the base": func(t *testing.T, o *Options) {
			o.BaseDir = side(t, "FROM ghcr.io/603-identity/devcontainer-devapp-tofu:4.151@sha256:x\n")
		},
		"surface 3: extras write the identity layer": func(t *testing.T, o *Options) {
			write(t, o.Dir, ".devcontainer/Dockerfile", strings.Replace(devappDF, "/opt/tools.txt", "/usr/local/bin/gh", 1))
		},
		"surface 3: a copied file is missing": func(t *testing.T, o *Options) {
			_ = os.Remove(filepath.Join(o.Dir, ".devcontainer", "tools.txt"))
		},
		"surface 3: fetch-consumer marked an irregular entry": func(t *testing.T, o *Options) {
			write(t, o.Dir, "_irregular/.devcontainer", "")
		},
		"surface 4: appPort on every address": func(t *testing.T, o *Options) {
			b, _ := os.ReadFile(filepath.Join(o.Dir, ".devcontainer", "devcontainer.json"))
			write(t, o.Dir, ".devcontainer/devcontainer.json", strings.Replace(string(b), `"init": true,`, `"init": true, "appPort": "8080:8080",`, 1))
		},
		"outside the surfaces": func(t *testing.T, o *Options) {
			b, _ := os.ReadFile(filepath.Join(o.Dir, ".devcontainer", "devcontainer.json"))
			write(t, o.Dir, ".devcontainer/devcontainer.json", strings.Replace(string(b), `"init": true,`, `"init": true, "initializeCommand": "x",`, 1))
		},
		"metadata label": func(t *testing.T, o *Options) {
			write(t, o.Dir, ".devcontainer/Dockerfile", strings.Replace(devappDF, "USER 0\n", "USER 0\nLABEL devcontainer.metadata=[]\n", 1))
		},
		"the pin's template is legacy": func(t *testing.T, o *Options) {
			legacy := t.TempDir()
			write(t, legacy, ".devcontainer/devcontainer.json", goodDJ)
			o.TemplateDir = legacy
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			o := opts(devAppHead(t))
			mutate(t, &o)
			if _, err := Check(o); !check.IsFailure(err) {
				t.Fatalf("want a check failure, got %v", err)
			}
		})
	}
}

func TestDevAppSnapshot(t *testing.T) {
	// The head matches the previous release's snapshot, not the template at the pin.
	old := strings.Replace(templateJSON(t), `"init": true,`, `"init": true, "hostRequirements": {"cpus": 2},`, 1)
	o := opts(devAppHead(t))
	write(t, o.Dir, ".devcontainer/devcontainer.json", strings.Replace(old, "tokens/OWNER/REPO", "tokens/"+repo, 1))
	if _, err := Check(o); !check.IsFailure(err) {
		t.Fatalf("without the snapshot: want a failure, got %v", err)
	}
	o.Snapshot = []byte(old)
	if _, err := Check(o); err != nil {
		t.Fatalf("with the snapshot: %v", err)
	}
	// A snapshot that is not dev-App is never loaded.
	o.Snapshot = []byte(strings.NewReplacer("glunk-identity", "x", "/run/wow", "/x").Replace(old))
	if _, err := Check(o); !check.IsFailure(err) {
		t.Fatalf("a plain snapshot: want a failure, got %v", err)
	}
}

func TestDevAppNeedsRepoAndTemplate(t *testing.T) {
	for name, o := range map[string]Options{
		"no repo":             {Dir: devAppHead(t), TemplateDir: templateDir},
		"no template":         {Dir: devAppHead(t), Repo: repo},
		"unreadable template": {Dir: devAppHead(t), Repo: repo, TemplateDir: filepath.Join(t.TempDir(), "nope")},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := Check(o); err == nil || check.IsFailure(err) {
				t.Fatalf("want an error that is not a failure, got %v", err)
			}
		})
	}
}

func TestHeadImage(t *testing.T) {
	ref, err := HeadImage(devAppHead(t))
	if err != nil || !ref.DevApp() {
		t.Fatalf("%+v %v", ref, err)
	}
}
