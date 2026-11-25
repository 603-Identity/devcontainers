#!/usr/bin/env bash
# Tests for .github/scripts/bump-binaries.sh, the tofu branch (#717): the SHA256SUMS file is taken
# only after cosign verifies its keyless signature against the pinned identity and the tag's commit.
# A scratch tree holds a copy of the script and a tofu Dockerfile; fake `gh`, `curl`, `cosign` and
# `git` log their calls. Most cases stop at "PR already open" (the fake `gh pr list` reports an
# open PR); the body case sets FAKE_OPEN=0 and reaches `gh pr create` through the logging fake
# `git`, as bump-python-test.sh does. Offline; needs bash and awk.
# shellcheck disable=SC2016  # the mutant-script sed patterns and greps hold literal $ signs
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/bump-binaries.sh"
suite "bump-binaries (tofu)"

SHA_OK=$(printf 'a%.0s' $(seq 1 64))
SHA_OLD=$(printf 'b%.0s' $(seq 1 64))
SHA_DECOY=$(printf 'c%.0s' $(seq 1 64))
COMMIT=0123456789abcdef0123456789abcdef01234567
BASE=https://github.com/opentofu/opentofu/releases/download

setup() { # setup <tofu version in the Dockerfile>
  SCRATCH="$(mktemp -d)"
  R="$SCRATCH/root"
  mkdir -p "$R/.github/scripts" "$R/images/tofu" "$SCRATCH/bin"
  cp "$SCRIPT" "$R/.github/scripts/"
  printf 'ARG TOFU_VERSION=%s\nARG TOFU_SHA256=%s\nARG TFLINT_VERSION=0.1.0\nARG TFLINT_SHA256=%s\n' \
    "$1" "$SHA_OLD" "$SHA_OLD" > "$R/images/tofu/Dockerfile"
  cp "$R/images/tofu/Dockerfile" "$SCRATCH/Dockerfile.orig"
  : > "$SCRATCH/calls.log"
  export FAKE_LOG="$SCRATCH/calls.log"
  export FAKE_OPEN=1 FAKE_COSIGN_RC=0 FAKE_TAG="v1.14.0" FAKE_COMMIT="$COMMIT"
  unset FAKE_COMMIT_RC FAKE_CURL_FAIL
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
case "$1 $2" in
  "api repos/opentofu/opentofu/releases/latest") printf '%s\thttps://example.test/tofu\n' "$FAKE_TAG" ;;
  "api repos/opentofu/opentofu/commits/"*) [ -z "${FAKE_COMMIT_RC:-}" ] || exit "$FAKE_COMMIT_RC"; printf '%s\n' "$FAKE_COMMIT" ;;
  "pr list") echo "$FAKE_OPEN" ;;
  "pr create") ;;
  "auth setup-git") ;;
  *) echo "unexpected gh $*" >&2; exit 9 ;;
esac
G
  cat > "$SCRATCH/bin/git" <<'G'
#!/usr/bin/env bash
echo "git $*" >> "$FAKE_LOG"
exit 0
G
  # The SHA256SUMS body lists decoys around the real line; a fetch without -o gets a different hash.
  cat > "$SCRATCH/bin/curl" <<'C'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
echo "curl $url${out:+ -o}" >> "$FAKE_LOG"
[ -z "$out" ] || echo "wrote $url $out" >> "$FAKE_LOG"
case "$url" in *.sig) k=sig ;; *.pem) k=pem ;; *) k=sums ;; esac
case " ${FAKE_CURL_FAIL:-} " in *" $k "*) exit 22 ;; esac
case "$url" in
  *_SHA256SUMS)
    ver="${url##*/tofu_}"; ver="${ver%_SHA256SUMS}"
    if [ -n "$out" ]; then
      printf '%s  tofu_%s_linux_amd64.zip.sig\n%s  tofu_%s_linux_amd64.zip\n%s  tofu_%s_linux_arm64.zip\n' \
        "$FAKE_DECOY" "$ver" "$FAKE_GOOD" "$ver" "$FAKE_DECOY" "$ver" > "$out"
    else
      printf '%s  tofu_%s_linux_amd64.zip\n' "$FAKE_OTHER" "$ver"
    fi ;;
  *_SHA256SUMS.sig) printf 'sig' > "$out" ;;
  *_SHA256SUMS.pem) printf 'pem' > "$out" ;;
  *) echo "unexpected curl $url" >&2; exit 9 ;;
