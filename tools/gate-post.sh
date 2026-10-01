#!/usr/bin/env bash
# Logic of the `post` job of architect-review-gate.yml (design spec v5.2 section 4).
#
# This file is the one copy: tools/render-gate.sh inlines it, byte for byte, into the
# `run:` block of template/.github/workflows/architect-review-gate.yml, and the selftest
# fails unless the template matches. Edit it here, never in the template.
#
# It computes the one status for a head SHA from: the candidate facts (resolve), the
# decision (decide), the kill switch, and the TARGET PR's reviews. Strings reach it through
# `env`, never through inline expressions.
#
# Inputs (env):
#   GH_TOKEN         token for `gh api` / `gh pr merge`
#   REPO             owner/name of this repo
#   HEAD_SHA         needs.resolve.outputs.head_sha
#   PR               needs.resolve.outputs.pr
#   CANDIDATE        needs.resolve.outputs.candidate  (true/false)
#   CANDIDATE_PR     needs.resolve.outputs.candidate_pr
#   DECIDE_RESULT    needs.decide.result
#   EXEMPT           needs.decide.outputs.exempt  (true/false)
#   RUN_URL          link put on every status
#   CONTEXT          status context, default architect-review
#   HEADER, ATTESTATION, REVIEWER_IDS   the per-consumer review values
#   GITHUB_SERVER_URL  optional, default https://github.com
set -euo pipefail

: "${GH_TOKEN:?}" "${REPO:?}" "${HEAD_SHA:?}" "${PR:?}" "${RUN_URL:?}"
: "${HEADER:?}" "${ATTESTATION:?}" "${REVIEWER_IDS:?}"
CONTEXT="${CONTEXT:-architect-review}"
CANDIDATE="${CANDIDATE:-}"
CANDIDATE_PR="${CANDIDATE_PR:-}"
DECIDE_RESULT="${DECIDE_RESULT:-}"
EXEMPT="${EXEMPT:-}"

# The repo that owns the kill-switch tag. Read with this job's own token (public repo).
KILL_SWITCH_PATH="repos/603-Identity/devcontainers/git/ref/tags/devc-automerge-on"
KILL_SWITCH_REF="refs/tags/devc-automerge-on"

if ! [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ && "$PR" =~ ^[0-9]+$ ]]; then
  echo "::error::Malformed head SHA or PR number from resolve. Nothing is posted."
  exit 1
fi

# target: the candidate PR when there is one, otherwise the PR that triggered the run.
# Every review lookup, status and disarm below acts on it. A malformed candidate_pr is
# handled by the error row, which still uses the triggering PR.
TARGET="$PR"
if [ "$CANDIDATE" = true ] && [[ "$CANDIDATE_PR" =~ ^[0-9]+$ ]]; then
  TARGET="$CANDIDATE_PR"
fi
TARGET_URL="${GITHUB_SERVER_URL:-https://github.com}/${REPO}/pull/${TARGET}"

post_status() { # state description
  gh api --method POST "repos/${REPO}/statuses/${HEAD_SHA}" \
    -f state="$1" -f context="${CONTEXT}" \
    -f description="$2" \
    -f target_url="${RUN_URL}"
}

disarm_failed=0
disarm() {
  # `--disable-auto` on a PR with no auto-merge request errors, which would turn this job red
  # on every run while the kill switch is off. Skip it when the PR is visibly not armed; if
  # that look itself fails, disarm anyway (fail safe).
  local armed
  armed="$(gh pr view "$TARGET_URL" --json autoMergeRequest --jq '.autoMergeRequest // empty' 2> /dev/null)" \
    || armed=unknown
  [ -n "$armed" ] || return 0
  if ! gh pr merge --disable-auto "$TARGET_URL"; then
    echo "::warning::Could not disable auto-merge on PR #${TARGET}."
    disarm_failed=1
  fi
}

# Sets KS to: arm (200, right ref), review (404, or 200 with another ref), error (anything
# else, including 5xx and a network failure).
KS=error
read_kill_switch() {
  local resp status body ref
  resp="$(gh api -i "$KILL_SWITCH_PATH" 2> /dev/null || true)"
  resp="$(printf '%s\n' "$resp" | tr -d '\r')"
  status="$(printf '%s\n' "$resp" | awk 'NR == 1 { print $2 }')"
  case "$status" in
    200)
      body="$(printf '%s\n' "$resp" | sed '1,/^$/d')"
      ref="$(printf '%s' "$body" | jq -r 'if type == "object" then (.ref // "") else "" end' 2> /dev/null || true)"
      if [ "$ref" = "$KILL_SWITCH_REF" ]; then KS=arm; else KS=review; fi
      ;;
    404) KS=review ;;
    *) KS=error ;;
  esac
}

