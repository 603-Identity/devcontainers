#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2119,SC2120,SC2015,SC2016
# Tests for tools/gate-post.sh: the existing review logic, the decision table row by row,
# target selection, the always-in-scope .github/ rule, and the H1 test.
# Fixtures are hand-built from the GitHub REST shapes (see fixtures/post-base).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite gate-post

CONSUMER_CASE='.devcontainer/*|docs/*) touches=1 ;;'
KS_PATH='repos/603-Identity/devcontainers/git/ref/tags/devc-automerge-on'
MERGE_CALL="gh pr merge --auto --squash --match-head-commit $SHA https://github.com/$REPO_NAME/pull/2"
DISARM_CALL="gh pr merge --disable-auto https://github.com/$REPO_NAME/pull/2"

# A scenario whose consumer case block is CONSUMER_CASE (not this repo's list).
post_scenario() {
  new_scenario post-base "$@"
  POST_SCRIPT="$(with_case_block "$CONSUMER_CASE")"
  export POST_SCRIPT
}
add_review() { # [PR number]  -> a qualifying formal review, on the head SHA, from a reviewer on that PR
  put "pulls__${1:-2}__reviews" post-reviews/formal-review-qualifying.json
}
all_statuses_on_head() {
  if [ -n "$(status_calls)" ] && ! status_calls | grep -qv "repos/$REPO_NAME/statuses/$SHA "; then pass; else fail "$1: every status goes to the head SHA" "$(status_calls)"; fi
}

# --- the harness itself: the case-block substitution really replaced the list ----------
post_scenario
if grep -qF 'images/*' "$POST_SCRIPT" || ! grep -qF "$CONSUMER_CASE" "$POST_SCRIPT"; then fail "with_case_block replaced the region"; else pass; fi
if grep -q '^        \.github/\*) touches=1 ;;$' "$POST_SCRIPT"; then pass; else fail "the .github/ rule is outside the consumer region"; fi
end_scenario

# =====================================================================================
# The existing review logic (candidate=false)
# =====================================================================================

# In scope, no review: pending, then failure. Exit 0 on purpose.
post_scenario
run_post
assert_rc "no review" 0 "$RC"
assert_states "no review" "pending failure"
assert_log_has "no review: files read from the PR" "pulls/2/files"
assert_log_lacks "no review: kill switch untouched" "$KS_PATH"
assert_log_lacks "no review: nothing armed or disarmed" "gh pr merge"
all_statuses_on_head "no review"
if status_calls | grep -qF -- '-f context=architect-review'; then pass; else fail "status context"; fi
end_scenario

# A qualifying formal review, made against the head SHA.
post_scenario
add_review
run_post
assert_states "qualifying formal review" "pending success"
end_scenario

# A comment never counts, even a perfect one from a reviewer (#94: a body can be edited).
post_scenario
put issues__2__comments post-reviews/comment-qualifying.json
run_post
assert_rc "qualifying comment" 0 "$RC"
assert_states "a comment does not qualify" "pending failure"
assert_log_lacks "a comment is never read" "issues/2/comments"
end_scenario

# Reviews that must not count: each is the qualifying review with one thing wrong.
while IFS='|' read -r name filter; do
  post_scenario
  add_review
  mut pulls__2__reviews "$filter"
  run_post
  assert_rc "$name" 0 "$RC"
  assert_states "$name does not qualify" "pending failure"
  end_scenario
done <<'CASES'
stranger|.[0].user.id = 999
quoted|.[0].body = "> " + (.[0].body | gsub("\n"; "\n> "))
id-prefix|.[0].user.id = 2816930
header-only|.[0].body = "**Opus/Architect HITL review (automated)** only"
other-sha (an earlier head)|.[0].commit_id = "0000000000000000000000000000000000000001"
no commit_id|del(.[0].commit_id)
null commit_id|.[0].commit_id = null
dismissed|.[0].state = "DISMISSED"
pending|.[0].state = "PENDING"
CASES

