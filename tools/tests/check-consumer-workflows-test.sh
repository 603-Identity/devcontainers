#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2015,SC2016
# Tests for tools/check-consumer-workflows.sh: the shipped template is clean, and each rule
# fires on the mutation it exists for. Needs jq and yq (mikefarah) as well as bash.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite check-consumer-workflows

LINT="$TOOLS_DIR/check-consumer-workflows.sh"
TEMPLATE_DIR="$ROOT_DIR/template/.github/workflows"
CALLER=devcontainer-image.yml
GATE=architect-review-gate.yml
SCAN=secret-scan.yml

# new_wf: a scratch copy of the shipped template workflows in $WF.
new_wf() {
  SCRATCH="$(mktemp -d)"
  WF="$SCRATCH/wf"
  mkdir -p "$WF"
  cp "$TEMPLATE_DIR/$CALLER" "$TEMPLATE_DIR/$GATE" "$TEMPLATE_DIR/$SCAN" "$WF/"
}
# lint: run the lint on $WF, leaving the exit code in RC and stderr in ERR.
lint() {
  RC=0
  ERR="$(bash "$LINT" "${1:-$WF}" 2>&1 > /dev/null)" || RC=$?
}
expect() { # description expected-rc [stderr-substring]
  assert_rc "$1" "$2" "$RC"
  if [ -n "${3:-}" ]; then
    if [[ "$ERR" == *"$3"* ]]; then pass; else fail "$1 (message)" "wanted '$3' in: $ERR"; fi
  fi
}

# --- the shipped template is clean ---------------------------------------------------------
new_wf; lint; expect "the shipped template" 0
# Both pins name one commit, so the lint has nothing to warn about.
if [[ "$ERR" == *warning* ]]; then fail "the shipped template's two pins agree" "$ERR"; else pass; fi
# The pin placeholder (40 zeros, or a vX.Y comment) can never ship.
if grep -rqE '@0{40}|# vX\.Y$' "$TEMPLATE_DIR"; then fail "no placeholder pin in template/.github/workflows"; else pass; fi
rm -rf "$SCRATCH"

# --- the caller ----------------------------------------------------------------------------
new_wf; sed -i 's|^  pull_request:$|  pull_request:\n    paths: [".devcontainer/**"]|' "$WF/$CALLER"
lint; expect "a paths: filter on the caller" 1 "no paths:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  pull_request:$|  pull_request:\n    branches: [main]|' "$WF/$CALLER"
lint; expect "a branches: filter on the caller" 1 "no paths:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  pull_request:$|  pull_request:\n  push:|' "$WF/$CALLER"
lint; expect "a second trigger on the caller" 1 "only trigger"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(verify-devcontainer-image\.yml)@[0-9a-f]{40} # v[0-9.]+|\1@v1.0|' "$WF/$CALLER"
lint; expect "a bare-tag verify pin" 1 "verify pin"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(verify-devcontainer-image\.yml@[0-9a-f]{40}) # v[0-9.]+|\1|' "$WF/$CALLER"
lint; expect "a verify pin with no version comment" 1 "verify pin"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(verify-devcontainer-image\.yml)@[0-9a-f]{40} # |\1@6ac20cedcd87 # |' "$WF/$CALLER"
lint; expect "a short-SHA verify pin" 1 "verify pin"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  verify:$|  verify:\n    name: Verify the image|' "$WF/$CALLER"
lint; expect "a name: override on the verify job" 1 "no name:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  verify:$|  verify:\n    if: github.actor != '"'"'bot'"'"'|' "$WF/$CALLER"
lint; expect "an if: on the verify job" 1 "no name:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|contents: read|contents: write|' "$WF/$CALLER"
lint; expect "contents: write on the verify job" 1 "contents: read"; rm -rf "$SCRATCH"

new_wf; sed -i 's|contents: read|contents: read\n      pull-requests: read|' "$WF/$CALLER"
lint; expect "an extra read permission on the verify job" 1 "contents: read"; rm -rf "$SCRATCH"

new_wf; printf '  other:\n    runs-on: ubuntu-latest\n    permissions: {}\n    steps:\n      - run: true\n' >> "$WF/$CALLER"
lint; expect "a second job in the caller" 1 "only job"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^permissions: {}$|permissions: {}\nenv: {}|; s|^    permissions:$|    with: {}\n    permissions:|' "$WF/$CALLER"
lint; expect "with: on the verify job" 1 "with: or secrets:"; rm -rf "$SCRATCH"

new_wf; rm "$WF/$CALLER"
lint; expect "a missing caller" 1 "devcontainer-image.yml is missing"; rm -rf "$SCRATCH"

