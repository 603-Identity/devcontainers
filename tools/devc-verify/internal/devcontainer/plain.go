package devcontainer

import (
	"bytes"
	"encoding/json"
	"regexp"
	"slices"
	"strings"

	"github.com/tailscale/hujson"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

// The legacy (PAT-route) template's container settings: template/.devcontainer/devcontainer.json
// as v1.5 shipped it, before #418's PR D made the template dev-App only. Plain mode (#392) is an
// allowlist built from these strings. They are written out here, not read from the template,
// because the template stops carrying them; testdata/legacy.devcontainer.json is that file, and
// a test proves it passes.
var (
	LegacyRunArgs = []string{
		"--cap-drop=ALL", "--security-opt=no-new-privileges",
		"--read-only", "--tmpfs=/run", "--tmpfs=/var/tmp",
	}
	LegacyMounts = []string{
		"source=${localEnv:HOME}${localEnv:USERPROFILE}/.gitconfig.d,target=/home/app/.gitconfig.d,type=bind,readonly",
		"source=${localWorkspaceFolderBasename}-home,target=/home/app,type=volume",
		"source=${localWorkspaceFolderBasename}-tmp,target=/tmp,type=volume",
		"source=devc-tofu-plugins,target=/home/app/.cache/tofu-plugins,type=volume",
		"source=${localWorkspaceFolderBasename}-node_modules,target=/workspace/node_modules,type=volume",
		"source=${localWorkspaceFolderBasename}-venv,target=/workspace/.venv,type=volume",
	}
)

const (
	LegacyWorkspaceFolder = "/workspace"
	LegacyWorkspaceMount  = "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
)

// volumeMount is the one mount shape plain mode accepts besides LegacyMounts: a per-repo named
// volume, no other keys.
var volumeMount = regexp.MustCompile(`^source=\$\{localWorkspaceFolderBasename\}-[a-z_]+,target=/[^,]+,type=volume$`)

// plainForbidden holds the lowercased top-level keys plain mode rejects: each one widens what
// the container can reach on the host (a port, privileges, a host command before the build).
// The match ignores letter case, which is stricter than the devcontainer tooling.
var plainForbidden = []string{"appport", "privileged", "capadd", "securityopt", "initializecommand"}

// hostVars are the substitutions that read the host: its environment (the devcontainer CLI
// reads `${env:` as `${localEnv:`), or the checkout's host path (with or without an argument
// after a colon, which the CLI ignores; ${localWorkspaceFolderBasename} is the folder's name
// only, and allowed). Plain mode rejects them in every string, keys included, outside the
// exact legacy strings above (containerEnv and remoteEnv too).
var hostVars = []string{"${localEnv:", "${env:", "${localWorkspaceFolder}", "${localWorkspaceFolder:"}

// CheckPlain applies plain mode's allowlist to a devcontainer.json that already passed Check.
// It is the cloud-credential guard (#392) widened: no host bind, port or host command can be
// added, so a credential directory such as ~/.aws cannot be mounted.
func CheckPlain(data []byte) error {
	std, err := hujson.Standardize(bytes.Clone(data)) // a copy: Standardize blanks comments in place
	if err != nil {
		return check.Failf("devcontainer.json is not valid JSON with comments: %q", err.Error())
	}
	var top map[string]any
	if err := json.Unmarshal(std, &top); err != nil || top == nil {
		return check.Failf("devcontainer.json is not a JSON object")
	}
	for _, k := range sortedKeys(top) {
		if slices.Contains(plainForbidden, strings.ToLower(k)) {
			return check.Failf("devcontainer.json key %q is not allowed", k)
		}
	}

	if err := equalStrings(top, "runArgs", LegacyRunArgs); err != nil {
		return err
	}
	for _, kv := range [][2]string{{"workspaceFolder", LegacyWorkspaceFolder}, {"workspaceMount", LegacyWorkspaceMount}} {
		if got, ok := top[kv[0]].(string); !ok || got != kv[1] {
			return check.Failf("devcontainer.json %s must be the string %q, as in the template", kv[0], kv[1])
		}
	}

	var exactMounts []bool // exactMounts[i]: mounts[i] is one of LegacyMounts
	if raw, ok := top["mounts"]; ok {
		mounts, ok := raw.([]any)
		if !ok {
			return check.Failf("devcontainer.json mounts must be a list of strings")
		}
		exactMounts = make([]bool, len(mounts))
		for i, m := range mounts {
			s, ok := m.(string)
			if !ok {
				return check.Failf("devcontainer.json mounts[%d] is not a string; the object form is not allowed", i)
			}
			switch {
			case slices.Contains(LegacyMounts, s):
				exactMounts[i] = true
			case volumeMount.MatchString(s):
			default:
				return check.Failf("devcontainer.json mount %q is neither a template mount nor a per-repo volume", s)
			}
		}
	}

	// Every key and string reads no host value, except the exact legacy strings in their own
	// places: workspaceMount (checked above) and the LegacyMounts entries of mounts.
	for _, k := range sortedKeys(top) {
		v := top[k]
		if hasHostVar(k) {
			return check.Failf("devcontainer.json key %q reads the host", k)
		}
		switch k {
		case "workspaceMount":
			continue
		case "mounts":
			for i, m := range v.([]any) {
				if !exactMounts[i] {
					if err := noHostVars(m); err != nil {
						return err
					}
				}
			}
			continue
		}
		if err := noHostVars(v); err != nil {
			return err
		}
	}
	return nil
}

// equalStrings requires top[key] to be exactly the list want.
func equalStrings(top map[string]any, key string, want []string) error {
	raw, _ := top[key].([]any)
	got := make([]string, 0, len(raw))
	for _, v := range raw {
		s, ok := v.(string)
		if !ok {
			break
		}
		got = append(got, s)
	}
	if len(got) != len(raw) || !slices.Equal(got, want) {
		return check.Failf("devcontainer.json %s must be exactly %q, as in the template", key, want)
	}
	return nil
}

// noHostVars rejects a host substitution in any key or string of v.
func noHostVars(v any) error {
	switch v := v.(type) {
	case map[string]any:
		for _, k := range sortedKeys(v) {
			if hasHostVar(k) {
				return check.Failf("devcontainer.json key %q reads the host", k)
			}
			if err := noHostVars(v[k]); err != nil {
				return err
			}
		}
	case []any:
		for _, e := range v {
			if err := noHostVars(e); err != nil {
				return err
			}
		}
	case string:
		if hasHostVar(v) {
			return check.Failf("devcontainer.json value %q reads the host (${localEnv:...} or ${localWorkspaceFolder})", v)
		}
	}
	return nil
}

func hasHostVar(s string) bool {
	for _, h := range hostVars {
		if strings.Contains(s, h) {
			return true
		}
	}
	return false
}

// sortedKeys returns m's keys in order, so a file with two violations always reports the same one.
func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	return keys
}