# #96: a missing id must not match a doubled space in REVIEWER_IDS; the numeric test alone stops it.
post_scenario
add_review
mut pulls__2__reviews '.[0].user.id = null'
run_post REVIEWER_IDS="1  $REVIEWER"
assert_states "null id with a doubled-space REVIEWER_IDS does not qualify" "pending failure"
end_scenario

# #92: the review's date no longer matters. A review made against the head SHA counts even when
# it predates the head commit's committer date (backdated commit); a newer one on another SHA does not.
post_scenario
add_review
mut pulls__2__reviews '.[0].submitted_at = "2020-01-01T00:00:00Z"'
run_post
assert_states "head-SHA review older than the commit date" "pending success"
end_scenario
post_scenario
add_review
mut pulls__2__reviews '.[0].commit_id = "0000000000000000000000000000000000000001" | .[0].submitted_at = "2099-01-01T00:00:00Z"'
run_post
assert_states "newer review on another SHA" "pending failure"
if grep -qF "not the head" "$SCRATCH/stdout"; then pass; else fail "other-SHA review: named in the output"; fi
end_scenario

# #94: a review whose body was edited counts only when EVERY editor in its history is in
# REVIEWER_IDS. The history comes from a GraphQL node lookup (REST has no edit metadata on
# reviews). Each case replaces the served GraphQL document for the qualifying review.
edits() { # editor-json... -> a userContentEdits document with one node per argument
  local nodes
  nodes="$(printf '%s,' "$@")"
  printf '{"data":{"node":{"userContentEdits":{"totalCount":%s,"nodes":[%s]}}}}\n' "$#" "${nodes%,}"
}
set_edit() { # json -> the GraphQL response served for the qualifying review
  printf '%s\n' "$1" > "$FAKE_FIX/graphql__PRR_qualifying.json"
}
ED() { printf '{"editor":{"login":"x","databaseId":%s}}' "$1"; } # an edit by this user id
post_scenario
add_review
run_post
assert_states "unedited review" "pending success"
assert_log_has "the review's node id is looked up" "id=PRR_qualifying"
end_scenario
post_scenario
add_review
set_edit "$(edits "$(ED "$REVIEWER")" "$(ED 999)")"
run_post
assert_rc "edited by a stranger" 0 "$RC"
assert_states "edited by a non-reviewer does not qualify" "pending failure"
if grep -qF "999" "$SCRATCH/stdout"; then pass; else fail "edited review: the editor is named in the output"; fi
end_scenario
post_scenario
add_review
set_edit "$(edits "$(ED 999)" "$(ED "$REVIEWER")")"
run_post
assert_states "a stranger's edit followed by a reviewer's does not qualify" "pending failure"
end_scenario
post_scenario
add_review
set_edit "$(edits "$(ED "$REVIEWER")" "$(ED "$REVIEWER")")"
run_post
assert_states "edited only by reviewers still qualifies" "pending success"
end_scenario
post_scenario
add_review
set_edit "$(edits "$(ED 3)" "$(ED "$REVIEWER")")"
run_post REVIEWER_IDS="1 $REVIEWER 3"
assert_states "edited by two different reviewers in a list qualifies" "pending success"
end_scenario
post_scenario
add_review
set_edit "$(edits "$(ED "${REVIEWER:0:7}")")"
run_post
assert_states "an editor id that is a prefix of a reviewer's id does not qualify" "pending failure"
end_scenario
post_scenario
add_review
set_edit "$(edits '{"editor":null}')"
run_post
assert_states "edited by an unreadable account fails closed" "pending failure"
end_scenario
post_scenario
add_review
set_edit "$(edits '{"editor":{"login":"ghost"}}')"
run_post
assert_states "edited by an account with no id fails closed" "pending failure"
end_scenario
post_scenario
add_review
set_edit '{"data":{"node":{"userContentEdits":{"totalCount":101,"nodes":[{"editor":{"databaseId":'"$REVIEWER"'}}]}}}}'
run_post
assert_states "a history longer than one page fails closed" "pending failure"
end_scenario
post_scenario
add_review
set_edit '{"data":{"node":{"userContentEdits":{"totalCount":1,"nodes":[{"deletedAt":"2026-10-06T15:00:00Z","editor":{"databaseId":'"$REVIEWER"'}}]}}}}'
run_post
assert_states "a deleted revision in the history fails closed" "pending failure"
end_scenario
post_scenario
add_review
set_edit '{"data":{"node":{}}}'
run_post
assert_states "a node that is not a review fails closed" "pending failure"
end_scenario
post_scenario
add_review
set_edit '{"data":{"node":null}}'
run_post
assert_states "a null node fails closed" "pending failure"
end_scenario
post_scenario
add_review
mut pulls__2__reviews 'del(.[0].node_id)'
run_post
assert_states "a review with no node id cannot be checked and does not qualify" "pending failure"
end_scenario
post_scenario
add_review
drop graphql__PRR_qualifying
run_post
assert_rc "failed edit lookup" 1 "$RC"
assert_states "a failed edit lookup fails the job, never reads as unedited" "pending"
end_scenario
post_scenario
add_review
mut pulls__2__reviews '.[0].commit_id = "0000000000000000000000000000000000000001"'
run_post
assert_log_lacks "no edit lookup for a review already ruled out by its SHA" "graphql"
end_scenario
post_scenario
add_review
mut pulls__2__reviews '.[0].user.id = 999'
run_post
assert_log_lacks "no edit lookup for a review by a stranger" "graphql"
end_scenario
# A later, unedited qualifying review is still found past an edited one.
post_scenario
add_review
set_edit "$(edits "$(ED 999)")"
mut pulls__2__reviews '. + [.[0] | .node_id = "PRR_second"]'
echo '{"data":{"node":{"userContentEdits":{"totalCount":0,"nodes":[]}}}}' > "$FAKE_FIX/graphql__PRR_second.json"
run_post
assert_states "an edited review does not hide a later unedited one" "pending success"
end_scenario

