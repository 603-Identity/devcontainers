#!/usr/bin/env bash
# shellcheck disable=SC1091
# Tests for .github/scripts/release-verify.sh (#486): a commit is releasable only when exactly one
# merged PR produced it, every required check is green on that PR's head, and main's push runs on it
# all succeeded. Offline: the fake `gh` (tools/tests/bin/gh) serves the fixtures in
# fixtures/release-verify and logs every call. Needs bash, jq and yq (mikefarah).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite release-verify

VERIFY="$ROOT_DIR/.github/scripts/release-verify.sh"
HEAD_SHA=feedfacefeedfacefeedfacefeedfacefeedface
PULLS="commits__${SHA}__pulls"
RUNS="commits__${HEAD_SHA}__check-runs"
STAT="commits__${HEAD_SHA}__status"
PUSH="actions__runs"
ARGS=()

# run_verify [-u VAR | VAR=value]...  -> RC, ERR. Defaults describe a valid call on $SHA.
run_verify() {
  local -a set=(REPO="$REPO_NAME" GH_TOKEN=test-token PROJECT_FILE="$FAKE_FIX/project.yml") extra=() skip=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -u) skip+=("$2"); shift 2 ;;
      *) extra+=("$1"); shift ;;
    esac
  done
  local -a keep=() s v
  for v in "${set[@]}"; do
    for s in "${skip[@]+"${skip[@]}"}"; do [ "${v%%=*}" = "$s" ] && continue 2; done
    keep+=("$v")
  done
  RC=0
  env -u REPO -u GH_TOKEN -u PROJECT_FILE "${keep[@]}" "${extra[@]+"${extra[@]}"}" \
    bash "$VERIFY" "${ARGS[@]+"${ARGS[@]}"}" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
  ERR="$(cat "$SCRATCH/stderr")"
}
ok_args() { ARGS=("$SHA"); }
has() { # description needle
  if [[ "$ERR" == *"$2"* ]]; then pass; else fail "$1" "wanted '$2' in: $ERR"; fi
}
refuses() { # description [needle]
  assert_rc "$1" 1 "$RC"
  if [ -n "${2:-}" ]; then has "$1 (message)" "$2"; fi
}
scenario() { new_scenario release-verify; ok_args; }

# --- pass ------------------------------------------------------------------------------------
scenario; run_verify
assert_rc "everything green passes" 0 "$RC"
assert_eq "the pass line" "release-verify: ok ($SHA)." "$(cat "$SCRATCH/stdout")"
end_scenario

# --- the PR ----------------------------------------------------------------------------------
scenario; mut "$PULLS" '[]'; run_verify
refuses "no PR for the SHA" "no PR merged into main has $SHA"; end_scenario
scenario; mut "$PULLS" '. + [(.[0] | .number = 8)]'; run_verify
refuses "two candidate PRs" "more than one PR"; has "...naming both" "#7 #8"; end_scenario
scenario; mut "$PULLS" '.[0].base.ref = "develop"'; run_verify
refuses "a PR whose base is not main"; end_scenario
scenario; mut "$PULLS" '.[0].merge_commit_sha = "1111111111111111111111111111111111111111"'; run_verify
refuses "a PR whose merge_commit_sha is not the SHA"; end_scenario
scenario; mut "$PULLS" '.[0].merged_at = null | .[0].state = "closed"'; run_verify
refuses "a closed PR with a null merged_at"; end_scenario
scenario; mut "$PULLS" '. + [(.[0] | .number = 9 | .base.ref = "develop")]'; run_verify
assert_rc "a second PR that does not qualify is ignored" 0 "$RC"; end_scenario

# --- the required checks ---------------------------------------------------------------------
for c in failure skipped neutral cancelled timed_out; do
  scenario; mut "$RUNS" "(.check_runs[] | select(.name == \"selftest\") | .conclusion) = \"$c\""; run_verify
  refuses "a required check run concluding $c" "selftest"; end_scenario
done
scenario; mut "$RUNS" '(.check_runs[] | select(.name == "selftest")) |= (.status = "in_progress" | .conclusion = null)'; run_verify
refuses "a required check run still in_progress" "selftest"; end_scenario
scenario; mut "$RUNS" '.check_runs |= map(select(.name != "selftest"))'; run_verify
refuses "a required check run missing entirely" "selftest is missing"; end_scenario

