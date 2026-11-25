#!/usr/bin/env bash
# Tests the `python` resolver of bump-binaries.sh (#561): it stays on the Dockerfile's pinned
# major.minor, lists python-build-standalone releases in ONE per_page=5 call, picks the asset by its
# exact name from the newest eligible release, and rewrites PYTHON_VERSION, PYTHON_BUILD and
# PYTHON_SHA256 together. An unreadable candidate SHA256SUMS is skipped with a warning; a newer build
# closes the older open python bump PRs the App opened. Fake `gh`, `curl` and `git` stand in for the
# network and log every call; the fake gh applies the --jq expression it was given with the real jq,
# so the draft/prerelease selection and the open-PR filter's listing run as written. Offline; needs
# bash, awk and jq.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/bump-binaries.sh"
suite "bump-binaries (python resolver)"

SHA_GOOD=$(printf 'a%.0s' $(seq 1 64))
SHA_DECOY=$(printf 'c%.0s' $(seq 1 64))
SHA_OLD=$(printf 'b%.0s' $(seq 1 64))
PIN_VER=3.15.2
PIN_BUILD=20261110
TRIPLE=x86_64-unknown-linux-gnu-install_only_stripped.tar.gz

# The asset name the image downloads, derived from the real Dockerfile's URL with both ARGs
# substituted and %2B read as +, so a resolver naming a different asset than the build fails.
dockerfile_asset() { # <version> <build>
  local url
  url="$(grep -oE 'curl -fsSL "https://[^"]*\$\{PYTHON_VERSION\}[^"]*"' "$ROOT_DIR/images/base/Dockerfile" | head -n 1 | sed -E 's/^curl -fsSL "//; s/"$//')"
  [ -n "$url" ] || return 1
  basename "$url" | sed "s/\${PYTHON_VERSION}/$1/g; s/\${PYTHON_BUILD}/$2/g; s/%2B/+/g"
}
REAL_NAME="$(dockerfile_asset 3.15.9 20261117)" || REAL_NAME=""
assert_eq "the Dockerfile's python asset is the install_only_stripped linux x86_64 tarball" \
  "cpython-3.15.9+20261117-$TRIPLE" "$REAL_NAME"

# setup <pin version> <pin build>: a scratch root with a copy of the script and a base Dockerfile.
# The listing fixture is $SCRATCH/releases.json; each release's SHA256SUMS is $SCRATCH/sums/<tag>.
setup() {
  SCRATCH="$(mktemp -d)"
  R="$SCRATCH/root"
  mkdir -p "$R/.github/scripts" "$R/images/base" "$SCRATCH/bin" "$SCRATCH/sums"
  cp "$SCRIPT" "$R/.github/scripts/"
  printf 'ARG PYTHON_VERSION=%s\nARG PYTHON_BUILD=%s\nARG PYTHON_SHA256=%s\n' "$1" "$2" "$SHA_OLD" > "$R/images/base/Dockerfile"
  cp "$R/images/base/Dockerfile" "$SCRATCH/Dockerfile.orig"
  : > "$SCRATCH/calls.log"
  echo '[]' > "$SCRATCH/releases.json"
  echo '[]' > "$SCRATCH/prs.json"
  export FAKE_LOG="$SCRATCH/calls.log" FAKE_REL="$SCRATCH/releases.json" FAKE_SUMS="$SCRATCH/sums" FAKE_PRS="$SCRATCH/prs.json"
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
case "$1 $2" in
  "api repos/astral-sh/python-build-standalone/releases?per_page=5")
    jq=""
    while [ $# -gt 0 ]; do [ "$1" = --jq ] && jq="$2"; shift; done
    jq -r "$jq" "$FAKE_REL" ;;
  "pr list")
    case "$*" in
      *--limit*)
        [ -z "${FAKE_PRLIST_FAIL:-}" ] || exit 1
        jq=""
        while [ $# -gt 0 ]; do [ "$1" = --jq ] && jq="$2"; shift; done
        jq -r "$jq" "$FAKE_PRS" ;;
      *) echo 0 ;;
    esac ;;
  "pr create") [ -z "${FAKE_CREATE_FAIL:-}" ] || exit 1 ;;
  "pr close") case " ${FAKE_CLOSE_FAIL:-} " in *" $3 "*) exit 1 ;; esac ;;
  *) ;;
esac
G
  cat > "$SCRATCH/bin/git" <<'G'
