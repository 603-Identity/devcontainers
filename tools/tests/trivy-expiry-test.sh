#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Offline tests for .github/scripts/trivy-expiry.sh and the shape of trivy-expiry.yml. The script
# runs against ignore files written into a scratch directory, with TRIVY_EXPIRY_TODAY pinned.
# Needs bash, GNU date and yq (mikefarah).
set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite trivy-expiry

SCRIPT="$ROOT_DIR/.github/scripts/trivy-expiry.sh"
WF="$ROOT_DIR/.github/workflows/trivy-expiry.yml"
TODAY=2026-12-01
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT

ignore_file() { # ignore_file <name> <expired_at...>: one entry per date, ids E1.., paths p1..
  local f="$S/$1" n=0 d
  shift
  printf 'vulnerabilities:\n' >"$f"
  for d in "$@"; do
    n=$((n + 1))
    printf '  - id: CVE-E%s\n    paths: ["usr/local/bin/p%s"]\n    statement: "x"\n' "$n" "$n" >>"$f"
    [ "$d" = @none ] || printf '    expired_at: %s\n' "$d" >>"$f"
  done
  printf '%s' "$f"
}
run() { # run <today|@unset> <file> [extra args]: sets RC, OUT
  local today=$1 f=$2
  shift 2
  RC=0
  if [ "$today" = @unset ]; then
    OUT=$(env -u TRIVY_EXPIRY_TODAY -u GITHUB_STEP_SUMMARY bash "$SCRIPT" "$f" "$@" 2>"$S/stderr") || RC=$?
  else
    OUT=$(env -u GITHUB_STEP_SUMMARY TRIVY_EXPIRY_TODAY="$today" bash "$SCRIPT" "$f" "$@" 2>"$S/stderr") || RC=$?
  fi
}

# window: today + 10 days = 2026-12-11
f=$(ignore_file plus11 2026-12-12); run $TODAY "$f"
assert_rc "today plus 11 days" 0 "$RC"
f=$(ignore_file plus10 2026-12-11); run $TODAY "$f"
assert_rc "today plus 10 days" 1 "$RC"
assert_eq "today plus 10 days: listed with id and path" "yes" "$(case $OUT in *CVE-E1*usr/local/bin/p1*2026-12-11*) echo yes ;; *) echo no ;; esac)"
f=$(ignore_file today 2026-12-01); run $TODAY "$f"
assert_rc "expires today" 1 "$RC"
f=$(ignore_file past 2026-11-01); run $TODAY "$f"
assert_rc "already expired" 1 "$RC"
assert_eq "already expired: listed" "yes" "$(case $OUT in *CVE-E1*2026-11-01*) echo yes ;; *) echo no ;; esac)"

# a mixed file lists only the entries inside the window
f=$(ignore_file mixed 2026-12-30 2026-12-05 2026-12-20); run $TODAY "$f"
assert_rc "a mixed file" 1 "$RC"
assert_eq "a mixed file: only the near entry is listed" "yes" "$(case $OUT in *CVE-E2*) case $OUT in *CVE-E1* | *CVE-E3*) echo no ;; *) echo yes ;; esac ;; *) echo no ;; esac)"

# the step summary gets the same listing when GITHUB_STEP_SUMMARY is set
: >"$S/summary"
RC=0; GITHUB_STEP_SUMMARY="$S/summary" TRIVY_EXPIRY_TODAY=$TODAY bash "$SCRIPT" "$S/plus10" >/dev/null 2>&1 || RC=$?
assert_rc "summary run" 1 "$RC"
assert_eq "the summary file lists the entry" "yes" "$(grep -q 'CVE-E1.*usr/local/bin/p1.*2026-12-11' "$S/summary" && echo yes || echo no)"
: >"$S/summary"
RC=0; GITHUB_STEP_SUMMARY="$S/summary" TRIVY_EXPIRY_TODAY=$TODAY bash "$SCRIPT" "$S/plus11" >/dev/null 2>&1 || RC=$?
assert_rc "summary run, nothing near" 0 "$RC"
assert_eq "the summary file stays empty when nothing is listed" "0" "$(wc -c <"$S/summary" | tr -d ' ')"

