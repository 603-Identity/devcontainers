#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Tests for .claude/hooks/merge-guard.sh, the PreToolUse hook that replaced the
# `gh pr merge` deny rules (#168): the merge shapes listed below blocked (the hook's header
# names what it cannot see), except
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
  # The envelope Claude Code sends, not a minimal one: its other fields hold the letters of
  # "merge" in order, which an input-wide pre-filter would mistake for a hit on every call.
  jq -cn --arg c "$1" --arg t "${2:-Bash}" '{session_id: "s", transcript_path: "/t.jsonl", cwd: "/w", permission_mode: "default", hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c, description: "Run the command"}, tool_use_id: "toolu_1"}' |
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

# --- not a merge: left alone ---------------------------------------------------------
# The hook looks for `merge` as a word in the command text, with quotes, backslashes and
# backticks removed. Words that only contain it, and git's own merge, are not merges.
expect_pass "plain command" "ls -la"
expect_pass "gh pr list of merged PRs" 'gh pr list --state merged --json mergeStateStatus'
expect_pass "gh pr view of a merged PR" 'gh pr view 5 --json mergedAt,mergeable'
expect_pass "git merge" "git merge --ff-only origin/main"
expect_pass "git merge after a separator" "cd x && git merge origin/main"
expect_pass "git merge with git's own flags" "git -C sub --no-pager -p merge --no-edit topic"
expect_pass "a regex ending in \$ with the letters of merge in the text" "grep -c 'x\$' emergency.txt"
expect_pass "a PowerShell regex ending in \$" "Select-String -Pattern 'x\$' emergency.txt"
expect_pass "a dollar-quoted string without an escape" "echo \$'plain' emergency"
expect_pass "a dollar-quoted string with a newline escape" "printf \$'emergency\\n'"
expect_pass "a regex ending in \$ before a Windows path" 'grep -n '"'"'foo$'"'"' C:\temp\emergency.txt'
expect_pass "Select-String with a Windows path" 'Select-String -Pattern '"'"'exit 0$'"'"' .claude\hooks\emergency.sh'
expect_pass "JSON body, not a brace expansion" "gh api repos/o/r/issues -f title=x --input - <<< '{\"a\":1,\"b\":2}' # emergency"
expect_pass "git merge-base" "git merge-base HEAD origin/main"
expect_pass "git merge-tree" "git merge-tree a b c"
expect_pass "git log --merges" "git log --merges --oneline"
expect_pass "git log --no-merges" "git log --no-merges --oneline"
expect_pass "a commit message that says merged" "git commit -m 'merged the thing'"
expect_pass "the hook's own file name" "git add .claude/hooks/merge-guard.sh"
expect_pass "running the hook's tests" "bash tools/tests/merge-guard-test.sh"
new_scenario merge-guard
RC=0; printf 'not json, no keyword' | bash "$HOOK" > /dev/null 2>&1 || RC=$?
assert_rc "non-JSON input without the keyword" 0 "$RC"
end_scenario
new_scenario merge-guard
RC=0; printf '%s' '{"tool_input":{"command":"gh pr merge\u0000x 5"}}' | bash "$HOOK" > /dev/null 2> "$SCRATCH/stderr" || RC=$?
assert_rc "a NUL byte in the command" 2 "$RC"
end_scenario

# --- mentions are refused too: the documented false blocks -----------------------------
# Telling a mention from a command is the shell-parsing problem the hook gave up on (#170,
# #171). The message points at the way round it (a file written with the Write tool).
mention_blocked() { # description command
  new_scenario merge-guard
  expect_block "false block: $1" "$2"
  assert_log_lacks "false block: $1: no GitHub read" "gh api"
  case "$(cat "$SCRATCH/stderr")" in *"git commit -F"*) pass ;; *) fail "false block: $1: the message does not name the way round" ;; esac
  end_scenario
}
mention_blocked "grep for the words" 'grep -n "gh pr merge" README.md'
mention_blocked "a quoted heredoc commit message" "git commit -q -F - <<'EOF'
feat(claude): x