#!/usr/bin/env bash
echo "git $*" >> "$FAKE_LOG"
exit 0
G
  cat > "$SCRATCH/bin/curl" <<'C'
#!/usr/bin/env bash
url=""
while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) url="$1"; shift ;; esac; done
echo "curl $url" >> "$FAKE_LOG"
tag="${url%/SHA256SUMS}"; tag="${tag##*/}"
[ -f "$FAKE_SUMS/$tag" ] || exit 22
case " ${FAKE_CURL_FAIL_TAGS:-} " in *" $tag "*) exit 22 ;; esac
# Like real curl, fail with 23 when a write fails (SIGPIPE ignored so the failed write is seen).
trap '' PIPE
cat "$FAKE_SUMS/$tag" || exit 23
if [ -n "${FAKE_CURL_RC:-}" ]; then
  # FAKE_CURL_RC_TAGS limits the late failure to those tags; unset, every fetch fails.
  case " ${FAKE_CURL_RC_TAGS:-$tag} " in *" $tag "*) exit "$FAKE_CURL_RC" ;; esac
fi
if [ -n "${FAKE_PAD:-}" ]; then
  printf '\n' || exit 23
  awk -v n="$FAKE_PAD" 'BEGIN { for (i = 0; i < n; i++) print "decoy" i " md5 sha1 " i }' || exit 23
fi
C
  chmod +x "$SCRATCH/bin/"*
}

# release <tag> <draft> <prerelease>: append one release to the listing fixture.
release() {
  jq --arg t "$1" --argjson d "$2" --argjson p "$3" \
    '. + [{tag_name:$t, html_url:("https://example.test/r/" + $t), draft:$d, prerelease:$p}]' \
    "$FAKE_REL" > "$FAKE_REL.tmp" && mv "$FAKE_REL.tmp" "$FAKE_REL"
}
# sums <tag> <version>: write the release's SHA256SUMS with the real asset
# (<version>) under SHA_GOOD; <version> "-" means no pinned-minor asset at all.
sums() {
  local f="$FAKE_SUMS/$1"
  : > "$f"
  [ "$2" = "-" ] || printf '%s  cpython-%s+%s-%s\n' "$SHA_GOOD" "$2" "$1" "$TRIPLE" >> "$f"
}
# pr <number> <head> <login> <is_bot> <cross-repo>: one open PR in the fake gh's own JSON shape.
pr() {
  jq --argjson n "$1" --arg h "$2" --arg l "$3" --argjson b "$4" --argjson c "$5" \
    '. + [{number:$n, headRefName:$h, author:{login:$l, is_bot:$b}, isCrossRepository:$c}]' \
    "$FAKE_PRS" > "$FAKE_PRS.tmp" && mv "$FAKE_PRS.tmp" "$FAKE_PRS"
}
# sums_add <tag>: append the lines on stdin (decoys) to that release's SHA256SUMS.
sums_add() { cat >> "$FAKE_SUMS/$1"; }

run() {
  RC=0
  OUT="$(env PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" python 2>&1)" || RC=$?
}
out_has() { case "$OUT" in *"$1"*) pass ;; *) fail "$2" "output lacks '$1': $OUT" ;; esac; }
out_lacks() { case "$OUT" in *"$1"*) fail "$2" "output has '$1': $OUT" ;; *) pass ;; esac; }
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
arg() { sed -n "s/^ARG $1=//p" "$R/images/base/Dockerfile"; }
assert_untouched() {
  if cmp -s "$SCRATCH/Dockerfile.orig" "$R/images/base/Dockerfile"; then pass; else fail "the Dockerfile is untouched ($1)" "$(cat "$R/images/base/Dockerfile")"; fi
  if grep -q '^git ' "$FAKE_LOG"; then fail "no git call ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
}
done_case() { rm -rf "$SCRATCH"; }
# run_noslug: as run, with APP_SLUG unset.
run_noslug() {
  RC=0
  OUT="$(env -u APP_SLUG PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" python 2>&1)" || RC=$?
}
count_log() { grep -c -- "$1" "$FAKE_LOG" || true; }
# no_delete: the call log never deletes a branch or ref, and every close names the run's repo.
no_delete() {
  if grep -qE -- '--delete-branch|push .*--delete|push .* :|update-ref -d|branch -[dD]' "$FAKE_LOG"; then fail "no branch or ref deletion ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
  if grep '^gh pr close ' "$FAKE_LOG" | grep -qv -- '--repo o/r'; then fail "every close carries --repo ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
}

