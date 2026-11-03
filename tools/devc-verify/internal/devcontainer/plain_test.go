package devcontainer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

func testdata(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// The allowlist is built from the legacy template, so the legacy template passes it, and so do
// the pilots' real files (#392's "Done when"). testdata/pilot.devcontainer.json is
// terraform-cloudflare-dns's at 922e9c6; terraform-microsoft365-entra's was byte-identical on
// 2026-11-02 (it is private, so it is not copied here).
func TestPlainAcceptsLegacyAndPilot(t *testing.T) {
	for _, name := range []string{"legacy.devcontainer.json", "pilot.devcontainer.json"} {
		src := testdata(t, name)
		if err := Check([]byte(src)); err != nil {
			t.Fatalf("%s: Check: %v", name, err)
		}
		if err := CheckPlain([]byte(src)); err != nil {
			t.Fatalf("%s: CheckPlain: %v", name, err)
		}
	}
}

// The template is dev-App only now, so it must never again be accepted by plain mode: a plain
// repo that copies it would be dev-App by its markers and fail the head-must-be-dev-App rule.
func TestTemplateIsNotPlain(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "template", ".devcontainer", "devcontainer.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := CheckPlain(b); !check.IsFailure(err) {
		t.Fatalf("the dev-App template passes plain mode: %v", err)
	}
}

func TestPlainAcceptsAPerRepoVolume(t *testing.T) {
	src := strings.Replace(testdata(t, "legacy.devcontainer.json"),
		`"source=${localWorkspaceFolderBasename}-tmp,target=/tmp,type=volume",`,
		`"source=${localWorkspaceFolderBasename}-tmp,target=/tmp,type=volume", "source=${localWorkspaceFolderBasename}-cargo_cache,target=/home/app/.cargo,type=volume",`, 1)
	if err := CheckPlain([]byte(src)); err != nil {
		t.Fatal(err)
	}
	// A comment that names a host variable is not a value.
	if err := CheckPlain([]byte("// ${localEnv:HOME}\n" + testdata(t, "legacy.devcontainer.json"))); err != nil {
		t.Fatal(err)
	}
}

func TestPlainRejects(t *testing.T) {
	legacy := testdata(t, "legacy.devcontainer.json")
	tmpMount := `"source=${localWorkspaceFolderBasename}-tmp,target=/tmp,type=volume",`
	addMount := func(m string) string { return strings.Replace(legacy, tmpMount, tmpMount+" "+m+",", 1) }
	addKey := func(kv string) string {
		return strings.Replace(legacy, `"remoteUser": "app",`, `"remoteUser": "app", `+kv+",", 1)
	}
	cases := map[string]string{
		// The cloud-credential guard (#392): no host bind beyond the template's own.
		"aws bind":                addMount(`"source=${localEnv:USERPROFILE}/.aws,target=/home/app/.aws,type=bind,readonly"`),
		"absolute host bind":      addMount(`"source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"`),
		"volume plus a key":       addMount(`"source=${localWorkspaceFolderBasename}-x,target=/x,type=volume,readonly"`),
		"shared volume":           addMount(`"source=other,target=/x,type=volume"`),
		"volume target var":       addMount(`"source=${localWorkspaceFolderBasename}-x,target=/${localEnv:HOME},type=volume"`),
		"object-form mount":       addMount(`{"source": "x", "target": "/x", "type": "volume"}`),
		"mounts not a list":       strings.Replace(legacy, `"mounts": [`, `"mounts": "x", "unused": [`, 1),
		"runArgs extra":           strings.Replace(legacy, `"--tmpfs=/var/tmp"`, `"--tmpfs=/var/tmp", "-v=/:/host"`, 1),
		"runArgs dropped":         strings.Replace(legacy, `"--cap-drop=ALL", `, ``, 1),
		"runArgs reordered":       strings.Replace(legacy, `"--cap-drop=ALL", "--security-opt=no-new-privileges"`, `"--security-opt=no-new-privileges", "--cap-drop=ALL"`, 1),
		"runArgs absent":          strings.Replace(legacy, `"runArgs"`, `"unusedRunArgs"`, 1),
		"workspaceMount moved":    strings.Replace(legacy, `consistency=cached`, `consistency=delegated`, 1),
		"workspaceMount absent":   strings.Replace(legacy, `"workspaceMount"`, `"unusedMount"`, 1),
		"workspaceFolder":         strings.Replace(legacy, `"workspaceFolder": "/workspace"`, `"workspaceFolder": "/"`, 1),
		"appPort":                 addKey(`"appPort": "127.0.0.1:8080:8080"`),
		"privileged":              addKey(`"privileged": true`),
		"capAdd":                  addKey(`"capAdd": ["SYS_ADMIN"]`),
		"securityOpt":             addKey(`"securityOpt": ["seccomp=unconfined"]`),
		"initializeCommand":       addKey(`"initializeCommand": "calc.exe"`),
		"initializeCommand, case": addKey(`"InitializeCommand": "calc.exe"`),
		"containerEnv localEnv":   addKey(`"containerEnv": {"T": "${localEnv:GH_TOKEN}"}`),
		"remoteEnv env alias":     addKey(`"remoteEnv": {"T": "${env:GH_TOKEN}"}`),
		"nested localEnv":         addKey(`"customizations2": {"a": ["${localEnv:X}"]}`),
		"host folder elsewhere":   addKey(`"containerEnv": {"W": "${localWorkspaceFolder}"}`),
		"host var in a key":       addKey(`"containerEnv": {"${localEnv:X}": "y"}`),
		"host folder with an arg": addKey(`"containerEnv": {"W": "${localWorkspaceFolder:x}"}`),
		"legacy string elsewhere": addKey(`"containerEnv": {"M": "` + LegacyWorkspaceMount + `"}`),
	}
	for name, src := range cases {
		t.Run(name, func(t *testing.T) {
			if src == legacy {
				t.Fatal("the mutation did not apply")
			}
			if err := CheckPlain([]byte(src)); !check.IsFailure(err) {
				t.Fatalf("want a check failure, got %v", err)
			}
		})
	}
}
