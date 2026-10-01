#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2119,SC2120,SC2015,SC2016
# Tests for tools/gate-resolve.sh: every row of the spec's resolve table, plus the
# fail-closed paths. Fixtures are hand-built from the GitHub REST shapes and the facts in
# the spec's appendices A and B (Dependabot's user id 49699333, verified commits with reason
# valid, forged commits with verified=false / unsigned, F7, E14).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite gate-resolve

expect() { # description candidate [candidate_pr]
  assert_rc "$1" 0 "$RC"
  assert_eq "$1: act" true "$(outv act)"
  assert_eq "$1: candidate" "$2" "$(outv candidate)"
  assert_eq "$1: candidate_pr" "${3:-}" "$(outv candidate_pr)"
}

# E6: Dependabot's docker bump, one file, +1/-1, verified commit.
new_scenario resolve-base
run_resolve
expect "E6 candidate" true 2
assert_eq "E6 head_sha" "$SHA" "$(outv head_sha)"
assert_eq "E6 pr" 2 "$(outv pr)"
assert_eq "E6 each output written once" 1 "$(outn candidate)"
end_scenario

# F1's recreated PR (#6): same shape under another number.
new_scenario resolve-base
for f in pulls__2 pulls__2__files pulls__2__commits; do mv "$FAKE_FIX/$f.json" "$FAKE_FIX/${f/__2/__6}.json"; done
mut pulls__6 '.number = 6'
mut "commits__${SHA}__pulls" '.[0].number = 6'
run_resolve PR_NUMBER=6
expect "F1 recreated #6" true 6
end_scenario

# E13b: both forgeries (Dependabot author forged; only verification separates them).
for forged in a b; do
  new_scenario resolve-base
  put pulls__2__commits "forged/commits-forgery-$forged.json"
  run_resolve
  expect "E13b forgery $forged" false
  end_scenario
done

# F1: a human push on a Dependabot branch. The commit is verified, but not Dependabot's.
new_scenario resolve-base
put pulls__2__commits human-push/commits-human-push.json
run_resolve
expect "F1 human push" false
end_scenario

# Verified but reason is not "valid" (e.g. expired key), and a commit with no author.
new_scenario resolve-base
mut pulls__2__commits '.[0].commit.verification.reason = "expired_key"'
run_resolve
expect "reason not valid" false
mut pulls__2__commits '.[0].commit.verification.reason = "valid" | .[0].author = null'
run_resolve
expect "no commit author" false
end_scenario

# E14: a fork PR at Dependabot's exact head SHA. Whichever PR triggered the run, the
# candidate is the SHA's own same-repo Dependabot PR.
new_scenario resolve-base e14-fork-pr7
run_resolve PR_NUMBER=7
expect "E14 fork PR resolves to the SHA's candidate" true 2
assert_eq "E14 pr is the triggering fork PR" 7 "$(outv pr)"
assert_eq "E14 head_sha" "$SHA" "$(outv head_sha)"
end_scenario

# F7: two same-repo Dependabot PRs at one SHA, both passing every check.
new_scenario resolve-base f7-second-pr5
run_resolve
expect "F7 two PRs at one SHA" false
end_scenario

# Row: a MAJOR bump and a downgrade. resolve parses no PR content, so both are
# shape-identical to a MINOR bump and ARE candidates here; decide (exempt=false) refuses
# them, and gate-post-test.sh covers that row.
new_scenario resolve-base
run_resolve
expect "MAJOR bump / downgrade are decided by decide, not resolve" true 2
end_scenario

# A second file, a rename, a deletion-only diff, an added file.
new_scenario resolve-base
mut pulls__2__files '. + [{"filename":"README.md","status":"modified","additions":1,"deletions":1}]'
run_resolve
expect "second file" false
end_scenario
new_scenario resolve-base
mut pulls__2__files '.[0] += {"status":"renamed","previous_filename":"Dockerfile"}'
run_resolve
expect "rename" false
mut pulls__2__files '.[0] |= (.status = "modified" | .previous_filename = "Dockerfile")'
run_resolve
expect "previous_filename present" false
mut pulls__2__files '.[0] |= (del(.previous_filename) | .additions = 2)'
run_resolve
expect "+2/-1" false
mut pulls__2__files '.[0] |= (.additions = 1 | .filename = ".devcontainer/devcontainer.json")'
run_resolve
expect "another file in .devcontainer" false
end_scenario

# A decision-pin bump of the gate file (a Dependabot github-actions PR): never a candidate,
# even when its branch name is forged to look like a docker one.
new_scenario resolve-base gate-pin-bump
run_resolve
expect "decision-pin bump" false
mut pulls__2 '.head.ref = "dependabot/docker/forged"'
mut "commits__${SHA}__pulls" '.[0].head.ref = "dependabot/docker/forged"'
run_resolve
expect "decision-pin bump with a docker-looking branch" false
end_scenario

