package dockerfile

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

const (
	digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	base   = "ghcr.io/603-identity/devcontainer-tofu:4.144@" + digest
	hdr    = "# syntax=" + CurrentSyntax + "\n"
)

func templateText(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "template", ".devcontainer", "Dockerfile"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestTemplateWithRealDigest(t *testing.T) {
	src := templateText(t)
	if !strings.Contains(src, "TAG@sha256:DIGEST") {
		t.Fatal("template FROM placeholder changed; update this test")
	}
	src = strings.Replace(src, "TAG@sha256:DIGEST", "4.144@"+digest, 1)
	ref, err := Check([]byte(src))
	if err != nil {
		t.Fatal(err)
	}
	if ref.Name != "tofu" || ref.Major != 4 || ref.Minor != 144 || ref.Digest != digest {
		t.Errorf("unexpected base %+v", ref)
	}
}

func TestTemplateWithPlaceholdersIsRejected(t *testing.T) {
	if _, err := Check([]byte(templateText(t))); !check.IsFailure(err) {
		t.Fatalf("the unfilled template must not pass, got %v", err)
	}
}

// The template's line 1 must be one of AllowedSyntax, and may still be PreviousSyntax: a syntax
// bump releases the verifier first, and the template moves with the pin bump to that release
// (README.md "Cutting a release"). Whether the value is allowed by the release the template's
// workflows pin is tools/check-self-pins.sh's check (#125), not this test's.
func TestTemplateSyntaxIsAllowed(t *testing.T) {
	first, _, _ := strings.Cut(templateText(t), "\n")
	if first != "# syntax="+CurrentSyntax && first != "# syntax="+PreviousSyntax {
		t.Fatalf("template first line %q is not an allowed syntax %q", first, AllowedSyntax)
	}
}

// The images build with this repo's own frontend pin, so they must carry CurrentSyntax.
func TestImagesCarryCurrentSyntax(t *testing.T) {
	for _, g := range []string{"base", "tofu", "node"} {
		b, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "images", g, "Dockerfile"))
		if err != nil {
			t.Fatal(err)
		}
		if first, _, _ := strings.Cut(string(b), "\n"); first != "# syntax="+CurrentSyntax {
			t.Errorf("images/%s/Dockerfile first line %q differs from the allowlist's current value", g, first)
		}
	}
}

// The vendored parser must be the BuildKit release that ships the frontend the allowed
// `# syntax=` pins (security L2). frontendToBuildkit maps a frontend minor series to the
// release whose frontend/dockerfile/{parser,instructions} code it was cut from.
//
// dockerfile/1.28.0 (the pinned digest sha256:bb22...) and v0.34.0 and v0.34.1 are the same
// commit (f5b59a1f): v0.34.1 re-tags it, rebuilt with Go 1.26.10 for CVE-2026-111943, with no
// functional change, so v0.34.1 is the release the frontend was cut from. (The previous pin,
// dockerfile/1.27.1, is v0.33.1 plus a version-string commit.)
// v0.34.1 needs go 1.26.8; go.mod and every setup-go go-version must agree (verify-selftest.yml checks this).
var frontendToBuildkit = map[string]string{"1.28": "v0.34.1"}

func TestBuildkitMatchesFrontend(t *testing.T) {
	m := regexp.MustCompile(`^docker/dockerfile:([0-9]+\.[0-9]+)@sha256:[0-9a-f]{64}$`).FindStringSubmatch(CurrentSyntax)
	if m == nil {
		t.Fatalf("CurrentSyntax %q is not series@digest", CurrentSyntax)
	}
	want, ok := frontendToBuildkit[m[1]]
	if !ok {
		t.Fatalf("no buildkit release is recorded for frontend %s; add it to frontendToBuildkit after checking the tag", m[1])
	}
	gomod, err := os.ReadFile(filepath.Join("..", "..", "go.mod"))
	if err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`(?m)^\s*github\.com/moby/buildkit ` + regexp.QuoteMeta(want) + `$`).Match(gomod) {
		t.Errorf("go.mod does not require github.com/moby/buildkit %s", want)
	}
	mods, err := os.ReadFile(filepath.Join("..", "..", "vendor", "modules.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(mods), "# github.com/moby/buildkit "+want+"\n") {
		t.Errorf("vendor/modules.txt does not hold github.com/moby/buildkit %s", want)
	}
}