# --- a newer patch and build in the newest release: all three ARGs, branch, title, body -------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.15.3
run
assert_rc "a newer patch and build is a bump" 0 "$RC"
assert_eq "PYTHON_VERSION is rewritten" "3.15.3" "$(arg PYTHON_VERSION)"
assert_eq "PYTHON_BUILD is rewritten" "20261117" "$(arg PYTHON_BUILD)"
assert_eq "PYTHON_SHA256 is the real asset's" "$SHA_GOOD" "$(arg PYTHON_SHA256)"
if log_has "git -C $R ls-remote origin refs/heads/bump/python-3.15.3-20261117"; then pass; else fail "ls-remote asks for the exact branch" "$(cat "$FAKE_LOG")"; fi
if log_has "git -C $R switch -c bump/python-3.15.3-20261117"; then pass; else fail "switch -c cuts that exact branch" "$(cat "$FAKE_LOG")"; fi
if log_has "git -C $R commit -m build(images): bump python 3.15.2+20261110 -> 3.15.3+20261117"; then pass; else fail "the commit message carries version and build" "$(cat "$FAKE_LOG")"; fi
if log_has "--title build(images): bump python 3.15.2+20261110 -> 3.15.3+20261117"; then pass; else fail "the PR title carries version and build" "$(cat "$FAKE_LOG")"; fi
if log_has "python 3.15.2+20261110 -> 3.15.3+20261117."; then pass; else fail "the PR body's move line carries version and build" "$(cat "$FAKE_LOG")"; fi
if log_has "Release notes: https://example.test/r/20261117"; then pass; else fail "the PR body cites the release URL" "$(cat "$FAKE_LOG")"; fi
if log_has "Checksum source: https://github.com/astral-sh/python-build-standalone/releases/download/20261117/SHA256SUMS"; then pass; else fail "the PR body cites the SHA256SUMS URL" "$(cat "$FAKE_LOG")"; fi
if log_has "consumers running actions/setup-python at the image's version"; then pass; else fail "the PR body names the consumer pin follow-up" "$(cat "$FAKE_LOG")"; fi
if log_has "#556"; then pass; else fail "the consumer note cites #556"; fi
if log_has "cosign signature was verified"; then fail "the python PR body carries no signature line" "$(cat "$FAKE_LOG")"; else pass; fi
# The listing is one cheap call.
if log_has "gh api repos/astral-sh/python-build-standalone/releases?per_page=5 "; then pass; else fail "the listing call carries per_page=5" "$(cat "$FAKE_LOG")"; fi
if grep -q -- '--paginate' "$FAKE_LOG"; then fail "the listing is never --paginate"; else pass; fi
assert_eq "exactly one release-listing call" "1" "$(grep -c 'repos/astral-sh/python-build-standalone/releases' "$FAKE_LOG")"
done_case

# --- same patch, newer build: a bump with PYTHON_VERSION unchanged -----------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.15.2
run
assert_rc "a same-patch newer build is a bump" 0 "$RC"
assert_eq "PYTHON_VERSION is unchanged" "3.15.2" "$(arg PYTHON_VERSION)"
assert_eq "PYTHON_BUILD is rewritten" "20261117" "$(arg PYTHON_BUILD)"
assert_eq "PYTHON_SHA256 is rewritten" "$SHA_GOOD" "$(arg PYTHON_SHA256)"
if log_has "git -C $R switch -c bump/python-3.15.2-20261117"; then pass; else fail "a new build of the same patch gets its own branch" "$(cat "$FAKE_LOG")"; fi
if log_has "--title build(images): bump python 3.15.2+20261110 -> 3.15.2+20261117"; then pass; else fail "a build-only bump reads as a move in the title" "$(cat "$FAKE_LOG")"; fi
done_case

# --- up to date: exit 0, the message, no git call ------------------------------------------------
setup "$PIN_VER" "$PIN_BUILD"
release "$PIN_BUILD" false false
sums "$PIN_BUILD" "$PIN_VER"
run
assert_rc "up to date exits 0" 0 "$RC"
out_has "python: up to date at 3.15.2+20261110" "the up-to-date message carries version and build"
assert_untouched "up to date"
done_case

# --- the newest release carries only another minor: the pinned minor's asset is chosen ----------
setup "$PIN_VER" "$PIN_BUILD"
release 20261120 false false
sums 20261120 3.16.0
sums_add 20261120 <<< "$SHA_DECOY  cpython-3.14.9+20261120-$TRIPLE"
release 20261117 false false
sums 20261117 3.15.3
run
assert_rc "a release with only other minors is skipped" 0 "$RC"
assert_eq "the pinned minor's asset is chosen, never another minor's" "3.15.3" "$(arg PYTHON_VERSION)"
assert_eq "its build tag is taken" "20261117" "$(arg PYTHON_BUILD)"
done_case