# A stranger's comment or review: act=false and nothing is computed or posted.
for ev in issue_comment pull_request_review; do
  new_scenario resolve-base
  run_resolve EVENT_NAME=$ev ACTOR_ID=999
  assert_rc "stranger $ev" 0 "$RC"
  assert_eq "stranger $ev: act" false "$(outv act)"
  assert_eq "stranger $ev: candidate" false "$(outv candidate)"
  assert_eq "stranger $ev: no candidate_pr" "" "$(outv candidate_pr)"
  assert_eq "stranger $ev: no API call at all" "" "$(cat "$FAKE_LOG")"
  end_scenario
done

# ACTOR_ID must match a whole word of REVIEWER_IDS, and a missing id never matches.
new_scenario resolve-base
run_resolve EVENT_NAME=issue_comment ACTOR_ID=2816930
assert_eq "id prefix is not a match" false "$(outv act)"
: > "$GITHUB_OUTPUT"
run_resolve EVENT_NAME=issue_comment ACTOR_ID=
assert_eq "missing actor id" false "$(outv act)"
: > "$GITHUB_OUTPUT"
run_resolve EVENT_NAME=issue_comment ACTOR_ID="$REVIEWER" REVIEWER_IDS="1 $REVIEWER 3"
assert_eq "id in a list" true "$(outv act)"
: > "$GITHUB_OUTPUT"
run_resolve EVENT_NAME=workflow_dispatch
assert_eq "an event the gate does not handle" false "$(outv act)"
end_scenario

# An allowlisted reviewer's comment on a fork PR at a candidate SHA.
new_scenario resolve-base e14-fork-pr7
run_resolve EVENT_NAME=issue_comment PR_NUMBER=7 ACTOR_ID="$REVIEWER"
expect "reviewer comment on fork PR at a candidate SHA" true 2
assert_eq "pr is the fork PR" 7 "$(outv pr)"
: > "$GITHUB_OUTPUT"
run_resolve EVENT_NAME=pull_request_review PR_NUMBER=7 ACTOR_ID="$REVIEWER"
expect "reviewer review on fork PR at a candidate SHA" true 2
end_scenario

# A PR whose head moves during the files call: the re-check sees another SHA.
new_scenario resolve-base
jq -c '.head.sha = "ffffffffffffffffffffffffffffffffffffffff"' "$FAKE_FIX/pulls__2.json" > "$FAKE_FIX/pulls__2.2.json"
run_resolve
expect "head moves during the files call" false
end_scenario
# ...and the same when the triggering PR is the fork PR (so pulls/2 is read once).
new_scenario resolve-base e14-fork-pr7
mut pulls__2 '.head.sha = "ffffffffffffffffffffffffffffffffffffffff"'
run_resolve PR_NUMBER=7
expect "candidate PR moved before the re-check" false
end_scenario
# ...and when the PR was closed meanwhile.
new_scenario resolve-base
jq -c '.state = "closed"' "$FAKE_FIX/pulls__2.json" > "$FAKE_FIX/pulls__2.2.json"
run_resolve
expect "PR closed before the re-check" false
end_scenario

# Single-fact failures in the candidate filter.
cases=(
  'closed PR|.state = "closed"'
  'not Dependabot|.user.id = 281693088'
  'not the docker ecosystem|.head.ref = "dependabot/npm_and_yarn/x"'
  'fork head repo|.head.repo.full_name = "JaredGroves-603/app"'
  'deleted head repo|.head.repo = null'
  'not the default branch|.base.ref = "release"'
)
for c in "${cases[@]}"; do
  new_scenario resolve-base
  mut "commits__${SHA}__pulls" "[.[0] | ${c#*|}]"
  run_resolve
  expect "${c%%|*}" false
  end_scenario
done

# Fail closed: bad inputs and API errors write no candidate=true.
new_scenario resolve-base
run_resolve PR_NUMBER=abc
assert_rc "non-numeric PR number" 1 "$RC"
assert_eq "non-numeric PR number: nothing written" "" "$(cat "$GITHUB_OUTPUT")"
run_resolve PR_NUMBER=
assert_rc "empty PR number" 1 "$RC"
mut pulls__2 '.head.sha = "not-a-sha"'
run_resolve
assert_rc "malformed head sha" 1 "$RC"
assert_eq "malformed head sha: nothing written" "" "$(cat "$GITHUB_OUTPUT")"
end_scenario
for broken in pulls__2__files pulls__2__commits "commits__${SHA}__pulls" _repo; do
  new_scenario resolve-base
  status_of "$broken" 500
  run_resolve
  if [ "$RC" -ne 0 ]; then pass; else fail "API error on $broken must fail the job"; fi
  assert_eq "API error on $broken: no candidate output" "" "$(outv candidate)"
  end_scenario
done
new_scenario resolve-base
drop pulls__2
run_resolve
assert_rc "PR lookup 404" 1 "$RC"
end_scenario

summary
