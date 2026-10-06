#!/usr/bin/env bash
# Tests that bump-binaries.sh reads the checksum of the SAME asset each Dockerfile downloads
# (#164: resolve_yq read yq_linux_amd64.tar.gz's hash while images/base/Dockerfile checks the
# raw yq_linux_amd64 binary, so every automated yq bump would have failed its own build).
#
# For each checksum-file tool, the expected asset name is read from the real Dockerfile's
# download URL. A fake `curl` serves a checksum file with the real asset under one hash and
# near-miss decoys (the name plus or minus an extension) under another; the bump runs against a
# scratch copy of images/ with `git` and `gh` faked, and the test asserts the Dockerfile's
# SHA256 ARG ended up as the real asset's hash. A resolver that names any other asset fails.
# npm is left out on purpose: it takes the registry's `integrity` field, not a named asset.
# Offline; needs bash, awk and jq (the node resolver).
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/bump-binaries.sh"
suite "bump-binaries (resolver asset names match the Dockerfiles)"

SHA_GOOD=$(printf 'a%.0s' $(seq 1 64))
SHA_DECOY=$(printf 'c%.0s' $(seq 1 64))
NEW_VER=99.88.77

# tool|dockerfile dir|version ARG|sha ARG|release tag the fake API reports
TOOLS='gh|base|GH_VERSION|GH_SHA256|v99.88.77
yq|base|YQ_VERSION|YQ_SHA256|v99.88.77
uv|base|UV_VERSION|UV_SHA256|99.88.77
tofu|tofu|TOFU_VERSION|TOFU_SHA256|v99.88.77
tflint|tofu|TFLINT_VERSION|TFLINT_SHA256|v99.88.77
node|node|NODE_VERSION|NODE_SHA256|v99.88.77
betterleaks|base|BETTERLEAKS_VERSION|BETTERLEAKS_SHA256|v99.88.77'

# A tool added to the script's dispatch must be added above (npm has no asset name).
in_script="$(sed -nE 's/^  ([a-z0-9_-]+)\) +dockerfile_dir=.*/\1/p' "$SCRIPT" | grep -vx npm | sort | tr '\n' ' ')"
in_test="$(cut -d'|' -f1 <<< "$TOOLS" | sort | tr '\n' ' ')"
assert_eq "TOOLS covers every checksum-file tool bump-binaries.sh dispatches" "$in_script" "$in_test"

# dockerfile_asset <Dockerfile> <version ARG> -> the basename the image downloads, with the
# version ARG replaced by NEW_VER. The download is the one URL that mentions ${<version ARG>}.
dockerfile_asset() {
  local url
  url="$(grep -oE 'curl -fsSL "https://[^"]*\$\{'"$2"'\}[^"]*"' "$1" | head -n 1 | sed -E 's/^curl -fsSL "//; s/"$//')"
  [ -n "$url" ] || return 1
  basename "$url" | sed "s/\${$2}/$NEW_VER/g"
}

# checksum_body <tool> <asset> -> the fake checksum file. yq's lists one hash per algorithm
# after the name (MD5, SHA-1, SHA-256, in the order its sidecar names them); everything else
# is "hash  name". Decoys are near misses a wrong resolver would pick up.
checksum_body() {
  local tool="$1" asset="$2" d
  local decoys=("${asset}.tar.gz" "${asset}.sig" "x_${asset}")
  case "$asset" in *.tar.gz) decoys+=("${asset%.tar.gz}") ;; esac
  for d in "${decoys[@]}"; do
    if [ "$tool" = yq ]; then printf '%s md5 sha1 %s\n' "$d" "$SHA_DECOY"
    else printf '%s  %s\n' "$SHA_DECOY" "$d"; fi
  done
  if [ "$tool" = yq ]; then printf '%s md5 sha1 %s\n' "$asset" "$SHA_GOOD"
  else printf '%s  %s\n' "$SHA_GOOD" "$asset"; fi
}

setup() { # setup <dockerfile dir>
  SCRATCH="$(mktemp -d)" || exit 1
  R="$SCRATCH/root"
  mkdir -p "$R/.github/scripts" "$R/images" "$SCRATCH/bin"
  cp "$SCRIPT" "$R/.github/scripts/"
  cp -R "$ROOT_DIR/images/$1" "$R/images/"
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
case "$1 $2" in
  "api repos/betterleaks/betterleaks/releases") printf '%s\thttps://example.test/r\n' "$FAKE_TAG" ;;
  "api repos/nodejs/node/releases"*) echo https://example.test/node ;;
  "api repos/"*) printf '%s\thttps://example.test/r\n' "$FAKE_TAG" ;;
  "pr list") echo 0 ;;
  *) ;;
esac
G
  cat > "$SCRATCH/bin/git" <<'G'
#!/usr/bin/env bash
exit 0
G
  cat > "$SCRATCH/bin/cosign" <<'G'
#!/usr/bin/env bash
exit 0
G
  cat > "$SCRATCH/bin/curl" <<'C'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