# --- the gate ------------------------------------------------------------------------------
new_wf; rm "$WF/$GATE"
lint; expect "a missing gate" 1 "architect-review-gate.yml is missing"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(devcontainer-bump-decision\.yml)@[0-9a-f]{40} # v[0-9.]+|\1@v1.0|' "$WF/$GATE"
lint; expect "a bare-tag decide pin" 1 "decide pin"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(devcontainer-bump-decision\.yml)@[0-9a-f]{40} # v[0-9.]+|\1@0000000000000000000000000000000000000000 # vX.Y|' "$WF/$GATE"
lint; expect "the placeholder decide pin" 1 "decide pin"; rm -rf "$SCRATCH"

# Different pins are a warning, not a failure.
new_wf; sed -i -E 's|(devcontainer-bump-decision\.yml)@[0-9a-f]{40} # v[0-9.]+|\1@1111111111111111111111111111111111111111 # v1.1|' "$WF/$GATE"
lint; expect "two different pins" 0 "name different commits"; rm -rf "$SCRATCH"

# `resolve` and `post` may not use an action. `resolve` is the first `steps:`, `post` the last.
new_wf
awk '/^    steps:$/ && !done { print; print "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"; done = 1; next } { print }' "$WF/$GATE" > "$WF/g.tmp" && mv "$WF/g.tmp" "$WF/$GATE"
lint; expect "a uses: step in resolve" 1 "job 'resolve' contains 'uses:"; rm -rf "$SCRATCH"

new_wf
awk '{ a[NR] = $0 } /^    steps:$/ { last = NR } END { for (i = 1; i <= NR; i++) { print a[i]; if (i == last) print "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" } }' "$WF/$GATE" > "$WF/g.tmp" && mv "$WF/g.tmp" "$WF/$GATE"
lint; expect "a uses: step in post" 1 "job 'post' contains 'uses:"; rm -rf "$SCRATCH"

new_wf; sed -i '/^ *\.github\/\*) touches=1 ;;$/d' "$WF/$GATE"
lint; expect "the .github/ rule removed" 1 ".github/ rule is missing"; rm -rf "$SCRATCH"

# `resolve` and `decide` may not hold a write token; only `post` may.
new_wf; sed -i '0,/^      pull-requests: read$/s//      pull-requests: write/' "$WF/$GATE"
lint; expect "pull-requests: write on resolve" 1 "job 'resolve' holds pull-requests: write"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^      issues: read$|      issues: read\n      statuses: write|' "$WF/$GATE"
lint; expect "statuses: write on resolve and post only" 1 "job 'resolve' holds statuses: write"; rm -rf "$SCRATCH"

# A job-level `uses:` (a called workflow) counts the same as a step's.
new_wf; sed -i 's|^  resolve:$|  resolve:\n    uses: o/r/.github/workflows/w.yml@6ac20cedcd87ec09c84160a280f8a2c288cd85be|' "$WF/$GATE"
lint; expect "a job-level uses: in resolve" 1 "job 'resolve' contains 'uses:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  post:$|  post:\n    uses: o/r/.github/workflows/w.yml@6ac20cedcd87ec09c84160a280f8a2c288cd85be|' "$WF/$GATE"
lint; expect "a job-level uses: in post" 1 "job 'post' contains 'uses:"; rm -rf "$SCRATCH"

# resolve and post run on the bare runner: a container or service image is third-party code.
new_wf; sed -i 's|^  post:$|  post:\n    container: evil/image:latest|' "$WF/$GATE"
lint; expect "a container: on post" 1 "job 'post' has container: or services:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  resolve:$|  resolve:\n    services: { x: { image: evil/image } }|' "$WF/$GATE"
lint; expect "services: on resolve" 1 "job 'resolve' has container: or services:"; rm -rf "$SCRATCH"

# post holds statuses, contents and pull-requests: write and issues: read, and nothing else.
new_wf; sed -i 's|^      issues: read  .*$|&\n      actions: write|' "$WF/$GATE"
lint; expect "actions: write on post" 1 "job 'post' may hold only"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^      statuses: write .*$|&\n      checks: write|' "$WF/$GATE"
lint; expect "checks: write on post" 1 "job 'post' may hold only"; rm -rf "$SCRATCH"

# Only the file named architect-review-gate.yml is the gate. A decoy with the same job names
# gets no `post` exemption, and cannot take the real gate's place in the checks above.
new_wf; cp "$WF/$GATE" "$WF/aaa-decoy.yml"
lint; expect "a copy of the gate under another name" 1 "is not architect-review-gate.yml"; rm -rf "$SCRATCH"

new_wf; cp "$WF/$GATE" "$WF/zzz-decoy.yml"
awk '{ a[NR] = $0 } /^    steps:$/ { last = NR } END { for (i = 1; i <= NR; i++) { print a[i]; if (i == last) print "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" } }' "$WF/$GATE" > "$WF/g.tmp" && mv "$WF/g.tmp" "$WF/$GATE"
lint; expect "a decoy gate beside a real gate whose post has uses:" 1 "job 'post' contains 'uses:"; rm -rf "$SCRATCH"