# The run of a name with the highest id decides, wherever it sits in the list.
scenario; mut "$RUNS" '(.check_runs[] | select(.name == "selftest")) |= (.conclusion = "failure")
  | .check_runs = [{ "id": 9, "name": "selftest", "status": "completed", "conclusion": "success" }] + .check_runs'; run_verify
assert_rc "a rerun whose highest-id run succeeded passes" 0 "$RC"; end_scenario
scenario; mut "$RUNS" '.check_runs = [{ "id": 9, "name": "selftest", "status": "completed", "conclusion": "failure" }] + .check_runs'; run_verify
refuses "a rerun whose highest-id run failed" "selftest"; end_scenario

# architect-review is read from the combined status, and only from there.
scenario; run_verify; assert_rc "architect-review: success passes" 0 "$RC"; end_scenario
for st in failure pending error; do
  scenario; mut "$STAT" "(.statuses[] | select(.context == \"architect-review\") | .state) = \"$st\""; run_verify
  refuses "architect-review status $st" "architect-review is $st"; end_scenario
done
scenario; mut "$STAT" '.statuses |= map(select(.context != "architect-review"))'; run_verify
refuses "architect-review absent from the statuses" "architect-review is missing"; end_scenario
scenario; mut "$STAT" '.statuses |= map(select(.context != "architect-review"))'
mut "$RUNS" '(.check_runs[] | select(.name == "architect-review")) |= (.conclusion = "success")'; run_verify
refuses "a success check run named architect-review with no such status" "architect-review is missing"; end_scenario
scenario; mut "$STAT" '.statuses = [{ "id": 11, "context": "architect-review", "state": "success" },
    { "id": 12, "context": "selftest", "state": "success" }]'
mut "$RUNS" '(.check_runs[] | select(.name == "selftest")) |= (.conclusion = "failure")'; run_verify
refuses "a success status named after a required check run whose run failed" "selftest"; end_scenario
scenario; mut "$STAT" '.statuses = [{ "id": 11, "context": "architect-review", "state": "success" }]'
mut "$RUNS" '.check_runs |= map(select(.name != "selftest"))'; run_verify
refuses "a success status named after a required check run whose run is missing" "selftest is missing"; end_scenario
scenario; mut "$STAT" '.statuses = [{ "id": 11, "context": "architect-review", "state": "success" }]'; run_verify
assert_rc "no status named after a required check run is needed when its run succeeded" 0 "$RC"; end_scenario
scenario; mut "$STAT" '.statuses = [{ "id": 20, "context": "architect-review", "state": "failure" }, { "id": 11, "context": "architect-review", "state": "success" }]'; run_verify
refuses "the latest status of a context decides (a later failure)" "architect-review is failure"; end_scenario

# The project file.
scenario; yq -i 'del(.rulesets[] | select(.name == "main-required-checks"))' "$FAKE_FIX/project.yml"; run_verify
refuses "a project file with no main-required-checks entry" "no required checks"; end_scenario
scenario; yq -i '(.rulesets[] | select(.name == "main-required-checks") | .required_checks) = []' "$FAKE_FIX/project.yml"; run_verify
refuses "an empty required_checks list" "no required checks"; end_scenario
scenario; yq -i 'del(.review.ci_gate.check)' "$FAKE_FIX/project.yml"; run_verify
refuses "no review.ci_gate.check" "review.ci_gate.check"; end_scenario
scenario; yq -i '.review.ci_gate.check = ""' "$FAKE_FIX/project.yml"; run_verify
refuses "an empty review.ci_gate.check" "review.ci_gate.check"; end_scenario
scenario; run_verify "PROJECT_FILE=$SCRATCH/does-not-exist.yml"
refuses "a PROJECT_FILE that does not exist" "missing or unreadable"; end_scenario
scenario; printf 'rulesets: [unterminated\n  - x: : :\n' > "$SCRATCH/bad.yml"; run_verify "PROJECT_FILE=$SCRATCH/bad.yml"
refuses "a PROJECT_FILE that does not parse"; end_scenario
# A check name is bound as a value, never spliced into an expression.
scenario; yq -i '(.rulesets[] | select(.name == "main-required-checks") | .required_checks) += ["x\") or (1==1"]' "$FAKE_FIX/project.yml"; run_verify
refuses "an expression-like check name is just a missing name" "is missing"; end_scenario

