// Package audit holds one test: spec section 8 "Parser residual". The pure-Go parsers read
// PR bytes in a read-only job, so the build graph of the binary is checked for cgo and for
// unsafe in our own code.
package audit

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
)

const ownModule = "github.com/603-identity/devcontainers/tools/devc-verify"

type pkg struct {
	ImportPath string
	Standard   bool
	CgoFiles   []string
	Imports    []string
	Module     *struct{ Path string }
}

func goBin() string {
	if p, err := exec.LookPath("go"); err == nil {
		return p
	}
	return filepath.Join(runtime.GOROOT(), "bin", "go")
}

// list returns the build graph of the binary (not its tests) under the given cgo setting.
func list(t *testing.T, cgo string) []pkg {
	t.Helper()
	cmd := exec.Command(goBin(), "list", "-deps", "-json", "../..")
	cmd.Env = append(os.Environ(), "CGO_ENABLED="+cgo, "GOFLAGS=-mod=vendor", "GOPROXY=off", "GOWORK=off", "GOTOOLCHAIN=local")
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("go list: %v", err)
	}
	var pkgs []pkg
	dec := json.NewDecoder(strings.NewReader(string(out)))
	for dec.More() {
		var p pkg
		if err := dec.Decode(&p); err != nil {
			t.Fatal(err)
		}
		pkgs = append(pkgs, p)
	}
	if len(pkgs) < 10 {
		t.Fatalf("suspiciously small build graph: %d packages", len(pkgs))
	}
	return pkgs
}

// No package outside the standard library may use cgo, and the module must have no
// package that imports "C" under either setting.
func TestNoCgoOutsideStdlib(t *testing.T) {
	for _, cgo := range []string{"0", "1"} {
		for _, p := range list(t, cgo) {
			if p.Standard {
				continue
			}
			if len(p.CgoFiles) != 0 || slices.Contains(p.Imports, "C") {
				t.Errorf("CGO_ENABLED=%s: %s uses cgo (%v)", cgo, p.ImportPath, p.CgoFiles)
			}
		}
	}
}

// Our own packages must not import unsafe. Vendored and standard-library packages that do
// are logged, not failed: many legitimately do (reflect, sync/atomic, protobuf).
func TestNoUnsafeInOurPackages(t *testing.T) {
	var vendored []string
	for _, p := range list(t, "0") {
		if !slices.Contains(p.Imports, "unsafe") || p.Standard {
			continue
		}
		if p.Module != nil && p.Module.Path == ownModule {
			t.Errorf("%s imports unsafe", p.ImportPath)
			continue
		}
		vendored = append(vendored, p.ImportPath)
	}
	t.Logf("vendored packages in the binary's build graph that import unsafe: %q", vendored)
}
