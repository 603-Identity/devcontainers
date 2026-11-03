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
#   * scans the whole ancestry of the head: git writes `log -p --root --diff-merges=separate
#     --text` and `betterleaks stdin --git-diff` parses it (rc.3 removed `git --log-opts`).
#     The merge option shows merge-resolution content and `--text` defeats a `-diff` attribute. No range arithmetic, no --first-parent. A git
#     failure is a failed scan;
#   * v2 exits 1 for findings AND for config errors, so it reads the JSONL `scan` record and
#     passes only when `state == "complete"`. A missing or incomplete record is an error; an
#     `incomplete` record is retried once, a findings result never is;
#   * refuses env that changes the config (BETTERLEAKS_CONFIG, BETTERLEAKS_CONFIG_TOML), changes
#     the fingerprints the ignore file matches (BETTERLEAKS_FINGERPRINT_HMAC_KEY) or contacts
#     credential providers (BETTERLEAKS_VALIDATE, BETTERLEAKS_ANALYZE);
#   * always --redact (100%), --no-allow-signatures and an explicit --ignore-file; never
#     --disable-rule, --isolate-rule, --confidence, --allow-signature, --set-attr, -v or -a;
#   * writes no report file.
# Test hooks: ORG_TOML (default: the path the repo config must extend) and SCAN_LINT.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG_TOML="${ORG_TOML:-/usr/local/share/devc/secret-scan/org.toml}"
LINT="${SCAN_LINT:-$here/secret-scan-lint.sh}"

die() { echo "::error::secret-scan: $*" >&2; exit 1; }

for v in BETTERLEAKS_CONFIG BETTERLEAKS_CONFIG_TOML BETTERLEAKS_VALIDATE BETTERLEAKS_ANALYZE BETTERLEAKS_FINGERPRINT_HMAC_KEY; do
  [ -z "${!v:-}" ] || die "$v is set; refusing to run (it changes the config or fingerprints, or contacts credential providers)."
done
: "${BASE_SHA:?}" "${HEAD_SHA:?}" "${REPO_DIR:?}" "${BETTERLEAKS:?}"
[[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || die "BASE_SHA is not 40 hex characters."
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || die "HEAD_SHA is not 40 hex characters."
command -v jq > /dev/null || die "jq not found."

git_() { GIT_NO_REPLACE_OBJECTS=1 git -C "$REPO_DIR" "$@"; }
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
scan_once() { # sets rc, gitrc, state, nfind
  # Betterleaks 2.0.0-rc.3 dropped `git --log-opts` and no longer shells out to git, so selection
  # moves here: git writes the patch stream, `stdin --git-diff` parses it. Every option that can
  # drop coverage from that stream is named, so a runner's git config (diff.noprefix, log.showRoot,
  # log.diffMerges, log.abbrevCommit, log.showSignature, color.ui, ...) and refs/replace/* do not
  # change what is scanned: the whole ancestry of the head (no range, no --first-parent), `--root`
  # for the first commit's patch, `--diff-merges=separate` for merge-resolution content against
  # each parent, `--text` so a binary or `-diff` file is scanned as text, no rename detection (a
  # renamed file is scanned in full), no external diff or textconv, full 40-hex commit ids, the default date format and UTF-8 output
  # (the org config's commit-bound filter reads the ids; a date or encoding the parser rejects loses
  # the header). tests/smoke.sh and the README's one-off sweep carry the same flags; a test
  # compares them.
  # The two exit codes are read apart: a git failure or a scanner that stopped reading early must
  # never look like "no findings".
  local pst
  set +e
  git_ --no-replace-objects log -p --root --diff-merges=separate --text --no-renames --no-ext-diff \
    --no-textconv --no-color --no-show-signature --no-abbrev-commit --no-decorate --no-notes \
    --no-relative --date=default --encoding=UTF-8 --pretty=medium --src-prefix=a/ --dst-prefix=b/ "$HEAD_SHA" 2> "$work/git.err" \
    | "$BETTERLEAKS" stdin --git-diff -c "$config" --ignore-file "$work/ignore" \
      --no-allow-signatures --redact --no-banner --no-color --jsonl > "$work/out.jsonl" 2> "$work/err.log"
  pst=("${PIPESTATUS[@]}")
  set -e
  gitrc="${pst[0]}"
  rc="${pst[1]}"
  state="$(jq -rs '[.[] | select(type == "object" and has("scan")) | .scan.state] | last // "none"' "$work/out.jsonl" 2> /dev/null || echo none)"
  nfind="$(jq -rs '[.[] | select(type == "object" and has("finding"))] | length' "$work/out.jsonl" 2> /dev/null || echo -1)"
  # git failed, or was cut off (SIGPIPE) because the scanner stopped reading: the stream the
  # scanner saw was not the whole ancestry, so whatever it printed proves nothing.
  # A scanner that could not even start, or was killed (126 and up), makes git die of SIGPIPE:
  # that is the scanner's failure, so leave the state as it read.
  if [ "$gitrc" -ne 0 ] && [ "$rc" -lt 126 ]; then state=gitfail; fi
}

scan_once
if [ "$state" = incomplete ]; then
  echo "scan reported 'incomplete'; retrying once" >&2
  scan_once
fi

# The JSONL half skips finding records: their paths and messages come from the scanned repo, so
# a file named "incomplete scan" must not turn a findings failure into did-not-complete.
# Captured first, not piped: under pipefail a jq failure or SIGPIPE would hide a grep match.
nonfinding="$(jq -r 'select(type != "object" or has("finding") == false) | tostring' "$work/out.jsonl" 2> /dev/null || true)"
if grep -qi 'incomplete scan' "$work/err.log" 2> /dev/null || grep -qi 'incomplete scan' <<< "$nonfinding"; then
  state=incomplete
fi

if [ "$state" != complete ]; then
  # Scanner stderr can quote paths from the scanned repo. Reduce it to a safe set (no CR, '#' or
  # '[', so no extra line and no legacy ##[command]) and prefix every line so none can start
  # with "::" and be read as a workflow command.
  { tail -n 5 "$work/git.err"; tail -n 15 "$work/err.log"; } 2> /dev/null | tr -c 'A-Za-z0-9._/:=, |()\n-' '_' | sed 's/^/  | /' >&2 || true
  die "scan did not complete (state: $state, exit $rc, git exit $gitrc); treating as a failure, not as 'no findings'."
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
         | (.location.start_line | if type == "number" and . >= 1 then tostring else null end) as $l
         | "::error file=\($f)\(if $l then ",line=\($l)" else "" end)::\(.rule_id | safe) at \($f)\(if $l then ":\($l)" else "" end)"'     "$work/out.jsonl" 2> /dev/null | sort -u | head -n 50 >&2 || true
  die "$nfind finding(s) (exit $rc). A red check means rotate the secret; never rewrite history and re-push."
fi
echo "secret-scan: complete, no findings (ancestry of $HEAD_SHA, $count commits)."