esac
C
  cat > "$SCRATCH/bin/cosign" <<'S'
#!/usr/bin/env bash
echo "cosign $*" >> "$FAKE_LOG"
exit "${FAKE_COSIGN_RC:-0}"
S
  chmod +x "$SCRATCH/bin/"*
  export FAKE_GOOD="$SHA_OK" FAKE_DECOY="$SHA_DECOY" FAKE_OTHER="$SHA_OLD"
}

run() { # run -> RC, OUT (stdout+stderr)
  RC=0
  OUT="$(env PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" tofu 2>&1)" || RC=$?
}
# sums_written: every path curl wrote the chosen tag's SHA256SUMS to (one line per download).
sums_written() { sed -n "s|^wrote $BASE/v1.14.0/tofu_1.14.0_SHA256SUMS ||p" "$FAKE_LOG"; }
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
log_count() { grep -cE -- "$1" "$FAKE_LOG" || true; }
out_has() { case "$OUT" in *"$1"*) pass ;; *) fail "$2" "output lacks '$1': $OUT" ;; esac; }
arg() { sed -n "s/^ARG $1=//p" "$R/images/tofu/Dockerfile"; }
# refused <case>: nothing after the refusal ran, and the Dockerfile is untouched.
refused() {
  if grep -qE '^(gh pr |git )' "$FAKE_LOG"; then fail "no gh pr or git call ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
  if cmp -s "$SCRATCH/Dockerfile.orig" "$R/images/tofu/Dockerfile"; then pass; else fail "the Dockerfile is untouched ($1)"; fi
}

# --- a newer release whose signature verifies goes ahead --------------------------------------
setup 1.13.10
run
assert_rc "a verified newer release is accepted" 0 "$RC"
out_has "PR already open" "a verified release reaches the PR step"
want="--certificate-identity https://github.com/opentofu/opentofu/.github/workflows/release.yml@refs/heads/v1.14 --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-github-workflow-repository opentofu/opentofu --certificate-github-workflow-sha $COMMIT"
if grep -F 'cosign verify-blob ' "$FAKE_LOG" | grep -qF -- "$want"; then pass; else fail "cosign gets the major.minor identity, issuer, repository and commit" "$(cat "$FAKE_LOG")"; fi
for ext in "" .sig .pem; do
  if log_has "curl $BASE/v1.14.0/tofu_1.14.0_SHA256SUMS$ext -o"; then pass; else fail "SHA256SUMS$ext is fetched for the chosen tag with -o" "$(cat "$FAKE_LOG")"; fi
done
assert_eq "the SHA256SUMS URL is fetched exactly once" "1" "$(log_count "curl $BASE/v1.14.0/tofu_1.14.0_SHA256SUMS( |$)")"
if log_has "gh api repos/opentofu/opentofu/commits/v1.14.0 --jq .sha"; then pass; else fail "the tag's commit is resolved" "$(cat "$FAKE_LOG")"; fi
rm -rf "$SCRATCH"

# --- the checksum comes from the verified file -------------------------------------------------
setup 1.13.10
FAKE_OPEN=0 run
assert_rc "the bump goes ahead" 0 "$RC"
assert_eq "TOFU_SHA256 is the line of the verified, downloaded file" "$SHA_OK" "$(arg TOFU_SHA256)"
assert_eq "TOFU_VERSION is rewritten" "1.14.0" "$(arg TOFU_VERSION)"
assert_eq "TFLINT_SHA256 is untouched" "$SHA_OLD" "$(arg TFLINT_SHA256)"
cos_file="$(grep -F 'cosign verify-blob ' "$FAKE_LOG" | awk '{print $NF}')"
assert_eq "the file cosign checked is named SHA256SUMS" "SHA256SUMS" "$(basename "$cos_file")"
assert_eq "cosign's blob is the exact path curl wrote SHA256SUMS to" "$(sums_written)" "$cos_file"
# the signature line in the PR body names the identity and the commit
if log_has "signer identity \`https://github.com/opentofu/opentofu/.github/workflows/release.yml@refs/heads/v1.14\` and the tag's commit \`$COMMIT\`"; then pass; else fail "the PR body's signature line names the identity and the commit" "$(cat "$FAKE_LOG")"; fi
rm -rf "$SCRATCH"

