#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Tests for .claude/hooks/merge-guard.sh, the PreToolUse hook that replaced the
# `gh pr merge` deny rules (#168): every merge blocked as before, except
# /way-of-working:resume's exact cursor-sync merge (v0.16.0 shape, with --admin), which
# goes to an `ask` prompt. --admin anywhere else, and the pre-0.16.0 shape, are blocked.
# Fixtures are hand-built from the GitHub REST shapes (see fixtures/merge-guard).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite merge-guard

HOOK="$ROOT_DIR/.claude/hooks/merge-guard.sh"
OK="gh pr merge 7 --repo 603-Identity/devcontainers --squash --admin --match-head-commit $SHA"
OLD="gh pr merge 7 --repo 603-Identity/devcontainers --squash --match-head-commit $SHA"

# guard <command> [tool]  -> sets RC; stdout and stderr land in SCRATCH.
guard() {
  RC=0
  jq -cn --arg c "$1" --arg t "${2:-Bash}" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}}' |
    CLAUDE_PROJECT_DIR="$ROOT_DIR" bash "$HOOK" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
}
decision() { jq -r '.hookSpecificOutput.permissionDecision // empty' "$SCRATCH/stdout" 2> /dev/null || true; }
expect_pass() { # description command  -> exit 0, no decision, GitHub never asked
  new_scenario merge-guard; guard "$2"
  assert_rc "$1" 0 "$RC"
  assert_eq "$1: no decision" "" "$(cat "$SCRATCH/stdout")"
  assert_log_lacks "$1: no GitHub read" "gh api"
  end_scenario
}
expect_block() { # description command  -> exit 2 (scenario left open for more asserts)
  guard "$2"
  assert_rc "$1" 2 "$RC"
  assert_eq "$1: no decision" "" "$(decision)"
}

# --- the repo config the hook reads is this repo's own ---------------------------------
if grep -q '^repo: 603-Identity/devcontainers' "$ROOT_DIR/.ai/project.yml"; then pass; else fail "fixtures assume repo 603-Identity/devcontainers"; fi

# --- not a merge: left alone, as under the deny rules ---------------------------------
expect_pass "plain command" "ls -la"
expect_pass "a grep that mentions the words" 'grep -n "gh pr merge" README.md'
expect_pass "gh pr view mentioning merged" 'gh pr list --state merged --json mergeStateStatus'
expect_pass "git merge" "git merge --ff-only origin/main"
# Text that only MENTIONS the command: the false positives that blocked #169's own commit.
expect_pass "quoted heredoc commit message" "git commit -q -F - <<'EOF'
feat(claude): x