# --- the listing comes back out of tag order: the higher tag is tried first ----------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261112 false false
sums 20261112 3.15.2
release 20261124 false false
sums 20261124 3.15.4
release 20261117 false false
sums 20261117 3.15.3
run
assert_rc "an out-of-order listing resolves" 0 "$RC"
assert_eq "the highest tag wins" "3.15.4" "$(arg PYTHON_VERSION)"
assert_eq "its build is rewritten" "20261124" "$(arg PYTHON_BUILD)"
done_case

# --- a newer prerelease, and separately a newer draft, are never chosen --------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261124 false true
sums 20261124 3.15.9
release 20261117 false false
sums 20261117 3.15.3
run
assert_eq "a newer prerelease is not chosen" "3.15.3" "$(arg PYTHON_VERSION)"
assert_eq "the ordinary release's build is taken (prerelease)" "20261117" "$(arg PYTHON_BUILD)"
if log_has "curl https://github.com/astral-sh/python-build-standalone/releases/download/20261124/"; then fail "a prerelease's SHA256SUMS is never fetched"; else pass; fi
done_case
setup "$PIN_VER" "$PIN_BUILD"
release 20261124 true false
sums 20261124 3.15.9
release 20261117 false false
sums 20261117 3.15.3
run
assert_eq "a newer draft is not chosen" "3.15.3" "$(arg PYTHON_VERSION)"
assert_eq "the ordinary release's build is taken (draft)" "20261117" "$(arg PYTHON_BUILD)"
if log_has "curl https://github.com/astral-sh/python-build-standalone/releases/download/20261124/"; then fail "a draft's SHA256SUMS is never fetched"; else pass; fi
done_case

# --- the only release with the pinned minor is older than the pin's build: downgrade refusal -----
setup "$PIN_VER" "$PIN_BUILD"
release 20261103 false false
sums 20261103 3.15.2
run
assert_rc "a lower build tag is refused" 1 "$RC"
out_has "python: resolved 3.15.2+20261103 is older than the current pin 3.15.2+20261110" "the downgrade message carries version and build"
assert_untouched "lower build"
done_case

# --- pin 3.15.2 at 20261110, newest 20261117 carries only 3.15.1: refused, nothing written -------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.15.1
run
assert_rc "an older patch under a newer build is refused" 1 "$RC"
out_has "python: resolved 3.15.1+20261117 is older than the current pin 3.15.2+20261110" "the downgrade message carries version and build (older patch)"
assert_untouched "older patch under a newer build"
done_case

# --- no listed release carries the pinned minor --------------------------------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.16.0
release 20261110 false false
sums 20261110 -
run
assert_rc "no release carrying the pinned minor fails" 1 "$RC"
out_has "3.15 install_only_stripped" "the error names the pinned minor"
assert_untouched "no asset"
done_case

# --- decoys under another hash: only the real asset's line is taken ------------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.15.3
sums_add 20261117 <<EOF
$SHA_DECOY  cpython-3.15.3+20261117-x86_64-unknown-linux-gnu-install_only.tar.gz
$SHA_DECOY  cpython-3.15.3+20261117-x86_64-unknown-linux-gnu-debug-full.tar.zst
$SHA_DECOY  cpython-3.15.3+20261117-x86_64-unknown-linux-gnu-debug-install_only_stripped.tar.gz
$SHA_DECOY  cpython-3.15.3+20261117-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz
$SHA_DECOY  cpython-3.15.3+20261117-x86_64_v3-unknown-linux-gnu-install_only_stripped.tar.gz
$SHA_DECOY  cpython-3.15.3+20261117-x86_64-unknown-linux-musl-install_only_stripped.tar.gz
$SHA_DECOY  cpython-3.15.3+20261117-$TRIPLE.sig
$SHA_DECOY  cpython-3.15.3rc1+20261117-$TRIPLE
$SHA_DECOY  cpython-3.150.2+20261117-$TRIPLE
$SHA_DECOY  cpython-3x15.2+20261117-$TRIPLE
$SHA_DECOY  cpython-3.15.3+20261116-$TRIPLE
EOF
run
assert_rc "decoys do not break the bump" 0 "$RC"
assert_eq "the written PYTHON_SHA256 is the real asset's" "$SHA_GOOD" "$(arg PYTHON_SHA256)"
done_case
# A release whose only pinned-minor-looking lines are decoys is not chosen.
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 -
sums_add 20261117 <<EOF
$SHA_DECOY  cpython-3.15.3+20261117-x86_64-unknown-linux-gnu-install_only.tar.gz
$SHA_DECOY  cpython-3.15.3rc1+20261117-$TRIPLE
$SHA_DECOY  cpython-3.150.2+20261117-$TRIPLE
$SHA_DECOY  cpython-3x15.2+20261117-$TRIPLE
$SHA_DECOY  cpython-3.15.3+20261117-$TRIPLE.sig
EOF
run
assert_rc "a release with only decoys is not chosen" 1 "$RC"
assert_untouched "only decoys"
done_case
# The expected asset name comes from the real Dockerfile's URL, so a resolver naming another
# asset than the build downloads fails here.
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
printf '%s  %s\n' "$SHA_GOOD" "$(dockerfile_asset 3.15.3 20261117)" > "$FAKE_SUMS/20261117"
run
assert_rc "the asset the real Dockerfile downloads is the one resolved" 0 "$RC"
assert_eq "its hash is written" "$SHA_GOOD" "$(arg PYTHON_SHA256)"
done_case

