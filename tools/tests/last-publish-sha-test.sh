#!/usr/bin/env bash
# Tests for .github/scripts/last-publish-sha.sh, the lookup behind build.yml's scope job (#159).
# A fake `gh` serves the workflow-run and job lists; the scratch repo is its own `origin`, so a
# listed commit is fetchable only when the repo holds it. Offline; needs bash, git and jq.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/last-publish-sha.sh"
PUBLISH='Build, test, push and attest'
ZERO=0000000000000000000000000000000000000000
GONE=1111111111111111111111111111111111111111   # a well-formed sha the scratch repo lacks

# runs ID:SHA:EVENT[:BRANCH]... -> serves the run list (newest first), all conclusion success,
# on main unless BRANCH says otherwise.
serve_runs() {
  local r id sha ev out="" sep=""
  for r in "$@"; do
    IFS=: read -r id sha ev br <<< "$r"
    out="$out$sep{\"id\":$id,\"head_sha\":\"$sha\",\"head_branch\":\"${br:-main}\",\"event\":\"$ev\",\"conclusion\":\"success\"}"
    sep=,
  done
  printf '{"workflow_runs":[%s]}\n' "$out" > "$FAKE_FIX/actions__workflows__build.yml__runs.json"
}
# serve_jobs ID CONCLUSION  -> the run's publish job concluded so (skipped|success|failure|cancelled);
# CONCLUSION "none" serves a job list with no publish job.
serve_jobs() {
  local name="$PUBLISH"
  [ "$2" != none ] || name='Did the push change an image?'
  printf '{"jobs":[{"name":"Did the push change an image?","conclusion":"success"},{"name":"%s","conclusion":"%s"}]}\n' \
    "$name" "$2" > "$FAKE_FIX/actions__runs__$1__jobs.json"
}
# Shas are only known once the repo exists, so scenarios call serve_runs with placeholders and
# this substitutes the real ones in.
fill() { [ -f "$FAKE_FIX/actions__workflows__build.yml__runs.json" ] || return 0; sed -i "s/@C1@/$C1/g;s/@C2@/$C2/g;s/@C3@/$C3/g" "$FAKE_FIX/actions__workflows__build.yml__runs.json"; }

# Make the repo first so the scenarios can name real commits, then run.
scenario() { # description expected-base-name(C1|C2|C3|ZERO) -- body sets up the fixtures
  local d="$1" want="$2"
  new_scenario
  # three commits, C1 (oldest) .. C3, in a scratch repo that is its own origin
  local repo="$SCRATCH/repo"
  git init -q "$repo"
  for i in 1 2 3; do
    git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m "c$i"
    eval "C$i=$(git -C "$repo" rev-parse HEAD)"
  done
  git -C "$repo" remote add origin "$repo"
  SETUP
  fill
  # every listed commit relates to HEAD (C3) as an ancestor unless SETUP served otherwise
  for c in "$C1" "$C2" "$C3"; do
    f="$FAKE_FIX/compare__$c...$C3"
    if [ ! -f "$f.json" ] && [ ! -f "$f.status" ]; then
      if [ "$c" = "$C3" ]; then echo '{"status":"identical"}' > "$f.json"; else echo '{"status":"ahead"}' > "$f.json"; fi
    fi
  done
  : > "$GITHUB_OUTPUT"; : > "$SCRATCH/summary"
  RC=0
  ( cd "$repo" && env GITHUB_REPOSITORY="$REPO_NAME" GITHUB_SHA="$C3" GITHUB_STEP_SUMMARY="$SCRATCH/summary" GH_TOKEN=test-token \
      bash "$SCRIPT" ) > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
  local expect
  case "$want" in C1) expect="$C1" ;; C2) expect="$C2" ;; C3) expect="$C3" ;; *) expect="$ZERO" ;; esac
  assert_rc "$d" 0 "$RC"
  assert_eq "$d: base" "$expect" "$(outv base)"
  assert_eq "$d: written once" 1 "$(outn base)"
  [ -z "${EXTRA_CHECK:-}" ] || "$EXTRA_CHECK"
  end_scenario
}

suite "last-publish-sha.sh"

# found: the newest run published
SETUP() { serve_runs "30:@C3@:push" "20:@C2@:push"; serve_jobs 30 success; serve_jobs 20 success; }
scenario "found: newest run published" C3

# publish skipped on the newest runs: the newest one that published wins, and the skipped
# runs (which also read conclusion=success) are passed over
SETUP() { serve_runs "30:@C3@:push" "20:@C2@:push" "10:@C1@:push"; serve_jobs 30 skipped; serve_jobs 20 skipped; serve_jobs 10 success; }
scenario "publish skipped: passes over skipped runs" C1

