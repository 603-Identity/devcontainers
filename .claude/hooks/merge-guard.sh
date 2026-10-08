#!/usr/bin/env bash
# PreToolUse hook for the Bash and PowerShell tools, standing in for the `gh pr merge`
# deny rules (#168). In Claude Code a deny rule wins over every allow rule and hook, so it
# could not make room for the one merge /way-of-working:resume (0.16.0+) makes on the
# human's explicit confirmation: a handoff cursor-sync PR. This hook refuses any command
# that mentions a merge, except /resume's exact command shape against a PR that GitHub
# confirms is a cursor-sync PR. Even that one goes to a permission prompt (`ask`), never
# straight through.
#
# THIS IS A SEATBELT, NOT A LOCK. It stops a model that merges by mistake, by writing the
# command the way people write it. It cannot stop one that is trying to: the agent's shell
# runs `gh` as the owner's admin login, so it could also delete the rulesets, post the review
# that turns architect-review green, or call the API with curl, and none of that is a command
# this hook can tell apart from any other. Whether a shell command runs a merge cannot be
# decided from its text (the word can be built at run time), so this hook does not try: it
# over-approximates. A real boundary needs the agent's credential to be unable to merge or
# bypass; docs/threat_model.md does not yet say so (#172 tracks the residuals there).
#
# How it decides. The command is lowercased and its quotes, backslashes and backticks are
# deleted (and, in a second reading, backticks become a break), which removes the quoting and
# escaping of both bash and PowerShell (`"gh" pr
# 'mer'ge`, `g\h pr mer\ge`, a backslash-newline join). A `$'..'` string with a \x, \u or
# octal escape, a brace expansion (`{a..b}`, `{x,y}`) and a PowerShell `u{..} escape are
# refused when the command also holds the letters of merge or a gh word, since they can
# spell a letter the deletion would not undo (`$'\x6d'erge`). If `merge` is not left
# in the text followed by a non-letter, the call is not this hook's business: `merged`,
# `mergeable`, `mergeStateStatus` and `--no-merges` hold the letters but are not merges, nor
# is `git merge ...` at the start of a command, nor the git plumbing `merge-base`,
# `merge-tree`, `merge-file`, `merge-index`, `merge-one-file`, `merge-recursive`,
# `merge-resolve`, `merge-octopus`, `merge-ours`, `merge-subtree`, nor this hook's own name
# `merge-guard`. (The GraphQL names
# `mergePullRequest` and `mergeBranch`, the REST path `/merges`, and `merge-upstream` are
# merges.) Anything else holding it is refused unless the whole
# command is the admitted shape. The word is looked for in the text as written, so the
# shapes the parser version of this hook chased one by one (wrappers, `eval`, `bash -c`,
# `gh pr -R x merge`, heredocs, `gh api .../merge`, aliases, `xargs`, `{gh,pr} merge`) are
# refused without being recognised.
#
# Mentions are refused too, on purpose: a commit message, PR body, `grep` or heredoc that
# contains the word `merge` as a word is blocked, because telling a mention from a command is
# the shell-parsing problem this hook gave up on. Put the text in a file written with the
# Write tool and pass it by name: `git commit -F`, `gh pr create --body-file`,
# `gh api ... --input`.
#
# The shape /resume sends is its v0.16.0 one, which carries --admin: the restrict-updates-to-main
# ruleset makes every merge to main an admin bypass (#262). --admin is admitted only in
# that exact shape, against a cursor-sync PR; on any other `gh pr merge` it is refused, as
# is the pre-0.16.0 shape without it (/resume no longer sends it, and under the ruleset it
# would be refused anyway). Refusing it keeps the admitted set to one command.
#
# Exit 2 blocks the call and sends stderr back to Claude. Exit 0 with no output leaves the
# call to the normal permission flow. Exit 0 with an `ask` decision forces a prompt. Claude
# Code treats any OTHER exit code as a non-blocking error, so once a merge has been seen,
# every path here ends in `block` or the `ask`, never in a stray exit 1. No `set -e`, on
# purpose.
#
# What --admin does and does not skip: the repo's admin role is the one bypass actor on
# restrict-updates-to-main (an `update` rule), in `pull_request` bypass mode: it lifts the
# restriction for a PR merge only, never for a direct push. main-required-checks has no
# bypass actors, so every required check must be green before a merge lands, admin or not.
# That includes architect-review, but a review from the owner's login turns it green, and an
# agent whose shell holds that login could post one, so it is a gate on honest runs, not on
# this agent.
#
# Residuals:
#  - Not seen: a word built at run time (`${x}ge`, the output of a substitution), a command
#    that spells both `gh` and the `m` of merge in escapes (the escape refusal needs one of
#    the two to be visible), a script
#    written with the Write tool and then run, python or node or curl calling the API, and
#    anything the agent does outside the Bash and PowerShell tools. The agent's credential
#    is an admin one (see above).
#  - Refused though harmless: a command that holds the letters of `merge` (or a gh word) and
#    also a `$'..'` string with a \x, \u or octal escape, a brace expansion (`cp f{,.bak}`) or
#    a PowerShell `u{..} escape; and any command with `automerge`, `merge_commit_sha` or the
#    like (the word is checked on its right side only). `git -c k=v merge` is refused too
#    (only `-C dir` and value-less flags may sit between `git` and `merge`), and so is
#    `git merge` after `then`, `do` or `{` (the carve-out anchors after ; & | and `(`).
#  - If this script cannot run at all (no bash), the call is not blocked. Without jq, only a
#    literal `merge` is looked for, and a split one (`mer\ge`) passes.
#  - The `ask` is the only human gate on the one merge this admits. A PR the hook takes as
#    cursor-sync (identified by its docs/sync-cursor-* branch and file list only) touches
#    .ai/next-steps.md, which is outside code_paths, so architect-review has nothing to
#    review on it.
#  - The hook sees Claude's tool calls only. A human running the merge with --admin in
#    their own terminal, or in the GitHub UI, is not guarded.
#  - A PR whose ledger changes type (to a symlink) may report status `modified`; the file
#    check goes no further than that status.
#  - The two GitHub reads are given 20 seconds each (when `timeout` is on PATH). A hook that
#    outlives its own timeout
#    (set in .claude/settings.json) is treated by Claude Code as a non-blocking error, which
#    leaves the call to the normal permission flow.
#  - A /resume older than 0.16.0 sends the refused shape, so its merge is blocked until
#    the plugin is refreshed.
#
# stdin: the hook input JSON (`.tool_input.command`). Reads `repo:` and `pr_base:` from
# .ai/project.yml under $CLAUDE_PROJECT_DIR (default: the current directory).
set -uo pipefail

