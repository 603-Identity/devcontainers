#!/usr/bin/env bash
# Tests for .github/scripts/bump-binaries.sh, the betterleaks branch (#190) and the version
# ordering all tools now share. A scratch tree holds a copy of the script and a Dockerfile;
# fake `gh`, `curl` and `cosign` stand in for the network; cosign is reached only through COSIGN_BIN
# and COSIGN_OUTCOME, as in the workflow. Every case but the PR-body one stops before any commit:
# the fake `git` answers ls-remote with the branch's own ref (FAKE_DECLINE=1), so a bump that would
# go ahead ends declined ("already exists on origin"); that one case sets FAKE_DECLINE= to reach
# `gh pr create` through the logging fake `git` (as bump-python-test.sh does). Offline; needs bash and awk.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/bump-binaries.sh"
suite "bump-binaries (betterleaks)"

SHA_OK=$(printf 'a%.0s' $(seq 1 64))
SHA_OLD=$(printf 'b%.0s' $(seq 1 64))

setup() { # setup <betterleaks version in the Dockerfile>
  SCRATCH="$(mktemp -d)"
  R="$SCRATCH/root"
  mkdir -p "$R/.github/scripts" "$R/images/base" "$SCRATCH/bin"
  cp "$SCRIPT" "$R/.github/scripts/"
  printf 'ARG GH_VERSION=2.102.0\nARG GH_SHA256=%s\nARG BETTERLEAKS_VERSION=%s\nARG BETTERLEAKS_SHA256=%s\n' \
    "$SHA_OLD" "$1" "$SHA_OLD" > "$R/images/base/Dockerfile"
  : > "$SCRATCH/calls.log"
  export FAKE_LOG="$SCRATCH/calls.log"
  export FAKE_DECLINE=1 FAKE_COSIGN_RC=0
  unset FAKE_RELEASES FAKE_CHECKSUMS
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
case "$1 $2" in
  "api repos/betterleaks/betterleaks/releases") printf '%b' "${FAKE_RELEASES:-}" ;;
  "api repos/cli/cli/releases/latest") printf 'v%s\thttps://example.test/gh\n' "${FAKE_GH_LATEST:-2.103.0}" ;;
  "pr list") ;;
  "pr create") ;;
  "auth setup-git") ;;
  *) echo "unexpected gh $*" >&2; exit 9 ;;
esac
G
  cat > "$SCRATCH/bin/curl" <<'C'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
echo "curl $url" >> "$FAKE_LOG"
case "$url" in
  *gh_*_checksums.txt) printf '%b' "${FAKE_CHECKSUMS:-}" ;;
  *checksums.txt.sigstore.json) printf '{}' > "$out" ;;
  *checksums.txt) printf '%b' "${FAKE_CHECKSUMS:-}" > "$out" ;;
  *) echo "unexpected curl $url" >&2; exit 9 ;;
esac
C
  cat > "$SCRATCH/bin/cosign" <<'S'
#!/usr/bin/env bash
echo "cosign $*" >> "$FAKE_LOG"
exit "${FAKE_COSIGN_RC:-0}"
S
  cat > "$SCRATCH/bin/git" <<'GIT'
#!/usr/bin/env bash
echo "git $*" >> "$FAKE_LOG"
case "$*" in *ls-remote*) [ -z "${FAKE_DECLINE:-}" ] || printf '%040d\t%s\n' 1 "${!#}" ;; esac
exit 0
GIT
  chmod +x "$SCRATCH/bin/"*
}

run() { # run <tool> -> RC, OUT (stdout+stderr)
  RC=0
  OUT="$(env PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    COSIGN_OUTCOME="${FAKE_COSIGN_OUTCOME-success}" COSIGN_BIN="${FAKE_COSIGN_BIN:-$SCRATCH/bin/cosign}" \
    bash "$R/.github/scripts/bump-binaries.sh" "$1" 2>&1)" || RC=$?
}
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
out_has() { case "$OUT" in *"$1"*) pass ;; *) fail "$2" "output lacks '$1': $OUT" ;; esac; }
checksums() { # checksums <version> <sha>
  FAKE_CHECKSUMS="$2  betterleaks_$1_linux_x64.tar.gz\n"
  export FAKE_CHECKSUMS
}
releases() { FAKE_RELEASES="$1"; export FAKE_RELEASES; }

