#!/usr/bin/env bash
# Logic of the `resolve` job of architect-review-gate.yml (design spec v5.2 section 4).
#
# This file is the one copy: tools/render-gate.sh inlines it, byte for byte, into the
# `run:` block of template/.github/workflows/architect-review-gate.yml, and the selftest
# fails unless the template matches. Edit it here, never in the template.
#
# It parses no PR content: it reads only API facts (ids, shas, refs, file counts, commit
# verification) and writes each output either as a literal true/false or as a value that
# passed a regex. Strings reach it through `env`, never through inline expressions.
#
# Inputs (env):
#   GH_TOKEN        token for `gh api`
#   GITHUB_OUTPUT   file the outputs are appended to
#   REPO            owner/name of this repo
#   EVENT_NAME      github.event_name
#   PR_NUMBER       github.event.pull_request.number || github.event.issue.number
#   ACTOR_ID        github.event.comment.user.id || github.event.review.user.id
#   REVIEWER_IDS    space-separated numeric user ids whose comment or review re-runs the gate
# Outputs: act, head_sha, pr, candidate, candidate_pr (candidate_pr only when candidate=true).
set -euo pipefail

DEPENDABOT_ID=49699333
BUMP_FILE=.devcontainer/Dockerfile

: "${GITHUB_OUTPUT:?}" "${REPO:?}" "${EVENT_NAME:?}"

out_bool() {
  case "$2" in
    true | false) printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT" ;;
    *) echo "::error::Refusing to write output $1: not a boolean."; exit 1 ;;
  esac
}
out_match() { # name value regex
  if [[ "$2" =~ $3 ]]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  else
    echo "::error::Refusing to write output $1: value failed its regex."
    exit 1
  fi
}

# 1. Find the PR. The job-level `if:` already limits issue_comment events to PRs.
if ! [[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]]; then
  echo "::error::Could not resolve a PR number from event '${EVENT_NAME}'."
  exit 1
fi

# 2. Early stop. A comment or review re-runs the gate only when its author is in
# REVIEWER_IDS. Any other event name is not one this gate handles: stop, fail closed.
act=false
case "$EVENT_NAME" in
  pull_request) act=true ;;
  issue_comment | pull_request_review)
    actor="${ACTOR_ID:-}"
    if [[ "$actor" =~ ^[0-9]+$ && " ${REVIEWER_IDS:-} " == *" ${actor} "* ]]; then
      act=true
    fi
    ;;
esac
if [ "$act" != true ]; then
  out_bool act false
  out_bool candidate false
  out_match pr "$PR_NUMBER" '^[0-9]+$'
  echo "Event '${EVENT_NAME}' is not from a reviewer in REVIEWER_IDS: nothing to do."
  exit 0
fi

# 3. Head SHA of the PR that triggered the run.
head_sha="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq '.head.sha')"
if ! [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Could not resolve PR #${PR_NUMBER}'s head commit."
  exit 1
fi

# 4. Candidacy, keyed on the SHA, never on the PR that triggered the run. Every call is
# captured into a variable, so a failing `gh api` aborts under `set -e` and can never read
# as "no candidate".
default_branch="$(gh api "repos/${REPO}" --jq '.default_branch // empty')"
if [ -z "$default_branch" ]; then
  echo "::error::Could not resolve the default branch of ${REPO}."
  exit 1
fi
sha_prs="$(gh api "repos/${REPO}/commits/${head_sha}/pulls" --paginate | jq -s 'add // []')"
# Cheap filters on the list first: open, same repo, same SHA, default branch, Dependabot's
# user id, a docker-ecosystem branch.
numbers="$(printf '%s' "$sha_prs" | jq -r \
  --arg sha "$head_sha" --arg repo "$REPO" --arg base "$default_branch" --argjson uid "$DEPENDABOT_ID" '
  .[]
  | select(.state == "open"
      and .head.sha == $sha
      and ((.head.repo.full_name // "") | ascii_downcase) == ($repo | ascii_downcase)
      and .base.ref == $base
      and .user.id == $uid
      and ((.head.ref // "") | startswith("dependabot/docker/")))
  | .number')"

survivors=()
for n in $numbers; do
  [[ "$n" =~ ^[0-9]+$ ]] || continue
  # Exactly one file, modified, +1/-1, no rename.
  files="$(gh api "repos/${REPO}/pulls/${n}/files" --paginate | jq -s 'add // []')"
  if ! printf '%s' "$files" | jq -e --arg f "$BUMP_FILE" '
      length == 1 and (.[0]
        | .filename == $f and .status == "modified" and .additions == 1 and .deletions == 1
          and ((.previous_filename // null) == null))' > /dev/null; then
    continue
  fi
  # Every commit verified by GitHub, authored by Dependabot, and the head among them.
  commits="$(gh api "repos/${REPO}/pulls/${n}/commits" --paginate | jq -s 'add // []')"
  if ! printf '%s' "$commits" | jq -e --arg sha "$head_sha" --argjson uid "$DEPENDABOT_ID" '
      length > 0 and any(.[]; .sha == $sha)
      and all(.[]; .commit.verification.verified == true
                   and .commit.verification.reason == "valid"
                   and .author.id == $uid)' > /dev/null; then
    continue
  fi
  # The head must not have moved while the files and commits were read.
  now="$(gh api "repos/${REPO}/pulls/${n}" --jq '[.head.sha, .state] | join(" ")')"
  if [ "$now" != "${head_sha} open" ]; then
    continue
  fi
  survivors+=("$n")
done

# 5. Outputs. Exactly one survivor makes a candidate (two PRs can share a SHA).
out_bool act true
out_match head_sha "$head_sha" '^[0-9a-f]{40}$'
out_match pr "$PR_NUMBER" '^[0-9]+$'
if [ "${#survivors[@]}" -eq 1 ]; then
  out_bool candidate true
  out_match candidate_pr "${survivors[0]}" '^[0-9]+$'
else
  out_bool candidate false
fi
echo "PR #${PR_NUMBER}, head ${head_sha}: ${#survivors[@]} candidate PR(s)."
