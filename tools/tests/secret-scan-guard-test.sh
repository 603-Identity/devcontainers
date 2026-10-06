#!/usr/bin/env bash
# Tests for the "Guard the event, the pin and the commits" step of .github/workflows/secret-scan.yml
# (devcontainers#200, from #190 section 2). The step is extracted from the workflow itself, so the
# test runs the exact code CI runs; it stays inline there because it must run before anything
# from the caller's pin is checked out. Offline.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKFLOW="$ROOT_DIR/.github/workflows/secret-scan.yml"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

suite "secret-scan guard"

name="$(yq -r '.jobs.scan.steps[0].name' "$WORKFLOW")"
assert_eq "step 0 is the guard" "Guard the event, the pin and the commits" "$name"
yq -r '.jobs.scan.steps[0].run' "$WORKFLOW" > "$T/guard.sh"
[ -s "$T/guard.sh" ] || fail "the guard script was extracted"

# The guard is only as good as its inputs: pin where each one comes from, so a rewiring (say
# CALLER_REPO to the fork-controlled head repo) cannot pass the logic cases below.
assert_eq "trigger is workflow_call only" '["workflow_call"]' "$(yq -o=json -I=0 '.on | keys' "$WORKFLOW")"
# shellcheck disable=SC2016 # the ${{ }} expressions are literal text to compare
for kv in 'EVENT_NAME=${{ github.event_name }}' 'CALLER_REPO=${{ github.repository }}' \
  'PR_NUMBER=${{ github.event.number }}' 'BASE_SHA=${{ github.event.pull_request.base.sha }}' \
  'HEAD_SHA=${{ github.event.pull_request.head.sha }}'; do
  assert_eq "job env ${kv%%=*} source" "${kv#*=}" "$(yq -r ".jobs.scan.env.${kv%%=*}" "$WORKFLOW")"
done
# shellcheck disable=SC2016
assert_eq "guard WORKFLOW_REF source" '${{ job.workflow_ref }}' "$(yq -r '.jobs.scan.steps[0].env.WORKFLOW_REF' "$WORKFLOW")"

unset BASE_SHA HEAD_SHA # the guard reads these; never inherit them from the caller
SELF=603-Identity/devcontainers
SHA40=0123456789abcdef0123456789abcdef01234567
BASE40=89abcdef0123456789abcdef0123456789abcdef
HEAD40=fedcba9876543210fedcba9876543210fedcba98

guard() { # EVENT_NAME CALLER_REPO PR_NUMBER WORKFLOW_REF -> RC, stderr in $T/err
  RC=0
  env EVENT_NAME="$1" CALLER_REPO="$2" PR_NUMBER="$3" WORKFLOW_REF="$4" \
    BASE_SHA="${BASE_SHA-$BASE40}" HEAD_SHA="${HEAD_SHA-$HEAD40}" \
    bash "$T/guard.sh" > "$T/out" 2> "$T/err" || RC=$?
}
expect_pass() { guard "$2" "$3" "$4" "$5"; assert_rc "$1" 0 "$RC"; }
expect_fail() { guard "$2" "$3" "$4" "$5"; assert_rc "$1" 1 "$RC"; }

# Passes.
expect_pass "this repo's self-test caller at exactly its own PR's merge ref" \
  pull_request "$SELF" 42 "$SELF/.github/workflows/secret-scan-self.yml@refs/pull/42/merge"
expect_pass "a consumer pinned to a 40-hex SHA" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@$SHA40"

# Fails.
expect_fail "self at another PR's merge ref" \
  pull_request "$SELF" 42 "$SELF/.github/workflows/secret-scan-self.yml@refs/pull/43/merge"
expect_fail "self at refs/pull/<n>/head" \
  pull_request "$SELF" 42 "$SELF/.github/workflows/secret-scan-self.yml@refs/pull/42/head"
expect_fail "a consumer at refs/pull/<n>/merge" \
  pull_request glunk-works/app 42 "$SELF/.github/workflows/secret-scan.yml@refs/pull/42/merge"
expect_fail "a consumer on a branch" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@refs/heads/main"
expect_fail "a consumer on a tag" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@refs/tags/v1.3"
expect_fail "pull_request_target, even at a SHA pin" \
  pull_request_target glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@$SHA40"
expect_fail "a push event" \
  push glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@$SHA40"
expect_fail "self at a merge ref with an empty PR number" \
  pull_request "$SELF" "" "$SELF/.github/workflows/secret-scan-self.yml@refs/pull//merge"
expect_fail "a short SHA pin" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@0123456"
expect_fail "a SHA pin with trailing characters" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@${SHA40}x"
expect_fail "a consumer on a branch named x@<40 hex> (#349)" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@refs/heads/x@$SHA40"
expect_fail "a consumer on a tag named x@<40 hex> (#349)" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@refs/tags/x@$SHA40"
expect_fail "a short branch name x@<40 hex> (#349)" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@x@$SHA40"
expect_fail "self-test shape from another repo's workflow path" \
  pull_request "$SELF" 42 "glunk-works/other/.github/workflows/secret-scan-self.yml@refs/pull/42/merge"
BASE_SHA=main expect_fail "a ref instead of a base SHA" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@$SHA40"
HEAD_SHA='' expect_fail "an empty head SHA" \
  pull_request glunk-works/app 7 "$SELF/.github/workflows/secret-scan.yml@$SHA40"

summary