# --- the push runs ---------------------------------------------------------------------------
for c in failure cancelled; do
  scenario; mut "$PUSH" "(.workflow_runs[] | select(.id == 102) | .conclusion) = \"$c\""; run_verify
  refuses "a push run concluding $c" "push run 102 (Lint)"; end_scenario
done
scenario; mut "$PUSH" '(.workflow_runs[] | select(.id == 102)) |= (.status = "in_progress" | .conclusion = null)'; run_verify
refuses "a push run still in_progress" "push run 102 (Lint)"; has "...says to dispatch again" "dispatch again once it has finished"; end_scenario
scenario; mut "$PUSH" '(.workflow_runs[] | select(.id == 101) | .conclusion) = "cancelled"'; run_verify
refuses "a cancelled build.yml push run" "push run 101"; has "...is never re-run" "never re-run a build.yml push run"; end_scenario
# An empty field must not shift the fields after it: a failed run with a null name and path is still read.
scenario; mut "$PUSH" '(.workflow_runs[] | select(.id == 102)) |= (.name = null | .path = null | .conclusion = "failure")'; run_verify
refuses "a failed push run with null name and path is still counted" "push run 102"; end_scenario
scenario; mut "$PUSH" '(.workflow_runs[] | select(.id == 102)) |= (.name = null | .path = null)'; run_verify
assert_rc "a green push run with null name and path passes" 0 "$RC"; end_scenario
scenario; mut "$RUNS" '(.check_runs[] | select(.name == "selftest")) |= (.conclusion = null | .status = "queued")'; run_verify
refuses "a check run with a null conclusion is read as not completed" "selftest"; end_scenario
scenario; mut "$PUSH" '.workflow_runs = []'; run_verify
refuses "no push runs" "no push-event workflow run"; end_scenario
scenario; mut "$PUSH" '.workflow_runs |= map(select(.id > 200))'; run_verify
refuses "only runs for other SHAs, events or branches" "no push-event workflow run"; end_scenario

# --- filtering and errors --------------------------------------------------------------------
scenario; run_verify
assert_rc "runs for another SHA, event or branch are ignored" 0 "$RC"
assert_log_has "the runs call asks for head_sha" "head_sha=$SHA"
assert_log_has "the runs call asks for event=push" "event=push"
assert_log_has "the runs call asks for branch=main" "branch=main"
assert_log_has "the PR is looked up by the SHA" "commits/$SHA/pulls"
assert_log_has "the checks are read on the PR's head" "commits/$HEAD_SHA/check-runs"
assert_log_has "the statuses are read on the PR's head" "commits/$HEAD_SHA/status"
assert_log_lacks "no slurp" "--slurp"
assert_log_lacks "no explicit method" " -X "
end_scenario

for fx in "$PULLS" "$RUNS" "$STAT" "$PUSH"; do
  for code in 500 neterr; do
    scenario; status_of "$fx" "$code"; run_verify
    refuses "an API error ($code) on ${fx%%__*} refuses" "API call"; end_scenario
  done
done
scenario; drop "$RUNS"; run_verify; refuses "a 404 on the check runs refuses" "API call"; end_scenario

# --- usage errors ----------------------------------------------------------------------------
scenario
ARGS=(); run_verify; assert_rc "a missing SHA" 2 "$RC"
ARGS=(abc); run_verify; assert_rc "a short SHA" 2 "$RC"
ARGS=("$(printf '%s' "$SHA" | tr a-f A-F)"); run_verify; assert_rc "an uppercase SHA" 2 "$RC"
ARGS=("${SHA}0"); run_verify; assert_rc "a 41-character SHA" 2 "$RC"
ARGS=("$SHA" extra); run_verify; assert_rc "an extra argument" 2 "$RC"
ok_args
run_verify -u REPO; assert_rc "an unset REPO" 2 "$RC"
for r in "" owner "owner/" "/name" "a/b/c" "../x" "./x" "owner/.." "owner/." "ow_ner/name" "owner/na me" "owner/na"$'\n'"me" "owner/name"$'\n'; do
  run_verify "REPO=$r"; assert_rc "REPO '${r//$'\n'/\\n}' is a usage error" 2 "$RC"
done
run_verify "REPO=Own-er9/na.me_1-x"; assert_rc "a well-formed REPO is accepted" 0 "$RC"
run_verify -u GH_TOKEN; assert_rc "an unset GH_TOKEN" 2 "$RC"
end_scenario

summary
