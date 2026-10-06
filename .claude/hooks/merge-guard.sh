#!/usr/bin/env bash
# PreToolUse hook for the Bash and PowerShell tools, standing in for the `gh pr merge`
# deny rules (#168). In Claude Code a deny rule wins over every allow rule and hook, so it
# could not make room for the one merge /way-of-working:resume (0.16.0+) makes on the
# human's explicit confirmation: a handoff cursor-sync PR. This hook blocks every
# `gh pr merge` the deny rules blocked, except /resume's exact command shape against a PR
# that GitHub confirms is a cursor-sync PR. Even that one goes to a permission prompt
# (`ask`), never straight through.
#
# The shape is /resume's v0.16.0 one, which carries --admin: the restrict-updates-to-main
# ruleset makes every merge to main an admin bypass (#262). --admin is admitted only in
# that exact shape, against a cursor-sync PR; on any other plain `gh pr merge` it is refused, as
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
# restriction for a PR merge only, never for a direct push. main-required-checks has no bypass actors,
# so every required check, architect-review included, must still be green before a merge
# lands, admin or not.
#
# Residuals:
#  - If this script cannot run at all (no bash), the call is not blocked, and nothing here
#    stops an `--admin` merge of any PR past restrict-updates-to-main. The required checks
#    still hold.
#  - The `ask` is the only human gate on the one merge this admits. A PR the hook takes
#    as cursor-sync (identified by its docs/sync-cursor-* branch and file list only) touches .ai/next-steps.md, which is outside
#    code_paths, so architect-review has nothing to review on it.
#  - The hook sees Claude's tool calls only. A human running the merge with --admin in
#    their own terminal, or in the GitHub UI, is not guarded.
#  - Only a segment that starts with `gh pr merge` is seen. A wrapper (`command`, `env`,
#    `exec`, a `{ }` group, `if`), a path or quoted `gh`, `gh api` on the merge endpoint, or
#    a `gh alias` is not, so --admin is refused on a plain `gh pr merge` only. The deny rules
#    this replaced had similar blind spots; the required checks still hold either way.
#  - The file check reads filenames only, not each file's status or mode.
#  - A /resume older than 0.16.0 sends the refused shape, so its merge is blocked until
#    the plugin is refreshed.
#
# stdin: the hook input JSON (`.tool_input.command`). Reads `repo:` and `pr_base:` from
# .ai/project.yml under $CLAUDE_PROJECT_DIR (default: the current directory).
set -uo pipefail

block() { echo "merge-guard: $1" >&2; exit 2; }

input="$(cat)" || block "could not read the hook input"

# Nothing says "merge" anywhere: nothing to guard.
case "$input" in *merge*) ;; *) exit 0 ;; esac

command -v jq >/dev/null 2>&1 || block "jq is missing, so a command mentioning merge cannot be checked"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" || block "could not parse the hook input"

LC_ALL=C   # byte-wise indexing below: faster, and no locale surprises

# The text of the command that bash would actually RUN as commands. Dropped: single-quoted
# text, comments, backslash-escaped characters, double-quoted text, and the bodies of
# heredocs whose delimiter is quoted (<<'EOF'). Kept: $( ) and backtick substitutions,
# including inside double quotes and unquoted heredocs, since those run; and a quoted
# string handed to an evaluator (bash -c, sh -c, eval, pwsh -Command, iex), since that
# text runs too. So a commit message or PR body that only MENTIONS the command passes.
# Where it cannot tell, it keeps the text: a false block is recoverable, a missed merge
# is not. Residual: an evaluator it does not name (`python -c`, `xargs`) is not seen
# through -- the same as the deny rules this replaced.
EVAL_RE='((^|[^A-Za-z0-9_.-])(bash|sh|zsh|dash|ksh|pwsh|powershell)(\.exe)?([[:space:]]+-[A-Za-z]+)*[[:space:]]+-(c|lc|ic|Command|command)|(^|[[:space:];&|(])(eval|iex|Invoke-Expression))[[:space:]]*$'
executable_text() { # text [heredoc]  -- "heredoc": the text is an unquoted heredoc body
  local s="$1" out="" str="" prev="" c i=0 n=${#1} state=normal depth=0 rest
  [ "${2:-}" = heredoc ] && state=dq
  while [ "$i" -lt "$n" ]; do
    c="${s:i:1}"
    case "$state" in
      normal)
        case "$c" in
          \\) out+=" "; i=$((i + 1)) ;;
          \') prev="$out" str="" state=sq ;;
          \") prev="$out" str="" state=dq ;;
          \#)
            if [ -z "$out" ] || [[ ${out: -1} =~ [[:space:]\;\&\|\(] ]]; then
              rest="${s:i}" rest="${rest%%$'\n'*}"
              i=$((i + ${#rest} - 1))
            else
              out+="$c"
            fi ;;
          *) out+="$c" ;;
        esac ;;
      sq)
        if [ "$c" = "'" ]; then
          if [[ $prev =~ $EVAL_RE ]]; then out+=$'\n'"$str"$'\n'; else out+=" "; fi
          state=normal
        else
          str+="$c"
        fi ;;
      dq)
        case "$c" in
          \\) str+="${s:i:2}"; i=$((i + 1)) ;;
          \")
            if [ "${2:-}" = heredoc ]; then
              str+="$c"
            else
              if [[ $prev =~ $EVAL_RE ]]; then out+=$'\n'"$str"$'\n'; else out+=" "; fi
              state=normal
            fi ;;
          \`) str+="$c"; out+=$'\n'; state=dqbt ;;
          \$)
            if [ "${s:i+1:1}" = "(" ]; then
              str+="\$("; out+=$'\n'; depth=1 state=dqsub; i=$((i + 1))
            else
              str+="$c"
            fi ;;
          *) str+="$c" ;;
        esac ;;
      dqbt)
        str+="$c"
        if [ "$c" = '`' ]; then out+=$'\n'; state=dq; else out+="$c"; fi ;;
      dqsub)
        str+="$c"
        case "$c" in
          \() depth=$((depth + 1)); out+="$c" ;;
          \))
            depth=$((depth - 1))
            if [ "$depth" -eq 0 ]; then out+=$'\n'; state=dq; else out+="$c"; fi ;;
          *) out+="$c" ;;
        esac ;;
    esac
    i=$((i + 1))
  done
  # An unterminated quote: bash would refuse the line, but keep the text all the same.
  case "$state" in sq | dq) [ "${2:-}" = heredoc ] || out+=$'\n'"$str" ;; esac
  printf '%s\n' "$out"
}