but the
\`gh pr merge\` deny rules beat every allow rule; gh pr merge 7
EOF
git push -u origin x"
mention_blocked "a commit message with the word" "git commit -m 'fix merge ordering'"
mention_blocked "a PR body with the word" 'gh pr create --title t --body "do not merge yet"'
mention_blocked "a comment" "ls # then merge"
mention_blocked "gh pr list searching for merge" 'gh pr list --search merge'
mention_blocked "echo of the words" 'echo gh pr merge'

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
  'git -C {.,-c,alias.y=!gh,y,pr} merge 7' \
  'git -C .${IFS}-c${IFS}alias.y=!gh${IFS}y${IFS}pr merge 7' \
  'git --git-dir=.git${IFS}-c${IFS}alias.y=!gh${IFS}y${IFS}pr merge 7' \
  'gh pr {m..m..1}erge 5' \
  "g''h pr \$'\\x6d'erge 5" \
  "g\\h pr \$'\\x6d'erge 5" \
  'gh pr {--body=,m}erge 7' \
  'gh pr m{,}erge 5' \
  'gh pr me$()rge 5' \
  'gh pr {m,}erge 5' \
  'gh pr {m..m}erge 7' \
  'gh pr mer{g..g}e 7' \
  'gh pr "`u{6d}erge" 7' \
  'git -c alias.x=!gh${IFS}pr --no-pager x merge 7' \
  'git -p x merge 7' \
  'git -c core.x=1 merge x' \
  'git --version;gh pr merge 5 --squash' \
  'git --version&&gh pr merge 5 --squash' \
  'git -p|gh pr merge 5' \
  'x=$(git -v;gh pr merge 5)' \
  'cd repo;git --no-pager;gh pr merge 5' \
  'git -C;gh pr merge 5' \
  'git merge main;gh pr merge 5' \
  'gh pr merge`true` 5' \
  'gh pr merge`echo -n` 5 --squash' \
  'gh api graphql -f query=mergeBranch' \
  'gh api -X POST repos/603-Identity/devcontainers/merge-upstream' \
  "gh pr \$'\\x6d'erge 1" \
  "gh pr mer\$''ge 1" \
  'gh pr mer$""ge 1' \
  'GH PR MERGE 1' \
  'gh api repos/603-Identity/devcontainers/merges -f base=main -f head=x' \
  'gh pr mer`ge 1' \
  'gh pr mer\
ge 1' \
  'git merge x && gh pr merge 1' \
  'git merge x; gh pr merge 1' \
  'gh api repos/603-Identity/devcontainers/pulls/1/merge -X PUT' \
  'gh alias set m "pr merge"' \
  'gh api graphql -f query=mergePullRequest' \
  'echo gh pr merge 1 | bash' \
  'echo gh pr merge 1 | xargs' \
  'xargs gh pr merge' \
  '{gh,pr} merge 1' \
  '/usr/bin/g[h] pr merge 1' \
  'f(){ gh "$@"; }; f pr merge 1' \
  'bash -c x"; gh pr merge 1"' \
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
  "echo a#b; gh pr merge 7" \
  '"gh" pr merge 1 --admin' \
  'gh "pr" merge 1' \
  "gh pr 'merge' 1" \
  'g\h pr merge 1 --admin' \
  "\$'gh' pr merge 1 --admin" \
  'gh pr -R 603-Identity/devcontainers merge 1 --admin' \
  'gh -R 603-Identity/devcontainers pr merge 1' \
  'env gh pr merge 1' \
  'command gh pr merge 1' \
  'exec gh pr merge 1' \
  'time gh pr merge 1' \
  'nohup gh pr merge 1' \
  'env -i FOO=1 gh pr merge 1' \
  '{ gh pr merge 1; }' \
  'if true; then gh pr merge 1; fi' \
  'if gh pr merge 1; then echo x; fi' \
  'for i in 1; do gh pr merge 1; done' \
  '! gh pr merge 1' \
  '/usr/bin/gh pr merge 1' \
  'gh pr merge 1 "--admin"' \
  "echo ok
\"gh\" pr merge 1" \
  'echo "<<EOF"
gh pr merge 1 --admin
EOF' \
  "cat <<< X
gh pr merge 1 --admin
X" \
  "echo '<<EOF'
gh pr merge 1 --admin
EOF" \
  'echo "line one
<<EOF"
gh pr merge 1 --admin
EOF' \
  'echo \<<EOF
gh pr merge 1 --admin
EOF' \
  'ls # <<EOF
gh pr merge 1 --admin
EOF' \
  'echo ""#; gh pr merge 1' \
  "echo ''#; gh pr merge 1" \
  'cat <<'"'A'"'; echo '"'"'
x'"'"' ; gh pr merge 1
A' \
  'echo "$(printf %s ")<<A")"
gh pr merge 1
A' \
  'echo $((1<<A))
gh pr merge 1
A' \
  "echo \$'\\'' '<<EOF'
