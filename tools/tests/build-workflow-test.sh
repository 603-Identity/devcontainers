#!/usr/bin/env bash
# Pins the event guard on build.yml's scope and publish jobs (#240): an allowlist, so a trigger
# added later fails closed. publish holds the packages, id-token and attestations write tokens.
# Also pins scope's last-publish lookup (#159): `actions: read` on scope alone, the lookup step
# running on push only, its output feeding image-scope.sh's base, and the job name it matches.
# Offline; needs bash and yq (mikefarah).
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WF="$ROOT_DIR/.github/workflows/build.yml"
ALLOW="contains(fromJSON('[\"push\",\"schedule\",\"workflow_dispatch\"]'), github.event_name) && github.ref == 'refs/heads/main'"

suite "build-workflow"
assert_eq "scope.if" "$ALLOW" "$(yq -r '.jobs.scope.if' "$WF")"
assert_eq "publish.if" "$ALLOW && needs.scope.outputs.build == '1'" "$(yq -r '.jobs.publish.if' "$WF")"

# scope reads the run list; nothing else in the workflow may (no job but scope holds actions:)
assert_eq "scope.permissions" '{"contents":"read","actions":"read"}' "$(yq -o=json -I=0 '.jobs.scope.permissions' "$WF")"
assert_eq "workflow-level permissions" '{}' "$(yq -o=json -I=0 '.permissions' "$WF")"
assert_eq "no other job holds actions:" "scope" "$(yq -r '.jobs | to_entries | .[] | select(.value.permissions.actions != null) | .key' "$WF")"
assert_eq "scope lookup step runs on push only" "github.event_name == 'push'"   "$(yq -r '.jobs.scope.steps[] | select(.id == "last") | .if' "$WF")"
assert_eq "scope lookup step script" "bash .github/scripts/last-publish-sha.sh"   "$(yq -r '.jobs.scope.steps[] | select(.id == "last") | .run' "$WF")"
# shellcheck disable=SC2016 # the expected value is a literal GitHub expression
assert_eq "scope diffs against the last publish, not github.event.before" '${{ steps.last.outputs.base }}'   "$(yq -r '.jobs.scope.steps[] | select(.id == "scope") | .env.BASE_SHA' "$WF")"
assert_eq "no step reads github.event.before" 0 "$(grep -c 'github\.event\.before' "$WF" || true)"
# the lookup matches the publish job by name; renaming the job must move the script's default too
PUBLISH_NAME="$(yq -r '.jobs.publish.name' "$WF")"
if grep -qF "PUBLISH_JOB:-$PUBLISH_NAME}" "$ROOT_DIR/.github/scripts/last-publish-sha.sh"; then pass
else fail "last-publish-sha.sh matches the publish job's name" "publish.name is '$PUBLISH_NAME'"; fi

summary