new_wf; printf 'name: Fake\non: pull_request\njobs:\n  resolve: { runs-on: ubuntu-latest, permissions: {}, steps: [{ run: "true" }] }\n  decide: { runs-on: ubuntu-latest, permissions: {}, steps: [{ run: "true" }] }\n  post:\n    runs-on: ubuntu-latest\n    permissions: write-all\n    steps:\n      - run: true\n' > "$WF/aaa.yml"
lint; expect "a decoy post with write-all" 1 "job 'post' has write-all"; rm -rf "$SCRATCH"

# --- the caller's secrets and a caller that is not YAML ------------------------------------
new_wf; printf '    secrets: inherit\n' >> "$WF/$CALLER"
lint; expect "secrets: inherit on the verify job" 1 "with: or secrets:"; rm -rf "$SCRATCH"

# An unexpected job key (#202); the secrets job's tests below say why.
new_wf; sed -i 's|^    permissions:$|    strategy:\n      matrix:\n        x: [a]\n    permissions:|' "$WF/$CALLER"
lint; expect "strategy: on the verify job" 1 "devcontainer-image.yml: job 'verify' must have only permissions: and uses:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^    permissions:$|    concurrency:\n      group: x\n      cancel-in-progress: true\n    permissions:|' "$WF/$CALLER"
lint; expect "concurrency: on the verify job" 1 "devcontainer-image.yml: job 'verify' must have only permissions: and uses:"; rm -rf "$SCRATCH"

new_wf; printf 'a: [unclosed\n' > "$WF/$CALLER"
lint; expect "a caller that is not valid YAML" 1 "not parseable"
if [[ "$ERR" == *"finding(s)."* ]]; then pass; else fail "an unparseable caller still ends in the summary line" "$ERR"; fi
rm -rf "$SCRATCH"

# --- any other workflow a PR can trigger ---------------------------------------------------
other() { # trigger-line permissions-line
  printf 'name: Other\non: %s\n%sjobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' "$1" "$2" > "$WF/ci.yml"
}
new_wf; other "pull_request" ""
lint; expect "a PR workflow with no permissions block" 1 "job 'build' has no permissions: block"; rm -rf "$SCRATCH"

new_wf; other "pull_request" $'permissions:\n  statuses: write\n'
lint; expect "a PR workflow with statuses: write" 1 "job 'build' holds statuses: write"; rm -rf "$SCRATCH"

new_wf; other "pull_request" $'permissions: write-all\n'
lint; expect "a PR workflow with write-all" 1 "write-all"; rm -rf "$SCRATCH"

new_wf; other "[pull_request_target]" $'permissions:\n  checks: write\n  contents: read\n'
lint; expect "pull_request_target with checks: write" 1 "checks: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  issue_comment:\n    types: [created]' $'permissions:\n  pull-requests: write\n'
lint; expect "issue_comment with pull-requests: write" 1 "pull-requests: write"; rm -rf "$SCRATCH"

new_wf; other "pull_request" $'permissions:\n  actions: write\n'
lint; expect "a PR workflow with actions: write" 1 "actions: write"; rm -rf "$SCRATCH"

new_wf; other "pull_request" $'permissions:\n  contents: read\n  id-token: write\n  packages: write\n'
lint; expect "a PR workflow with only unwatched write scopes" 0; rm -rf "$SCRATCH"

new_wf; other "pull_request" $'permissions: {}\n'
lint; expect "a PR workflow with permissions: {}" 0; rm -rf "$SCRATCH"

new_wf; other "pull_request" $'permissions: read-all\n'
lint; expect "a PR workflow with read-all" 0; rm -rf "$SCRATCH"

new_wf; other "pull_request" $'permissions:\n  contents: write\n'
lint; expect "contents: write on a PR job outside the caller" 1 "job 'build' holds contents: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  pull_request_review:\n    types: [submitted]' $'permissions:\n  contents: write\n'
lint; expect "pull_request_review with contents: write" 1 "contents: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  pull_request_review_comment:\n    types: [created]' $'permissions:\n  contents: write\n'
lint; expect "pull_request_review_comment with contents: write" 1 "contents: write"; rm -rf "$SCRATCH"

# Dependabot pushes its branch into the repo, and an unfiltered push (or create) workflow then
# runs that branch's own, bumped, workflow files.
new_wf; other "push" $'permissions:\n  statuses: write\n'
lint; expect "an unfiltered push workflow with statuses: write" 1 "statuses: write"; rm -rf "$SCRATCH"

new_wf; other "[push]" ""
lint; expect "an unfiltered push workflow with no permissions block" 1 "no permissions: block"; rm -rf "$SCRATCH"