# --- a newer release candidate, verified, goes ahead ------------------------------------
setup 2.0.0-rc.1
releases 'v2.0.0-rc.2\thttps://example.test/rc2\nv2.0.0-rc.1\thttps://example.test/rc1\n'
checksums 2.0.0-rc.2 "$SHA_OK"
run betterleaks
assert_rc "newer rc is accepted" 0 "$RC"
out_has "already exists on origin" "newer rc reaches the PR step"
# The bundle lives in a mktemp dir, so match the stable parts of the cosign call.
want="--certificate-identity https://github.com/betterleaks/betterleaks/.github/workflows/release.yml@refs/tags/v2.0.0-rc.2 --certificate-oidc-issuer https://token.actions.githubusercontent.com"
if grep -F 'cosign verify-blob --bundle ' "$FAKE_LOG" | grep -qF -- "$want"; then pass; else fail "cosign gets the exact tag identity and the Actions issuer" "$(cat "$FAKE_LOG")"; fi
if log_has "curl https://github.com/betterleaks/betterleaks/releases/download/v2.0.0-rc.2/checksums.txt.sigstore.json"; then pass; else fail "the bundle is fetched for the chosen tag"; fi
rm -rf "$SCRATCH"

# --- a bump that reaches `gh pr create` carries the signature line ----------------------
setup 2.0.0-rc.1
releases 'v2.0.0-rc.2\thttps://example.test/rc2\n'
checksums 2.0.0-rc.2 "$SHA_OK"
FAKE_DECLINE='' run betterleaks
assert_rc "a verified newer rc opens its PR" 0 "$RC"
if log_has "verified at resolution time against the signer identity \`https://github.com/betterleaks/betterleaks/.github/workflows/release.yml@refs/tags/v2.0.0-rc.2\`"; then pass; else fail "the PR body's signature line names the tag identity" "$(cat "$FAKE_LOG")"; fi
rm -rf "$SCRATCH"

# --- verification failure refuses, and goes no further -----------------------------------
setup 2.0.0-rc.1
releases 'v2.0.0-rc.2\thttps://example.test/rc2\n'
checksums 2.0.0-rc.2 "$SHA_OK"
FAKE_COSIGN_RC=1 run betterleaks
assert_rc "a failed signature check fails the bump" 1 "$RC"
out_has "did not verify" "says the signature did not verify"
if log_has "gh pr list"; then fail "no PR step after a failed signature check"; else pass; fi
if log_has "git -C $R commit"; then fail "no commit after a failed signature check"; else pass; fi
rm -rf "$SCRATCH"

# --- no usable COSIGN_BIN or a non-success install is an error, never a skip, and a cosign on PATH is not used
setup 2.0.0-rc.1
releases 'v2.0.0-rc.2\thttps://example.test/rc2\n'
checksums 2.0.0-rc.2 "$SHA_OK"
FAKE_COSIGN_BIN="$SCRATCH/bin/missing-cosign" run betterleaks
assert_rc "a COSIGN_BIN that is not a file fails" 1 "$RC"
out_has "cosign is required" "says cosign is required"
if log_has "cosign "; then fail "a cosign on PATH is not called when COSIGN_BIN is unusable" "$(cat "$FAKE_LOG")"; else pass; fi
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
releases 'v2.0.0-rc.2\thttps://example.test/rc2\n'
checksums 2.0.0-rc.2 "$SHA_OK"
chmod 0644 "$SCRATCH/bin/cosign"
run betterleaks
assert_rc "a COSIGN_BIN that is not executable fails" 1 "$RC"
out_has "cosign is required" "says cosign is required for a non-executable COSIGN_BIN"
rm -rf "$SCRATCH"

