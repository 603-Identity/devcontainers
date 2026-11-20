#!/usr/bin/env bash
# shellcheck disable=SC1091
# Tests for the agent-side deny rules in .claude/settings.json: both `gh pr merge` forms and
# the twelve force-push and --no-verify rules are present, and no `hooks` key is. Offline;
# needs bash and jq. Claude Code's matching of the rules cannot be exercised here, so the
# suite keeps their presence.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

suite settings-deny

SETTINGS="$ROOT_DIR/.claude/settings.json"

REQUIRED='["Bash(gh pr merge:*)","PowerShell(gh pr merge:*)",
"Bash(git push --force:*)","Bash(git push --force-with-lease:*)","Bash(git push -f:*)",
"PowerShell(git push --force:*)","PowerShell(git push --force-with-lease:*)","PowerShell(git push -f:*)",
"Bash(git commit --no-verify:*)","Bash(git commit -n:*)","Bash(git push --no-verify:*)",
"PowerShell(git commit --no-verify:*)","PowerShell(git commit -n:*)","PowerShell(git push --no-verify:*)"]'

# check_settings FILE -> exit 0 only when every required deny string is present and the file has no `hooks` key.
check_settings() {
  jq -e --argjson req "$REQUIRED" \
    '(.permissions.deny // []) as $d | ($req | all(. as $r | $d | index($r) != null)) and (has("hooks") | not)' \
    "$1" > /dev/null 2>&1
}

rc_of() { local rc=0; "$@" || rc=$?; echo "$rc"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

assert_eq "repo settings file passes" 0 "$(rc_of check_settings "$SETTINGS")"

variant() { # name jq-filter -> exit code of the check on a modified copy
  jq "$2" "$SETTINGS" > "$SCRATCH/$1.json"
  rc_of check_settings "$SCRATCH/$1.json"
}

assert_eq "missing Bash gh pr merge deny is refused" 1 \
  "$(variant no-bash-merge 'del(.permissions.deny[] | select(. == "Bash(gh pr merge:*)"))')"
assert_eq "missing PowerShell gh pr merge deny is refused" 1 \
  "$(variant no-ps-merge 'del(.permissions.deny[] | select(. == "PowerShell(gh pr merge:*)"))')"
assert_eq "missing Bash force-push deny is refused" 1 \
  "$(variant no-force 'del(.permissions.deny[] | select(. == "Bash(git push --force:*)"))')"
assert_eq "a hooks object is refused" 1 \
  "$(variant with-hooks '. + {hooks: {PreToolUse: []}}')"

summary
