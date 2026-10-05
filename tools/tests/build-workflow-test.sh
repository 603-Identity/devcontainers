#!/usr/bin/env bash
# Pins the event guard on build.yml's scope and publish jobs (#240): an allowlist, so a trigger
# added later fails closed. publish holds the packages, id-token and attestations write tokens.
# Offline; needs bash and yq (mikefarah).
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WF="$ROOT_DIR/.github/workflows/build.yml"
ALLOW="contains(fromJSON('[\"push\",\"schedule\",\"workflow_dispatch\"]'), github.event_name) && github.ref == 'refs/heads/main'"

suite "build-workflow"
assert_eq "scope.if" "$ALLOW" "$(yq -r '.jobs.scope.if' "$WF")"
assert_eq "publish.if" "$ALLOW && needs.scope.outputs.build == '1'" "$(yq -r '.jobs.publish.if' "$WF")"

summary