# a publish that failed or was cancelled is not a publish, even in a run that went on
SETUP() { serve_runs "30:@C3@:push" "20:@C2@:push" "10:@C1@:push"; serve_jobs 30 failure; serve_jobs 20 cancelled; serve_jobs 10 success; }
scenario "failed and cancelled publish are passed over" C1

# schedule and dispatch runs publish too
SETUP() { serve_runs "30:@C3@:schedule" "20:@C2@:push"; serve_jobs 30 success; serve_jobs 20 success; }
scenario "found: a scheduled run counts" C3
SETUP() { serve_runs "30:@C3@:workflow_dispatch"; serve_jobs 30 success; }
scenario "found: a dispatched run counts" C3

# none: every run skipped publish, or there are no runs, or no run lists a publish job
SETUP() { serve_runs "30:@C3@:push" "20:@C2@:push"; serve_jobs 30 skipped; serve_jobs 20 skipped; }
scenario "none: every publish skipped" ZERO
SETUP() { serve_runs; }
scenario "none: no runs" ZERO
SETUP() { serve_runs "30:@C3@:push"; serve_jobs 30 none; }
scenario "none: run has no publish job" ZERO

# a run on another ref never counts: head_branch must be main
SETUP() { serve_runs "30:@C3@:push:release"; serve_jobs 30 success; }
scenario "a run on another branch is ignored" ZERO

# the query narrows to main's successful runs, newest 100
extra_query_check() { assert_log_has "run query" 'branch=main&status=success&per_page=100'; }
SETUP() { serve_runs "30:@C3@:push"; serve_jobs 30 success; }
EXTRA_CHECK=extra_query_check scenario "queries main's successful runs" C3
EXTRA_CHECK=

# the found commit must be an ancestor of HEAD: a run on a tag named main can fake a publish job
SETUP() { serve_runs "30:@C2@:push"; serve_jobs 30 success; echo '{"status":"diverged"}' > "$FAKE_FIX/compare__$C2...$C3.json"; }
scenario "not an ancestor: diverged" ZERO
SETUP() { serve_runs "30:@C2@:push"; serve_jobs 30 success; echo '{"status":"behind"}' > "$FAKE_FIX/compare__$C2...$C3.json"; }
scenario "not an ancestor: behind" ZERO
SETUP() { serve_runs "30:@C2@:push"; serve_jobs 30 success; echo 404 > "$FAKE_FIX/compare__$C2...$C3.status"; }
scenario "lookup failed: compare 404" ZERO

# a pull request run never counts, even one wearing a success publish job
SETUP() { serve_runs "30:@C3@:pull_request"; serve_jobs 30 success; }
scenario "a pull_request run is ignored" ZERO

# lookup failed: the run list, a job list, or the commit fetch
SETUP() { :; }   # nothing served: the run list is a 404
scenario "lookup failed: run list 404" ZERO
SETUP() { serve_runs "30:@C3@:push"; status_of actions__workflows__build.yml__runs neterr; }
scenario "lookup failed: run list network error" ZERO
SETUP() { serve_runs "30:@C3@:push" "20:@C2@:push"; serve_jobs 20 success; }   # run 30's jobs 404
scenario "lookup failed: a job list 404s before a good run" ZERO
SETUP() { serve_runs "30:@C3@:push"; printf 'not json' > "$FAKE_FIX/actions__runs__30__jobs.json"; }
scenario "lookup failed: job list unreadable" ZERO
SETUP() { serve_runs "30:$GONE:push"; serve_jobs 30 success; }
scenario "lookup failed: published commit not fetchable" ZERO
SETUP() { serve_runs "30:not-a-sha:push"; serve_jobs 30 success; }
scenario "lookup failed: malformed commit id" ZERO
SETUP() { serve_runs "30:@C3@:push"; sed -i 's/"id":30/"id":"3;0"/' "$FAKE_FIX/actions__workflows__build.yml__runs.json"; }
scenario "lookup failed: malformed run id" ZERO

# the failure cases say so out loud
new_scenario; SETUP() { :; }
repo="$SCRATCH/repo"; git init -q "$repo"; git -C "$repo" remote add origin "$repo"
: > "$SCRATCH/summary"
( cd "$repo" && env GITHUB_REPOSITORY="$REPO_NAME" GITHUB_SHA="$ZERO" GITHUB_STEP_SUMMARY="$SCRATCH/summary" GH_TOKEN=t bash "$SCRIPT" ) > "$SCRATCH/stdout" 2>&1
if grep -q '^::warning::Last successful publish not found (run lookup failed): building' "$SCRATCH/stdout"; then pass; else fail "a failed lookup warns" "$(cat "$SCRATCH/stdout")"; fi
if grep -q 'building' "$SCRATCH/summary"; then pass; else fail "a failed lookup writes the step summary"; fi
end_scenario

summary