# --- two lines matching the pinned minor's asset shape ------------------------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.15.3
sums_add 20261117 <<< "$SHA_DECOY  cpython-3.15.4+20261117-$TRIPLE"
run
assert_rc "two matching assets fail" 1 "$RC"
out_has "lists 2 assets" "the error says how many matched"
assert_untouched "duplicate match"
done_case

# --- a non-eight-digit tag is skipped: never in a URL, never chosen ------------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 2026111799 false false
sums 2026111799 3.15.9
release "v20261118" false false
sums "v20261118" 3.15.9
release 20261117 false false
sums 20261117 3.15.3
run
assert_rc "bad tags are skipped and the valid candidate is chosen" 0 "$RC"
assert_eq "the valid candidate's version is taken" "3.15.3" "$(arg PYTHON_VERSION)"
if log_has "2026111799" || log_has "v20261118"; then fail "no curl URL or call contains a skipped tag" "$(cat "$FAKE_LOG")"; else
  # the listing call itself does not name tags, so any hit would be a curl URL or git/gh argument
  pass; fi
out_lacks "2026111799" "no message names a skipped tag"
done_case

# --- a SHA256SUMS line whose hash is not 64 lowercase hex ----------------------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
printf 'ABCDEF  cpython-3.15.3+20261117-%s\n' "$TRIPLE" > "$FAKE_SUMS/20261117"
run
assert_rc "a malformed checksum fails" 1 "$RC"
out_has "not a 64-char lowercase hex sha256" "says the checksum is malformed"
out_lacks "ABCDEF" "the upstream hash text is not echoed"
assert_untouched "bad hash"
done_case

# --- a malformed pin: an error naming the Dockerfile, with no gh, curl or git call ---------------
setup "$PIN_VER" ""
sed -i 's/^ARG PYTHON_BUILD=.*/ARG PYTHON_BUILD=/' "$R/images/base/Dockerfile"
cp "$R/images/base/Dockerfile" "$SCRATCH/Dockerfile.orig"
run
assert_rc "an empty PYTHON_BUILD fails" 1 "$RC"
out_has "$R/images/base/Dockerfile" "the error names the Dockerfile"
assert_eq "no gh, curl or git call (empty build)" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"
done_case
setup "3.15" "$PIN_BUILD"
run
assert_rc "a malformed PYTHON_VERSION fails" 1 "$RC"
out_has "$R/images/base/Dockerfile" "the error names the Dockerfile (version)"
assert_eq "no gh, curl or git call (bad version)" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"
done_case
setup "$PIN_VER" "2026111"
run
assert_rc "a seven-digit PYTHON_BUILD fails" 1 "$RC"
assert_eq "no gh, curl or git call (short build)" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"
done_case

# --- a large SHA256SUMS: the wanted line first, then bulk (pipe-closing readers fail) ------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.15.3
FAKE_PAD=40000 run
assert_rc "a large SHA256SUMS still resolves" 0 "$RC"
assert_eq "the right hash is written" "$SHA_GOOD" "$(arg PYTHON_SHA256)"
done_case

