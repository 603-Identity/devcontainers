#!/usr/bin/env bash
# Tests the `python` resolver of bump-binaries.sh (#561): it stays on the Dockerfile's pinned
# major.minor, lists python-build-standalone releases in ONE per_page=5 call, picks the asset by its
# exact name from the newest eligible release, and rewrites PYTHON_VERSION, PYTHON_BUILD and
# PYTHON_SHA256 together. Fake `gh`, `curl` and `git` stand in for the network and log every call;
# the fake gh applies the --jq expression it was given with the real jq, so the draft/prerelease
# selection runs as written. Offline; needs bash, awk and jq.
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
  export FAKE_LOG="$SCRATCH/calls.log" FAKE_REL="$SCRATCH/releases.json" FAKE_SUMS="$SCRATCH/sums"
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
case "$1 $2" in
  "api repos/astral-sh/python-build-standalone/releases?per_page=5")
    jq=""
    while [ $# -gt 0 ]; do [ "$1" = --jq ] && jq="$2"; shift; done
    jq -r "$jq" "$FAKE_REL" ;;
  "pr list") echo 0 ;;
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
# Like real curl, fail with 23 when a write fails (SIGPIPE ignored so the failed write is seen).
trap '' PIPE
cat "$FAKE_SUMS/$tag" || exit 23
[ -z "${FAKE_CURL_RC:-}" ] || exit "$FAKE_CURL_RC"
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
assert_untouched "failed transfer"
done_case

summary
