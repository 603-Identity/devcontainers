#!/usr/bin/env bash
# The "gates are not re-run" check for .github/workflows/release.yml (#486): before a commit is released,
# prove through the API that it already passed everything that guards `main`. Nothing is re-run.
#
#   GH_TOKEN=... REPO=owner/name [PROJECT_FILE=.ai/project.yml] release-verify.sh <sha>
#
# Three checks, all read through `gh api`:
#   1. The PR. Exactly one PR merged into `main` has the SHA as its merge commit.
#   2. The required checks. Every name in the project file's `main-required-checks` ruleset entry is
#      green on that PR's head commit, each read from one source chosen by name: the name equal to
#      `review.ci_gate.check` (a commit status posted by review-gate.yml) from the combined status,
#      every other name from check runs (the run of that name with the highest id). Only `success`
#      counts; a same-named entry in the other source never counts, for or against.
#   3. The push runs. `main`'s own push-event workflow runs on the SHA exist, and every one has
#      completed with `success`.
#
# Exit 0: all three pass. 1: a refusal, each reason one `::error::` line naming the PR, check or run;
# an API error is a refusal, never a pass, and so is a project file that is missing, unreadable or
# does not parse. 2: a usage error (a missing or malformed SHA, an unset or malformed REPO, an unset
# GH_TOKEN). Needs gh, jq and yq (mikefarah).
set -euo pipefail
export LC_ALL=C

SHA_RE='^[0-9a-f]{40}$'
REPO_RE='^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$'
BASE=main
# Rows from jq are joined with the unit separator, which `read` does not treat as whitespace, so an
# empty field stays an empty field instead of shifting the ones after it.
US=$'\x1f'
RULESET=main-required-checks

usage_error() { echo "release-verify.sh: $*" >&2; exit 2; }
[ "$#" -eq 1 ] || usage_error "usage: release-verify.sh <sha>"
sha="$1"
[[ "$sha" =~ $SHA_RE ]] || usage_error "the SHA must be 40 lowercase hex characters."
repo="${REPO:-}"
[[ "$repo" =~ $REPO_RE ]] || usage_error "REPO must be owner/name."
repo_name="${repo#*/}"
[ "$repo_name" != . ] && [ "$repo_name" != .. ] || usage_error "REPO must be owner/name."
[ -n "${GH_TOKEN:-}" ] || usage_error "GH_TOKEN is not set."
project="${PROJECT_FILE:-.ai/project.yml}"

problems=0
problem() { problems=$((problems + 1)); echo "::error::$*" >&2; }
finish() {
  if [ "$problems" -gt 0 ]; then
    echo "release-verify: $problems problem(s); $sha is not releasable." >&2
    exit 1
  fi
  echo "release-verify: ok ($sha)."
}
api_failed() { problem "the GitHub API call for $1 failed; an API error is never a pass."; }

# --- the project file ------------------------------------------------------------------------
[ -r "$project" ] || { problem "the project file $project is missing or unreadable."; finish; }
required="$(RULESET="$RULESET" yq -r '[.rulesets[] | select(.name == strenv(RULESET)) | .required_checks[]] | .[]' "$project" 2> /dev/null)" \
  || { problem "the project file $project does not parse, or has no $RULESET entry with a required_checks list."; finish; }
[ -n "$required" ] || { problem "the project file declares no required checks for the $RULESET ruleset."; finish; }
gate_check="$(yq -r '.review.ci_gate.check // ""' "$project" 2> /dev/null)" \
  || { problem "the project file $project does not parse."; finish; }
[ -n "$gate_check" ] && [ "$gate_check" != null ] || { problem "the project file declares no review.ci_gate.check."; finish; }

# --- 1. the PR -------------------------------------------------------------------------------
head_sha="" pr_list=""
if prs="$(gh api "repos/$repo/commits/$sha/pulls?per_page=100" --paginate \
  --jq 'def c: tostring | gsub("[\n\r\u001f]"; " "); .[] | [.number, (.merged_at // ""), (.base.ref // ""), (.merge_commit_sha // ""), (.head.sha // "")] | map(c) | join("\u001f")')"; then
  matched=0
  while IFS="$US" read -r number merged_at base_ref merge_sha pr_head; do
    [ -n "$number" ] || continue
    if [ -n "$merged_at" ] && [ "$base_ref" = "$BASE" ] && [ "$merge_sha" = "$sha" ]; then
      matched=$((matched + 1))
      pr_list="$pr_list #$number"
      head_sha="$pr_head"
    fi
  done <<< "$prs"
  if [ "$matched" -eq 0 ]; then
    problem "no PR merged into $BASE has $sha as its merge commit."
  elif [ "$matched" -gt 1 ]; then
    problem "more than one PR merged into $BASE has $sha as its merge commit:$pr_list."
  elif [[ ! "$head_sha" =~ $SHA_RE ]]; then
    problem "PR$pr_list has no usable head commit."
    head_sha=""
  fi