# --- a transfer that fails after the wanted line arrived fails the bump --------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261117 false false
sums 20261117 3.15.3
FAKE_CURL_RC=18 run
assert_rc "a failed SHA256SUMS transfer fails the bump" 1 "$RC"
out_has "could not read the SHA256SUMS of 1 candidate release(s) for 3.15, and no readable release above the pin carries the asset" "the count error names one failure"
assert_untouched "failed transfer"
done_case

# --- an unreadable candidate is skipped: the next one above the pin is taken -----------------------
for mode in missing late; do
  setup "$PIN_VER" "$PIN_BUILD"
  release 20261124 false false
  sums 20261124 3.15.4
  release 20261117 false false
  sums 20261117 3.15.3
  if [ "$mode" = missing ]; then FAKE_CURL_FAIL_TAGS=20261124 run; else FAKE_CURL_RC=18 FAKE_CURL_RC_TAGS=20261124 run; fi
  assert_rc "the newest candidate unreadable ($mode) is skipped" 0 "$RC"
  assert_eq "the next candidate's version is taken ($mode)" "3.15.3" "$(arg PYTHON_VERSION)"
  assert_eq "its build is taken ($mode)" "20261117" "$(arg PYTHON_BUILD)"
  assert_eq "its checksum is taken ($mode)" "$SHA_GOOD" "$(arg PYTHON_SHA256)"
  assert_eq "the warning is printed once ($mode)" "1" "$(printf '%s\n' "$OUT" | grep -cF '::warning::python: could not read the SHA256SUMS of a candidate release for 3.15, trying the next')"
  out_lacks "20261124" "no tag of the failed candidate is in the output ($mode)"
  done_case
done
setup "$PIN_VER" "$PIN_BUILD"
release 20261124 false false
sums 20261124 3.15.4
release 20261120 false false
sums 20261120 3.15.4
release 20261117 false false
sums 20261117 3.15.3
FAKE_CURL_FAIL_TAGS="20261124 20261120" run
assert_rc "two unreadable candidates still resolve the third" 0 "$RC"
assert_eq "two warnings are printed" "2" "$(printf '%s\n' "$OUT" | grep -cF '::warning::python: could not read')"
assert_eq "the readable candidate is taken" "20261117" "$(arg PYTHON_BUILD)"
done_case

# --- the count error ---------------------------------------------------------------------------------
setup "$PIN_VER" "$PIN_BUILD"
release 20261124 false false
sums 20261124 3.15.4
release 20261117 false false
sums 20261117 3.15.3
FAKE_CURL_FAIL_TAGS="20261124 20261117" run
assert_rc "every candidate above the pin unreadable fails" 1 "$RC"
out_has "::error::python: could not read the SHA256SUMS of 2 candidate release(s) for 3.15, and no readable release above the pin carries the asset" "the count error carries the failure count"
assert_untouched "all unreadable"
done_case
setup "$PIN_VER" "$PIN_BUILD"
release 20261124 false false
sums 20261124 3.15.4
release 20261117 false false
sums 20261117 3.16.0
FAKE_CURL_FAIL_TAGS="20261124" run
assert_rc "one unreadable and one readable without the asset fails" 1 "$RC"
out_has "SHA256SUMS of 1 candidate release(s) for 3.15" "the count error counts only the unreadable one"
out_lacks "none of the listed releases" "the no-asset error is not the one printed after a failed fetch"
assert_untouched "one unreadable, one without the asset"
done_case
# The pin's own release is newest and unreadable, an older one is listed: it is never fetched.
setup "$PIN_VER" "$PIN_BUILD"
release "$PIN_BUILD" false false
sums "$PIN_BUILD" "$PIN_VER"
release 20261103 false false
sums 20261103 3.15.2
FAKE_CURL_FAIL_TAGS="$PIN_BUILD" run
assert_rc "the pin's own release unreadable fails" 1 "$RC"
out_has "SHA256SUMS of 1 candidate release(s)" "the count error is printed"
out_lacks "older than the current pin" "no downgrade text"
if log_has "curl https://github.com/astral-sh/python-build-standalone/releases/download/20261103/"; then fail "no candidate below the pin is fetched after a failure"; else pass; fi
assert_untouched "the pin's release unreadable"
done_case
# A newer release is unreadable and the pin's release is readable: the count error, never up to date.
setup "$PIN_VER" "$PIN_BUILD"
release 20261124 false false
sums 20261124 3.15.4
release "$PIN_BUILD" false false
sums "$PIN_BUILD" "$PIN_VER"
FAKE_CURL_FAIL_TAGS="20261124" run
assert_rc "a newer unreadable release with the pin's release readable fails" 1 "$RC"
out_has "SHA256SUMS of 1 candidate release(s)" "the count error is printed"
out_lacks "up to date" "never the up-to-date message"
if log_has "curl https://github.com/astral-sh/python-build-standalone/releases/download/$PIN_BUILD/"; then fail "the pin's own release is not fetched after a failure"; else pass; fi
assert_untouched "newer unreadable, pin readable"
done_case
# Two matching assets in a readable candidate after a failed one: today's error.
setup "$PIN_VER" "$PIN_BUILD"
release 20261124 false false
sums 20261124 3.15.4
release 20261117 false false
sums 20261117 3.15.3
sums_add 20261117 <<< "$SHA_DECOY  cpython-3.15.5+20261117-$TRIPLE"
FAKE_CURL_FAIL_TAGS="20261124" run
assert_rc "two matching assets after a failed fetch fail" 1 "$RC"
out_has "lists 2 assets" "today's two-assets error"
assert_untouched "duplicate after a failed fetch"
done_case