for outcome in failure skipped cancelled ""; do
  setup 2.0.0-rc.1
  releases 'v2.0.0-rc.2\thttps://example.test/rc2\n'
  checksums 2.0.0-rc.2 "$SHA_OK"
  FAKE_COSIGN_OUTCOME="$outcome" run betterleaks
  assert_rc "COSIGN_OUTCOME '$outcome' fails" 1 "$RC"
  out_has "failed at step: cosign" "the failed leg names the cosign step ('$outcome')"
  if log_has "cosign "; then fail "no cosign call for COSIGN_OUTCOME '$outcome'" "$(cat "$FAKE_LOG")"; else pass; fi
  rm -rf "$SCRATCH"
done

# --- ordering ----------------------------------------------------------------------------
setup 2.0.0-rc.1
releases 'v2.0.0-rc.1\thttps://example.test/rc1\n'
checksums 2.0.0-rc.1 "$SHA_OK"
run betterleaks
assert_rc "same version" 0 "$RC"
out_has "up to date" "same version is up to date"
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
releases 'v1.9.1\thttps://example.test/191\nv2.0.0-rc.1\thttps://example.test/rc1\nv1.9.0\thttps://example.test/190\n'
checksums 2.0.0-rc.1 "$SHA_OK"
run betterleaks
assert_rc "a later-published 1.x patch does not outrank 2.0.0-rc.1" 0 "$RC"
out_has "up to date" "the highest version wins, not the newest upload"
rm -rf "$SCRATCH"

setup 2.0.0-rc.2
releases 'v2.0.0-rc.1\thttps://example.test/rc1\n'
checksums 2.0.0-rc.1 "$SHA_OK"
run betterleaks
assert_rc "rc.1 below the pinned rc.2 is a downgrade" 1 "$RC"
out_has "downgrade" "refuses the downgrade"
rm -rf "$SCRATCH"

# In rc mode the error names the pin's own X.Y.Z rule: a later line's rc matches tag_re but is skipped (#377).
setup 2.0.0-rc.1
releases 'v2.1.0-rc.1\thttps://example.test/rc21\n'
run betterleaks
assert_rc "a later line's rc alone leaves no candidate" 1 "$RC"
out_has "no release matching" "rc mode still says no release matching"
out_has "2.0.0-rc.N" "rc mode names the pin's own X.Y.Z rc rule (#377)"
rm -rf "$SCRATCH"

setup 2.0.0
releases 'v2.0.0-rc.3\thttps://example.test/rc3\n'
checksums 2.0.0-rc.3 "$SHA_OK"
run betterleaks
assert_rc "a GA pin with only an rc listed fails closed" 1 "$RC"
out_has "no release matching" "an rc is not a candidate once the pin is GA (#208)"
case "$OUT" in *"-rc.N"*) fail "the GA message does not carry the rc rule" "$OUT" ;; *) pass ;; esac
rm -rf "$SCRATCH"

setup 2.0.0-rc.9
releases 'v2.0.0\thttps://example.test/ga\nv2.0.0-rc.9\thttps://example.test/rc9\n'
checksums 2.0.0 "$SHA_OK"
run betterleaks
assert_rc "GA 2.0.0 outranks rc.9" 0 "$RC"
out_has "already exists on origin" "rc to GA reaches the PR step"
rm -rf "$SCRATCH"

setup 2.0.0-rc.9
releases 'v2.0.0-rc.10\thttps://example.test/rc10\nv2.0.0-rc.9\thttps://example.test/rc9\n'
checksums 2.0.0-rc.10 "$SHA_OK"
run betterleaks
assert_rc "rc.10 outranks rc.9 numerically" 0 "$RC"
out_has "already exists on origin" "rc.10 is newer than rc.9"
rm -rf "$SCRATCH"