# The existing review logic. $1 = 1 forces "in scope" (the error row never reads a file list
# to decide that no review is needed). Plain call, never inside `if`/`||`, so `set -e` stays
# in force: a failed `gh api` must fail closed, never read as "nothing in scope".
review_logic() {
  local force_scope="$1" files f touches=0 head_date comments_json reviews_json found_at
  local item body at uid login

  # Posted first so the required check shows `pending`, not absent, while this runs.
  post_status pending "Checking for a fresh-session review..."

  # Each renamed file's OLD path is checked too (`previous_filename`), so renaming a file
  # out of scope cannot skip review. An empty file list fails closed, because every real PR
  # changes at least one file.
  if [ "$force_scope" = 1 ]; then
    touches=1
  else
    files="$(gh api "repos/${REPO}/pulls/${TARGET}/files" --paginate --jq '.[] | .filename, (.previous_filename // empty)')"
    if [ -z "$files" ]; then
      post_status failure "PR files API returned no entries -- cannot evaluate scope, failing closed."
      echo
      echo "::error::PR files API returned no entries. Failing closed rather than reporting that no review is required."
      exit 1
    fi
    while IFS= read -r f; do
      # .github/ is ALWAYS in scope, whatever the consumer's list below says: a pin bump of
      # `decide` edits only .github/, and must never be exempt. Not consumer-editable.
      case "$f" in
        .github/*) touches=1 ;;
      esac
      case "$f" in
        # >>> CONSUMER: code_paths
        images/*|template/*|tests/*|.github/*|.claude/*|tools/*) touches=1 ;;
        .trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;
        # <<< CONSUMER: code_paths
      esac
    done <<< "$files"
  fi

  if [ "$touches" != 1 ]; then
    post_status success "No code_paths touched -- no review required."
    return 0
  fi

  head_date="$(gh api "repos/${REPO}/commits/${HEAD_SHA}" --jq '.commit.committer.date')"
  echo "Head commit: ${HEAD_SHA} (${head_date})"

  # Captured into variables, not process substitution, so a failing `gh api` aborts
  # under `set -e` instead of vanishing inside a subshell.
  comments_json="$(gh api "repos/${REPO}/issues/${TARGET}/comments" --paginate --jq '.[] | {body, at: .created_at, uid: .user.id, login: .user.login} | tojson')"
  reviews_json="$(gh api "repos/${REPO}/pulls/${TARGET}/reviews" --paginate --jq '.[] | {body, at: .submitted_at, uid: .user.id, login: .user.login} | tojson')"

  found_at=""
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    # Quoted lines (`> ...`) are dropped first, so quote-replying someone else's
    # pasted strings does not make the reply qualify.
    body="$(printf '%s' "$item" | jq -r '.body // "" | split("\n") | map(select(test("^\\s*>") | not)) | join("\n")')"
    at="$(printf '%s' "$item" | jq -r '.at // ""')"
    uid="$(printf '%s' "$item" | jq -r '.uid // ""')"
    login="$(printf '%s' "$item" | jq -r '.login // ""')"
    # Who posted it counts: anyone can paste the two strings. Only an ID in REVIEWER_IDS
    # qualifies; a missing or non-numeric ID fails closed. Padding both sides with spaces
    # makes this a whole-word match.
    if ! [[ "$uid" =~ ^[0-9]+$ && " ${REVIEWER_IDS} " == *" ${uid} "* ]]; then
      # Name the cause in the log, so a skipped review doesn't look like a missing one.
      if [[ "$body" == *"$HEADER"* && "$body" == *"$ATTESTATION"* ]]; then
        echo "Skipped a matching comment/review by ${login:-<none>} (id ${uid:-<none>}): not in REVIEWER_IDS."
      fi
      continue
    fi
    if [[ "$body" == *"$HEADER"* && "$body" == *"$ATTESTATION"* ]] \
       && [[ "$at" > "$head_date" || "$at" == "$head_date" ]]; then
      found_at="$at"
      echo "Qualifying review found, posted ${at}."
      break
    fi
  done <<< "${comments_json}"$'\n'"${reviews_json}"

  if [ -n "$found_at" ]; then
    post_status success "Fresh-session review found (${found_at})."
  else
    post_status failure "No fresh-session review posted against this commit yet."
    # `gh api` prints no trailing newline, and the runner reads a workflow command
    # only at the start of a line, so this `echo` is what makes the ::error:: render.
    echo
    echo "::error::No fresh-session review posted against head commit ${HEAD_SHA} (${head_date}) yet. A PR comment or review by a user in REVIEWER_IDS containing both \"${HEADER}\" and \"${ATTESTATION}\", posted at or after that commit, is required."
    # Exit 0 on purpose: the status above is the enforcement.
  fi
  return 0
}

# The decision table. mode is one of: plain, arm, disarm-review, error.
mode=error
case "$CANDIDATE" in
  false)
    # Not a candidate: decide was skipped, and whatever it said is ignored.
    mode=plain
    ;;
  true)
    if [[ "$CANDIDATE_PR" =~ ^[0-9]+$ ]]; then
      case "$DECIDE_RESULT" in
        success)
          case "$EXEMPT" in
            true)
              read_kill_switch
              case "$KS" in
                arm) mode=arm ;;
                review) mode=disarm-review ;;
                *) mode=error ;;
              esac
              ;;
            false) mode=disarm-review ;;
            *) mode=error ;;
          esac
          ;;
        *) mode=error ;; # failure, cancelled, skipped, or anything unknown
      esac
    fi
    ;;
esac
echo "Gate row: candidate='${CANDIDATE}' decide='${DECIDE_RESULT}' exempt='${EXEMPT}' -> ${mode} (target PR #${TARGET})."

case "$mode" in
  plain)
    review_logic 0
    ;;
  arm)
    # No `pending` here: the exempt path never shows a pending check.
    post_status success "Verified image bump -- exempt from review."
    gh pr merge --auto --squash --match-head-commit "$HEAD_SHA" "$TARGET_URL"
    ;;
  disarm-review)
    disarm
    review_logic 0
    ;;
  *)
    echo "::warning::Decision inputs are missing or malformed (or the kill switch could not be read): never arming, sending this PR to review."
    disarm
    review_logic 1
    ;;
esac

if [ "$disarm_failed" != 0 ]; then
  exit 1
fi