# --- a script that verifies one copy and parses another fails the same check ------------------
setup 1.13.10
M="$R/.github/scripts/bump-binaries.sh"
sed -i '/curl -fsSL "\$base" -o "\$dir\/SHA256SUMS"$/a\  curl -fsSL "$base" -o "$dir/parsed"' "$M"
sed -i 's|\(awk -v f="tofu_\${ver}_linux_amd64.zip" .*\) "\$dir/SHA256SUMS")"|\1 "$dir/parsed")"|' "$M"
if grep -qF '"$dir/parsed")"' "$M" && grep -qF -- '-o "$dir/parsed"' "$M"; then pass; else fail "the mutant script was built" "$(grep -n 'dir/' "$M")"; fi
FAKE_OPEN=0 run
mut_cos="$(grep -F 'cosign verify-blob ' "$FAKE_LOG" | awk '{print $NF}')"
if [ "$(sums_written)" = "$mut_cos" ]; then fail "the same-path check flags a script that parses a second copy" "$(cat "$FAKE_LOG")"; else pass; fi
rm -rf "$SCRATCH"

# --- a cosign failure refuses ----------------------------------------------------------------
setup 1.13.10
FAKE_COSIGN_RC=1 run
assert_rc "a failed signature check fails the bump" 1 "$RC"
out_has "did not verify" "says the signature did not verify"
refused "cosign failure"
rm -rf "$SCRATCH"

# --- no cosign on PATH ------------------------------------------------------------------------
setup 1.13.10
rm "$SCRATCH/bin/cosign"
run
assert_rc "cosign missing fails" 1 "$RC"
out_has "cosign is required" "says cosign is required"
refused "cosign missing"
rm -rf "$SCRATCH"

# --- a malformed commit lookup ----------------------------------------------------------------
for bad in "" "0123456789ABCDEF0123456789ABCDEF01234567" "0123456789abcdef" "$COMMIT; touch pwned"; do
  setup 1.13.10
  FAKE_COMMIT="$bad" run
  assert_rc "a malformed commit ('$bad') fails" 1 "$RC"
  out_has "40-char lowercase hex" "says the commit is malformed"
  if log_has "cosign "; then fail "no cosign call after a malformed commit" "$(cat "$FAKE_LOG")"; else pass; fi
  refused "malformed commit"
  rm -rf "$SCRATCH"
done

setup 1.13.10
FAKE_COMMIT_RC=1 run
assert_rc "a failed commit lookup fails" 1 "$RC"
if log_has "cosign "; then fail "no cosign call after a failed commit lookup" "$(cat "$FAKE_LOG")"; else pass; fi
refused "failed commit lookup"
rm -rf "$SCRATCH"

# --- a tag that is not exactly vX.Y.Z -----------------------------------------------------------
for bad in "v1.14.0-rc.1" "v1.14" "1.14.0" "v1.14.0;x" "v01.14.0x"; do
  setup 1.13.10
  FAKE_TAG="$bad" run
  assert_rc "tag '$bad' is rejected" 1 "$RC"
  out_has "not exactly vX.Y.Z" "says the tag is malformed"
  if log_has "curl "; then fail "no download for a malformed tag ($bad)" "$(cat "$FAKE_LOG")"; else pass; fi
  if log_has "commits/"; then fail "no commit lookup for a malformed tag ($bad)" "$(cat "$FAKE_LOG")"; else pass; fi
  refused "malformed tag"
  rm -rf "$SCRATCH"
done

# --- a failed download of each file --------------------------------------------------------------
for ext in "" .sig .pem; do
  setup 1.13.10
  case "$ext" in .sig) k=sig ;; .pem) k=pem ;; *) k=sums ;; esac
  FAKE_CURL_FAIL="$k" run
  if [ "$RC" -ne 0 ]; then pass; else fail "a failed download of SHA256SUMS$ext fails the bump" "$OUT"; fi
  if log_has "cosign "; then fail "no cosign call after a failed download of SHA256SUMS$ext" "$(cat "$FAKE_LOG")"; else pass; fi
  refused "failed download of SHA256SUMS$ext"
  rm -rf "$SCRATCH"
done

# --- the same version still verifies, then reports up to date ----------------------------------
setup 1.13.10
FAKE_TAG=v1.13.10 run
assert_rc "same version" 0 "$RC"
out_has "up to date" "same version is up to date"
if log_has "cosign verify-blob"; then pass; else fail "cosign runs even when up to date" "$(cat "$FAKE_LOG")"; fi
rm -rf "$SCRATCH"

summary