case "$url" in
  *checksums_hashes_order) printf 'MD5\nSHA-1\nSHA-256\n' ;;
  *dist/index.json) printf '[{"version":"v%s","lts":"Fake"}]' "$FAKE_VER" ;;
  *sigstore.json) printf '{}' > "$out" ;;
  *) if [ -n "$out" ]; then printf '%s' "$FAKE_BODY" > "$out"
     else
       # FAKE_PAD: that many decoy lines AFTER the body, so a reader that stops at the first
       # match closes the pipe while this is still writing. Like real curl, fail with 23 when a
       # write fails (SIGPIPE ignored, so the failed write is seen).
       trap '' PIPE
       printf '%s' "$FAKE_BODY" || exit 23
       # FAKE_CURL_RC: the transfer dies (this exit code) after the whole body was written.
       [ -z "${FAKE_CURL_RC:-}" ] || exit "$FAKE_CURL_RC"
       if [ -n "${FAKE_PAD:-}" ]; then
         printf '\n' || exit 23
         awk -v n="$FAKE_PAD" 'BEGIN { for (i = 0; i < n; i++) print "decoy" i " md5 sha1 " i }' || exit 23
       fi
     fi ;;
esac
C
  chmod +x "$SCRATCH/bin/"*
}

while IFS='|' read -r tool dir ver_arg sha_arg tag; do
  asset="$(dockerfile_asset "$ROOT_DIR/images/$dir/Dockerfile" "$ver_arg")" || asset=""
  if [ -z "$asset" ]; then fail "$tool: found the asset its Dockerfile downloads"; continue; fi
  setup "$dir"
  FAKE_BODY="$(checksum_body "$tool" "$asset")" FAKE_TAG="$tag" FAKE_VER="$NEW_VER" \
    PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" "$tool" > "$SCRATCH/out" 2>&1
  rc=$?
  got="$(sed -n "s/^ARG ${sha_arg}=//p" "$R/images/$dir/Dockerfile")"
  assert_rc "$tool bump runs" 0 "$rc"
  if [ "$got" = "$SHA_GOOD" ]; then pass
  else fail "$tool: resolver reads the checksum of $asset, the asset its Dockerfile downloads" "wrote '$got': $(cat "$SCRATCH/out")"; fi
  rm -rf "$SCRATCH"
done <<< "$TOOLS"

# A checksum file longer than the pipe buffer, with the wanted line before the bulk: a resolver
# that pipes curl into an awk that exits on the first match makes curl fail with exit 23 (seen on
# yq, #102). Every tool must still resolve.
while IFS='|' read -r tool dir ver_arg sha_arg tag; do
  asset="$(dockerfile_asset "$ROOT_DIR/images/$dir/Dockerfile" "$ver_arg")" || asset=""
  if [ -z "$asset" ]; then fail "$tool: found the asset its Dockerfile downloads"; continue; fi
  setup "$dir"
  FAKE_PAD=40000 FAKE_BODY="$(checksum_body "$tool" "$asset")" FAKE_TAG="$tag" FAKE_VER="$NEW_VER" \
    PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" "$tool" > "$SCRATCH/out" 2>&1
  rc=$?
  got="$(sed -n "s/^ARG ${sha_arg}=//p" "$R/images/$dir/Dockerfile")"
  assert_rc "$tool bump runs against a large checksum file" 0 "$rc"
  if [ "$got" = "$SHA_GOOD" ]; then pass
  else fail "$tool: a large checksum file still resolves the right hash" "wrote '$got': $(cat "$SCRATCH/out")"; fi
  rm -rf "$SCRATCH"
done <<< "$TOOLS"


# A transfer that fails AFTER the wanted line arrived must fail the bump, not be accepted
# (sha256_line runs inside `$( )`, where `set -e` does not reach). betterleaks downloads with
# `curl -o` and is covered by its own suite.
while IFS='|' read -r tool dir ver_arg sha_arg tag; do
  [ "$tool" != betterleaks ] || continue
  asset="$(dockerfile_asset "$ROOT_DIR/images/$dir/Dockerfile" "$ver_arg")" || asset=""
  if [ -z "$asset" ]; then fail "$tool: found the asset its Dockerfile downloads"; continue; fi
  setup "$dir"
  FAKE_CURL_RC=18 FAKE_BODY="$(checksum_body "$tool" "$asset")" FAKE_TAG="$tag" FAKE_VER="$NEW_VER" \
    PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" "$tool" > "$SCRATCH/out" 2>&1
  rc=$?
  got="$(sed -n "s/^ARG ${sha_arg}=//p" "$R/images/$dir/Dockerfile")"
  if [ "$rc" -ne 0 ]; then pass; else fail "$tool: a transfer that dies after the wanted line fails the bump" "exit $rc: $(cat "$SCRATCH/out")"; fi
  if [ "$got" != "$SHA_GOOD" ]; then pass; else fail "$tool: nothing is written from a failed transfer" "wrote the hash"; fi
  rm -rf "$SCRATCH"
done <<< "$TOOLS"

summary
