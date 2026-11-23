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

# the Trivy evidence steps (docs/trivy-renewal.md): four non-fatal steps after Summary, on schedule
# and dispatch only. publish's permissions and action set are pinned so none of them gains a token.
PUB='.jobs.publish'
assert_eq "publish.permissions" '{"contents":"read","packages":"write","id-token":"write","attestations":"write","artifact-metadata":"write","security-events":"write"}' "$(yq -o=json -I=0 "$PUB.permissions" "$WF")"
assert_eq "publish uses: set (action names; upload-artifact pinned by 40 hex)" \
  "actions/attest actions/checkout actions/upload-artifact github/codeql-action/upload-sarif" \
  "$(yq -r "$PUB.steps[].uses | select(. != null)" "$WF" | sed 's/@.*//' | sort -u | tr '\n' ' ' | sed 's/ $//')"
if grep -qE '^ +uses: actions/upload-artifact@[0-9a-f]{40} # v[0-9]' "$WF"; then pass
else fail "actions/upload-artifact is pinned by a 40-hex SHA with a version comment"; fi
assert_eq "Summary, then exactly the four evidence steps, are the last five steps" "Summary logout evidence upload evidence-summary" \
  "$(yq -r "[$PUB.steps[-5:][] | (.id // .name)] | join(\" \")" "$WF")"
for id in logout evidence upload evidence-summary; do
  assert_eq "step $id: continue-on-error" "true" "$(yq -r "$PUB.steps[] | select(.id == \"$id\") | .\"continue-on-error\"" "$WF")"
done
# shellcheck disable=SC2016 # the expected values are literal GitHub expressions
{
  assert_eq "logout.if" "\${{ !cancelled() && steps.push.outcome == 'success' && contains(fromJSON('[\"schedule\",\"workflow_dispatch\"]'), github.event_name) }}" "$(yq -r "$PUB.steps[] | select(.id == \"logout\") | .if" "$WF")"
  assert_eq "logout.run" "docker logout ghcr.io" "$(yq -r "$PUB.steps[] | select(.id == \"logout\") | .run" "$WF")"
  assert_eq "logout.name" "Log out of GHCR before the evidence pass" "$(yq -r "$PUB.steps[] | select(.id == \"logout\") | .name" "$WF")"
  assert_eq "evidence.if" "\${{ !cancelled() && steps.logout.outcome == 'success' }}" "$(yq -r "$PUB.steps[] | select(.id == \"evidence\") | .if" "$WF")"
  assert_eq "evidence.timeout-minutes" "45" "$(yq -r "$PUB.steps[] | select(.id == \"evidence\") | .\"timeout-minutes\"" "$WF")"
  assert_eq "evidence.env" '{"TAG":"${{ env.MAJOR }}.${{ github.run_number }}","BASE_DIGEST":"${{ steps.push.outputs.base_digest }}","TOFU_DIGEST":"${{ steps.push.outputs.tofu_digest }}","NODE_DIGEST":"${{ steps.push.outputs.node_digest }}","DEVAPP_DIGEST":"${{ steps.push.outputs.devapp_digest }}","DEVAPP_TOFU_DIGEST":"${{ steps.push.outputs.devapp_tofu_digest }}"}' "$(yq -o=json -I=0 "$PUB.steps[] | select(.id == \"evidence\") | .env" "$WF")"
  assert_eq "evidence.run" 'bash .github/scripts/trivy-evidence.sh "$TAG" out/trivy-evidence.md' "$(yq -r "$PUB.steps[] | select(.id == \"evidence\") | .run" "$WF")"
  assert_eq "upload.if" "\${{ !cancelled() && steps.evidence.outcome == 'success' }}" "$(yq -r "$PUB.steps[] | select(.id == \"upload\") | .if" "$WF")"
  assert_eq "upload.with" '{"name":"trivy-evidence","path":"out/trivy-evidence.md","if-no-files-found":"error"}' "$(yq -o=json -I=0 "$PUB.steps[] | select(.id == \"upload\") | .with" "$WF")"
  assert_eq "upload has no github-token input" "null" "$(yq -r "$PUB.steps[] | select(.id == \"upload\") | .with.\"github-token\"" "$WF")"
  assert_eq "evidence-summary.if (the Summary step above has none)" "\${{ !cancelled() && steps.upload.outcome == 'success' }}" "$(yq -r "$PUB.steps[] | select(.id == \"evidence-summary\") | .if" "$WF")"
}
# shellcheck disable=SC2016 # the pattern is a literal GitHub expression opener
if yq -r "$PUB.steps[] | select(.id == \"evidence-summary\") | .run" "$WF" | grep -qF '${{'; then fail "evidence-summary.run holds no \${{ }}"; else pass; fi

summary
