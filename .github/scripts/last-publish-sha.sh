#!/usr/bin/env bash
# Finds the commit of the last successful publish on main and writes base=<sha> to
# $GITHUB_OUTPUT, for build.yml's scope job to hand to image-scope.sh as the commit to diff
# HEAD against (#159). Diffing the push's own `before` loses a change whose publish never ran:
# a pending run cancelled by a newer push (concurrency keeps one running and one pending), or
# a publish that failed, followed only by docs-only pushes.
#
# Env: GH_TOKEN (actions: read for the run and job lists; contents: read for the compare call), GITHUB_REPOSITORY, GITHUB_SHA (HEAD), GITHUB_OUTPUT,
# GITHUB_STEP_SUMMARY.
# Run from a checkout with `origin` pointing at the repo.
#
# "Successful" is the publish JOB's conclusion, not the run's: a run whose publish was skipped
# (a docs-only push) also reads `success`. Only a push, schedule or dispatch run on main counts
# (a pull request run's publish job is always skipped, and a fork's branch can be named
# `main`). A tag can be named `main` too, and a run on it carries that tag's own workflow file,
# whose publish job could be anything: so the found commit must also be an ancestor of HEAD (the
# compare API, `ahead` or `identical`). With squash-only merges (a repo setting this relies on:
# a merge commit would make a PR branch's unreviewed commits ancestors too) that means a commit
# of main's history, whose build.yml has guarded publish with `github.ref == 'refs/heads/main'`
# since b4a490b, so a tag run there skips it.
#
# Every failure gives the all-zero sha, which image-scope.sh reads as "no base: build=1". A
# lookup that fails, finds nothing (none of the newest $LIMIT successful runs
# published, or the runs have aged out), or names a commit that is not an ancestor of
# HEAD or that this checkout cannot fetch must fail toward building, never toward skipping.
# The sha is validated as 40 hex before it is used: it is API output.
set -euo pipefail

ZERO=0000000000000000000000000000000000000000
LIMIT=100   # the API's per_page maximum; the scan stops at the first publish, so this only bounds the worst case
PUBLISH_JOB="${PUBLISH_JOB:-Build, test, push and attest}"  # build.yml jobs.publish.name; build-workflow-test.sh pins it
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
HEAD_SHA="${GITHUB_SHA:?GITHUB_SHA is required}"

emit() { echo "base=$1" >> "$GITHUB_OUTPUT"; }
giveup() { # why
  emit "$ZERO"
  echo "::warning::Last successful publish not found ($1): building."
  echo "No last successful publish ($1): building." >> "$GITHUB_STEP_SUMMARY"
  exit 0
}

runs="$(gh api "repos/$REPO/actions/workflows/build.yml/runs?branch=main&status=success&per_page=$LIMIT" \
  --jq '.workflow_runs[] | select(.head_branch == "main" and (.event | IN("push", "schedule", "workflow_dispatch"))) | [.id, .head_sha] | @tsv')" \
  || giveup "run lookup failed"

while IFS=$'\t' read -r id sha; do
  [ -n "$id" ] || continue
  case "$id" in *[!0-9]*) giveup "unexpected run id" ;; esac
  # gh's --jq cannot bind a variable, so the job name goes through jq --arg, not into a filter.
  jobs="$(gh api "repos/$REPO/actions/runs/$id/jobs?per_page=100")" || giveup "job lookup failed for run $id"
  conclusion="$(printf '%s' "$jobs" | jq -r --arg n "$PUBLISH_JOB" '[.jobs[] | select(.name == $n) | .conclusion] | first // ""')" \
    || giveup "job list unreadable for run $id"
  [ "$conclusion" = success ] || continue
  case "$sha" in *[!0-9a-f]* | "") giveup "unexpected commit id" ;; esac
  [ "${#sha}" = 40 ] || giveup "unexpected commit id"
  rel="$(gh api "repos/$REPO/compare/$sha...$HEAD_SHA?per_page=1" --jq .status)" || giveup "compare lookup failed"
  case "$rel" in ahead | identical) ;; *) giveup "commit $sha is not an ancestor of HEAD" ;; esac
  # image-scope.sh fetches it again; this fetch is what turns "unfetchable" into a build, not a red job.
  git fetch --no-tags --depth=1 origin "$sha" || giveup "commit $sha is not fetchable"
  emit "$sha"
  echo "Diffing against $sha, the last successful publish (run $id)." >> "$GITHUB_STEP_SUMMARY"
  exit 0
done <<< "$runs"

giveup "none in the newest $LIMIT successful runs"
