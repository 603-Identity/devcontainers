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
  *) if [ -n "$out" ]; then printf '%s' "$FAKE_BODY" > "$out"; else printf '%s' "$FAKE_BODY"; fi ;;
esac
C
  chmod +x "$SCRATCH/bin/"*
}

while IFS='|' read -r tool dir ver_arg sha_arg tag; do
  asset="$(dockerfile_asset "$ROOT_DIR/images/$dir/Dockerfile" "$ver_arg")" || asset=""
  if [ -z "$asset" ]; then fail "$tool: found the asset its Dockerfile downloads"; continue; fi
  setup "$dir"
  FAKE_BODY="$(checksum_body "$tool" "$asset")" FAKE_TAG="$tag" FAKE_VER="$NEW_VER" \
    PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app APP_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" "$tool" > "$SCRATCH/out" 2>&1
  rc=$?
  got="$(sed -n "s/^ARG ${sha_arg}=//p" "$R/images/$dir/Dockerfile")"
  assert_rc "$tool bump runs" 0 "$rc"
  if [ "$got" = "$SHA_GOOD" ]; then pass
  else fail "$tool: resolver reads the checksum of $asset, the asset its Dockerfile downloads" "wrote '$got': $(cat "$SCRATCH/out")"; fi
  rm -rf "$SCRATCH"
done <<< "$TOOLS"

summary