# One stale review does not hide a later qualifying one, and REVIEWER_IDS is a list.
post_scenario
add_review
mut pulls__2__reviews '. + [.[0] | .commit_id = "0000000000000000000000000000000000000001"] | reverse'
run_post REVIEWER_IDS="1 $REVIEWER 3"
assert_states "stale review first, qualifying second, id in a list" "pending success"
end_scenario

# Out of scope: success, with pending first.
post_scenario
put pulls__2__files post-base/pulls__7__files.json
run_post
assert_states "out of scope" "pending success"
assert_log_has "out of scope: description" "No code_paths touched -- no review required."
assert_log_lacks "out of scope: review not looked up" "pulls/2/reviews"
end_scenario

# A rename out of scope checks the OLD path.
post_scenario
echo '[{"filename":"README.md","previous_filename":".devcontainer/Dockerfile","status":"renamed","additions":0,"deletions":0}]' > "$FAKE_FIX/pulls__2__files.json"
run_post
assert_states "rename out of scope" "pending failure"
end_scenario

# Empty file list fails closed, with exit 1.
post_scenario
echo '[]' > "$FAKE_FIX/pulls__2__files.json"
run_post
assert_rc "empty files" 1 "$RC"
assert_states "empty files" "pending failure"
end_scenario

# A failing files call fails the job and never reads as "nothing in scope".
post_scenario
status_of pulls__2__files 500
run_post
if [ "$RC" -ne 0 ]; then pass; else fail "files API error must fail the job"; fi
assert_states "files API error" "pending"
end_scenario

# A failing review lookup fails the job and posts no success.
post_scenario
status_of pulls__2__reviews 500
run_post
if [ "$RC" -ne 0 ]; then pass; else fail "reviews API error must fail the job"; fi
assert_states "reviews API error" "pending"
end_scenario

# This repo's own list (no case-block substitution): tools/, .ai/project.yml in scope; docs/ out.
new_scenario post-base
unset POST_SCRIPT
for f in tools/gate-post.sh .ai/project.yml images/base/Dockerfile .trivyignore.yaml template/x; do
  echo "[{\"filename\":\"$f\",\"status\":\"modified\"}]" > "$FAKE_FIX/pulls__2__files.json"
  : > "$FAKE_LOG"
  run_post
  assert_states "default list: $f in scope" "pending failure"