new_wf; other "[create]" $'permissions:\n  checks: write\n'
lint; expect "a create workflow with checks: write" 1 "checks: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    branches: [main]' $'permissions:\n  contents: write\n'
lint; expect "a push workflow limited to branches: [main]" 0; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    tags: ["v*"]' $'permissions:\n  contents: write\n'
lint; expect "a push workflow limited to tags" 0; rm -rf "$SCRATCH"

new_wf; other "workflow_dispatch" $'permissions:\n  contents: write\n'
lint; expect "a workflow_dispatch-only workflow with contents: write" 0; rm -rf "$SCRATCH"

# A push filter keeps Dependabot's branch out only when it names literal branches, or tags alone.
new_wf; other $'\n  push:\n    branches: ["**"]' $'permissions:\n  statuses: write\n'
lint; expect "a push filter of branches: [**]" 1 "statuses: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    branches: ["release/*"]' $'permissions:\n  statuses: write\n'
lint; expect "a push filter with a glob branch" 1 "statuses: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    branches: []' $'permissions:\n  statuses: write\n'
lint; expect "a push filter of branches: []" 1 "statuses: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    branches:' $'permissions:\n  statuses: write\n'
lint; expect "a push filter of branches: null" 1 "statuses: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    branches-ignore: [main]' $'permissions:\n  statuses: write\n'
lint; expect "a push filter of branches-ignore only" 1 "statuses: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    branches: [main, release]' $'permissions:\n  statuses: write\n'
lint; expect "a push filter naming literal branches" 0; rm -rf "$SCRATCH"

# resolve and post run on a GitHub-hosted runner.
new_wf; sed -i '0,/^    runs-on: ubuntu-latest$/s//    runs-on: self-hosted/' "$WF/$GATE"
lint; expect "resolve on a self-hosted runner" 1 "job 'resolve' must run on a GitHub-hosted runner"; rm -rf "$SCRATCH"

new_wf
awk '/^  post:$/ { inpost = 1 } inpost && /^    runs-on: ubuntu-latest$/ { print "    runs-on: [self-hosted, linux]"; inpost = 0; next } { print }' "$WF/$GATE" > "$WF/g.tmp" && mv "$WF/g.tmp" "$WF/$GATE"
lint; expect "post on a self-hosted runner" 1 "job 'post' must run on a GitHub-hosted runner"; rm -rf "$SCRATCH"
# A `branches-ignore` never keeps Dependabot out (its branch name follows the configurable
# pull-request-branch-name.separator), and tags do not change that: a branches-ignore + tags
# filter still runs on every other branch push. A map-form push with no branch or tag filter
# (paths only) runs on every branch too.
new_wf; other $'\n  push:\n    branches-ignore: [main]\n    tags: ["v*"]' $'permissions:\n  statuses: write\n'
lint; expect "a push filter of branches-ignore plus tags" 1 "statuses: write"; rm -rf "$SCRATCH"

new_wf; other $'\n  push:\n    branches-ignore: ["dependabot/**"]' $'permissions:\n  statuses: write\n'
lint; expect "a push filter that ignores dependabot/** (the branch prefix is configurable)" 1 "statuses: write"; rm -rf "$SCRATCH"

for g in 'rel?' 'rel[ab]' '!main' 'a+'; do
  new_wf; other $'\n  push:\n    branches: ["'"$g"$'"]' $'permissions:\n  statuses: write\n'
  lint; expect "a push filter with the glob character in '$g'" 1 "statuses: write"; rm -rf "$SCRATCH"
done

# The gate must define its three jobs, and post may not hold issues: write or a short decide pin.
new_wf; sed -i 's|^  resolve:$|  resolvex:|' "$WF/$GATE"
lint; expect "a gate with a job renamed" 1 "must define the gate's three jobs"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^      issues: read          # PR comments.*$|      issues: write|' "$WF/$GATE"
lint; expect "issues: write on post" 1 "job 'post' may hold only"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(devcontainer-bump-decision\.yml)@[0-9a-f]{40} # |\1@6ac20cedcd87 # |' "$WF/$GATE"
lint; expect "a short-SHA decide pin" 1 "decide pin"; rm -rf "$SCRATCH"

new_wf; printf 'name: Y\non: pull_request\npermissions: write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$WF/ci.yaml"
lint; expect "a .yaml workflow with write-all" 1 "write-all"; rm -rf "$SCRATCH"

# A file that is YAML but not a workflow mapping is one finding, not a crash.
for body in 'just a string' $'- a\n- b' $'jobs:\n  - a' $'jobs:\n  b: x'; do
  new_wf; printf '%s\n' "$body" > "$WF/aaa-odd.yml"
  # Sorts after the odd file: the loop must carry on past it and still flag this one.
  printf 'name: Z\non: pull_request\npermissions: write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$WF/zzz.yml"
  lint; expect "a non-mapping workflow file ($(printf '%s' "$body" | head -n 1))" 1 "not a workflow"
  if [[ "$ERR" == *"zzz.yml: job 'b' has write-all"* ]]; then pass; else fail "the loop continues past a non-mapping file" "$ERR"; fi
  if [[ "$ERR" == *"finding(s)."* ]]; then pass; else fail "a non-mapping file still ends in the summary line" "$ERR"; fi
  rm -rf "$SCRATCH"
done

# The same for the caller, which the gate checks separately.
for body in 'just a string' $'- a\n- b' $'jobs:\n  - a' $'jobs:\n  verify: x' $'jobs:\n  verify: [a]'; do
  new_wf; printf '%s\n' "$body" > "$WF/$CALLER"
  lint; expect "a non-mapping caller ($(printf '%s' "$body" | head -n 1))" 1 "not a workflow"
  if [[ "$ERR" == *"finding(s)."* ]]; then pass; else fail "a non-mapping caller still ends in the summary line" "$ERR"; fi
  assert_eq "a non-mapping caller is exactly one finding" 1 "$(grep -c 'devcontainer-image.yml' <<< "$ERR")"
  rm -rf "$SCRATCH"
done

# A gate job whose value is not a mapping is reported, not a crash.
new_wf; sed -i 's|^  decide:$|  decide: x\n  decide2:|' "$WF/$GATE"
lint; expect "a gate whose decide job is a scalar" 1 "not a workflow"
if [[ "$ERR" == *"finding(s)."* ]]; then pass; else fail "a gate with a scalar job still ends in the summary line" "$ERR"; fi
rm -rf "$SCRATCH"

# Only a GitHub-hosted label counts: a self-hosted runner can be named ubuntu-anything.
new_wf; sed -i 's|^    runs-on: ubuntu-latest$|    runs-on: ubuntu-selfhosted-pool|' "$WF/$GATE"
lint; expect "a self-hosted runner labelled ubuntu-selfhosted-pool" 1 "must run on a GitHub-hosted runner"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^    runs-on: ubuntu-latest$|    runs-on: ubuntu-24.04|' "$WF/$GATE"
lint; expect "resolve and post on ubuntu-24.04" 0; rm -rf "$SCRATCH"

# Files GitHub may run that a plain glob would skip.
new_wf; printf 'name: Hidden\non: pull_request\npermissions: write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$WF/.hidden.yml"
lint; expect "a dotfile workflow with write-all" 1 "write-all"; rm -rf "$SCRATCH"

new_wf; printf 'name: Upper\non: pull_request\npermissions: write-all\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$WF/ci.YML"
lint; expect "an upper-case extension with write-all" 1 "write-all"; rm -rf "$SCRATCH"

# A job-level block overrides a workflow-level write.
new_wf
printf 'name: Other\non: pull_request\npermissions: write-all\njobs:\n  build:\n    runs-on: ubuntu-latest\n    permissions: {}\n    steps:\n      - run: true\n' > "$WF/ci.yml"
lint; expect "a job-level block overriding a workflow-level write-all" 0; rm -rf "$SCRATCH"

# `post` is exempt only in the gate: a job of that name elsewhere is not.
new_wf
printf 'name: Other\non: pull_request\njobs:\n  post:\n    runs-on: ubuntu-latest\n    permissions:\n      statuses: write\n    steps:\n      - run: true\n' > "$WF/ci.yml"
lint; expect "a job called post outside the gate" 1 "job 'post' holds statuses: write"; rm -rf "$SCRATCH"

# --- the secret-scan caller (#190) -----------------------------------------------------------
new_wf; sed -i 's|^  pull_request:$|  pull_request:\n    paths: ["**.tf"]|' "$WF/$SCAN"
lint; expect "a paths: filter on the scan caller" 1 "secret-scan.yml: pull_request must have no paths:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  pull_request:$|  pull_request:\n    branches: [main]|' "$WF/$SCAN"
lint; expect "a branches: filter on the scan caller" 1 "secret-scan.yml: pull_request must have no paths:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  pull_request:$|  pull_request:\n  push:|' "$WF/$SCAN"
lint; expect "a second trigger on the scan caller" 1 "secret-scan.yml: the only trigger"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  pull_request:$|  pull_request_target:|' "$WF/$SCAN"
lint; expect "pull_request_target on the scan caller" 1 "secret-scan.yml: the only trigger"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  secrets:$|  secrets:\n    name: Scan|' "$WF/$SCAN"
lint; expect "a name: override on the secrets job" 1 "secret-scan.yml: job 'secrets' must have no name:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  secrets:$|  secrets:\n    if: github.actor != '"'"'bot'"'"'|' "$WF/$SCAN"
lint; expect "an if: on the secrets job" 1 "secret-scan.yml: job 'secrets' must have no name:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^  secrets:$|  scan:|' "$WF/$SCAN"
lint; expect "a renamed scan job" 1 "secret-scan.yml: the only job must be 'secrets'"; rm -rf "$SCRATCH"

new_wf; sed -i 's|contents: read|contents: write|' "$WF/$SCAN"
lint; expect "contents: write on the secrets job" 1 "secret-scan.yml: job 'secrets' must have exactly"; rm -rf "$SCRATCH"

new_wf; sed -i 's|contents: read|contents: read\n      pull-requests: read|' "$WF/$SCAN"
lint; expect "an extra permission on the secrets job" 1 "secret-scan.yml: job 'secrets' must have exactly"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^    permissions:$|    with: {}\n    permissions:|' "$WF/$SCAN"
lint; expect "with: on the secrets job" 1 "secret-scan.yml: job 'secrets' takes no with:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^    permissions:$|    secrets: inherit\n    permissions:|' "$WF/$SCAN"
lint; expect "secrets: inherit on the secrets job" 1 "secret-scan.yml: job 'secrets' takes no with:"; rm -rf "$SCRATCH"

# An unexpected job key (#202): strategy: renames the check to `secrets (a) / scan`, so the
# required context never reports, and concurrency: can cancel it. Neither is a
# with:/secrets:/name:/if: the rules above catch.
new_wf; sed -i 's|^    permissions:$|    strategy:\n      matrix:\n        x: [a]\n    permissions:|' "$WF/$SCAN"
lint; expect "strategy: on the secrets job" 1 "secret-scan.yml: job 'secrets' must have only permissions: and uses:"; rm -rf "$SCRATCH"

new_wf; sed -i 's|^    permissions:$|    concurrency:\n      group: x\n      cancel-in-progress: true\n    permissions:|' "$WF/$SCAN"
lint; expect "concurrency: on the secrets job" 1 "secret-scan.yml: job 'secrets' must have only permissions: and uses:"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(secret-scan\.yml)@[0-9a-f]{40} # v[0-9.]+|\1@v1.1|' "$WF/$SCAN"
lint; expect "a bare-tag secrets pin" 1 "the secrets pin"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(secret-scan\.yml@[0-9a-f]{40}) # v[0-9.]+|\1|' "$WF/$SCAN"
lint; expect "a secrets pin with no version comment" 1 "the secrets pin"; rm -rf "$SCRATCH"

new_wf; sed -i -E 's|(secret-scan\.yml)@[0-9a-f]{40} # |\1@5bccf291f80b # |' "$WF/$SCAN"
lint; expect "a short-SHA secrets pin" 1 "the secrets pin"; rm -rf "$SCRATCH"

new_wf; sed -i 's|603-Identity/devcontainers/.github/workflows/secret-scan.yml|evil/repo/.github/workflows/secret-scan.yml|' "$WF/$SCAN"
lint; expect "a secrets pin to another repo" 1 "the secrets pin"; rm -rf "$SCRATCH"

new_wf; printf '  other:\n    runs-on: ubuntu-latest\n    permissions: {}\n    steps:\n      - run: true\n' >> "$WF/$SCAN"
lint; expect "a second job in the scan caller" 1 "secret-scan.yml: the only job must be 'secrets'"; rm -rf "$SCRATCH"

new_wf; rm "$WF/$SCAN"
lint; expect "a missing scan caller" 1 "secret-scan.yml is missing"; rm -rf "$SCRATCH"

# The scan pin is independent of the verify/decide pins, but must still be a full SHA.
scan_sha="$(grep -oE 'workflows/secret-scan\.yml@[0-9a-f]{40}' "$TEMPLATE_DIR/$SCAN" | cut -d@ -f2)"
if [[ "$scan_sha" =~ ^[0-9a-f]{40}$ ]]; then pass; else fail "the template scan caller carries a 40-hex pin"; fi

# --- the CONSUMER code_paths block against the repo's own .ai/project.yml (#214) ----------------
# new_repo CODE_PATHS_YAML: a scratch repo ($REPO) whose .github/workflows holds the template and
# whose .ai/project.yml carries the given `code_paths:` body. $WF points at its workflows.
new_repo() {
  SCRATCH="$(mktemp -d)"
  REPO="$SCRATCH/repo"
  WF="$REPO/.github/workflows"
  mkdir -p "$WF" "$REPO/.ai"
  cp "$TEMPLATE_DIR/$CALLER" "$TEMPLATE_DIR/$GATE" "$TEMPLATE_DIR/$SCAN" "$WF/"
  printf 'code_paths:\n%s\n' "$1" > "$REPO/.ai/project.yml"
}
# set_block 'arms': replaces the gate's CONSUMER code_paths arms in $WF with the given lines.
set_block() {
  awk -v arms="$1" '
    /# >>> CONSUMER: code_paths/ { print; print arms; skip = 1; next }
    /# <<< CONSUMER: code_paths/ { skip = 0 }
    !skip { print }' "$WF/$GATE" > "$WF/g.tmp" && mv "$WF/g.tmp" "$WF/$GATE"
}
TEMPLATE_PATHS=$'  - images/\n  - template/\n  - tests/\n  - tools/\n  - .github/\n  - .claude/\n  - .trivyignore.yaml\n  - .gitattributes\n  - .ai/project.yml'

new_repo "$TEMPLATE_PATHS"; lint; expect "a block that covers the repo's code_paths" 0
if [[ "$ERR" == *warning* ]]; then fail "a matching block has nothing to warn about" "$ERR"; else pass; fi
rm -rf "$SCRATCH"

# The #214 repro: a code_paths entry the copied block does not list.
new_repo "$TEMPLATE_PATHS"; set_block '                  images/*|template/*|tests/*|tools/*) touches=1 ;;
                  .trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "a block that drops .claude/" 1 "code_paths entry '.claude/' in"
if [[ "$ERR" == *"touches=0"* ]]; then pass; else fail "the finding names the touches=0 reading" "$ERR"; fi
assert_eq "only the dropped entry is a finding" 1 "$(grep -c "does not cover" <<< "$ERR")"
rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"$'\n  - docs/'
lint; expect "a dir entry the block does not list" 1 "code_paths entry 'docs/'"; rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"$'\n  - Makefile'
lint; expect "a file entry the block does not list" 1 "code_paths entry 'Makefile'"; rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"$'\n  - "src/**/*.tf"'
lint; expect "a glob entry the block does not list" 1 "code_paths entry 'src/**/*.tf'"; rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"$'\n  - "src/**/*.tf"'; set_block '                  images/*|template/*|tests/*|tools/*|.claude/*|src/*) touches=1 ;;
                  .trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "a glob entry the block covers" 0; rm -rf "$SCRATCH"

