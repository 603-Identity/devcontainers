#!/usr/bin/env bash
# Sets up this repo's local Linux environment in WSL (Ubuntu): jq, mikefarah yq v4,
# the shellcheck linter, Go and Node (template-proof.sh runs the pinned devcontainer CLI).
# Idempotent: a pinned tool already at its pinned version is left alone (the apt packages,
# jq and the linter, are updated by each run).
#
#   bash tools/wsl-setup.sh
#
# Pins are read from the repo, never repeated here, so they cannot drift from the repo's
# own. Only Go matches what CI runs; CI uses the runner's own jq, yq, node and shellcheck:
#   yq  -- YQ_VERSION and YQ_SHA256 in images/base/Dockerfile (the release binary, not
#          apt's `yq`, which is the Python wrapper and fails the gate suites)
#   Node -- NODE_VERSION and NODE_SHA256 in images/node/Dockerfile, the same linux-x64
#          tarball and extraction the image uses (npm is whatever that Node bundles; the
#          proof only needs it to install the pinned CLI)
#   Go  -- go-version in .github/workflows (the same lines verify-selftest.yml requires to
#          agree); the tarball's sha256 comes from go.dev's own release index
# jq and shellcheck come from apt, unpinned: whatever the distro ships.
#
# Everything runs as root (the script re-runs itself under sudo), so the downloads are
# verified and installed from a root-owned temp directory. The pins come from the checkout
# and reach root-run curl and tar, so each is shape-checked first: run this on a checkout
# you trust, the same as the other scripts here.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || exec sudo -- bash "${BASH_SOURCE[0]}" "$@"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
bin=/usr/local/bin
goroot=/usr/local/go

die() { echo "wsl-setup: $*" >&2; exit 1; }

[ "$(uname -s)" = Linux ] || die "run this inside WSL, not on Windows"
[ "$(uname -m)" = x86_64 ] || die "only x86_64 is supported (the pinned checksums are for amd64)"

version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
sha_re='^[0-9a-f]{64}$'
check_shape() { # check_shape <name> <regex> <value>
  [[ "$3" =~ $2 ]] || die "$1 is not of the expected shape (got: $(printf '%s' "$3" | head -c 80))"
}

dockerfile="$root/images/base/Dockerfile"
yq_version="$(sed -nE 's/^ARG YQ_VERSION=(.+)$/\1/p' "$dockerfile")"
yq_sha256="$(sed -nE 's/^ARG YQ_SHA256=(.+)$/\1/p' "$dockerfile")"
check_shape YQ_VERSION "$version_re" "$yq_version"
check_shape YQ_SHA256 "$sha_re" "$yq_sha256"

node_dockerfile="$root/images/node/Dockerfile"
node_version="$(sed -nE 's/^ARG NODE_VERSION=(.+)$/\1/p' "$node_dockerfile")"
node_sha256="$(sed -nE 's/^ARG NODE_SHA256=(.+)$/\1/p' "$node_dockerfile")"
check_shape NODE_VERSION "$version_re" "$node_version"
check_shape NODE_SHA256 "$sha_re" "$node_sha256"

go_versions="$(grep -hE '^[[:space:]]+go-version: ' "$root"/.github/workflows/*.yml \
  | sed -E 's/.*go-version: *"?([^" ]+)"?.*/\1/' | sort -u)"
[ -n "$go_versions" ] || die "found no go-version lines in .github/workflows"
[ "$(printf '%s\n' "$go_versions" | wc -l)" -eq 1 ] || die "workflows disagree on go-version: $go_versions"
go_version="$go_versions"
check_shape go-version "$version_re" "$go_version"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- jq, shellcheck, and what the downloads below need
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl jq shellcheck tar xz-utils

# --- yq (mikefarah v4)
if [ "$("$bin/yq" --version 2>/dev/null | sed -nE 's/.*mikefarah.*version v?([0-9.]+).*/\1/p')" != "$yq_version" ]; then
  echo "installing yq $yq_version"
  curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${yq_version}/yq_linux_amd64" -o "$tmp/yq"
  echo "$yq_sha256  $tmp/yq" | sha256sum -c - >/dev/null || die "yq sha256 mismatch"
  install -m 0755 "$tmp/yq" "$bin/yq"
fi

# --- Node
if [ "$("$bin/node" --version 2>/dev/null)" != "v$node_version" ]; then
  echo "installing node $node_version"
  curl -fsSL "https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-x64.tar.xz" -o "$tmp/node.tar.xz"
  echo "$node_sha256  $tmp/node.tar.xz" | sha256sum -c - >/dev/null || die "node sha256 mismatch"
  tar -xJf "$tmp/node.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
    --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE'
fi

# --- Go
if [ "$("$goroot/bin/go" env GOVERSION 2>/dev/null)" != "go$go_version" ]; then
  echo "installing go $go_version"
  tarball="go${go_version}.linux-amd64.tar.gz"
  go_sha256="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' \
    | jq -r --arg f "$tarball" '[.[].files[] | select(.filename == $f) | .sha256][0] // empty')"
  [ -n "$go_sha256" ] || die "go.dev lists no $tarball"
  check_shape "go.dev's sha256 for $tarball" "$sha_re" "$go_sha256"
  curl -fsSL "https://go.dev/dl/$tarball" -o "$tmp/$tarball"
  echo "$go_sha256  $tmp/$tarball" | sha256sum -c - >/dev/null || die "go sha256 mismatch"
  rm -rf "$goroot"
  tar -C /usr/local -xzf "$tmp/$tarball"
fi
ln -sf "$goroot/bin/go" "$bin/go"
ln -sf "$goroot/bin/gofmt" "$bin/gofmt"

echo "jq:         $(jq --version)"
echo "yq:         $(yq --version)"
echo "shellcheck: $(shellcheck --version | sed -n 's/^version: //p')"
echo "go:         $(go version)"
echo "node:       $(node --version), npm $(npm --version)"