done
echo '[{"filename":"docs/roadmap.md","status":"modified"}]' > "$FAKE_FIX/pulls__2__files.json"
: > "$FAKE_LOG"
run_post
assert_states "default list: docs/ out of scope" "pending success"
end_scenario

# =====================================================================================
# The decision table
# =====================================================================================

# Row 1: candidate=false, decide skipped: the existing logic on PR, never the kill switch.
# A stale or lying decide output is ignored when candidate is false.
post_scenario
run_post CANDIDATE=false DECIDE_RESULT=success EXEMPT=true
assert_states "candidate=false ignores exempt=true" "pending failure"
assert_log_lacks "candidate=false: no kill switch" "$KS_PATH"
assert_log_lacks "candidate=false: no merge call" "gh pr merge"
end_scenario

# Row 2: candidate, success, exempt=true, kill switch on (200 + right ref): success + arm.
post_scenario
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
assert_rc "arm" 0 "$RC"
assert_states "arm: success only, never pending" "success"
assert_log_has "arm: kill switch read" "gh api -i $KS_PATH"
assert_log_has "arm: exact merge call" "$MERGE_CALL"
assert_log_lacks "arm: not disarmed" "--disable-auto"
assert_log_lacks "arm: no review lookup" "pulls/2/reviews"
assert_log_has "arm: description" "Verified image bump -- exempt from review."
all_statuses_on_head "arm"
end_scenario

# An arm failure fails the job (the status stays: the bump is verified).
post_scenario
FAKE_MERGE_RC=1 run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
if [ "$RC" -ne 0 ]; then pass; else fail "a failed arm must fail the job"; fi
end_scenario

# Kill switch off: 200 with the wrong ref, and 404 -> disarm, then review (K1).
post_scenario
mut git__ref__tags__devc-automerge-on '.ref = "refs/tags/devc-automerge-onx"'
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
assert_states "kill switch wrong ref, no review" "pending failure"
assert_log_has "kill switch wrong ref: disarmed" "$DISARM_CALL"
assert_log_lacks "kill switch wrong ref: never armed" "--auto --squash"
end_scenario
post_scenario
echo '[{"ref":"refs/tags/devc-automerge-on"}]' > "$FAKE_FIX/git__ref__tags__devc-automerge-on.json"
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
assert_states "kill switch array body is not the switch" "pending failure"
assert_log_lacks "kill switch array body: never armed" "--auto --squash"
end_scenario
post_scenario
drop git__ref__tags__devc-automerge-on
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
assert_states "kill switch 404, no review" "pending failure"
assert_log_has "kill switch 404: disarmed" "$DISARM_CALL"
assert_log_lacks "kill switch 404: never armed" "--auto --squash"
end_scenario
post_scenario
drop git__ref__tags__devc-automerge-on
add_review
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
assert_states "kill switch 404, reviewed" "pending success"
end_scenario

# Kill switch unreadable: 500 and network failure -> the error row.
for ks in 500 502 403 neterr; do
  post_scenario
  status_of git__ref__tags__devc-automerge-on "$ks"
  run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
  assert_rc "kill switch $ks" 0 "$RC"
  assert_states "kill switch $ks -> error row, no review" "pending failure"
  assert_log_has "kill switch $ks: disarmed" "$DISARM_CALL"
  assert_log_lacks "kill switch $ks: never armed" "--auto --squash"
  end_scenario
done
post_scenario
status_of git__ref__tags__devc-automerge-on 500
add_review
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
assert_states "kill switch 500, reviewed: a review can still make it green" "pending success"
end_scenario

# Row: success but exempt=false (a MAJOR bump or a downgrade): disarm + review.
post_scenario
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=false
assert_states "exempt=false, no review" "pending failure"
assert_log_has "exempt=false: disarmed" "$DISARM_CALL"
assert_log_lacks "exempt=false: kill switch not read" "$KS_PATH"
assert_log_lacks "exempt=false: never armed" "--auto --squash"
end_scenario
post_scenario
add_review
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=false
assert_states "exempt=false, reviewed" "pending success"
end_scenario