gh pr merge 1 --admin
EOF" \
  "echo \$'\\'' ; gh pr merge 1 ; echo '" \
  "\$'\\x67h' pr merge 1 --admin" \
  "\$'g\\150' pr merge 1" \
  'gh pr mer\ge 1 --admin' \
  "gh pr m''erge 1 --admin" \
  'gh pr "merg"e 1 --admin' \
  'cat <<"EOF"x
hi
EOFx
gh pr merge 1 --admin
EOF' \
  'cat <<E\OF
EOF
gh pr merge 1 --admin
E' \
  '>/dev/null gh pr merge 1 --admin' \
  'a+=1 gh pr merge 1 --admin' \
  'eval gh pr merge 1 --admin' \
  'timeout 10 gh pr merge 1' \
  'nice gh pr merge 1' \
  "bash -xc 'gh pr merge 1'" \
  "bash --norc -c 'gh pr merge 1'" \
  "bash -o pipefail -c 'gh pr merge 1'" \
  'eval gh\ pr\ merge\ 1' \
  'bash -c gh\ pr\ merge\ 1' \
  'eval "gh" pr merge 1' \
  'eval "gh pr" merge 1' \
  "eval 'gh pr '\"merge 1\"" \
  "bash -c 'gh \"pr\" merge 1'" \
  "bash -c 'g\\h pr merge 1'" \
  "bash -c \"bash -c 'gh pr merge 1'\"" \
  'gh pr merge>/dev/null 1 --admin' \
  'gh pr merge</dev/null 1' \
  'gh 2>/dev/null pr merge 1' \
  'gh pr >/dev/null merge 1' \
  "$(printf 'true \r#; gh pr merge 1')" \
  "$(printf 'true \v#; gh pr merge 1')" \
  "$(printf 'true \f#; gh pr merge 1')" \
  'echo ${x:- #}; gh pr merge 1 --admin' \
  'echo $[1<<X]
gh pr merge 1 --admin
X]' \
  'echo ${x:-<<X}
gh pr merge 1 --admin
X}' \
  '(( x = 1
<<X ))
gh pr merge 1 --admin
X' \
  "cat <<A <<'B'
a
A
b <<C
B
gh pr merge 1
C" \
  'function f { gh pr merge 1 --admin; }; f' \
  'winpty gh pr merge 1' \
  'gh >| out.txt pr merge 1' \
  'gh >&2 pr merge 1' \
  'gh 2>&1 pr merge 1' \
  'gh &>/dev/null pr merge 1' \
  "bash -ce 'gh pr merge 1'" \
  "bash -c -- 'gh pr merge 1'" \
  "bash -c -e 'gh pr merge 1'" \
  'bash -c -- gh\ pr\ merge\ 1' \
  "bash -c \"bash -c 'bash -c \\\"bash -c \\\\\\\"gh pr merge 1\\\\\\\"\\\"'\"" \
  '(true)#<<EOF
gh pr merge 1 --admin
EOF' \
  'echo "$(case a in a) echo "<<EOF " ;; esac)"
gh pr merge 1
EOF' \
  'echo $(echo a)#; gh pr merge 1' \
  'x=$(true)#; gh pr merge 1' \
  'echo "`date`"; cat > n.md <<'"'EOF'"'
don'"'"'t
EOF
gh pr merge 1 && echo '"'done'" \
  'cat <<A <<B
a
A
it'"'"'s
B
gh pr merge 1 && echo '"'ok'" \
  'cat <<E\ F
x
E F
gh pr merge 1
E' \
  "cat <<'E O F'
x
E O F
gh pr merge 1
E" \
  'coproc gh pr merge 1' \
  'GH pr merge 1' \
  '/usr/bin/GH.EXE pr merge 1' \
  '"C:\Program Files\GitHub CLI\gh.exe" pr merge 1'; do
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
github_block "ledger removed" '.' '[{"filename": ".ai/next-steps.md", "status": "removed"}]'
github_block "ledger renamed onto its name" '.' '[{"filename": ".ai/next-steps.md", "previous_filename": "NOTES.md", "status": "renamed"}]'
github_block "ledger mode-only change" '.' '[{"filename": ".ai/next-steps.md", "status": "changed"}]'
github_block "ledger added" '.' '[{"filename": ".ai/next-steps.md", "status": "added"}]'
github_block "ledger with no status" '.' '[{"filename": ".ai/next-steps.md"}]'
github_block "ledger twice" '.' '. + .'

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