else
  api_failed "the PR that produced $sha"
fi

# --- 2. the required checks on the PR's head commit ------------------------------------------
if [ -n "$head_sha" ]; then
  runs="" statuses="" runs_ok=1 statuses_ok=1
  runs="$(gh api "repos/$repo/commits/$head_sha/check-runs?per_page=100" --paginate \
    --jq 'def c: tostring | gsub("[\n\r\u001f]"; " "); .check_runs[] | [.id, (.name // ""), (.status // ""), (.conclusion // "")] | map(c) | join("\u001f")')" || runs_ok=0
  statuses="$(gh api "repos/$repo/commits/$head_sha/status?per_page=100" --paginate \
    --jq 'def c: tostring | gsub("[\n\r\u001f]"; " "); .statuses[] | [.id, (.context // ""), (.state // "")] | map(c) | join("\u001f")')" || statuses_ok=0
  [ "$runs_ok" -eq 1 ] || api_failed "the check runs on $head_sha"
  [ "$statuses_ok" -eq 1 ] || api_failed "the commit statuses on $head_sha"

  # The row of the highest id whose name is $1, from the unit-separator-joined rows in $2 (id, name, ...).
  latest_row() {
    NAME="$1" awk -F"$US" '$2 == ENVIRON["NAME"] && ($1 + 0) >= best { best = $1 + 0; row = $0 } END { print row }' <<< "$2"
  }
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$name" = "$gate_check" ]; then
      [ "$statuses_ok" -eq 1 ] || continue
      row="$(latest_row "$name" "$statuses")"
      if [ -z "$row" ]; then
        problem "the status $name is missing on PR$pr_list's head $head_sha."
      else
        state="$(cut -d"$US" -f3 <<< "$row")"
        [ "$state" = success ] || problem "the status $name is $state, not success, on PR$pr_list's head $head_sha."
      fi
    else
      [ "$runs_ok" -eq 1 ] || continue
      row="$(latest_row "$name" "$runs")"
      if [ -z "$row" ]; then
        problem "the check $name is missing on PR$pr_list's head $head_sha."
      else
        status="$(cut -d"$US" -f3 <<< "$row")"
        conclusion="$(cut -d"$US" -f4 <<< "$row")"
        if [ "$status" != completed ]; then
          problem "the check $name is $status, not completed, on PR$pr_list's head $head_sha."
        elif [ "$conclusion" != success ]; then
          problem "the check $name concluded ${conclusion:-nothing}, not success, on PR$pr_list's head $head_sha."
        fi
      fi
    fi
  done <<< "$required"
fi

# --- 3. main's push runs on the SHA ----------------------------------------------------------
if push_runs="$(gh api "repos/$repo/actions/runs?head_sha=$sha&event=push&branch=$BASE&per_page=100" --paginate \
  --jq 'def c: tostring | gsub("[\n\r\u001f]"; " "); .workflow_runs[] | [.id, (.name // ""), (.path // ""), (.head_sha // ""), (.event // ""), (.head_branch // ""), (.status // ""), (.conclusion // "")] | map(c) | join("\u001f")')"; then
  seen=0
  while IFS="$US" read -r id name path run_sha event branch status conclusion; do
    [ -n "$id" ] || continue
    [ "$run_sha" = "$sha" ] && [ "$event" = push ] && [ "$branch" = "$BASE" ] || continue
    seen=$((seen + 1))
    if [ "$status" != completed ]; then
      problem "the push run $id ($name) on $sha is $status; dispatch again once it has finished."
    elif [ "$conclusion" != success ]; then
      case "$path" in
        .github/workflows/build.yml) hint="never re-run a build.yml push run (an attempt-2 image fails every consumer's verify); release a later main commit." ;;
        *) hint="" ;;
      esac
      problem "the push run $id ($name) on $sha concluded ${conclusion:-nothing}, not success. $hint"
    fi
  done <<< "$push_runs"
  [ "$seen" -gt 0 ] || problem "no push-event workflow run of $BASE exists for $sha."
else
  api_failed "main's push runs on $sha"
fi

finish