# Row: decide failure / cancelled / skipped for a candidate: the error row (K2).
for r in failure cancelled skipped; do
  for ex in true false ""; do
    post_scenario
    run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=$r EXEMPT=$ex
    assert_states "decide $r exempt='$ex': error row, no review" "pending failure"
    assert_log_has "decide $r exempt='$ex': disarmed" "$DISARM_CALL"
    assert_log_lacks "decide $r exempt='$ex': never armed" "--auto --squash"
    assert_log_lacks "decide $r exempt='$ex': kill switch not read" "$KS_PATH"
    end_scenario
  done
done
post_scenario
add_review
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=failure EXEMPT=true
assert_states "decide failure, reviewed: a review can still make it green" "pending success"
end_scenario

# The error row forces "in scope": an earlier exempt success becomes failure even when the
# consumer's list would call the files out of scope.
post_scenario
put pulls__2__files post-base/pulls__7__files.json
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=cancelled EXEMPT=
assert_states "error row never reads 'no code_paths touched'" "pending failure"
assert_log_lacks "error row: files not consulted" "pulls/2/files"
end_scenario

# Row: a candidate/exempt/decide value other than the allowed ones: the error row.
for bad in "" yes TRUE True 1 null; do
  post_scenario
  run_post CANDIDATE="$bad" CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
  assert_states "malformed candidate '$bad'" "pending failure"
  assert_log_lacks "malformed candidate '$bad': never armed" "--auto --squash"
  assert_log_lacks "malformed candidate '$bad': kill switch not read" "$KS_PATH"
  end_scenario
done
for bad in "" yes TRUE True 1 null; do
  post_scenario
  run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT="$bad"
  assert_states "malformed exempt '$bad'" "pending failure"
  assert_log_lacks "malformed exempt '$bad': never armed" "--auto --squash"
  assert_log_has "malformed exempt '$bad': disarmed" "$DISARM_CALL"
  end_scenario
done
for bad in "" abc "2 3" "-1"; do
  post_scenario
  run_post CANDIDATE=true CANDIDATE_PR="$bad" DECIDE_RESULT=success EXEMPT=true
  assert_states "malformed candidate_pr '$bad'" "pending failure"
  assert_log_lacks "malformed candidate_pr '$bad': never armed" "--auto --squash"
  end_scenario
done
post_scenario
run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=weird EXEMPT=true
assert_states "unknown decide result" "pending failure"
assert_log_lacks "unknown decide result: never armed" "--auto --squash"
end_scenario

# Malformed resolve outputs (head sha, PR): nothing is posted.
post_scenario
run_post HEAD_SHA=nothex
assert_rc "malformed head sha" 1 "$RC"
assert_eq "malformed head sha: nothing posted" "" "$(cat "$FAKE_LOG")"
run_post PR=abc
assert_rc "malformed pr" 1 "$RC"
assert_eq "malformed pr: nothing posted" "" "$(cat "$FAKE_LOG")"
end_scenario

# A disarm failure still posts the status, and fails the job loudly.
post_scenario
FAKE_DISARM_RC=1 run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=false
assert_rc "disarm failure" 1 "$RC"
assert_states "disarm failure still posts the status" "pending failure"
end_scenario

# A PR that was never armed is not disarmed: `--disable-auto` would error on it.
post_scenario
FAKE_ARMED=0 run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=false
assert_rc "unarmed PR: job stays green" 0 "$RC"
assert_log_lacks "unarmed PR: no disable-auto call" "--disable-auto"
assert_states "unarmed PR: status still posted" "pending failure"
end_scenario

# If the armed-or-not lookup fails, disarm anyway.
post_scenario
FAKE_VIEW_RC=1 run_post CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=false
assert_log_has "lookup failed: disarmed anyway" "$DISARM_CALL"
end_scenario

# =====================================================================================
# Target selection (security MEDIUM-1): everything acts on candidate_pr when candidate=true
# =====================================================================================

