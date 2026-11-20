#!/usr/bin/env bash
# The differential Trivy gate of a pull request (build-and-test.sh local): compares the Trivy JSON
# report of a PR image with the report of the published image of the same flavour, and fails on
# what the PR image has and the published one does not, and on any secret finding.
#
# Usage: bash .github/scripts/trivy-diff.sh FLAVOR PR_REPORT BEFORE
#
#   FLAVOR     base, tofu, node, devapp or devapp-tofu
#   PR_REPORT  Trivy JSON of the PR image
#   BEFORE     Trivy JSON of the published image, or the word `none` (no before set: every finding
#              counts as added, which is the full gate)
#
# A vulnerability's key is (VulnerabilityID, PkgName, location): the finding's PkgPath when Trivy
# gives one; otherwise, for an os-pkgs result, the empty string (that Target names the image
# reference, which differs between the two scans); otherwise the result's Target. Versions are not
# part of the key. Keys are built and compared in jq on the raw strings; the cut to 256 characters
# and the keep-set replacement happen only when a line is printed. Secrets are never differential.
#
# Stdout: one line per vulnerability of the PR report (`::error::<flavor>: added ...` or
# `trivy-diff: <flavor>: published ...`), one `::error::<flavor>: secret <rule> in <target>` line per
# secret (never the matched text), then `trivy-diff: <flavor>: <a> added, <p> published, <s> secret`.
# Every line starts with fixed text, and no report field goes into the properties part of a command.
#
# Exit status: 0 nothing added and no secret; 1 a vulnerability is added or a secret is found;
# 2 a usage error or a report that is not well formed (one fixed line on stderr, nothing on stdout).
set -euo pipefail
export LC_ALL=C

# The same keep set as trivy-daily.sh's KEEP, in jq's regex syntax: every other character is `?`.
KEEP_JQ='[^A-Za-z0-9 ._:/@+~,=()-]'
MAX_FIELD=256

usage_error() { echo "trivy-diff: usage error" >&2; exit 2; }
bad_report() { echo "trivy-diff: a report is not well formed" >&2; exit 2; }

[ "$#" -eq 3 ] || usage_error
flavor=$1 pr=$2 before=$3
case $flavor in base|tofu|node|devapp|devapp-tofu) ;; *) usage_error ;; esac
[ -f "$pr" ] || bad_report
if [ "$before" != none ] && [ ! -f "$before" ]; then usage_error; fi

# shellcheck disable=SC2016 # a jq program
SHAPE='
  def str: type == "string";
  def nes: str and length > 0;
  def arr_or_null(f): . == null or (type == "array" and all(.[]; f));
  type == "object"
  and (.Results | arr_or_null(
    type == "object" and (.Target | nes) and (.Class | str)
    and (.Vulnerabilities | arr_or_null(
      type == "object" and (.VulnerabilityID | nes) and (.PkgName | nes)
      and (.PkgPath | . == null or str) and (.InstalledVersion | . == null or str)
      and (.FixedVersion | . == null or str)))
    and (.Secrets | arr_or_null(type == "object" and (.RuleID | nes)))))'

wellformed() { jq -e -s "length == 1 and (.[0] | $SHAPE)" "$1" >/dev/null 2>&1; }
wellformed "$pr" || bad_report
if [ "$before" != none ]; then wellformed "$before" || bad_report; fi

# shellcheck disable=SC2016 # a jq program
PROGRAM='
  def loc($t; $class): if (.PkgPath | type) == "string" and (.PkgPath | length) > 0 then .PkgPath
    elif $class == "os-pkgs" then "" else $t end;
  def clean: .[0:$max] | gsub($keep; "?");
  def vulns: [.Results[]? | .Class as $class | .Target as $t | .Vulnerabilities[]?
    | {id: .VulnerabilityID, pkg: .PkgName, loc: loc($t; $class),
       inst: (.InstalledVersion // ""), fix: (.FixedVersion // "")}];
  (($before[0] | vulns) | map({([.id, .pkg, .loc] | tojson): true}) | add // {}) as $have
  | (vulns | map(. + {added: (($have[[.id, .pkg, .loc] | tojson]) | not)})) as $v
  | [.Results[]? | .Target as $t | .Secrets[]? | {rule: .RuleID, target: $t}] as $s
  | ([$v[] | select(.added)] | length) as $a
  | ([$v[] | select(.added | not)] | length) as $p
  | ($s | length) as $n
  | {added: $a, secret: $n, lines:
      ([$v[] | (if .added then "::error::\($flavor): added" else "trivy-diff: \($flavor): published" end)
        + " \(.id | clean) \(.pkg | clean) \(if .loc == "" then "-" else (.loc | clean) end)"
        + " installed \(.inst | clean) fixed \(.fix | clean)"]
       + [$s[] | "::error::\($flavor): secret \(.rule | clean) in \(.target | clean)"]
       + ["trivy-diff: \($flavor): \($a) added, \($p) published, \($n) secret"])}'

if [ "$before" = none ]; then
  result=$(jq -c --arg flavor "$flavor" --argjson max "$MAX_FIELD" --arg keep "$KEEP_JQ" \
    --slurpfile before <(echo '{}') "$PROGRAM" "$pr" 2>/dev/null) || bad_report
else
  result=$(jq -c --arg flavor "$flavor" --argjson max "$MAX_FIELD" --arg keep "$KEEP_JQ" \
    --slurpfile before "$before" "$PROGRAM" "$pr" 2>/dev/null) || bad_report
fi
printf '%s\n' "$result" | jq -r '.lines[]'
[ "$(printf '%s\n' "$result" | jq '.added + .secret' 2>/dev/null)" -eq 0 ] 2>/dev/null
