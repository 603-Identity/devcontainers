#!/usr/bin/env bash
# shellcheck disable=SC1091
# Pins .github/workflows/release.yml (#486): it runs on workflow_dispatch only, the inputs reach a
# shell only through env:, `verify` is read-only, `release` sits behind the environment, and the App
# token is minted right before the one step that uses it. Offline; needs bash, yq (mikefarah) and grep.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WF="$ROOT_DIR/.github/workflows/release.yml"
CHECKOUT='actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
APP_TOKEN='actions/create-github-app-token@f418cff399f7aef4c2f0ad47e25ca7a6abbdd6fc'
j() { yq -o=json -I=0 "$1" "$WF"; }
r() { yq -r "$1" "$WF"; }
has() { # description haystack needle
  if [[ "$2" == *"$3"* ]]; then pass; else fail "$1" "wanted '$3' in: $2"; fi
}
# shellcheck disable=SC2016 # the expected values are literal GitHub expressions
{
suite "release-workflow"

# --- trigger and inputs ---------------------------------------------------------------------
assert_eq "the only trigger is workflow_dispatch" '["workflow_dispatch"]' "$(j '.on | keys')"
assert_eq "bump is a required choice of minor and major" '{"type":"choice","options":["minor","major"],"required":true}' \
  "$(j '.on.workflow_dispatch.inputs.bump | pick(["type","options","required"])')"
assert_eq "bump has no default" false "$(r '.on.workflow_dispatch.inputs.bump | has("default")')"
assert_eq "dry_run is a boolean defaulting to true" '{"type":"boolean","default":true}' \
  "$(j '.on.workflow_dispatch.inputs.dry_run | pick(["type","default"])')"
assert_eq "no other input" '["bump","dry_run"]' "$(j '.on.workflow_dispatch.inputs | keys')"

# --- workflow and job settings --------------------------------------------------------------
assert_eq "concurrency" '{"group":"release","cancel-in-progress":false}' "$(j '.concurrency')"
assert_eq "workflow-level permissions" '{}' "$(j '.permissions')"
assert_eq "verify permissions" '{"contents":"read","actions":"read","checks":"read","statuses":"read","pull-requests":"read"}' "$(j '.jobs.verify.permissions')"
assert_eq "release permissions" '{"contents":"read"}' "$(j '.jobs.release.permissions')"
assert_eq "the jobs" '["verify","release"]' "$(j '.jobs | keys')"
assert_eq "verify timeout" 10 "$(r '.jobs.verify.timeout-minutes')"
assert_eq "release timeout" 10 "$(r '.jobs.release.timeout-minutes')"
assert_eq "verify exposes the computed tag" '${{ steps.plan.outputs.tag }}' "$(r '.jobs.verify.outputs.tag')"

# --- asserts --------------------------------------------------------------------------------
for job in verify release; do
  assert_eq "$job: first step's REF" '${{ github.ref }}' "$(r ".jobs.$job.steps[0].env.REF")"
  assert_eq "$job: first step's DEFAULT_BRANCH" '${{ github.event.repository.default_branch }}' "$(r ".jobs.$job.steps[0].env.DEFAULT_BRANCH")"
  run="$(r ".jobs.$job.steps[0].run")"
  has "$job: the first step compares the ref" "$run" '"$REF" != "refs/heads/$DEFAULT_BRANCH"'
  has "$job: the first step fails the job" "$run" 'exit 1'
  assert_eq "$job: the first step is a step, not an if:" null "$(r ".jobs.$job.steps[0].if")"
done
assert_eq "verify fails on an empty RELEASE_CLIENT_ID" '${{ vars.RELEASE_CLIENT_ID }}' "$(r '.jobs.verify.steps[1].env.RELEASE_CLIENT_ID')"
has "verify's second step tests it" "$(r '.jobs.verify.steps[1].run')" '[ -z "$RELEASE_CLIENT_ID" ]'
has "...and exits 1" "$(r '.jobs.verify.steps[1].run')" 'exit 1'
assert_eq "verify has no job-level if" null "$(r '.jobs.verify.if')"

# --- the release job ------------------------------------------------------------------------
assert_eq "release needs verify" verify "$(r '.jobs.release.needs')"
assert_eq "release environment" release "$(r '.jobs.release.environment')"
assert_eq "release is skipped without the App wired up" "vars.RELEASE_CLIENT_ID != ''" "$(r '.jobs.release.if')"

# --- step order -----------------------------------------------------------------------------
assert_eq "verify steps, in order" '["Assert the dispatch is on the default branch","Assert the release App is wired up","Check out the dispatched commit","Read the mode","Verify the commit passed every gate","Compute the plan","Build the notes","Show the plan and the notes to the approver"]' "$(j '[.jobs.verify.steps[].name]')"
assert_eq "release steps, in order" '["Assert the dispatch is on the default branch","Check out the dispatched commit","Read the mode","Recompute the plan","Check the tag is the one verify computed","Build the notes","Generate a token for the release app","Create the tag and the Release"]' "$(j '[.jobs.release.steps[].name]')"

# --- checkouts and mode ---------------------------------------------------------------------
for job in verify release; do
  assert_eq "$job: one checkout" 1 "$(r "[.jobs.$job.steps[] | select(.uses != null and (.uses | test(\"^actions/checkout@\")))] | length")"
  assert_eq "$job: checkout pinned by SHA" "$CHECKOUT" "$(r ".jobs.$job.steps[] | select(.uses != null and (.uses | test(\"^actions/checkout@\"))) | .uses | sub(\" #.*\", \"\")")"
  assert_eq "$job: checkout inputs" '{"ref":"${{ github.sha }}","fetch-depth":0,"persist-credentials":false}' "$(j ".jobs.$job.steps[] | select(.uses != null and (.uses | test(\"^actions/checkout@\"))) | .with")"
  ci="$(r ".jobs.$job.steps | to_entries | .[] | select(.value.uses != null and (.value.uses | test(\"^actions/checkout@\"))) | .key")"
  assert_eq "$job: one step with id mode" 1 "$(r "[.jobs.$job.steps[] | select(.id == \"mode\")] | length")"
  assert_eq "$job: the mode step is right after the checkout" mode "$(r ".jobs.$job.steps[$((ci + 1))].id")"
  assert_eq "$job: the mode step reads dry_run through env" '${{ inputs.dry_run }}' "$(r ".jobs.$job.steps[$((ci + 1))].env.DRY_RUN")"
  has "$job: the mode step runs release-plan.sh mode" "$(r ".jobs.$job.steps[$((ci + 1))].run")" 'release-plan.sh mode "$DRY_RUN"'
  assert_eq "$job: every plan step takes the mode from the mode step" '["${{ steps.mode.outputs.mode }}"]' "$(j "[.jobs.$job.steps[] | select(.run != null and (.run | test(\"release-plan.sh plan\"))) | .env.MODE]")"
  assert_eq "$job: ...and passes it on" '["bash .github/scripts/release-plan.sh plan \"$BUMP\" \"$SHA\" \"$MODE\""]' "$(j "[.jobs.$job.steps[] | select(.run != null and (.run | test(\"release-plan.sh plan\"))) | .run]")"
done

# --- summary and tag ------------------------------------------------------------------------
sumrun="$(r '.jobs.verify.steps[] | select(.name == "Show the plan and the notes to the approver") | .run')"
has "verify's summary step runs release-plan.sh summary" "$sumrun" 'release-plan.sh summary'
has "...into the step summary" "$sumrun" '>> "$GITHUB_STEP_SUMMARY"'
assert_eq "release compares with verify's tag" '${{ needs.verify.outputs.tag }}' "$(r '.jobs.release.steps[] | select(.name == "Check the tag is the one verify computed") | .env.VERIFIED_TAG')"
assert_eq "...against its own" '${{ steps.plan.outputs.tag }}' "$(r '.jobs.release.steps[] | select(.name == "Check the tag is the one verify computed") | .env.TAG')"
has "...and fails on a difference" "$(r '.jobs.release.steps[] | select(.name == "Check the tag is the one verify computed") | .run')" '[ "$TAG" != "$VERIFIED_TAG" ]'

# --- the token ------------------------------------------------------------------------------
tok='.jobs.release.steps[] | select(.id == "app-token")'
assert_eq "the token action, pinned by SHA" "$APP_TOKEN" "$(r "$tok | .uses | sub(\" #.*\", \"\")")"
assert_eq "the token repositories" devcontainers "$(r "$tok | .with.repositories")"
assert_eq "the token permissions" '{"permission-contents":"write"}' "$(j "$tok | .with | with_entries(select(.key | test(\"^permission-\")))")"
assert_eq "the token's client id is the repository variable" '${{ vars.RELEASE_CLIENT_ID }}' "$(r "$tok | .with.client-id")"
assert_eq "the token's key is a secret" '${{ secrets.RELEASE_APP_PRIVATE_KEY }}' "$(r "$tok | .with.private-key")"
assert_eq "the token step has no condition (it is minted on dry runs too)" null "$(r "$tok | .if")"
assert_eq "exactly one step mints a token" 1 "$(r '[.jobs[].steps[] | select(.uses != null and (.uses | test("create-github-app-token")))] | length')"
assert_eq "the token step sits immediately before the create step" "app-token" "$(r '.jobs.release.steps[-2].id')"

# --- the create step ------------------------------------------------------------------------
assert_eq "the create step is the last step" "Create the tag and the Release" "$(r '.jobs.release.steps[-1].name')"
assert_eq "the create step runs on real only" "steps.mode.outputs.mode == 'real'" "$(r '.jobs.release.steps[-1].if')"
assert_eq "the create step's command" 'gh release create "$TAG" --target "$SHA" --title "$TAG" --notes-file "$NOTES_FILE"' "$(r '.jobs.release.steps[-1].run')"
assert_eq "the create step uses the App token" '${{ steps.app-token.outputs.token }}' "$(r '.jobs.release.steps[-1].env.GH_TOKEN')"
assert_eq "no other step sees the App token" 1 "$(grep -c 'steps.app-token.outputs.token' "$WF")"

# --- text checks ----------------------------------------------------------------------------
assert_eq "no run: block contains an expression" 0 "$(r '[.jobs[].steps[] | select(.run != null and (.run | test("\\$\\{\\{")))] | length')"
assert_eq "the file never mentions github.event.inputs" 0 "$(grep -c 'github\.event\.inputs' "$WF" || true)"
assert_eq "no if: mentions inputs.dry_run" 0 "$(r '[(.jobs[].if, .jobs[].steps[].if) | select(. != null and test("dry_run"))] | length')"
assert_eq "no if: compares with a quoted true or false" 0 "$(r "[(.jobs[].if, .jobs[].steps[].if) | select(. != null and test(\"'(true|false)'\"))] | length")"
assert_eq "inputs are read as inputs.* only" '["${{ inputs.bump }}","${{ inputs.bump }}"]' "$(j '[.jobs[].steps[].env.BUMP | select(. != null)]')"
assert_eq "every action is pinned by full SHA with its version comment" 0 "$(grep -E '^\s*(- )?uses:' "$WF" | grep -cvE '@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' || true)"

# --- the notes file -------------------------------------------------------------------------
assert_eq "verify: the notes file is touched by the notes step and the summary step only" \
  '["Build the notes","Show the plan and the notes to the approver"]' "$(j '[.jobs.verify.steps[] | select(tostring | test("release-notes.md")) | .name]')"
assert_eq "release: the notes file is touched by the notes step and the create step only" \
  '["Build the notes","Create the tag and the Release"]' "$(j '[.jobs.release.steps[] | select(tostring | test("release-notes.md")) | .name]')"
assert_eq "the notes file lives in the runner's temp directory" '${{ runner.temp }}/release-notes.md' "$(r '.jobs.release.steps[] | select(.name == "Build the notes") | .env.NOTES_FILE')"
}
summary
