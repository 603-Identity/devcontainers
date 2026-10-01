// Package devcontainer checks a consumer's .devcontainer/devcontainer.json: it must build
// from the sibling Dockerfile and from nothing else.
package devcontainer

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strings"

	"github.com/tailscale/hujson"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

const (
	maxSize  = 1 << 20
	maxDepth = 64
)

// forbidden holds the lowercased top-level key names that select an image source. Only the
// exact key "build" survives; every other casing (L8: Go's struct decoding is
// case-insensitive, the devcontainer tooling's is not) is rejected.
var forbidden = map[string]bool{
	"image": true, "dockerfile": true, "context": true,
	"dockercomposefile": true, "features": true, "build": true,
}

// Check applies the devcontainer.json rules. A violation, including text that is not
// JSON-with-comments, is a *check.Failure.
func Check(data []byte) error {
	if len(data) > maxSize {
		return check.Failf("devcontainer.json is larger than %d bytes", maxSize)
	}
	std, err := hujson.Standardize(data)
	if err != nil {
		return check.Failf("devcontainer.json is not valid JSON with comments: %q", err.Error())
	}

	// Decoding into a map silently keeps the last of two equal keys, so find duplicates
	// with a token walk. Tokens carry the JSON-unescaped key: "build" duplicates build.
	dec := json.NewDecoder(bytes.NewReader(std))
	if err := walk(dec, 0); err != nil {
		return err
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return check.Failf("devcontainer.json has data after its top-level value")
	}

	var top map[string]json.RawMessage
	if err := json.Unmarshal(std, &top); err != nil || top == nil {
		return check.Failf("devcontainer.json is not a JSON object")
	}
	for k := range top {
		if forbidden[strings.ToLower(k)] && k != "build" {
			return check.Failf("devcontainer.json key %q is not allowed", k)
		}
	}
	rawBuild, ok := top["build"]
	if !ok {
		return check.Failf(`devcontainer.json has no "build" object`)
	}
	var build map[string]json.RawMessage
	if err := json.Unmarshal(rawBuild, &build); err != nil || build == nil {
		return check.Failf(`devcontainer.json "build" is not an object`)
	}
	for k, v := range build {
		var want string
		switch k {
		case "dockerfile":
			want = "Dockerfile"
		case "context":
			want = "."
		default:
			return check.Failf("devcontainer.json build key %q is not allowed", k)
		}
		var got string
		if err := json.Unmarshal(v, &got); err != nil || got != want {
			return check.Failf("devcontainer.json build.%s must be the string %q", k, want)
		}
	}
	if _, ok := build["dockerfile"]; !ok {
		return check.Failf(`devcontainer.json build.dockerfile is required`)
	}
	return nil
}

// walk consumes one JSON value from dec, rejecting duplicate keys at every depth.
func walk(dec *json.Decoder, depth int) error {
	if depth > maxDepth {
		return check.Failf("devcontainer.json is nested deeper than %d levels", maxDepth)
	}
	tok, err := dec.Token()
	if err != nil {
		return check.Failf("devcontainer.json does not tokenize: %q", err.Error())
	}
	d, ok := tok.(json.Delim)
	if !ok {
		return nil
	}
	switch d {
	case '{':
		seen := map[string]bool{}
		for dec.More() {
			kt, err := dec.Token()
			if err != nil {
				return check.Failf("devcontainer.json does not tokenize: %q", err.Error())
			}
			key, _ := kt.(string)
			if seen[key] {
				return check.Failf("devcontainer.json has the duplicate key %q", key)
			}
			if key == "__proto__" {
				return check.Failf("devcontainer.json has a \"__proto__\" key")
			}
			seen[key] = true
			if err := walk(dec, depth+1); err != nil {
				return err
			}
		}
	case '[':
		for dec.More() {
			if err := walk(dec, depth+1); err != nil {
				return err
			}
		}
	}
	if _, err := dec.Token(); err != nil { // the closing delimiter
		return check.Failf("devcontainer.json does not tokenize: %q", err.Error())
	}
	return nil
}