func check1(t *testing.T, src string) error {
	t.Helper()
	_, err := Check([]byte(src))
	return err
}

func TestAcceptsMinimal(t *testing.T) {
	for _, h := range []string{CurrentSyntax, PreviousSyntax} {
		if err := check1(t, "# syntax="+h+"\nFROM "+base+"\nUSER 1000:1000\nRUN --mount=type=cache,target=/tmp/c true\nCOPY a b\n"); err != nil {
			t.Errorf("syntax %q: %v", h, err)
		}
	}
	// Comments, blank lines and a continuation after FROM are fine.
	if err := check1(t, hdr+"#\n# note\n\nFROM "+base+"\n\nRUN echo a \\\n  && echo b\n"); err != nil {
		t.Error(err)
	}
}

func TestRejects(t *testing.T) {
	from := "FROM " + base + "\n"
	cases := map[string]string{
		// The four L4 bypasses (spike 1 appendix A).
		"L4 FR continuation": hdr + "FR\\\nOM alpine\n" + from,
		"L4 escape split":    hdr + "# escape=`\nFR`\nOM alpine\n" + from,
		"L4 ARG swallows":    hdr + "ARG x=\\\n" + from,
		"L4 FROM comment":    hdr + "FROM \\\n# comment\nalpine\n" + from,

		"meta ARG":              hdr + "ARG V=4\n" + from,
		"dollar in base":        hdr + "FROM ghcr.io/603-identity/devcontainer-tofu:4.${N}@" + digest + "\n",
		"dollar base var":       hdr + "FROM $IMG\n",
		"COPY --from":           hdr + from + "COPY --from=alpine /a /b\n",
		"COPY --from image":     hdr + from + "COPY --from=docker.io/library/alpine:3 /a /b\n",
		"RUN --mount from":      hdr + from + "RUN --mount=type=bind,from=alpine,target=/x true\n",
		"RUN --mount FROM case": hdr + from + "RUN --mount=type=bind,FROM=alpine,target=/x true\n",
		"ONBUILD":               hdr + from + "ONBUILD RUN true\n",
		"two stages":            hdr + from + from,
		"two stages, last evil": hdr + from + "FROM alpine\n",
		"stage name":            hdr + "FROM " + base + " AS dev\n",
		"platform":              hdr + "FROM --platform=linux/amd64 " + base + "\n",
		"unpinned base":         hdr + "FROM ghcr.io/603-identity/devcontainer-tofu:4.144\n",
		"foreign base":          hdr + "FROM alpine@" + digest + "\n",
		"no FROM":               hdr + "USER 1000\n",
		"command before FROM":   hdr + "USER 1000\n" + from,
		"nothing but a comment": hdr,
		"empty":                 "",
		"unknown instruction":   hdr + from + "BOGUS x\n",

		"syntax unknown":        "# syntax=docker/dockerfile:1.28\n" + from,
		"syntax other digest":   "# syntax=docker/dockerfile:1.27@sha256:" + strings.Repeat("0", 64) + "\n" + from,
		"syntax foreign":        "# syntax=evil/frontend:1\n" + from,
		"syntax trailing words": "# syntax=" + CurrentSyntax + " extra\n" + from,
		"syntax missing":        "# comment\n" + from,
		"syntax not first":      from + hdr,
		"syntax after comment":  "# hello\n\n" + hdr + from,
		"syntax twice":          hdr + hdr + from,
		"extra check directive": hdr + "# check=skip=all\n" + from,
		"extra escape":          hdr + "# escape=`\n" + from,
		"only escape":           "# escape=`\n" + from,
		"shebang then syntax":   "#!/bin/sh\n" + hdr + from,

		"CRLF":          strings.ReplaceAll(hdr+from, "\n", "\r\n"),
		"lone CR":       hdr + from + "\r",
		"BOM":           "\xef\xbb\xbf" + hdr + from,
		"non-ASCII":     hdr + "# café\n" + from,
		"non-ASCII arg": hdr + from + "ENV X=é\n",
		"NUL":           hdr + from + "\x00",
		"oversize":      hdr + from + "#" + strings.Repeat("a", maxSize),
	}
	for name, src := range cases {
		t.Run(name, func(t *testing.T) {
			err := check1(t, src)
			if !check.IsFailure(err) {
				t.Fatalf("want a check failure, got %v", err)
			}
		})
	}
}