# A reviewer's review on fork PR #7 at a candidate SHA, candidate PR #2 (kill switch off).
post_scenario
add_review 2
run_post PR=7 CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=false
assert_states "target = candidate PR: review on the candidate PR counts" "pending success"
assert_log_has "target: files of the candidate PR" "pulls/2/files"
assert_log_has "target: reviews of the candidate PR" "pulls/2/reviews"
assert_log_lacks "target: nothing read from the fork PR" "pulls/7"
assert_log_lacks "target: nothing read from the fork PR (comments)" "issues/7"
assert_log_has "target: disarm acts on the candidate PR" "$DISARM_CALL"
end_scenario
post_scenario
add_review 7
run_post PR=7 CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=false
assert_states "target = candidate PR: a review on the fork PR does not count" "pending failure"
end_scenario
post_scenario
run_post PR=7 CANDIDATE=true CANDIDATE_PR=2 DECIDE_RESULT=success EXEMPT=true
assert_log_has "target: arming acts on the candidate PR" "$MERGE_CALL"
assert_log_lacks "target: nothing armed on the fork PR" "pull/7"
end_scenario
# candidate=false: the triggering PR.
post_scenario
run_post PR=7 CANDIDATE=false
assert_log_has "candidate=false: target = the triggering PR" "pulls/7/files"
assert_log_lacks "candidate=false: the other PR untouched" "pulls/2"
assert_states "candidate=false on PR 7 (README only)" "pending success"
end_scenario

# =====================================================================================
# The .github/ rule (security HIGH-1): always in scope, whatever the consumer's list says
# =====================================================================================
GATE_FILE='.github/workflows/architect-review-gate.yml'
post_scenario # the consumer list omits .github/
echo "[{\"filename\":\"$GATE_FILE\",\"status\":\"modified\",\"additions\":1,\"deletions\":1}]" > "$FAKE_FIX/pulls__2__files.json"
run_post
assert_states ".github/ in scope though the consumer list omits it" "pending failure"
add_review
: > "$FAKE_LOG"
run_post
assert_states ".github/ with a review" "pending success"
end_scenario
post_scenario
echo "[{\"filename\":\"docs/x.md\",\"previous_filename\":\"$GATE_FILE\",\"status\":\"renamed\"}]" > "$FAKE_FIX/pulls__2__files.json"
run_post
assert_states ".github/ renamed away is still in scope" "pending failure"
end_scenario
post_scenario
POST_SCRIPT="$(with_case_block '')"
echo "[{\"filename\":\"$GATE_FILE\",\"status\":\"modified\"}]" > "$FAKE_FIX/pulls__2__files.json"
run_post
assert_states ".github/ in scope with an EMPTY consumer list" "pending failure"
echo '[{"filename":"src/app.go","status":"modified"}]' > "$FAKE_FIX/pulls__2__files.json"
: > "$FAKE_LOG"
run_post
assert_states "an empty consumer list leaves everything else out of scope" "pending success"
end_scenario

# =====================================================================================
# The H1 test: a decide that always says exempt=true must never turn a decision-pin bump
# PR green without a review. Chain resolve -> post on the same fixtures.
# =====================================================================================
new_scenario resolve-base post-base gate-pin-bump
POST_SCRIPT="$(with_case_block "$CONSUMER_CASE")"
export POST_SCRIPT
run_resolve
assert_eq "H1: resolve says not a candidate" false "$(outv candidate)"
cand="$(outv candidate)"
cpr="$(outv candidate_pr)"
: > "$FAKE_LOG"
# The stub decision: always success + exempt=true (it is skipped in reality, but even a
# lying output must not matter).
run_post CANDIDATE="$cand" CANDIDATE_PR="$cpr" DECIDE_RESULT=success EXEMPT=true
assert_states "H1: stub exempt=true, no review" "pending failure"
assert_log_lacks "H1: never armed" "--auto --squash"
: > "$FAKE_LOG"
run_post CANDIDATE="$cand" CANDIDATE_PR="$cpr" DECIDE_RESULT=skipped EXEMPT=true
assert_states "H1: skipped decide with exempt=true, no review" "pending failure"
for last in $(states); do
  if [ "$last" = success ]; then fail "H1: success without a review"; fi
done
add_review
: > "$FAKE_LOG"
run_post CANDIDATE="$cand" CANDIDATE_PR="$cpr" DECIDE_RESULT=skipped EXEMPT=true
assert_states "H1: with a review it can be green" "pending success"
end_scenario

summary
