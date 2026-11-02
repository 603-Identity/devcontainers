package devapp

import (
	"bytes"
	"encoding/json"
	"fmt"
	"reflect"
	"regexp"
	"strconv"
	"strings"

	"github.com/tailscale/hujson"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

// The token mount: surface 1. The part between tokenPrefix and tokenSuffix is OWNER/REPO.
const (
	tokenPrefix = "source=${localEnv:USERPROFILE}/.config/glunk-identity/tokens/"
	tokenSuffix = ",target=/run/wow,type=bind,readonly"
	placeholder = "OWNER/REPO"
	maxAppPorts = 5
)

// appPortRE is surface 4's one shape: a loopback-only host port. The numbers are checked below.
var appPortRE = regexp.MustCompile(`^127\.0\.0\.1:([1-9][0-9]{3,4}):([1-9][0-9]{3,4})$`)

// Candidate is one dev-App template devcontainer.json the head may match: the template at the
// verifier's pin, or the previous release's snapshot.
type Candidate struct {
	Name string // for messages: "the template at this pin", "the previous release's snapshot"
	Data []byte
}

// CompareJSON checks a head devcontainer.json (already through devcontainer.Check) in
// dev-App mode: the token mount names repo, appPort is loopback only, and with those two
// surfaces taken out the file equals one of the candidates, compared as parsed JSON (so
// comments, whitespace and key order do not matter, and nothing else may differ). A candidate
// that is not itself dev-App is never used. It returns a *check.Failure when nothing matches.
func CompareJSON(head []byte, repo string, candidates []Candidate) error {
	if err := ValidateRepo(repo); err != nil {
		return err
	}
	h, err := normalize(head, repo)
	if err != nil {
		return err
	}
	var tried []string
	for _, c := range candidates {
		if c.Data == nil || !HasMarker(c.Data) {
			continue
		}
		t, err := normalize(c.Data, "")
		if err != nil {
			// Not wrapped: a template that does not load is the verifier's own fault, never a "no".
			return fmt.Errorf("%s does not load: %v", c.Name, err)
		}
		if reflect.DeepEqual(h, t) {
			return nil
		}
		tried = append(tried, c.Name)
	}
	if len(tried) == 0 {
		return check.Failf("the verifier at this pin carries no dev-App template; pin a release that does")
	}
	return check.Failf("devcontainer.json differs from %s outside the token mount name and appPort", strings.Join(tried, " and from "))
}

// normalize parses a devcontainer.json and takes out the two JSON surfaces. For the head
// (repo != "") it also checks them; for a template it only replaces the token directory with
// the placeholder.
func normalize(data []byte, repo string) (map[string]any, error) {
	std, err := hujson.Standardize(bytes.Clone(data)) // a copy: Standardize blanks comments in place
	if err != nil {
		return nil, check.Failf("devcontainer.json is not valid JSON with comments: %q", err.Error())
	}
	var top map[string]any
	if err := json.Unmarshal(std, &top); err != nil || top == nil {
		return nil, check.Failf("devcontainer.json is not a JSON object")
	}

	mounts, _ := top["mounts"].([]any)
	found := 0
	for i, m := range mounts {
		s, ok := m.(string)
		if !ok {
			continue
		}
		dir, ok := strings.CutPrefix(s, tokenPrefix)
		if !ok {
			continue
		}
		dir, ok = strings.CutSuffix(dir, tokenSuffix)
		if !ok {
			continue
		}
		found++
		if repo != "" && dir != repo {
			return nil, check.Failf("the token mount names %q, but this repository is %q (case-sensitive, in GitHub's canonical case)", dir, repo)
		}
		mounts[i] = tokenPrefix + placeholder + tokenSuffix
	}
	if found != 1 {
		return nil, check.Failf("devcontainer.json has %d token mounts (%s<OWNER>/<REPO>%s); exactly 1 is required", found, tokenPrefix, tokenSuffix)
	}

	if v, ok := top["appPort"]; ok {
		if repo != "" {
			if err := checkAppPort(v); err != nil {
				return nil, err
			}
		}
		delete(top, "appPort")
	}
	return top, nil
}

// checkAppPort accepts a string or a list of up to maxAppPorts strings, each
// 127.0.0.1:<host>:<container> with both ports in 1024..65535.
func checkAppPort(v any) error {
	var ports []any
	switch v := v.(type) {
	case string:
		ports = []any{v}
	case []any:
		if len(v) == 0 || len(v) > maxAppPorts {
			return check.Failf("appPort lists %d ports; 1 to %d are allowed", len(v), maxAppPorts)
		}
		ports = v
	default:
		return check.Failf("appPort must be a string or a list of strings")
	}
	for _, p := range ports {
		s, ok := p.(string)
		if !ok {
			return check.Failf("appPort entries must be strings like 127.0.0.1:8080:8080")
		}
		m := appPortRE.FindStringSubmatch(s)
		if m == nil {
			return check.Failf("appPort %q is not 127.0.0.1:<host>:<container>", s)
		}
		for _, n := range m[1:] {
			if p, _ := strconv.Atoi(n); p < 1024 || p > 65535 {
				return check.Failf("appPort %q: port %s is outside 1024..65535", s, n)
			}
		}
	}
	return nil
}
