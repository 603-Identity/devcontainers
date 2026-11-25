#!/usr/bin/env bash
# Tests that bump-binaries.sh declines a tool version whose bump/<tool>-<version> branch already
# exists on origin, whatever the state of any PR on it (#86: a human closes the bump PR unmerged and
# leaves the branch; #715: the branch alone is the decline, and an orphan branch with no PR declines
# too instead of failing the run). Fake `gh`, `curl` and `git` stand in for the network; the fake
# git answers ls-remote from FAKE_LS_OUT / FAKE_LS_RC and records every call, so the test can
# assert that nothing was switched, pushed or deleted. Offline; needs bash and awk.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/bump-binaries.sh"
suite "bump-binaries (declined remote branch)"

SHA_OK=$(printf 'a%.0s' $(seq 1 64))
SHA_OLD=$(printf 'b%.0s' $(seq 1 64))
REF=refs/heads/bump/gh-2.103.0
SHA1=1111111111111111111111111111111111111111

# setup <ls-remote stdout> <ls-remote exit code>
setup() {
  SCRATCH="$(mktemp -d)"
  R="$SCRATCH/root"
  mkdir -p "$R/.github/scripts" "$R/images/base" "$SCRATCH/bin"
  cp "$SCRIPT" "$R/.github/scripts/"
  printf 'ARG GH_VERSION=2.102.0\nARG GH_SHA256=%s\n' "$SHA_OLD" > "$R/images/base/Dockerfile"
  : > "$SCRATCH/calls.log"
  export FAKE_LOG="$SCRATCH/calls.log" FAKE_LS_OUT="$1" FAKE_LS_RC="$2"
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
case "$1 $2" in
  "api repos/cli/cli/releases/latest") printf 'v2.103.0\thttps://example.test/gh\n' ;;
  *) ;;
esac
G
  cat > "$SCRATCH/bin/git" <<'G'
#!/usr/bin/env bash
echo "git $*" >> "$FAKE_LOG"
case "$*" in *ls-remote*) printf '%s' "$FAKE_LS_OUT"; exit "$FAKE_LS_RC" ;; esac
exit 0
G
  cat > "$SCRATCH/bin/curl" <<'C'
#!/usr/bin/env bash
printf '%s  gh_2.103.0_linux_amd64.tar.gz\n' "$FAKE_SHA"
C
  chmod +x "$SCRATCH/bin/"*
  export FAKE_SHA="$SHA_OK"
}

run() {
  RC=0
  OUT="$(env PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" gh 2>&1)" || RC=$?
}
out_has() { case "$OUT" in *"$1"*) pass ;; *) fail "$2" "output lacks '$1': $OUT" ;; esac; }
git_has() { grep -qF -- "git $1" "$FAKE_LOG"; }
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
assert_untouched() { # nothing was configured, switched, committed, pushed or opened
  local verb
  for verb in switch push branch "config user" add commit; do
    if grep -qE "^git .*(^| )$verb( |$)" "$FAKE_LOG"; then fail "no git $verb ($1)"; else pass; fi
  done
  if log_has "gh pr create"; then fail "no PR is created ($1)"; else pass; fi
  if log_has "gh pr list"; then fail "no PR listing ($1)"; else pass; fi
  assert_eq "the Dockerfile is untouched ($1)" "ARG GH_SHA256=$SHA_OLD" "$(sed -n '2p' "$R/images/base/Dockerfile")"
}

# --- the remote branch exists: warn and skip, touch nothing, whatever the state of any PR --------
setup "$SHA1	$REF
" 0
run
assert_rc "a declined version is a skip, not a failure" 0 "$RC"
out_has "::warning::gh: bump/gh-2.103.0 already exists on origin" "says the branch already exists, as a warning annotation"
if log_has "git -C $R ls-remote origin $REF"; then pass; else fail "asks origin for the exact ref" "$(cat "$FAKE_LOG")"; fi
if log_has "gh pr list"; then fail "no PR lookup decides a decline" "$(cat "$FAKE_LOG")"; else pass; fi
if git_has "-C $R ls-remote origin refs/heads/bump/weekly-"; then fail "a run where nothing moved never asks about the weekly ref"; else pass; fi
assert_untouched "declined"
rm -rf "$SCRATCH"