# --- prereleases only while the pin is itself an rc (#208) --------------------------------
setup 2.0.0
releases 'v2.1.0-rc.1\thttps://example.test/rc\nv2.0.0\thttps://example.test/ga\n'
checksums 2.0.0 "$SHA_OK"
run betterleaks
assert_rc "a GA pin ignores a newer rc" 0 "$RC"
out_has "up to date" "pin 2.0.0 with only v2.1.0-rc.1 newer is up to date"
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
releases 'v2.1.0-rc.1\thttps://example.test/rc21\nv2.0.0\thttps://example.test/ga\nv2.0.0-rc.1\thttps://example.test/rc1\n'
checksums 2.0.0 "$SHA_OK"
run betterleaks
assert_rc "an rc pin reaches GA past a later line's rc (#304)" 0 "$RC"
out_has "already exists on origin" "the bump goes ahead"
if log_has "curl https://github.com/betterleaks/betterleaks/releases/download/v2.0.0/checksums.txt"; then pass; else fail "the checksum is taken from v2.0.0, not v2.1.0-rc.1" "$(cat "$FAKE_LOG")"; fi
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
releases 'v2.1.0-rc.1\thttps://example.test/rc21\nv2.0.0-rc.1\thttps://example.test/rc1\n'
checksums 2.0.0-rc.1 "$SHA_OK"
run betterleaks
assert_rc "a later line's rc alone is ignored (#304)" 0 "$RC"
out_has "up to date" "the pin stays on its own rc"
rm -rf "$SCRATCH"

setup 2.0.0
releases 'v2.1.0\thttps://example.test/210\nv2.1.0-rc.1\thttps://example.test/rc\nv2.0.0\thttps://example.test/ga\n'
checksums 2.1.0 "$SHA_OK"
run betterleaks
assert_rc "a GA pin still takes a newer GA release" 0 "$RC"
out_has "already exists on origin" "pin 2.0.0 reaches the PR step for v2.1.0"
rm -rf "$SCRATCH"

# --- hostile or malformed upstream data --------------------------------------------------
setup 2.0.0-rc.1
releases 'v2.0.0-rc.2; touch pwned\thttps://example.test/x\nv3.0.0-beta\thttps://example.test/y\nlatest\thttps://example.test/z\nv2.0.0-rc.1\thttps://example.test/rc1\n'
checksums 2.0.0-rc.1 "$SHA_OK"
run betterleaks
assert_rc "tags that are not vX.Y.Z[-rc.N] are ignored" 0 "$RC"
out_has "up to date" "only the well-formed tag is considered"
if [ -e "$R/pwned" ] || [ -e pwned ]; then fail "a crafted tag executes nothing"; else pass; fi
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
releases ''
run betterleaks
assert_rc "no usable release" 1 "$RC"
out_has "no release matching" "says there is no usable release"
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
releases 'v2.0.0-rc.2\thttps://example.test/rc2\n'
FAKE_CHECKSUMS="$SHA_OK  some_other_asset.tar.gz\n"; export FAKE_CHECKSUMS
run betterleaks
assert_rc "no checksum line for the linux_x64 tarball" 1 "$RC"
out_has "could not resolve" "fails closed on a missing checksum"
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
releases 'v2.0.0-rc.2\thttps://example.test/rc2\n'
FAKE_CHECKSUMS="NOTHEX  betterleaks_2.0.0-rc.2_linux_x64.tar.gz\n"; export FAKE_CHECKSUMS
run betterleaks
assert_rc "a malformed checksum" 1 "$RC"
out_has "64-char lowercase hex" "rejects a malformed checksum"
rm -rf "$SCRATCH"

# --- the other tools still order versions numerically ------------------------------------
setup 2.0.0-rc.1
export FAKE_GH_LATEST=2.103.0
FAKE_CHECKSUMS="$SHA_OK  gh_2.103.0_linux_amd64.tar.gz\n"; export FAKE_CHECKSUMS
run gh
assert_rc "gh 2.102.0 -> 2.103.0" 0 "$RC"
out_has "already exists on origin" "a plain bump still reaches the PR step"
rm -rf "$SCRATCH"

setup 2.0.0-rc.1
export FAKE_GH_LATEST=2.99.0
FAKE_CHECKSUMS="$SHA_OK  gh_2.99.0_linux_amd64.tar.gz\n"; export FAKE_CHECKSUMS
run gh
assert_rc "gh 2.99.0 is older than 2.102.0 (numeric, not lexical)" 1 "$RC"
out_has "downgrade" "refuses the downgrade"
rm -rf "$SCRATCH"
unset FAKE_GH_LATEST

summary