# A leading ./ on an entry is dropped (#245): the gate sees `git diff` paths, never `./tools/a`.
new_repo "${TEMPLATE_PATHS/  - tools\//  - .\/tools\/}"
lint; expect "a ./tools/ entry against a block with tools/*" 0
if [[ "$ERR" == *warning* ]]; then fail "a ./ entry covered by tools/* has nothing to warn about" "$ERR"; else pass; fi
rm -rf "$SCRATCH"

new_repo "${TEMPLATE_PATHS/  - tools\//  - .\/tools\/}"; set_block '                  images/*|template/*|tests/*|./tools/*|.claude/*) touches=1 ;;
                  .trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "a ./tools/ entry against a block with only ./tools/*" 1 "code_paths entry './tools/' in"
if [[ "$ERR" == *"(tools/a reads touches=0"* ]]; then pass; else fail "the finding samples the entry without its ./" "$ERR"; fi
rm -rf "$SCRATCH"

# A directory entry with no trailing slash is a directory when it exists next to .github/.
new_repo "$TEMPLATE_PATHS"$'\n  - docs'; mkdir "$REPO/docs"
lint; expect "an existing directory entry without a trailing slash" 1 "code_paths entry 'docs'"; rm -rf "$SCRATCH"

# The same finding when the lint is run from inside .github/workflows with `.`, or with a
# trailing `/.` (the root is resolved, not trimmed from the text).
new_repo "$TEMPLATE_PATHS"$'\n  - docs'; mkdir "$REPO/docs"; set_block '                  docs) touches=1 ;;'
RC=0; ERR="$(cd "$WF" && bash "$LINT" . 2>&1 > /dev/null)" || RC=$?
expect "a directory entry, run with . from .github/workflows" 1 "code_paths entry 'docs'"
lint "$WF/."; expect "a directory entry, run with a trailing /." 1 "code_paths entry 'docs'"; rm -rf "$SCRATCH"