block() { echo "merge-guard: $1" >&2; exit 2; }

input="$(cat)" || block "could not read the hook input"

if ! command -v jq >/dev/null 2>&1; then
  lower="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" || block "could not read the hook input"
  case "$lower" in *merge*) block "jq is missing, so a command mentioning merge cannot be checked" ;; *) exit 0 ;; esac
fi
# A NUL in the command: bash's $( ) would drop it below and see a different word.
case "$input" in *'\u0000'*) block "the command holds a NUL byte, which cannot be checked" ;; esac
if ! cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"; then
  # Not JSON we can read: refuse it only if the letters of "merge" appear in it.
  lower="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in *m*e*r*g*e*) block "could not parse the hook input" ;; *) exit 0 ;; esac
fi

# The letters of "merge" appear nowhere in the command, in order: nothing to guard. This is
# looser than *merge* on purpose: quotes and escapes can split the word (`mer\ge`, `m''erge`),
# and the check below runs on the text with those removed. (The command, not the whole hook
# input: the envelope's other fields hold those letters on every call.)
lcmd="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')" || block "could not read the command"
case "$lcmd" in *m*e*r*g*e*) letters=1 ;; *) letters=0 ;; esac

# Spellings the shell resolves before the command runs, and that deleting quotes does not
# undo: $'..' with an escape that can write a letter ($'\x6d' is m), a brace expansion
# ({m..m}erge, {--body=,m}erge) and PowerShell's `u{6d}. Not looked through, so refused when
# the command also holds the letters of merge, or a gh word (the escape may be hiding the m).
# Brace expansion is told from ${x}, JSON and the like by having no space, quote or colon in
# it and no $ before it.
lq="${lcmd//[\'\"\\\`]/}" # for the gh word: gh split by quotes or escapes is still gh
if [[ $cmd =~ \$\'[^\']*\\(x[0-9A-Fa-f]|u[0-9A-Fa-f]|U[0-9A-Fa-f]|[0-7]) ]] ||
  [[ $lcmd =~ (^|[^$])\{[^{}[:space:]\"\':]*(,|\.\.)[^{}[:space:]\"\':]*\} ]] || [[ $lcmd == *'`u{'* ]]; then
  if [ "$letters" = 1 ] || [[ $lq =~ (^|[^a-z0-9_])gh(\.exe)?([^a-z0-9_]|$) ]]; then
    block "a command with a \$'..' escape, a brace expansion or a \`u{..} escape cannot be checked for a merge; write the word out"
  fi
fi
[ "$letters" = 1 ] || exit 0

# Normalise: join backslash-newline lines; a $ before a quote (\$'..', \$"..") goes with it.
norm="${cmd//\\$'\r\n'/}"
norm="${norm//\\$'\n'/}"
norm="${norm//\$\'/\'}"
norm="${norm//\$\"/\"}"
norm="${norm//\$\(\)/}" # an empty substitution vanishes from a word (me$()rge)

# Does a merge remain in this normalised text? First take out what is not a merge but holds
# the word: `git merge ...` at the start of a command (after ; & | or an opening parenthesis;
# only `-C dir` and flags without a value may sit between, so `git -c alias.x=... x merge`
# is not carved out), and hyphenated git plumbing (merge-base, merge-tree, ...). Then look for `merge` followed by a non-letter
# (so merged, mergeable, mergeStateStatus and --no-merges do not count). These longer names
# are merges all the same: the GraphQL mutations mergePullRequest and mergeBranch, and the
# REST path /merges (merge a branch into a branch). A sed failure counts as a merge.
has_merge() {
  local t
  # The git carve-out is read before lowercasing, so that -C (a directory) and -c (a config
  # value, which may define an alias) stay different flags.
  t="$(printf '%s' "$1" | sed -E '
    s/(^|[;&|(])[[:space:]]*git(([[:space:]]+(-C[[:space:]]+[A-Za-z0-9_.\/~+:@][A-Za-z0-9_.\/~+:@-]*|-[a-zA-Z]+|--[a-z][a-z-]*(=[A-Za-z0-9_.\/~+:@-]*)?))*)[[:space:]]+merge([^a-z-]|$)/\1 \6/g
  ' | tr '[:upper:]' '[:lower:]' | sed -E '
    s/merge-(base|tree|file|index|one-file|recursive|resolve|octopus|ours|subtree|guard)/ /g
  ')" || return 0
  [[ $t =~ merge([^a-z]|$)|mergepullrequest|mergebranch|/merges([^a-z]|$) ]]
}
# A backtick pair is a command substitution in bash, which can vanish from a word
# (merge`true` is merge), and an escape in PowerShell (mer`ge is merge): read the text both
# ways, with backticks deleted and with them as a break, and refuse if either holds a merge.
norm_del="${norm//[\'\"\\\`]/}"
norm_brk="${norm//[\'\"\\]/}"
norm_brk="${norm_brk//\`/ }"
has_merge "$norm_del" || has_merge "$norm_brk" || exit 0

usage="only /way-of-working:resume's cursor-sync merge passes here:
  gh pr merge <N> --repo <repo> --squash --admin --match-head-commit <40-hex sha>
on its own, against a cursor-sync PR. Any other merge is the human's, on GitHub.
If the command only mentions a merge in text (a commit message, a PR body), put the text in
a file with the Write tool and pass it by name: git commit -F, gh pr create --body-file,
gh api --input."

trimmed="${cmd#"${cmd%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
re='^gh pr merge ([1-9][0-9]*) --repo ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) --squash --admin --match-head-commit ([0-9a-f]{40})$'
[[ $trimmed =~ $re ]] || block "$usage"
n="${BASH_REMATCH[1]}" repo="${BASH_REMATCH[2]}" oid="${BASH_REMATCH[3]}"

cfg="${CLAUDE_PROJECT_DIR:-.}/.ai/project.yml"
want_repo="$(sed -n 's/^repo:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$cfg" 2>/dev/null | head -n 1)"
want_base="$(sed -n 's/^pr_base:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$cfg" 2>/dev/null | head -n 1)"
want_repo="${want_repo%$'\r'}" want_base="${want_base%$'\r'}"
if [ -z "$want_repo" ] || [ -z "$want_base" ]; then block "could not read repo and pr_base from $cfg"; fi
[ "$repo" = "$want_repo" ] || block "--repo $repo is not this repo ($want_repo)"

# gh, given 20 seconds: a hang must end in `block`, not in a hook timeout (which passes the call on).
gh_t() { if command -v timeout >/dev/null 2>&1; then timeout -k 5 20 gh "$@"; else gh "$@"; fi; }

pr="$(gh_t api "repos/$repo/pulls/$n" \
  --jq '[.state, .base.ref, .head.ref, .head.sha, (.head.repo.full_name // "")] | @tsv' 2>/dev/null)" ||
  block "could not read PR #$n from GitHub"
pr="${pr//$'\r'/}"
IFS=$'\t' read -r state base head_ref head_sha head_repo <<< "$pr"
[ "$state" = open ] || block "PR #$n is not open (state: ${state:-unknown})"
[ "$base" = "$want_base" ] || block "PR #$n is based on '$base', not $want_base"
[ "$head_repo" = "$repo" ] || block "PR #$n comes from '$head_repo', not $repo"
case "$head_ref" in
  docs/sync-cursor-?*) ;;
  *) block "PR #$n's branch '$head_ref' is not a docs/sync-cursor-* branch. $usage" ;;
esac
[ "$head_sha" = "$oid" ] || block "PR #$n's head is $head_sha, not $oid"

# Exactly one row: the ledger, modified in place. A delete, a rename onto the ledger's
# name (status renamed) and a mode-only change (status changed) list the same filename.
files="$(gh_t api --paginate "repos/$repo/pulls/$n/files" --jq '.[] | [.filename, .status] | @tsv' 2>/dev/null)" ||
  block "could not read PR #$n's files from GitHub"
files="${files//$'\r'/}"
[ "$files" = ".ai/next-steps.md"$'\t'"modified" ] ||
  block "PR #$n changes more than .ai/next-steps.md, or not as a plain edit: $(printf '%s' "$files" | tr '\t\n' ': ')"

jq -cn --arg reason "merge-guard: PR #$n is a cursor-sync PR ($head_ref, only .ai/next-steps.md) at $oid. Confirm to admin squash-merge it (--admin bypasses restrict-updates-to-main)." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}' ||
  block "could not write the ask decision"
exit 0
