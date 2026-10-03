#!/usr/bin/env bash
# Run Betterleaks over a pull request's full ancestry, failing closed (devcontainers#190, section 2).
# Called by .github/workflows/secret-scan.yml; runnable by hand for the same answer.
#
#   BASE_SHA=<40 hex> HEAD_SHA=<40 hex> REPO_DIR=<git checkout> \
#   BETTERLEAKS=<binary> secret-scan.sh
#
# Exit 0: the scan completed and found nothing. 1: findings, or anything that stopped the scan
# from proving there are none (every error path is red; nothing is "skipped"). 2: usage.
#
# What it does:
#   * trusted inputs only: the config and the ignore file are read from the BASE commit, never
#     from the head, so a PR cannot disable its own scan. A repo with no `betterleaks.toml` on
#     base gets the org config; one with a `betterleaks.toml` gets it only after
#     secret-scan-lint.sh accepts it (it may extend the org config, nothing more);
#   * scans the whole ancestry of the head with `-m --text`: `-m` shows merge-resolution
#     content and `--text` defeats a `-diff` attribute. No range arithmetic;
#   * v2 exits 1 for findings AND for config errors, so it reads the JSONL `scan` record and
#     passes only when `state == "complete"`. A missing or incomplete record is an error; an
#     `incomplete` record is retried once, a findings result never is;
#   * refuses env that changes the config (BETTERLEAKS_CONFIG, BETTERLEAKS_CONFIG_TOML) or
#     contacts credential providers (BETTERLEAKS_VALIDATE, BETTERLEAKS_ANALYZE);
#   * always --redact (100%), --no-allow-signatures and an explicit --ignore-file; never
#     --disable-rule, --isolate-rule, --confidence, --allow-signature, -v or -a;
#   * writes no report file.
# Test hooks: ORG_TOML (default: the path the repo config must extend) and SCAN_LINT.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG_TOML="${ORG_TOML:-/usr/local/share/devc/secret-scan/org.toml}"
LINT="${SCAN_LINT:-$here/secret-scan-lint.sh}"

die() { echo "::error::secret-scan: $*" >&2; exit 1; }

for v in BETTERLEAKS_CONFIG BETTERLEAKS_CONFIG_TOML BETTERLEAKS_VALIDATE BETTERLEAKS_ANALYZE; do
  [ -z "${!v:-}" ] || die "$v is set; refusing to run (it changes the config or contacts credential providers)."
done
: "${BASE_SHA:?}" "${HEAD_SHA:?}" "${REPO_DIR:?}" "${BETTERLEAKS:?}"
[[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || die "BASE_SHA is not 40 hex characters."
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || die "HEAD_SHA is not 40 hex characters."
command -v jq > /dev/null || die "jq not found."

git_() { git -C "$REPO_DIR" "$@"; }
git_ rev-parse --verify --quiet "${BASE_SHA}^{commit}" > /dev/null || die "base commit $BASE_SHA is not in the checkout."
git_ cat-file -e "${HEAD_SHA}^{commit}" 2> /dev/null || die "head commit $HEAD_SHA is not in the checkout."
count="$(git_ rev-list --count "$HEAD_SHA")"
[ "$count" -ge 1 ] || die "head has no commits to scan."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- config and ignore file, from the base commit -----------------------------------------
if git_ cat-file -e "${BASE_SHA}:betterleaks.toml" 2> /dev/null; then
  git_ show "${BASE_SHA}:betterleaks.toml" > "$work/betterleaks.toml"
  bash "$LINT" "$work/betterleaks.toml" || die "betterleaks.toml at the base commit is not an allowed repo config."
  [ -f "$ORG_TOML" ] || die "org config missing at $ORG_TOML (the workflow installs it)."
  config="$work/betterleaks.toml"
else
  [ -f "$ORG_TOML" ] || die "org config missing at $ORG_TOML (the workflow installs it)."
  config="$ORG_TOML"
fi
if git_ cat-file -e "${BASE_SHA}:.betterleaksignore" 2> /dev/null; then
  git_ show "${BASE_SHA}:.betterleaksignore" > "$work/ignore"
else
  : > "$work/ignore"
fi

# --- scan ----------------------------------------------------------------------------------
scan_once() { # sets rc, state, nfind
  rc=0
  "$BETTERLEAKS" git "$REPO_DIR" -c "$config" --ignore-file "$work/ignore" \
    --no-allow-signatures --redact --no-banner --no-color --jsonl \
    --log-opts="-m --text $HEAD_SHA" > "$work/out.jsonl" 2> "$work/err.log" || rc=$?
  state="$(jq -rs '[.[] | select(type == "object" and has("scan")) | .scan.state] | last // "none"' "$work/out.jsonl" 2> /dev/null || echo none)"
  nfind="$(jq -rs '[.[] | select(type == "object" and has("finding"))] | length' "$work/out.jsonl" 2> /dev/null || echo -1)"
}

scan_once
if [ "$state" = incomplete ]; then
  echo "scan reported 'incomplete'; retrying once" >&2
  scan_once
fi

if grep -qi 'incomplete scan' "$work/err.log" "$work/out.jsonl" 2> /dev/null; then
  state=incomplete
fi

if [ "$state" != complete ]; then
  tail -n 20 "$work/err.log" >&2 || true
  die "scan did not complete (state: $state, exit $rc); treating as a failure, not as 'no findings'."
fi
if [ "$nfind" -lt 0 ]; then
  die "could not read the scan output."
fi
if [ "$nfind" -gt 0 ] || [ "$rc" -ne 0 ]; then
  # Paths and rule ids come from the scanned repo: strip everything but a safe set so a crafted
  # file name cannot inject a workflow command into the log.
  jq -r 'def safe: tostring | gsub("[^A-Za-z0-9._/-]"; "_");
         select(type == "object" and has("finding")) | .finding
         | (.location.path // "?" | safe) as $f
         | (.location.start_line | if type == "number" then tostring else null end) as $l
         | "::error file=\($f)\(if $l then ",line=\($l)" else "" end)::\(.rule_id | safe) at \($f)\(if $l then ":\($l)" else "" end)"'     "$work/out.jsonl" 2> /dev/null | sort -u | head -n 50 >&2 || true
  die "$nfind finding(s) (exit $rc). A red check means rotate the secret; never rewrite history and re-push."
fi
echo "secret-scan: complete, no findings (ancestry of $HEAD_SHA, $count commits)."
