package devapp

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/tailscale/hujson"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/dockerfile"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

const (
	digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	repo   = "glunk-works/app"
	from   = "FROM ghcr.io/603-identity/devcontainer-devapp-tofu:4.150@" + digest + "\n"
	hdr    = "# syntax=" + dockerfile.CurrentSyntax + "\n"
)

func realTemplate(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "template", ".devcontainer", "devcontainer.json"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// head is the real template as an adopter fills it in: the token directory names the repo.
func head(t *testing.T) string {
	return strings.Replace(realTemplate(t), "tokens/OWNER/REPO", "tokens/"+repo, 1)
}

func cands(t *testing.T) []Candidate {
	return []Candidate{{Name: "the template", Data: []byte(realTemplate(t))}}
}

func isFailure(t *testing.T, err error) {
	t.Helper()
	if !check.IsFailure(err) {
		t.Fatalf("want a check failure, got %v", err)
	}
}

func TestValidateRepo(t *testing.T) {
	for _, ok := range []string{"glunk-works/app", "603-Identity/devcontainers", "a/b.c", "a_b/.github", "o/con-x"} {
		if err := ValidateRepo(ok); err != nil {
			t.Errorf("%q: %v", ok, err)
		}
	}
	for _, bad := range []string{"app", "a/b/c", "a/", "/b", "a/b c", "a/./", "./b", "a/..", "a/b.", "a./b", "a/con", "a/CON.txt", "lpt1/b", "a/nul", "a/b\\c", "ä/b"} {
		if err := ValidateRepo(bad); !check.IsFailure(err) {
			t.Errorf("%q: want a check failure, got %v", bad, err)
		}
	}
	if err := ValidateRepo(""); err == nil || check.IsFailure(err) {
		t.Errorf("empty: want an error that is not a failure, got %v", err)
	}
}

func TestCompareJSON(t *testing.T) {
	if err := CompareJSON([]byte(head(t)), repo, cands(t)); err != nil {
		t.Fatalf("the filled-in template: %v", err)
	}
	// Comments, whitespace and key order do not count.
	commented := strings.Replace(head(t), `"remoteUser": "app",`, `"remoteUser": "app" /* hi */ ,`, 1)
	if err := CompareJSON([]byte(commented), repo, cands(t)); err != nil {
		t.Fatalf("a comment: %v", err)
	}
	moved := strings.Replace(strings.Replace(head(t), `"remoteUser": "app",`, ``, 1), `"init": true,`, `"init": true, "remoteUser": "app",`, 1)
	if moved == head(t) || !strings.Contains(moved, `"init": true, "remoteUser"`) {
		t.Fatal("the key move did not apply")
	}
	if err := CompareJSON([]byte(moved), repo, cands(t)); err != nil {
		t.Fatalf("a top-level key moved: %v", err)
	}
	// appPort, loopback only, is a surface.
	for _, ap := range []string{`"127.0.0.1:8080:8080"`, `["127.0.0.1:3000:3000", "127.0.0.1:65535:1024"]`} {
		src := strings.Replace(head(t), `"remoteUser": "app",`, `"remoteUser": "app", "appPort": `+ap+",", 1)
		if err := CompareJSON([]byte(src), repo, cands(t)); err != nil {
			t.Errorf("appPort %s: %v", ap, err)
		}
	}
	// The snapshot is the second candidate.
	snap := strings.Replace(realTemplate(t), `"init": true,`, `"init": true, "oldKey": 1,`, 1)
	h := strings.Replace(head(t), `"init": true,`, `"init": true, "oldKey": 1,`, 1)
	if err := CompareJSON([]byte(h), repo, append(cands(t), Candidate{Name: "the snapshot", Data: []byte(snap)})); err != nil {
		t.Errorf("matching the snapshot: %v", err)
	}
}

func TestCompareJSONRejects(t *testing.T) {
	h := head(t)
	addKey := func(kv string) string {
		return strings.Replace(h, `"remoteUser": "app",`, `"remoteUser": "app", `+kv+",", 1)
	}
	cases := map[string]string{
		// Surface 1, the token mount name.
		"another repo's tokens": strings.Replace(h, "tokens/"+repo, "tokens/glunk-works/other", 1),
		"case differs":          strings.Replace(h, "tokens/"+repo, "tokens/Glunk-Works/app", 1),
		"placeholder left":      realTemplate(t),
		"owner only":            strings.Replace(h, "tokens/"+repo, "tokens/glunk-works", 1),
		"token mount writable":  strings.Replace(h, "target=/run/wow,type=bind,readonly", "target=/run/wow,type=bind", 1),
		"second token mount":    strings.Replace(h, `"mounts": [`, `"mounts": ["source=${localEnv:USERPROFILE}/.config/glunk-identity/tokens/`+repo+`,target=/run/wow,type=bind,readonly",`, 1),
		"token mount dropped":   strings.Replace(h, `"source=${localEnv:USERPROFILE}/.config/glunk-identity/tokens/`+repo+`,target=/run/wow,type=bind,readonly"`, `"source=${localWorkspaceFolderBasename}-x,target=/x,type=volume"`, 1),
		// Surface 4, appPort.
		"appPort on every address": addKey(`"appPort": "8080:8080"`),
		"appPort 0.0.0.0":          addKey(`"appPort": "0.0.0.0:8080:8080"`),
		"appPort low port":         addKey(`"appPort": "127.0.0.1:80:8080"`),
		"appPort too high":         addKey(`"appPort": "127.0.0.1:70000:8080"`),
		"appPort number":           addKey(`"appPort": 8080`),
		"appPort six":              addKey(`"appPort": ["127.0.0.1:2001:2001","127.0.0.1:2002:2002","127.0.0.1:2003:2003","127.0.0.1:2004:2004","127.0.0.1:2005:2005","127.0.0.1:2006:2006"]`),
		"appPort empty list":       addKey(`"appPort": []`),
		"appPort publish flag":     addKey(`"appPort": "-p 127.0.0.1:8080:8080"`),
		// Everything else is matched exactly.
		"initializeCommand": addKey(`"initializeCommand": "calc.exe"`),
		"aws mount":         strings.Replace(h, `"mounts": [`, `"mounts": ["source=${localEnv:USERPROFILE}/.aws,target=/home/app/.aws,type=bind,readonly",`, 1),
		"containerEnv":      addKey(`"containerEnv": {"A": "b"}`),
		"runArgs":           strings.Replace(h, `"--tmpfs=/var/tmp"`, `"--tmpfs=/var/tmp", "--privileged"`, 1),
		"workspaceMount":    strings.Replace(h, "consistency=cached", "consistency=delegated", 1),
		"an extension":      strings.Replace(h, `"init": true`, `"customizations": {"vscode": {"extensions": ["x.y"]}}, "init": true`, 1),
		"postStartCommand":  strings.Replace(h, "sh /usr/local/share/devc/devapp-check.sh; ", "", 1),
		"tofu cache volume": strings.Replace(h, `"mounts": [`, `"mounts": ["source=devc-tofu-plugins,target=/home/app/.cache/tofu-plugins,type=volume",`, 1),
		"mounts reordered": strings.Replace(h,
			"\"source=${localWorkspaceFolderBasename}-home,target=/home/app,type=volume\",\n    \"source=${localWorkspaceFolderBasename}-tmp,target=/tmp,type=volume\",",
			"\"source=${localWorkspaceFolderBasename}-tmp,target=/tmp,type=volume\",\n    \"source=${localWorkspaceFolderBasename}-home,target=/home/app,type=volume\",", 1),
		"a number as a string": strings.Replace(h, `"init": true`, `"init": "true"`, 1),
	}
	for name, src := range cases {
		t.Run(name, func(t *testing.T) {
			if src == h {
				t.Fatal("the mutation did not apply")
			}
			isFailure(t, CompareJSON([]byte(src), repo, cands(t)))
		})
	}
}

func TestCompareJSONCandidates(t *testing.T) {
	legacy, err := os.ReadFile(filepath.Join("..", "..", "testdata", "legacy.devcontainer.json"))
	if err != nil {
		t.Fatal(err)
	}
	// A candidate that is not dev-App is never loaded, so a legacy template at the pin (any
	// release before v1.6) offers nothing to match.
	err = CompareJSON([]byte(head(t)), repo, []Candidate{{Name: "the template", Data: legacy}, {Name: "the snapshot"}})
	isFailure(t, err)
	if !strings.Contains(err.Error(), "carries no dev-App template") {
		t.Errorf("unexpected reason %v", err)
	}
	// A dev-App candidate that does not load is an error in the verifier's own files.
	if err := CompareJSON([]byte(head(t)), repo, []Candidate{{Name: "x", Data: []byte(`{"a": "/run/wow"}`)}}); err == nil || check.IsFailure(err) {
		t.Errorf("want an error, got %v", err)
	}
}

func TestReadLenient(t *testing.T) {
	dir := t.TempDir()
	// Without the sentinel a missing file could be a failed read: an error, never "absent".
	if _, err := ReadLenient(dir); err == nil || check.IsFailure(err) {
		t.Fatalf("no sentinel: want an error, got %v", err)
	}
	if _, err := ReadLenient(filepath.Join(dir, "missing")); err == nil || check.IsFailure(err) {
		t.Fatalf("a missing directory: want an error, got %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, ListedRel), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if l, err := ReadLenient(dir); err != nil || l.DevApp || l.HasFrom {
		t.Fatalf("an empty tree: %+v %v", l, err)
	}
	if err := os.MkdirAll(filepath.Join(dir, ".devcontainer"), 0o755); err != nil {
		t.Fatal(err)
	}
	// A base with a retired syntax line and broken JSON is still read.
	write := func(name, s string) {
		if err := os.WriteFile(filepath.Join(dir, ".devcontainer", name), []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("Dockerfile", "# syntax=docker/dockerfile:1.0\n  from ghcr.io/603-identity/devcontainer-tofu:4.141@sha256:x\n")
	write("devcontainer.json", "{ not json")
	l, err := ReadLenient(dir)
	if err != nil || l.DevApp || !l.HasFrom || l.FromMajor != 4 || l.FromMinor != 141 {
		t.Fatalf("plain base: %+v %v", l, err)
	}
	for _, m := range Markers {
		write("devcontainer.json", "{ broken "+m)
		if l, err := ReadLenient(dir); err != nil || !l.DevApp {
			t.Errorf("marker %q in the JSON: %+v %v", m, l, err)
		}
	}
}

func TestCheckMinor(t *testing.T) {
	ref, err := image.Parse("ghcr.io/603-identity/devcontainer-devapp:4.150@" + digest)
	if err != nil {
		t.Fatal(err)
	}
	for _, base := range []Lenient{{}, {HasFrom: true, FromMajor: 4, FromMinor: 150}, {HasFrom: true, FromMajor: 4, FromMinor: 99}, {HasFrom: true, FromMajor: 3, FromMinor: 900}} {
		if err := CheckMinor(ref, base); err != nil {
			t.Errorf("base %+v: %v", base, err)
		}
	}
	for _, base := range []Lenient{{HasFrom: true, FromMajor: 4, FromMinor: 151}, {HasFrom: true, FromMajor: 5, FromMinor: 1}} {
		isFailure(t, CheckMinor(ref, base))
	}
}

func parse(t *testing.T, body string) dockerfile.Parsed {
	t.Helper()
	p, err := dockerfile.Parse([]byte(hdr + from + body))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return p
}

func TestCheckDockerfile(t *testing.T) {
	files := map[string][]byte{
		"Dockerfile":        []byte("# names /run/wow in a comment"),
		"devcontainer.json": []byte(`{"x": "/run/wow"}`),
		"tools.txt":         []byte("jq\n"),
		"scripts/setup.sh":  []byte("#!/bin/sh\napt-get install -y jq\n"),
	}
	for name, body := range map[string]string{
		"no extras":              "USER 1000:1000\n",
		"root install":           "USER 0\nRUN apt-get update && apt-get install -y jq\nUSER 1000:1000\n",
		"copy a file":            "USER 0\nCOPY tools.txt /opt/tools.txt\nUSER 1000:1000\n",
		"copy a directory":       "COPY scripts/ /opt/scripts/\nRUN sh /opt/scripts/setup.sh\nUSER 1000:1000\n",
		"copy everything":        "COPY . /opt/devc/\nUSER 1000:1000\n",
		"leading ./ and /":       "COPY ./tools.txt /tools.txt /opt/\nUSER 1000:1000\n",
		"ordinary env":           "ENV PIP_NO_CACHE_DIR=1 NODE_OPTIONS=--max-old-space-size=4096\nUSER 1000:1000\n",
		"gh-like name":           "RUN ln -s /opt/ghq/ghq /usr/local/bin/ghq\nUSER 1000:1000\n",
		"bind-mount a file":      "RUN --mount=type=bind,source=scripts/setup.sh,target=/tmp/s.sh sh /tmp/s.sh\nUSER 1000:1000\n",
		"cache mount":            "RUN --mount=type=cache,target=/root/.cache pip install x\nUSER 1000:1000\n",
		"relative to /workspace": "COPY tools.txt etc/gitconfig\nUSER 1000:1000\n",
		"remote ADD":             "ADD --checksum=sha256:" + strings.Repeat("a", 64) + " https://example.com/x.tgz /opt/\nUSER 1000:1000\n",
		"uv --system":            "RUN uv pip install --system ruff\nUSER 1000:1000\n",
		"user git config":        "RUN git config --global init.defaultBranch main\nUSER 1000:1000\n",
		"other workdir":          "WORKDIR /opt\nCOPY tools.txt .\nUSER 1000:1000\n",
	} {
		t.Run(name, func(t *testing.T) {
			if err := CheckDockerfile(parse(t, body), files); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestCheckDockerfileRejects(t *testing.T) {
	files := map[string][]byte{
		"tools.txt":        []byte("jq\n"),
		"evil.sh":          []byte("#!/bin/sh\nrm -f /usr/local/libexec/dev-token\n"),
		"gitcfg.sh":        []byte("git config --system credential.helper store\n"),
		"scripts/setup.sh": []byte("cp x /etc/claude-code/managed-settings.json\n"),
		"gh":               []byte("#!/bin/sh\n"),
		"bin/gh":           []byte("#!/bin/sh\n"),
		"etc/gitconfig":    []byte("[user]\n"),
		"usr/local/bin/gh": []byte("#!/bin/sh\n"),
		"inst.sh":          []byte("rm /usr/local/bin/claude\n"),
		"t.tar":            []byte("archive"),
	}
	cases := map[string]string{
		"no final USER":            "RUN true\n",
		"final USER is root":       "USER 0\n",
		"final USER by name":       "USER app\n",
		"USER then more":           "USER 1000:1000\nRUN true\n",
		"ENV GIT_":                 "ENV GIT_SSH_COMMAND=x\nUSER 1000:1000\n",
		"ENV git_ lower case":      "ENV git_dir=x\nUSER 1000:1000\n",
		"ENV proxy":                "ENV HTTPS_PROXY=http://p\nUSER 1000:1000\n",
		"ENV proxy lower case":     "ENV http_proxy=http://p\nUSER 1000:1000\n",
		"ENV all proxy":            "ENV ALL_PROXY=http://p\nUSER 1000:1000\n",
		"ENV all proxy lower case": "ENV all_proxy=http://p\nUSER 1000:1000\n",
		"ENV Anthropic":            "ENV ANTHROPIC_BASE_URL=http://p\nUSER 1000:1000\n",
		"RUN replaces gh":          "USER 0\nRUN cp /bin/true /usr/local/bin/gh\nUSER 1000:1000\n",
		"RUN under libexec":        "USER 0\nRUN rm /usr/local/libexec/dev-token\nUSER 1000:1000\n",
		"RUN claude":               "RUN rm -f /usr/local/bin/claude\nUSER 1000:1000\n",
		"RUN managed settings":     "RUN rm -rf /etc/claude-code\nUSER 1000:1000\n",
		"RUN system gitconfig":     "RUN echo x >> /etc/gitconfig\nUSER 1000:1000\n",
		"RUN git config --system":  "RUN git config --system --unset-all credential.helper\nUSER 1000:1000\n",
		"RUN devc scripts":         "RUN rm /usr/local/share/devc/unsigned\nUSER 1000:1000\n",
		"RUN /run/wow":             "RUN ln -s /tmp/x /run/wow\nUSER 1000:1000\n",
		"RUN /var/run/wow":         "RUN cat /var/run/wow/dev-token\nUSER 1000:1000\n",
		"RUN heredoc":              "RUN <<EOF\nrm /usr/local/bin/gh\nEOF\nUSER 1000:1000\n",
		"RUN exec form":            "RUN [\"rm\", \"/usr/local/bin/gh\"]\nUSER 1000:1000\n",
		"COPY onto gh":             "COPY tools.txt /usr/local/bin/gh\nUSER 1000:1000\n",
		"COPY into libexec":        "COPY tools.txt /usr/local/libexec/\nUSER 1000:1000\n",
		"COPY via WORKDIR":         "WORKDIR /usr/local/bin\nCOPY tools.txt gh\nUSER 1000:1000\n",
		"COPY via relative dest":   "WORKDIR /opt\nCOPY tools.txt ../../etc/gitconfig\nUSER 1000:1000\n",
		"COPY a missing file":      "COPY missing.txt /opt/\nUSER 1000:1000\n",
		"COPY a glob":              "COPY *.txt /opt/\nUSER 1000:1000\n",
		"COPY a variable":          "ARG F=tools.txt\nCOPY $F /opt/\nUSER 1000:1000\n",
		"COPY to a variable":       "ARG D=/opt\nCOPY tools.txt $D/\nUSER 1000:1000\n",
		"COPY a script that does":  "COPY evil.sh /opt/evil.sh\nUSER 1000:1000\n",
		"COPY system git config":   "COPY gitcfg.sh /opt/\nUSER 1000:1000\n",
		"COPY a dir that does":     "COPY scripts /opt/scripts\nUSER 1000:1000\n",
		"COPY heredoc":             "COPY <<EOF /opt/x\nrm /usr/local/bin/claude\nEOF\nUSER 1000:1000\n",
		"COPY escapes the context": "COPY ../../secret /opt/\nUSER 1000:1000\n",
		"ADD onto gh":              "ADD https://example.com/gh /usr/local/bin/gh\nUSER 1000:1000\n",
		"WORKDIR identity":         "WORKDIR /run/wow\nUSER 1000:1000\n",
		"VOLUME identity":          "VOLUME /etc/claude-code\nUSER 1000:1000\n",
		// A directory destination: the copied file lands on an identity path.
		"COPY a file into a dir":         "COPY gh /usr/local/bin/\nUSER 1000:1000\n",
		"COPY a file, dir no slash":      "COPY gh /usr/local/bin\nUSER 1000:1000\n",
		"COPY a dir onto a dir":          "COPY bin /usr/local/bin\nUSER 1000:1000\n",
		"COPY an etc overlay":            "COPY etc /etc\nUSER 1000:1000\n",
		"COPY an etc overlay, slashes":   "COPY etc/ /etc/\nUSER 1000:1000\n",
		"COPY into WORKDIR":              "WORKDIR /usr/local/bin\nCOPY gh .\nUSER 1000:1000\n",
		"COPY --parents":                 "COPY --parents usr/local/bin/gh /\nUSER 1000:1000\n",
		"RUN bind-mounts a script":       "RUN --mount=type=bind,source=inst.sh,target=/tmp/i.sh sh /tmp/i.sh\nUSER 1000:1000\n",
		"RUN bind-mounts the context":    "RUN --mount=type=bind,target=/ctx sh /ctx/inst.sh\nUSER 1000:1000\n",
		"RUN bind-mounts a missing file": "RUN --mount=type=bind,source=nope.sh,target=/tmp/i.sh sh /tmp/i.sh\nUSER 1000:1000\n",
		"local ADD":                      "ADD t.tar /\nUSER 1000:1000\n",
		"ENV key from an ARG":            "ARG K=GIT_SSH_COMMAND\nENV $K=x\nUSER 1000:1000\n",
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			isFailure(t, CheckDockerfile(parse(t, body), files))
		})
	}
}

// RUN --mount and copy-target cases with a files map where only the named file is bad, so each
// one passes or fails for its own reason, not because some unrelated context file names an
// identity path.
func TestCheckDockerfileMountsAndTargets(t *testing.T) {
	files := map[string][]byte{
		"README.md":          []byte("The image's gh wrapper is /usr/local/bin/gh, root-owned.\n"),
		"ok.sh":              []byte("apt-get install -y jq\n"),
		"libexec/x":          []byte("x\n"),
		"x/usr/local/bin/gh": []byte("#!/bin/sh\n"),
	}
	for name, body := range map[string]string{
		"a cache mount beside a README naming gh": "RUN --mount=type=cache,target=/root/.cache pip install x\nUSER 1000:1000\n",
		"a tmpfs mount":                  "RUN --mount=type=tmpfs,target=/tmp/t true\nUSER 1000:1000\n",
		"a bind mount of a clean file":   "RUN --mount=type=bind,source=ok.sh,target=/tmp/ok.sh sh /tmp/ok.sh\nUSER 1000:1000\n",
		"a dir copied without --parents": "COPY libexec /usr/local/\nUSER 1000:1000\n",
		"a URL into a plain dir":         "ADD https://example.com/tools.tgz /opt/\nUSER 1000:1000\n",
	} {
		t.Run(name, func(t *testing.T) {
			if err := CheckDockerfile(parse(t, body), files); err != nil {
				t.Fatal(err)
			}
		})
	}
	for name, c := range map[string]struct{ body, reason string }{
		"a bind mount of a missing file":    {"RUN --mount=type=bind,source=nope.sh,target=/x sh /x\nUSER 1000:1000\n", "is not a regular file"},
		"a bind mount of the README":        {"RUN --mount=type=bind,source=README.md,target=/x true\nUSER 1000:1000\n", "names \"/usr/local/bin/gh\""},
		"a bind mount of the whole context": {"RUN --mount=type=bind,target=/ctx true\nUSER 1000:1000\n", "names \"/usr/local/bin/gh\""},
		"a bind source with a variable":     {"ARG S=ok.sh\nRUN --mount=type=bind,source=$S,target=/x true\nUSER 1000:1000\n", "not a literal path"},
		"a variable in a mount option":      {"ARG U=1000\nRUN --mount=type=cache,target=/c,uid=$U true\nUSER 1000:1000\n", "no variables in mount options"},
		"a --parents pivot":                 {"COPY --parents x/./usr/local/bin/gh /\nUSER 1000:1000\n", "pivot"},
		"a URL into /usr/local/bin":         {"ADD https://example.com/dl/gh /usr/local/bin/\nUSER 1000:1000\n", "\"/usr/local/bin/gh\""},
	} {
		t.Run(name, func(t *testing.T) {
			err := CheckDockerfile(parse(t, c.body), files)
			if !check.IsFailure(err) || !strings.Contains(err.Error(), c.reason) {
				t.Fatalf("want a failure naming %q, got %v", c.reason, err)
			}
		})
	}
}

func TestCheckDockerfileNeedsADevAppImage(t *testing.T) {
	p, err := dockerfile.Parse([]byte(hdr + "FROM ghcr.io/603-identity/devcontainer-tofu:4.150@" + digest + "\nUSER 1000:1000\n"))
	if err != nil {
		t.Fatal(err)
	}
	isFailure(t, CheckDockerfile(p, nil))
}

// The real template/ is what every dev-App head is compared with, so what it must NOT carry is
// pinned here, apart from the comparison: an edit that adds one of these to the template would
// otherwise pass every head that copies it (#392, the design's "Not in the template").
func TestRealTemplateShape(t *testing.T) {
	tmpl := realTemplate(t)
	for _, banned := range []string{
		`"extensions"`, `"containerEnv"`, `"remoteEnv"`, `"initializeCommand"`, `"appPort"`, `"features"`,
		`"image"`, "devc-tofu-plugins", ".aws", "${localEnv:HOME}", "--privileged", `"privileged"`,
		`"capAdd"`, `"securityOpt"`, "docker.sock", `"forwardPorts"`, `"onCreateCommand"`,
		`"updateContentCommand"`, `"runServices"`, `"dockerComposeFile"`, `"customizations"`,
	} {
		// Comments may name them; the JSON below the header may not. Strip // comments first.
		var code []string
		for _, l := range strings.Split(tmpl, "\n") {
			if i := strings.Index(l, "//"); i >= 0 && !strings.Contains(l[:i], `"`) {
				continue
			}
			code = append(code, l)
		}
		if strings.Contains(strings.Join(code, "\n"), banned) {
			t.Errorf("the template carries %s", banned)
		}
	}
	for _, want := range []string{
		"tokens/OWNER/REPO,target=/run/wow,type=bind,readonly",
		"--read-only",
	} {
		if !strings.Contains(tmpl, want) {
			t.Errorf("the template lacks %s", want)
		}
	}
	// runArgs and mounts are pinned exactly: a value that widens every adopter (--network=host,
	// --pid=host, a mount of the whole broker directory) is not a banned key.
	std, err := hujson.Standardize([]byte(tmpl))
	if err != nil {
		t.Fatal(err)
	}
	// Case-sensitive decoding: encoding/json would match "RUNARGS" to runArgs and let the last
	// duplicate win, while the devcontainer CLI reads the exact key only.
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(std, &raw); err != nil {
		t.Fatal(err)
	}
	for k := range raw {
		// The decoded key, not the raw text: "customizations" is the same key.
		if strings.EqualFold(k, "customizations") {
			t.Errorf("the template carries the top-level key %q (no VS Code settings: README \"Using an image\")", k)
		}
		for _, known := range []string{"runArgs", "mounts"} {
			if k != known && strings.EqualFold(k, known) {
				t.Errorf("the template carries a case-variant %q of %q", k, known)
			}
		}
	}
	var top struct {
		RunArgs []string
		Mounts  []string
	}
	if err := json.Unmarshal(raw["runArgs"], &top.RunArgs); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw["mounts"], &top.Mounts); err != nil {
		t.Fatal(err)
	}
	wantArgs := []string{"--cap-drop=ALL", "--security-opt=no-new-privileges", "--read-only", "--tmpfs=/run", "--tmpfs=/var/tmp"}
	if !slices.Equal(top.RunArgs, wantArgs) {
		t.Errorf("runArgs = %q, want %q", top.RunArgs, wantArgs)
	}
	wantMounts := []string{
		"source=${localEnv:USERPROFILE}/.gitconfig.d,target=/home/app/.gitconfig.d,type=bind,readonly",
		"source=${localWorkspaceFolderBasename}-home,target=/home/app,type=volume",
		"source=${localWorkspaceFolderBasename}-tmp,target=/tmp,type=volume",
		"source=${localWorkspaceFolderBasename}-node_modules,target=/workspace/node_modules,type=volume",
		"source=${localWorkspaceFolderBasename}-venv,target=/workspace/.venv,type=volume",
		"source=${localEnv:USERPROFILE}/.config/glunk-identity/tokens/OWNER/REPO,target=/run/wow,type=bind,readonly",
	}
	if !slices.Equal(top.Mounts, wantMounts) {
		t.Errorf("mounts = %q, want %q", top.Mounts, wantMounts)
	}
	// The credential-file cleanup runs first in postStartCommand, before any other start-up step,
	// and the pinned-plugin install (#503) runs last, so that its failure skips nothing. The exact
	// value covers both.
	var postStart string
	if err := json.Unmarshal(raw["postStartCommand"], &postStart); err != nil {
		t.Fatal(err)
	}
	const wantPostStart = "rm -f /tmp/vscode-remote-containers-*.js; sh /usr/local/share/devc/owner-check.sh; sh /usr/local/share/devc/devapp-check.sh; sh /usr/local/share/devc/git-identity.sh; sh /usr/local/share/devc/plugin-install.sh"
	if postStart != wantPostStart {
		t.Errorf("postStartCommand = %q, want the credential-file cleanup first and plugin-install.sh last: %q", postStart, wantPostStart)
	}
	// The attach notice (VS Code attach is unsupported) stays.
	if !strings.Contains(tmpl, `"postAttachCommand": "echo 'devapp: open this repo through the launcher only' >&2"`) {
		t.Errorf("the postAttachCommand warning is missing")
	}
	// It is not valid as a head until OWNER/REPO is filled in.
	isFailure(t, CompareJSON([]byte(tmpl), repo, cands(t)))
}
