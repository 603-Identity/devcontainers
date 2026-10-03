#!/usr/bin/env bash
# Tests for tools/secret-scan-lint.sh: what a repo's betterleaks.toml may and may not say.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LINT="$TOOLS_DIR/secret-scan-lint.sh"
EXT='[extend]
path = "/usr/local/share/devc/secret-scan/org.toml"'

suite "secret-scan-lint"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

lint() { # name expected-rc toml [expected stderr substring]
  printf '%s\n' "$3" > "$T/c.toml"
  local rc=0
  bash "$LINT" "$T/c.toml" > /dev/null 2> "$T/err" || rc=$?
  assert_rc "$1" "$2" "$rc"
  if [ -n "${4:-}" ]; then
    if grep -qF -- "$4" "$T/err"; then pass; else fail "$1" "stderr lacks '$4': $(cat "$T/err")"; fi
  fi
}

lint "extend only" 0 "$EXT"
lint "extend plus a new repo rule" 0 "$EXT
[[rules]]
id = \"repo-internal-token\"
description = \"x\"
regex = 'itk_[a-z0-9]{20}'
keywords = [\"itk_\"]
path = '\\.tf\$'
confidence = \"high\""
lint "title is allowed" 0 "title = \"x\"
$EXT"

lint "no extend" 1 "title = \"x\"" "[extend] is required"
lint "wrong extend path" 1 '[extend]
path = "/tmp/evil.toml"' "[extend] path must be exactly"
lint "extend with useDefault" 1 "$EXT
useDefault = false" "[extend] key not allowed: useDefault"
lint "extend with a second key" 1 "$EXT
disabledRules = [\"x\"]" "[extend] key not allowed: disabledRules"
lint "top-level useDefault" 1 "useDefault = false
$EXT" "top-level key not allowed: useDefault"
lint "top-level disabledRules" 1 "disabledRules = [\"generic-api-key\"]
$EXT" "top-level key not allowed: disabledRules"
lint "top-level prefilter" 1 "prefilter = 'true'
$EXT" "top-level key not allowed: prefilter"
lint "top-level filter" 1 "filter = 'true'
$EXT" "top-level key not allowed: filter"
lint "unknown top-level key" 1 "frobnicate = 1
$EXT" "top-level key not allowed: frobnicate"
lint "overriding an org rule id" 1 "$EXT
[[rules]]
id = \"org-passphrase\"
regex = 'x'" "id must match"
lint "overriding a default rule id" 1 "$EXT
[[rules]]
id = \"generic-api-key\"
regex = 'x'" "id must match"
for k in "filter = 'true'" "skipReport = true" "validate = 'x'" "analyze = 'x'" "revoke = 'x'" "entropy = 3.5"; do
  lint "rule with ${k%% =*}" 1 "$EXT
[[rules]]
id = \"repo-a\"
regex = 'x'
$k" "key not allowed: ${k%% =*}"
done
lint "rule with an allowlist table" 1 "$EXT
[[rules]]
id = \"repo-a\"
regex = 'x'
[[rules.allowlists]]
regexes = ['.*']" "key not allowed: allowlists"
lint "not TOML" 1 "this is = = not toml [" "not valid TOML"

rc=0; bash "$LINT" > /dev/null 2>&1 || rc=$?; assert_rc "no argument" 2 "$rc"
rc=0; bash "$LINT" "$T/missing.toml" > /dev/null 2>&1 || rc=$?; assert_rc "missing file" 2 "$rc"

summary