# The -d branch: an existing directory entry with no slash is sampled as x/a, so docs/* covers it.
new_repo "$TEMPLATE_PATHS"$'\n  - docs'; mkdir "$REPO/docs"; set_block '                  images/*|template/*|tests/*|tools/*|.claude/*|docs/*|.trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "an existing directory entry covered by docs/*" 0; rm -rf "$SCRATCH"

# `**/*.tf` also means a .tf file at the root.
new_repo "$TEMPLATE_PATHS"$'\n  - "**/*.tf"'; set_block '                  images/*|template/*|tests/*|tools/*|.claude/*|*/*.tf|.trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "an arm */*.tf for **/*.tf misses a root file" 1 "code_paths entry '**/*.tf'"; rm -rf "$SCRATCH"

# A glob with no matching sample (a bracket class) is skipped with a warning, and a comment inside the block is fine.
new_repo "$TEMPLATE_PATHS"$'\n  - "foo[ab].txt"'; set_block '                  # a comment
                  images/*|template/*|tests/*|tools/*|.claude/*|.trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "a bracket-class entry and a comment line" 0 "cannot build a sample path for the code_paths entry 'foo[ab].txt'"; rm -rf "$SCRATCH"

# An exported CDPATH must not switch the check off (cd would print the directory it found).
new_repo "$TEMPLATE_PATHS"$'\n  - docs/'
RC=0; ERR="$(cd "$REPO" && CDPATH=".:/tmp" bash "$LINT" 2>&1 > /dev/null)" || RC=$?
expect "an uncovered entry with CDPATH exported" 1 "code_paths entry 'docs/'"; rm -rf "$SCRATCH"

# A glob inside a directory entry is filled in, not skipped.
new_repo "$TEMPLATE_PATHS"$'\n  - "modules/*/"'
lint; expect "an uncovered directory glob entry" 1 "code_paths entry 'modules/*/'"; rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"$'\n  - "modules/*/"'; set_block '                  images/*|template/*|tests/*|tools/*|.claude/*|modules/*|.trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "a covered directory glob entry" 0; rm -rf "$SCRATCH"

# One lucky sample shape per entry is not enough.
new_repo "$TEMPLATE_PATHS"; set_block '                  images/a|template/*|tests/*|tools/*|.claude/*|.trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "an arm that covers only images/a" 1 "code_paths entry 'images/'"; rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"; set_block '                  images/[a-z]*|template/*|tests/*|tools/*|.claude/*|.trivyignore.yaml|.gitattributes|.ai/project.yml) touches=1 ;;'
lint; expect "an arm that misses an upper-case name under images/" 1 "code_paths entry 'images/'"; rm -rf "$SCRATCH"

# A reserved word as a pattern is a finding, not an abort before the other rules run.
new_repo "$TEMPLATE_PATHS"; set_block '                  esac) touches=1 ;;'
lint; expect "esac as a case pattern" 1 "does not parse as case arms"
if [[ "$ERR" == *"finding(s)."* ]]; then pass; else fail "esac still ends in the summary line" "$ERR"; fi
rm -rf "$SCRATCH"

# The reverse is only a warning.
new_repo $'  - images/\n  - .github/'
lint; expect "a block pattern no code_paths entry matches" 0 "pattern 'template/*' matches none"; rm -rf "$SCRATCH"

# The block is evaluated to read it, so only literal case arms may reach that.
new_repo "$TEMPLATE_PATHS"; set_block '                  images/*) touches=1 ;;
                  $(touch pwned)) touches=1 ;;'
lint; expect "a command substitution in the block" 1 "is not '<glob>|<glob>) touches=1 ;;'"
if [ -e pwned ] || [ -e "$REPO/pwned" ]; then fail "the block was evaluated"; rm -f pwned; else pass; fi
rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"; set_block '                  images/*) touches=1; touch pwned ;;'
lint; expect "a second command on an arm" 1 "is not '<glob>|<glob>) touches=1 ;;'"; rm -rf "$SCRATCH"

new_repo "$TEMPLATE_PATHS"; sed -i '/# >>> CONSUMER: code_paths/d; /# <<< CONSUMER: code_paths/d' "$WF/$GATE"
lint; expect "a gate with no CONSUMER code_paths region" 1 "region is missing"; rm -rf "$SCRATCH"

new_repo '  images/: x'
lint; expect "code_paths that is not a list of strings" 1 "code_paths must be a list of strings"; rm -rf "$SCRATCH"

# No .ai/project.yml next to .github/: nothing to check against (the cases above all run without one).
new_repo "$TEMPLATE_PATHS"; rm "$REPO/.ai/project.yml"
lint; expect "no .ai/project.yml" 0; rm -rf "$SCRATCH"

# --- input handling ------------------------------------------------------------------------
new_wf; printf 'a: [unclosed\n' > "$WF/bad.yml"
lint; expect "a workflow that is not valid YAML" 1 "not parseable"; rm -rf "$SCRATCH"

new_wf; mkdir "$SCRATCH/empty"
lint "$SCRATCH/empty"; expect "an empty directory" 1 "no workflow files"; rm -rf "$SCRATCH"

new_wf
lint "$SCRATCH/nope"; expect "a missing directory" 2 "not a directory"; rm -rf "$SCRATCH"

# The two template pins agree (the lint only warns on a mismatch; this repo's template must not).
caller_sha="$(grep -oE 'verify-devcontainer-image\.yml@[0-9a-f]{40}' "$TEMPLATE_DIR/$CALLER" | cut -d@ -f2)"
gate_sha="$(grep -oE 'devcontainer-bump-decision\.yml@[0-9a-f]{40}' "$TEMPLATE_DIR/$GATE" | cut -d@ -f2)"
if [[ "$caller_sha" =~ ^[0-9a-f]{40}$ ]]; then pass; else fail "the template caller carries a 40-hex pin"; fi
assert_eq "the template's verify and decide pins name one commit" "$caller_sha" "$gate_sha"

summary
