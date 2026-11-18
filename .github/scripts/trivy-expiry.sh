#!/usr/bin/env bash
# Early warning for .trivyignore.yaml: lists every `vulnerabilities` entry whose `expired_at` is on
# or before today plus 10 days (UTC, already-expired entries included), and fails when there is
# at least one. After an entry's date Trivy ignores it and the weekly build goes red, so this
# gives a renewal lane ten days of notice (docs/trivy-renewal.md).
#
# Usage:      bash .github/scripts/trivy-expiry.sh <ignore file>
#
#   TRIVY_EXPIRY_TODAY   overrides today (YYYY-MM-DD, a real date); for tests only.
#   GITHUB_STEP_SUMMARY  when set, the listing is also appended to that file.
#
# Exit status:
#   0  no entry expires within the window
#   1  at least one entry does, or an entry's expired_at is missing, not YYYY-MM-DD, or not a real
#      date (listed as malformed)
#   2  wrong argument count, an unreadable file, a file yq cannot parse, or a bad TRIVY_EXPIRY_TODAY
#
# It makes no network call and needs no token. Only `vulnerabilities` is read. Each printed field
# is cut to a safe character set, because a pull request can edit the file.
set -euo pipefail
export LC_ALL=C

usage_error() { echo "trivy-expiry: $1" >&2; exit 2; }
KEEP='[^A-Za-z0-9 ._:/@+~,=()-]'
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

real_date() { # real_date <text>: succeeds for a real YYYY-MM-DD calendar date
  local d=$1
  [[ $d =~ $DATE_RE ]] || return 1
  [ "$(date -u -d "$d" +%F 2>/dev/null)" = "$d" ]
}

[ "$#" -eq 1 ] || usage_error "usage: trivy-expiry.sh <ignore file>"
file=$1
{ [ -f "$file" ] && [ -r "$file" ]; } || usage_error "cannot read $file"

today=${TRIVY_EXPIRY_TODAY-}
if [ -n "${TRIVY_EXPIRY_TODAY+x}" ]; then
  real_date "$today" || usage_error "TRIVY_EXPIRY_TODAY is not a real YYYY-MM-DD date"
else
  today=$(date -u +%F)
fi
limit=$(date -u -d "$today + 10 days" +%F)

# a unit separator, not a tab: tab is IFS whitespace, so `read` would merge an empty field
SEP=$'\037'; export SEP
# yq and the YAML spec disagree about merge keys and duplicate keys, so a file could show this
# check one date and Trivy another. An ignore file has no use for anchors, aliases or merge keys:
# refuse them (exit 2) rather than guess which reading Trivy takes.
bad=$(yq -r '[.. | select(anchor != "" or tag == "!!merge" or kind == "alias")] | length' "$file") \
  || usage_error "yq could not read $file"
[ "$bad" = 0 ] || usage_error "$file uses YAML anchors, aliases or merge keys"
# Every field has its control characters (the separator and newlines included) replaced in yq, so
# a value cannot move a row boundary: one entry is exactly one line of three fields.
rows=$(yq -r '(.vulnerabilities // [])[] | [(.id // ""), ((.paths // []) | join(",")), (.expired_at // "")] | map(tostring | sub("[\x01-\x1f]"; "?")) | join(strenv(SEP))' "$file") \
  || usage_error "yq could not read $file"

lines=()
[ -z "$rows" ] || while IFS=$'\037' read -r id paths expired || [ -n "${id}${paths}${expired}" ]; do
  id=${id//$KEEP/?}
  paths=${paths//$KEEP/?}
  expired_clean=${expired//$KEEP/?}
  if ! real_date "$expired"; then
    lines+=("- ${id:-?} (${paths:-?}): malformed expired_at \`${expired_clean}\`")
  elif [[ $expired < $limit || $expired == "$limit" ]]; then
    lines+=("- ${id:-?} (${paths:-?}): expires ${expired}")
  fi
done <<<"$rows"

if [ "${#lines[@]}" -eq 0 ]; then
  echo "trivy-expiry: no entry expires on or before $limit"
  exit 0
fi
{
  echo "### Trivy exceptions near expiry (today $today, window ends $limit)"
  printf '%s\n' "${lines[@]}"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit 1
