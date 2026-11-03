#!/bin/bash
# claude-fetch.sh <version> <sha256> <key.asc> <out-dir> [<base-url> <fingerprint>]
#
# Build-time only (the `claude-fetch` stage of images/devapp/Dockerfile, run as root). Fetches
# Anthropic's signed release manifest and the linux-x64 `claude` binary, proves the binary
# is the one Anthropic signed for exactly this version, and installs it at <out-dir>/claude.
# Any failure exits non-zero, which fails the build: the stage that runs this is built
# BEFORE anything is pushed (.github/scripts/build-and-test.sh).
#
# What is checked, in order, and what each check closes:
#   1. the committed key file holds exactly ONE primary key and its fingerprint is the one
#      Anthropic publishes (31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE, "Verify release
#      signatures" in the Claude Code setup docs). A file with a second key, which gpgv would
#      also accept, is refused;
#   2. gpgv, with the status stream parsed (never its prose or just its exit code), reports
#      exactly one GOODSIG and one VALIDSIG on manifest.json, and none of BADSIG, ERRSIG,
#      EXPKEYSIG, REVKEYSIG or NO_PUBKEY, and VALIDSIG's last field, the primary key's
#      fingerprint, is the pinned one;
#   3. the manifest's `.version` is the pinned version, so a validly signed manifest of
#      another release (a downgrade, or a replay) is refused;
#   4. the manifest's linux-x64 checksum, the pinned CLAUDE_SHA256 and the sha256 of the
#      downloaded file are all the same value.
#
# Not closed (stated in docs/threat_model.md, and for the key file in README.md "Bumping
# `claude`"): a committed key cannot learn that Anthropic
# revoked it, and the key file here is only as trustworthy as the review of the PR that
# changes it.
#
# The two optional arguments exist for tools/tests/claude-fetch-test.sh, which runs this script
# against a throwaway key and a fake curl to prove the main refusals below fire. The Dockerfile
# never passes them, and they are arguments, not environment variables, so nothing a build
# environment carries can reach them.
set -euo pipefail

version=${1:?usage: claude-fetch.sh <version> <sha256> <key.asc> <out-dir>}
sha256=${2:?}
key=${3:?}
out=${4:?}

BASE=${5:-https://downloads.claude.ai/claude-code-releases}
FPR=${6:-31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE}

die() { echo "claude-fetch: $*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "CLAUDE_VERSION is not a plain x.y.z version: $version"
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || die "CLAUDE_SHA256 is not a lowercase sha256"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
install -d -m 0700 "$GNUPGHOME"

# 1. The key file: one primary key, the pinned fingerprint, then a binary keyring for gpgv.
colons=$(gpg --batch --show-keys --with-colons "$key")
[ "$(grep -c '^pub:' <<<"$colons")" = 1 ] || die "$key does not hold exactly one primary key"
primary=$(awk -F: '$1 == "fpr" { print $10; exit }' <<<"$colons")
[ "$primary" = "$FPR" ] || die "the key's fingerprint is $primary, not the pinned $FPR"
gpg --batch --dearmor <"$key" >"$work/keyring.gpg"

# Download. -f fails on an HTTP error, --proto/--tlsv1.2 refuse a downgrade or a redirect off https.
fetch() { curl -fsSL --proto '=https' --tlsv1.2 "$1" -o "$2"; }
fetch "$BASE/$version/manifest.json" "$work/manifest.json"
fetch "$BASE/$version/manifest.json.sig" "$work/manifest.json.sig"
fetch "$BASE/$version/linux-x64/claude" "$work/claude"

# 2. The signature, from gpgv's machine-readable status stream. A non-zero exit fails the
# build here; the counts below then decide on what a zero exit leaves possible (a second
# signature, an expired or revoked key).
status=$(gpgv --status-fd 1 --keyring "$work/keyring.gpg" "$work/manifest.json.sig" "$work/manifest.json" 2>/dev/null) \
    || die "gpgv rejected manifest.json.sig"
count() { grep -c "^\[GNUPG:\] $1 " <<<"$status" || true; }
[ "$(count GOODSIG)" = 1 ] || die "expected exactly one GOODSIG status"
[ "$(count VALIDSIG)" = 1 ] || die "expected exactly one VALIDSIG status"
for bad in BADSIG ERRSIG EXPKEYSIG REVKEYSIG NO_PUBKEY; do
    [ "$(count "$bad")" = 0 ] || die "gpgv reported $bad"
done
signer=$(awk '$2 == "VALIDSIG" { print $NF }' <<<"$status")
[ "$signer" = "$FPR" ] || die "signed by $signer, not the pinned $FPR"

# 3 and 4. What the signed manifest says about this release.
[ "$(jq -r '.version' "$work/manifest.json")" = "$version" ] || die "the signed manifest is for another version"
listed=$(jq -r '.platforms["linux-x64"].checksum // empty' "$work/manifest.json")
actual=$(sha256sum "$work/claude" | awk '{ print $1 }')
[ "$listed" = "$sha256" ] || die "the manifest lists $listed for linux-x64, not the pinned CLAUDE_SHA256"
[ "$actual" = "$sha256" ] || die "the downloaded binary is $actual, not the pinned CLAUDE_SHA256"

install -d -m 0755 "$out"
install -m 0755 "$work/claude" "$out/claude"
echo "claude-fetch: claude $version verified (sha256 $sha256, signed by $FPR)"