# --- the declines reach the job summary on a run where nothing moved ----------------------------
setup "$SHA1	$REF
" 0
SUMMARY="$SCRATCH/summary.md"
RC=0
OUT="$(env PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t GITHUB_STEP_SUMMARY="$SUMMARY" \
  bash "$R/.github/scripts/bump-binaries.sh" gh 2>&1)" || RC=$?
assert_rc "only a decline still exits 0" 0 "$RC"
# shellcheck disable=SC2016  # a literal backtick pair, not a command substitution
if grep -qF '`bump/gh-2.103.0`' "$SUMMARY" 2> /dev/null; then pass; else fail "the job summary names the declined branch" "$(cat "$SUMMARY" 2> /dev/null)"; fi
assert_untouched "declined with a summary"
rm -rf "$SCRATCH"

# --- a ref that merely ENDS with the branch name is not the branch (ls-remote suffix match) ------
setup "$SHA1	refs/heads/x/$REF
" 0
run
assert_rc "a suffix-matching ref does not stop the bump" 0 "$RC"
if git_has "-C $R push -u origin bump/weekly-"; then pass; else fail "the weekly branch is pushed" "$(cat "$FAKE_LOG")"; fi
if log_has "gh pr create"; then pass; else fail "the PR is created"; fi
assert_eq "the Dockerfile checksum is rewritten" "ARG GH_SHA256=$SHA_OK" "$(sed -n '2p' "$R/images/base/Dockerfile")"
rm -rf "$SCRATCH"

# --- no remote branch at all: the bump goes ahead ---------------------------------------------
setup "" 0
run
assert_rc "a missing remote branch lets the bump proceed" 0 "$RC"
if git_has "-C $R push -u origin bump/weekly-"; then pass; else fail "the weekly branch is pushed" "$(cat "$FAKE_LOG")"; fi
# #85: the PR body cites the URL the checksum was read from, not only the release page.
if log_has "Checksum source: https://github.com/cli/cli/releases/download/v2.103.0/gh_2.103.0_checksums.txt"; then pass; else fail "the PR body cites the checksum source" "$(cat "$FAKE_LOG")"; fi
rm -rf "$SCRATCH"

# --- ls-remote itself fails (network/auth): that leg fails, never a silent proceed or skip -------
setup "" 128
run
assert_rc "an ls-remote failure fails the run" 1 "$RC"
out_has "could not check origin" "says the check failed"
out_has "failed at step: decline check" "names the decline check step"
if git_has "-C $R push"; then fail "nothing is pushed when the check failed"; else pass; fi
assert_untouched "ls-remote failure"
rm -rf "$SCRATCH"

# --- ls-remote runs authenticated: setup-git comes first ---------------------------------------
setup "" 0
run
first_auth="$(grep -n '^gh auth setup-git' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
first_ls="$(grep -n 'ls-remote' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
if [ -n "$first_auth" ] && [ -n "$first_ls" ] && [ "$first_auth" -lt "$first_ls" ]; then pass; else fail "gh auth setup-git runs before ls-remote" "$(cat "$FAKE_LOG")"; fi
rm -rf "$SCRATCH"

# --- a gh bump that opens its PR closes no PR when the supersede listing is empty ----------------
setup "" 0
run
assert_rc "a gh bump that opens its PR succeeds" 0 "$RC"
if log_has "gh pr create"; then pass; else fail "the PR is created"; fi
if log_has "gh pr close"; then fail "no PR is closed when the listing is empty" "$(cat "$FAKE_LOG")"; else pass; fi
rm -rf "$SCRATCH"

summary