# malformed dates fail and are listed as malformed
for d in @none 2026-12-1 12/20/2026 2026-02-30 2026-13-01 soon; do
  f=$(ignore_file bad "$d"); run $TODAY "$f"
  assert_rc "malformed expired_at '$d'" 1 "$RC"
  assert_eq "malformed expired_at '$d': listed as malformed" "yes" "$(case $OUT in *malformed*) echo yes ;; *) echo no ;; esac)"
done

# an empty list, and a file with no vulnerabilities key
printf 'vulnerabilities: []\n' >"$S/empty.yaml"; run $TODAY "$S/empty.yaml"
assert_rc "an empty vulnerabilities list" 0 "$RC"
printf 'misconfigurations: []\n' >"$S/nokey.yaml"; run $TODAY "$S/nokey.yaml"
assert_rc "a file with no vulnerabilities key" 0 "$RC"

# an entry with no paths (legal in Trivy) or no id is judged by its date alone
printf 'vulnerabilities:\n  - id: CVE-NP\n    expired_at: 2027-06-01\n  - paths: ["x"]\n    expired_at: 2027-06-01\n' >"$S/nopaths.yaml"
run $TODAY "$S/nopaths.yaml"
assert_rc "entries without paths or id, far dates" 0 "$RC"
printf 'vulnerabilities:\n  - id: CVE-NP\n    expired_at: 2026-12-02\n' >"$S/nopaths2.yaml"
run $TODAY "$S/nopaths2.yaml"
assert_rc "an entry without paths, near date" 1 "$RC"
assert_eq "an entry without paths: listed as expiring, not malformed" "yes" "$(case $OUT in *malformed*) echo no ;; *CVE-NP*2026-12-02*) echo yes ;; *) echo no ;; esac)"

# a control character in a value cannot make a missing expired_at read as a date, or split an entry
printf 'vulnerabilities:\n  - id: CVE-X\n    paths: ["a\\u001F2099-01-01"]\n' >"$S/ctl.yaml"
run $TODAY "$S/ctl.yaml"
assert_rc "a unit separator in paths, no expired_at" 1 "$RC"
assert_eq "a unit separator in paths: listed as malformed" "yes" "$(case $OUT in *malformed*) echo yes ;; *) echo no ;; esac)"
printf 'vulnerabilities:\n  - id: "CVE-Z\\n"\n    paths: ["c"]\n    expired_at: 2026-12-02\n' >"$S/nl.yaml"
run $TODAY "$S/nl.yaml"
assert_rc "a newline in id" 1 "$RC"
assert_eq "a newline in id: the entry stays one line, with its date" "yes" "$(case $OUT in *malformed*) echo no ;; *'CVE-Z? (c): expires 2026-12-02'*) echo yes ;; *) echo no ;; esac)"
printf 'vulnerabilities:\n  - id: CVE-Y\n    paths: ["p"]\n    expired_at: "2099-01-01\\u001F"\n' >"$S/ctl2.yaml"
run $TODAY "$S/ctl2.yaml"
assert_rc "a separator inside expired_at" 1 "$RC"

# a printed field cannot carry markup
printf 'vulnerabilities:\n  - id: "[x](http://e)<b>"\n    paths: ["a|b"]\n    expired_at: 2026-12-02\n' >"$S/markup.yaml"
run $TODAY "$S/markup.yaml"
assert_rc "an id with markup" 1 "$RC"
assert_eq "an id with markup: no brackets or angle brackets are printed" "no" "$(case $OUT in *'['* | *']'* | *'<'* | *'|'*) echo yes ;; *) echo no ;; esac)"