but the
\`gh pr merge\` deny rules beat every allow rule; gh pr merge 7
EOF
git push -u origin x"
expect_pass "double-quoted delimiter heredoc" 'cat > f <<"EOF"
gh pr merge 7 --squash
EOF'
expect_pass "dash heredoc with tab-indented end" "$(printf 'cat <<-'"'"'EOF'"'"'\n\tgh pr merge 7\n\tEOF\n')"
expect_pass "single-quoted message" "git commit -m 'note: \`gh pr merge\` is denied; gh pr merge 7'"
expect_pass "multi-line double-quoted body" 'gh pr create --title t --body "line one
gh pr merge in a body line; also | gh pr merge 7"'
expect_pass "escaped backticks in double quotes" 'gh pr comment 5 --body "use \`gh pr merge\` here"'
expect_pass "comment" "ls # then gh pr merge 7"
expect_pass "comment after a separator" "ls; # x; gh pr merge 7"
expect_pass "grep -c on the words" 'grep -c "gh pr merge" README.md'
expect_pass "unquoted heredoc mentioning the words" "cat <<EOF
gh pr merge 7; echo \$HOME
EOF"
new_scenario merge-guard
RC=0; printf 'not json, no keyword' | bash "$HOOK" > /dev/null 2>&1 || RC=$?
assert_rc "non-JSON input without the keyword" 0 "$RC"
end_scenario

# --- the cursor-sync merge: asked, never allowed outright ------------------------------
new_scenario merge-guard
guard "$OK"
assert_rc "cursor-sync merge" 0 "$RC"
assert_eq "cursor-sync merge: forced prompt" ask "$(decision)"
assert_log_has "cursor-sync merge: PR read" "gh api repos/603-Identity/devcontainers/pulls/7 "
assert_log_has "cursor-sync merge: files read" "repos/603-Identity/devcontainers/pulls/7/files"
end_scenario

new_scenario merge-guard
guard "$OK" PowerShell
assert_eq "cursor-sync merge from PowerShell: forced prompt" ask "$(decision)"
end_scenario

new_scenario merge-guard
guard "
  $OK  "
assert_eq "surrounding whitespace is trimmed" ask "$(decision)"
end_scenario

# --- every other merge shape is blocked before GitHub is asked -------------------------
for c in \
  "gh pr merge 7 --squash" \
  "$OLD" \
  "gh pr merge 7 --admin" \
  "gh pr merge 7 --squash --admin" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --squash --admin" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --admin --squash --match-head-commit $SHA" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --squash --match-head-commit $SHA --admin" \
  "$OK --admin" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --merge --admin --match-head-commit $SHA" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --squash --admin --auto --match-head-commit $SHA" \
  "gh pr merge 7 --repo other/fork --squash --admin --match-head-commit $SHA" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --squash --match-head-commit $SHA --auto" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --merge --match-head-commit $SHA" \
  "gh pr merge 7 --repo 603-Identity/devcontainers --squash --match-head-commit ${SHA:0:12}" \
  "gh pr merge --repo 603-Identity/devcontainers --squash" \
  "echo hi && $OK" \
  "$OK; rm -rf x" \
  "$OK
rm -rf x" \
  "GH_TOKEN=x $OK" \
  'x=$(gh pr merge 7 --squash)' \
  'echo `gh pr merge 7`' \
  "true || gh pr merge 7" \
  "& gh pr merge 7 --squash" \
  "gh.exe pr merge 7 --squash" \
  "gh pr merge 7 --repo other/fork --squash --match-head-commit $SHA" \
  'echo "x $(gh pr merge 7) y"' \
  'echo "x `gh pr merge 7` y"' \
  'echo "x $(echo $(gh pr merge 7)) y"' \
  "bash -c 'gh pr merge 7'" \
  "bash -lc 'gh pr merge 7'" \
  'sh -c "gh pr merge 7"' \
  "bash -x -c 'gh pr merge 7'" \
  'eval "gh pr merge 7"' \
  "pwsh -Command 'gh pr merge 7'" \
  "iex 'gh pr merge 7'" \
  'cat <<EOF
$(gh pr merge 7)
EOF' \
  'cat <<EOF
`gh pr merge 7`
EOF' \
  "cat <<'EOF'
text
EOF
gh pr merge 7" \
  "cat <<'EOF'
never closed
gh pr merge 7" \
  "echo 'unterminated; gh pr merge 7" \
  "ls #comment
gh pr merge 7" \
  "echo a#b; gh pr merge 7"; do
  new_scenario merge-guard
  expect_block "blocked shape: $c" "$c"
  assert_log_lacks "blocked shape: $c: no GitHub read" "gh api"
  end_scenario
done

# --- the right shape, but GitHub says it is not a cursor-sync PR -----------------------
github_block() { # description jq-filter-on-pulls__7 [jq-filter-on-files]
  new_scenario merge-guard
  mut pulls__7 "$2"
  [ -z "${3:-}" ] || mut pulls__7__files "$3"
  expect_block "--admin shape, $1" "$OK"
  end_scenario
}
github_block "closed PR" '.state = "closed"'
github_block "other base" '.base.ref = "release"'
github_block "not a sync branch" '.head.ref = "feat/x"'
github_block "bare sync prefix" '.head.ref = "docs/sync-cursor-"'
github_block "head moved" '.head.sha = "0000000000000000000000000000000000000000"'
github_block "fork head" '.head.repo.full_name = "someone/devcontainers"'
github_block "deleted fork head" '.head.repo = null'
github_block "extra file" '.' '. + [{"filename": "README.md"}]'
github_block "parked sprint file" '.' '. + [{"filename": ".ai/parked/x.md"}]'
github_block "wrong single file" '.' '[{"filename": ".ai/state.json"}]'
github_block "no files" '.' '[]'

new_scenario merge-guard
status_of pulls__7 neterr
expect_block "GitHub unreachable" "$OK"
end_scenario

new_scenario merge-guard
drop pulls__7__files
expect_block "files unreadable" "$OK"
end_scenario

new_scenario merge-guard
RC=0
jq -cn --arg c "$OK" '{tool_input: {command: $c}}' |
  CLAUDE_PROJECT_DIR="$SCRATCH/nowhere" bash "$HOOK" > /dev/null 2> "$SCRATCH/stderr" || RC=$?
assert_rc "no .ai/project.yml" 2 "$RC"
end_scenario

summary