# Split heredoc bodies off the command line. A quoted delimiter's body (<<'EOF',
# <<"EOF", <<-'EOF') is dropped: bash expands nothing in it. An unquoted delimiter's
# body goes through executable_text as a heredoc, keeping only its substitutions.
strip_heredocs() {
  local line cmp delim="" quoted=0 strip=0 body="" tail=""
  local re="<<(-?)[[:space:]]*('([A-Za-z_][A-Za-z0-9_]*)'|\"([A-Za-z_][A-Za-z0-9_]*)\"|([A-Za-z_][A-Za-z0-9_]*))"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$delim" ]; then
      cmp="${line%$'\r'}"
      [ "$strip" = 1 ] && cmp="${cmp#"${cmp%%[!$'\t']*}"}"
      if [ "$cmp" = "$delim" ]; then
        [ "$quoted" = 1 ] || tail+="$(executable_text "$body" heredoc)"$'\n'
        delim="" body=""
      else
        body+="$line"$'\n'
      fi
      continue
    fi
    printf '%s\n' "$line"
    if [[ $line =~ $re ]]; then
      strip=0 quoted=1
      [ -n "${BASH_REMATCH[1]}" ] && strip=1
      delim="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
      [ -n "${BASH_REMATCH[5]}" ] && delim="${BASH_REMATCH[5]}" quoted=0
    fi
  done <<< "$1"
  # A heredoc never terminated: keep its body whole, as if it were command lines.
  [ -z "$delim" ] || tail+="$body"
  printf '%s' "$tail"
}

# Does any segment of what runs start with `gh pr merge`, the prefix the deny rules
# matched? Segments split on ; & | ( ) backticks and line breaks; leading VAR=value
# assignments are skipped.
is_merge() {
  local seg
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    while [[ $seg =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*)$ ]]; do
      seg="${BASH_REMATCH[1]}"
    done
    [[ $seg =~ ^gh(\.exe)?[[:space:]]+pr[[:space:]]+merge([[:space:]]|$) ]] && return 0
  done < <(printf '%s\n' "$1" | tr ';&|()`\r' '[\n*]')
  return 1
}
heredocs="$(strip_heredocs "$cmd")" || block "could not scan the command"
runs="$(executable_text "$heredocs")" || block "could not scan the command"
is_merge "$runs" || exit 0

usage="only /way-of-working:resume's cursor-sync merge passes here:
  gh pr merge <N> --repo <repo> --squash --admin --match-head-commit <40-hex sha>
on its own, against a cursor-sync PR. Any other merge is the human's, on GitHub."

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

pr="$(gh api "repos/$repo/pulls/$n" \
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

files="$(gh api --paginate "repos/$repo/pulls/$n/files" --jq '.[].filename' 2>/dev/null)" ||
  block "could not read PR #$n's files from GitHub"
files="${files//$'\r'/}"
[ "$files" = ".ai/next-steps.md" ] ||
  block "PR #$n changes more than .ai/next-steps.md: $(printf '%s' "$files" | tr '\n' ' ')"

jq -cn --arg reason "merge-guard: PR #$n is a cursor-sync PR ($head_ref, only .ai/next-steps.md) at $oid. Confirm to admin squash-merge it (--admin bypasses restrict-updates-to-main)." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}' ||
  block "could not write the ask decision"
exit 0