# --- supersede: older App-authored python PRs are closed after the new PR is created -------------------
NEWB=20261117
older_setup() { # a new 3.15.3+20261117 bump, ready to resolve
  setup "$PIN_VER" "$PIN_BUILD"
  release $NEWB false false
  sums $NEWB 3.15.3
}
older_setup
pr 41 bump/python-3.15.2-20261112 app/app true false
run
assert_rc "an older App python PR does not stop the bump" 0 "$RC"
if log_has "gh pr close 41 --repo o/r --comment Superseded by bump/python-3.15.3-20261117."; then pass; else fail "the older PR is closed with a comment naming the new branch" "$(cat "$FAKE_LOG")"; fi
assert_eq "exactly one close" "1" "$(count_log '^gh pr close ')"
create_line="$(grep -n '^gh pr create' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
close_line="$(grep -n '^gh pr close' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
if [ -n "$create_line" ] && [ -n "$close_line" ] && [ "$create_line" -lt "$close_line" ]; then pass; else fail "the create call comes before the close" "$(cat "$FAKE_LOG")"; fi
if log_has "gh pr list --repo o/r --state open --limit 500 --json number,headRefName,author,isCrossRepository"; then pass; else fail "the listing carries the run's repo and the limit" "$(cat "$FAKE_LOG")"; fi
no_delete "one older PR"
done_case
older_setup
pr 41 bump/python-3.15.2-20261112 app/app true false
pr 42 bump/python-3.15.2-20261103 app/app true false
run
assert_rc "two older PRs: the bump succeeds" 0 "$RC"
assert_eq "both older PRs are closed" "2" "$(count_log '^gh pr close ')"
if log_has "gh pr close 41 --repo o/r" && log_has "gh pr close 42 --repo o/r"; then pass; else fail "each number is closed" "$(cat "$FAKE_LOG")"; fi
no_delete "two older PRs"
done_case

# A not-older PR blocks: nothing is cut, created or closed.
for case_ in "3.15.2-20261124" "3.15.4-20261112" "3.15.2-20261117" "3.15.3-20261117" "3.15.4-20261124"; do
  older_setup
  pr 41 bump/python-3.15.2-20261103 app/app true false
  pr 50 "bump/python-$case_" app/app true false
  run
  assert_rc "a not-older PR ($case_) exits 0" 0 "$RC"
  assert_eq "the not-older message names the PR ($case_)" "python: open PR #50 (bump/python-$case_) is not older than 3.15.3+20261117, nothing to do" "$OUT"
  if grep -qE '^git |^gh pr (create|close)' "$FAKE_LOG"; then fail "no git, create or close call ($case_)" "$(cat "$FAKE_LOG")"; else pass; fi
  assert_untouched "not older ($case_)"
  done_case
done