# exit 2
run $TODAY "$S/plus11" extra
assert_rc "a wrong argument count (two)" 2 "$RC"
RC=0; bash "$SCRIPT" >/dev/null 2>&1 || RC=$?
assert_rc "a wrong argument count (none)" 2 "$RC"
run $TODAY "$S/does-not-exist"
assert_rc "an unreadable file" 2 "$RC"
run $TODAY "$S"
assert_rc "a directory" 2 "$RC"
printf 'a: [\n' >"$S/notyaml.yaml"; run $TODAY "$S/notyaml.yaml"
assert_rc "a non-YAML file" 2 "$RC"
printf 'base: &b\n  expired_at: 2099-01-01\nvulnerabilities:\n  - id: X\n    expired_at: 2026-12-02\n    <<: *b\n' >"$S/merge.yaml"
run $TODAY "$S/merge.yaml"
assert_rc "a merge key and anchor" 2 "$RC"
for t in "" 2026-02-30 2026-12-1 tomorrow 2026-13-01; do
  run "$t" "$S/plus11"
  assert_rc "TRIVY_EXPIRY_TODAY '$t'" 2 "$RC"
done

# the ignore file in the tree: every entry 2026-12-17 at the time of writing
# the dates come from the file itself, so a renewal that moves every expired_at keeps this green
first=$(yq -r '[.vulnerabilities[].expired_at] | sort | .[0]' "$ROOT_DIR/.trivyignore.yaml")
run "$(date -u -d "$first - 11 days" +%F)" "$ROOT_DIR/.trivyignore.yaml"
assert_rc "the tree's ignore file 11 days before its first expiry" 0 "$RC"
run "$(date -u -d "$first - 10 days" +%F)" "$ROOT_DIR/.trivyignore.yaml"
assert_rc "the tree's ignore file 10 days before its first expiry (window opens)" 1 "$RC"
f=$(ignore_file farclock "$(date -u -d '+400 days' +%F)"); run @unset "$f"
assert_rc "with the real clock, a far entry" 0 "$RC"

# --- the workflow's shape ------------------------------------------------------------------------
JOB='.jobs.trivy-expiry'
assert_eq "workflow-level permissions" '{}' "$(yq -o=json -I=0 '.permissions' "$WF")"
assert_eq "the job's permissions" '{"contents":"read"}' "$(yq -o=json -I=0 "$JOB.permissions" "$WF")"
assert_eq "the job's name" 'Trivy exceptions near expiry (not required)' "$(yq -r "$JOB.name" "$WF")"
# shellcheck disable=SC2016 # the expected value is a literal GitHub expression
assert_eq "the job's if" '${{ github.event_name == '"'pull_request'"' || (contains(fromJSON('"'"'["schedule","workflow_dispatch"]'"'"'), github.event_name) && github.ref == '"'refs/heads/main'"') }}' "$(yq -r "$JOB.if" "$WF")"
assert_eq "no needs" "null" "$(yq -r "$JOB.needs" "$WF")"
assert_eq "the trigger keys, exactly (no push)" "pull_request,schedule,workflow_dispatch" "$(yq -r '.on | keys | join(",")' "$WF")"
assert_eq "the schedule is build.yml's" "$(yq -r '.on.schedule[0].cron' "$ROOT_DIR/.github/workflows/build.yml")" "$(yq -r '.on.schedule[0].cron' "$WF")"
assert_eq "the checkout does not persist credentials" "false" "$(yq -r "$JOB.steps[0].with.\"persist-credentials\"" "$WF")"
assert_eq "the checkout is the pinned one" "$(yq -r '.jobs.test.steps[0].uses' "$ROOT_DIR/.github/workflows/build.yml")" "$(yq -r "$JOB.steps[0].uses" "$WF")"
assert_eq "two steps" "2" "$(yq -r "$JOB.steps | length" "$WF")"
assert_eq "the script step runs the script on the ignore file" "bash .github/scripts/trivy-expiry.sh .trivyignore.yaml" "$(yq -r "$JOB.steps[1].run" "$WF")"
assert_eq "the script step has no env" "null" "$(yq -r "$JOB.steps[1].env" "$WF")"
assert_eq "one job" "trivy-expiry" "$(yq -r '.jobs | keys | join(",")' "$WF")"
# the job is never a required check
if grep -qF 'Trivy exceptions near expiry' "$ROOT_DIR/.ai/project.yml"; then fail "the job name is in .ai/project.yml"; else pass; fi

summary