# Records that fail the filter are neither closed nor blocking, and never appear in the output.
older_setup
pr 61 bump/python-3.15.2-20261124 app true false
pr 62 bump/python-3.15.2-20261124 other/app true false
pr 63 bump/python-3.15.2-20261124 app/app false false
pr 64 bump/python-3.15.2-20261124 app/app true true
pr 65 bump/python-3.15.2-20261124 app/app true false
pr 66 bump/python-3.16.2-20261124 app/app true false
pr 67 bump/python-3x15.2-20261124 app/app true false
pr 68 bump/python-3.15.x-20261124 app/app true false
pr 69 bump/python-3.15.2-2026112 app/app true false
pr 70 xbump/python-3.15.2-20261124 app/app true false
pr 71 bump/python-3.15.2-20261124x app/app true false
pr 72 bump/python-3.15.2-20261124-1 app/app true false
pr 73 bump/python-3.15.2-202611240 app/app true false
jq '(.[] | select(.number == 65) | .number) = 0' "$FAKE_PRS" > "$FAKE_PRS.tmp" && mv "$FAKE_PRS.tmp" "$FAKE_PRS"
pr 80 bump/python-3.15.2-20261112 app/app true false
run
assert_rc "look-alike and foreign records never block" 0 "$RC"
assert_eq "only the real older PR is closed" "1" "$(count_log '^gh pr close ')"
if log_has "gh pr close 80 --repo o/r"; then pass; else fail "the real older PR is closed" "$(cat "$FAKE_LOG")"; fi
for n in 61 62 63 64 66 67 68 69 70 71 72 73; do out_lacks "#$n" "PR $n is not named in the output"; done
out_lacks "20261124" "no filtered head appears in the output"
no_delete "filter"
done_case

# --- the listing -----------------------------------------------------------------------------------------
older_setup
pr 41 bump/python-3.15.2-20261112 app/app true false
FAKE_PRLIST_FAIL=1 run
assert_rc "a failing listing fails the bump" 1 "$RC"
out_has "::error::python: could not list the open pull requests" "the listing error"
if grep -q '^git ' "$FAKE_LOG"; then fail "no git call after a failed listing" "$(cat "$FAKE_LOG")"; else pass; fi
done_case
older_setup
jq -n '[range(1; 501) | {number: ., headRefName: "feature/x", author: {login: "someone", is_bot: false}, isCrossRepository: true}]' > "$FAKE_PRS"
run
assert_rc "a listing at the limit fails the bump" 1 "$RC"
out_has "::error::python: the open pull request listing may be truncated" "the truncation error"
if grep -q '^git ' "$FAKE_LOG"; then fail "no git call after a truncated listing" "$(cat "$FAKE_LOG")"; else pass; fi
done_case
older_setup
jq -n '[range(1; 500) | {number: ., headRefName: "feature/x", author: {login: "someone", is_bot: false}, isCrossRepository: true}]' > "$FAKE_PRS"
run
assert_rc "a listing just under the limit is used" 0 "$RC"
done_case
older_setup
pr 41 bump/python-3.15.2-20261112 app/app true false
run_noslug
assert_rc "APP_SLUG unset fails a python run that reaches the listing" 1 "$RC"
out_has "APP_SLUG must be set" "the unset APP_SLUG is named"
if log_has "gh pr list --repo o/r --head"; then pass; else fail "the run reached the open-PR check before stopping" "$(cat "$FAKE_LOG")"; fi
assert_eq "no supersede listing call without APP_SLUG" "0" "$(count_log '^gh pr list .*--limit')"
if grep -q '^git ' "$FAKE_LOG"; then fail "no git call without APP_SLUG" "$(cat "$FAKE_LOG")"; else pass; fi
done_case

# --- the create and the closes ---------------------------------------------------------------------------
older_setup
pr 41 bump/python-3.15.2-20261112 app/app true false
FAKE_CREATE_FAIL=1 run
if [ "$RC" -ne 0 ]; then pass; else fail "a failed create fails the run" "$OUT"; fi
if log_has "gh pr create"; then pass; else fail "the create was attempted" "$(cat "$FAKE_LOG")"; fi
assert_eq "no close after a failed create" "0" "$(count_log '^gh pr close ')"
done_case
older_setup
pr 41 bump/python-3.15.2-20261112 app/app true false
pr 42 bump/python-3.15.2-20261103 app/app true false
FAKE_CLOSE_FAIL=41 run
assert_rc "a failed close fails the run after the loop" 1 "$RC"
assert_eq "both closes are attempted" "2" "$(count_log '^gh pr close ')"
out_has "::error::python: could not close superseded PR #41" "the error names the failed number"
out_lacks "superseded PR #42" "the second close's number is not reported as failed"
create_line="$(grep -n '^gh pr create' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
first_close="$(grep -n '^gh pr close' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
if [ -n "$create_line" ] && [ -n "$first_close" ] && [ "$create_line" -lt "$first_close" ]; then pass; else fail "the create call comes before both closes" "$(cat "$FAKE_LOG")"; fi
no_delete "failed first close"
done_case

summary
