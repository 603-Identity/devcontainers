#!/usr/bin/env bash
# Proves the main refusals in images/devapp/files/claude-fetch.sh fire (not each gpgv status token). That script is the build's
# only trust decision about a third-party binary, and a real build exercises just the
# passing path: a regression that made one check vacuous would still go green. Here each case
# breaks exactly one thing in an otherwise valid release and expects the script to refuse for
# that reason.
#
# Needs gpg and gpgv (preinstalled on ubuntu-latest). Offline. It signs fixture manifests with a throwaway key, and puts a fake `curl` on PATH that
# serves them. Needs bash, gpg, gpgv, jq and sha256sum. The script's optional arguments (base
# URL and fingerprint) point it at the throwaway key; the Dockerfile never passes them.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/images/devapp/files/claude-fetch.sh"
PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL [claude-fetch] $1" >&2; [ -z "${2:-}" ] || echo "     $2" >&2; }

for t in gpg gpgv jq sha256sum; do
  command -v "$t" >/dev/null || { echo "claude-fetch-test: $t is required" >&2; exit 1; }
done

echo "== claude-fetch"
W="$(mktemp -d)"
trap 'gpgconf --kill gpg-agent 2>/dev/null; rm -rf "$W"' EXIT
export GNUPGHOME="$W/gnupg"
install -d -m 0700 "$GNUPGHOME"

genkey() { # genkey <name>: writes $W/<name>.asc, prints the fingerprint
  gpg --batch --quiet --passphrase '' --quick-gen-key "$1 <$1@example.test>" ed25519 sign never 2>/dev/null
  local fpr
  fpr=$(gpg --batch --with-colons --list-keys "$1@example.test" | awk -F: '$1 == "fpr" { print $10; exit }')
  gpg --batch --armor --export "$fpr" >"$W/$1.asc"
  printf '%s' "$fpr"
}
FPR_A=$(genkey a)
FPR_B=$(genkey b)
cat "$W/a.asc" "$W/b.asc" >"$W/both.asc"

# Key c (made just before its case) expires two seconds after it is made; key d is revoked. Both sign the manifest while still
# good (c) or are exported after the fact (d): gpgv can exit 0 for these, so the status-token
# loop in claude-fetch.sh, not gpgv's exit code, is what has to refuse them.
FPR_D=$(genkey d)

# A fake curl: serves $FIX/manifest.json, $FIX/manifest.json.sig and $FIX/claude by the URL's tail.
mkdir -p "$W/bin"
cat >"$W/bin/curl" <<'SHIM'
#!/usr/bin/env bash
out= url=
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; https://*) url=$1 ;; esac
  shift
done
case "$url" in
  */manifest.json.sig) cp "$FIX/manifest.json.sig" "$out" ;;
  */manifest.json) cp "$FIX/manifest.json" "$out" ;;
  */linux-x64/claude) cp "$FIX/claude" "$out" ;;
  *) echo "unexpected url $url" >&2; exit 22 ;;
esac
SHIM
chmod +x "$W/bin/curl"
export PATH="$W/bin:$PATH"

VERSION=1.2.3
BIN="$W/claude.bin"
printf 'not really a binary\n' >"$BIN"
SHA=$(sha256sum "$BIN" | awk '{ print $1 }')

fixture() { # fixture: a valid release, signed by key a
  FIX="$W/fix"; export FIX
  rm -rf "$FIX"; mkdir -p "$FIX"
  cp "$BIN" "$FIX/claude"
  jq -n --arg v "$VERSION" --arg c "$SHA" '{version: $v, platforms: {"linux-x64": {binary: "claude", checksum: $c}}}' >"$FIX/manifest.json"
  gpg --batch --quiet --local-user "$FPR_A" --detach-sign -o "$FIX/manifest.json.sig" "$FIX/manifest.json"
}

# Expire c, revoke d, then export both (an expired or revoked key signs nothing new, so the
# signatures are made before).
sign_with() { # sign_with <fpr> <manifest> <sig>
  rm -f "$3"; gpg --batch --quiet --local-user "$1" --detach-sign -o "$3" "$2"
}

run() { # run <label> <expected rc 0|fail> <expected stderr substring> <version> <sha> <keyfile> <fpr>
  local label=$1 want=$2 msg=$3 ver=$4 sha=$5 key=$6 fpr=$7 out="$W/out" log rc
  rm -rf "$out"
  log=$("$SCRIPT" "$ver" "$sha" "$key" "$out" https://example.test/releases "$fpr" 2>&1)
  rc=$?
  if [ "$want" = 0 ]; then
    if [ "$rc" = 0 ] && [ "$(cat "$out/claude" 2>/dev/null)" = "$(cat "$BIN")" ] && [ "$(stat -c %a "$out/claude")" = 755 ]; then pass
    else fail "$label" "rc=$rc: $log"; fi
  else
    if [ "$rc" != 0 ] && [ ! -e "$out/claude" ] && printf '%s' "$log" | grep -qE -- "$msg"; then pass
    else fail "$label" "rc=$rc, wanted a refusal mentioning '$msg': $log"; fi
  fi
}

fixture; run "a valid release is installed" 0 "" "$VERSION" "$SHA" "$W/a.asc" "$FPR_A"

fixture; run "a key file with two primary keys is refused" fail "exactly one primary key" "$VERSION" "$SHA" "$W/both.asc" "$FPR_A"
fixture; run "a key with another fingerprint is refused" fail "not the pinned" "$VERSION" "$SHA" "$W/b.asc" "$FPR_A"

fixture; printf '{"version":"%s","platforms":{}}\n' "$VERSION" >"$FIX/manifest.json"
run "a manifest changed after signing (BADSIG) is refused" fail "gpgv rejected" "$VERSION" "$SHA" "$W/a.asc" "$FPR_A"

fixture; rm -f "$FIX/manifest.json.sig"; gpg --batch --quiet --local-user "$FPR_B" --detach-sign -o "$FIX/manifest.json.sig" "$FIX/manifest.json"
run "a manifest signed by another key is refused" fail "gpgv rejected" "$VERSION" "$SHA" "$W/a.asc" "$FPR_A"

# Made and used back to back (key c lives two seconds), then waited out.
gpg --batch --quiet --passphrase '' --quick-gen-key "c <c@example.test>" ed25519 sign seconds=2 2>/dev/null
FPR_C=$(gpg --batch --with-colons --list-keys c@example.test | awk -F: '$1 == "fpr" { print $10; exit }')
fixture; sign_with "$FPR_C" "$FIX/manifest.json" "$FIX/manifest.json.sig"; sleep 4
gpg --batch --armor --export "$FPR_C" >"$W/c.asc"
run "a manifest signed by an expired key is refused" fail "gpgv rejected|GOODSIG status|EXPKEYSIG" "$VERSION" "$SHA" "$W/c.asc" "$FPR_C"

fixture; sign_with "$FPR_D" "$FIX/manifest.json" "$FIX/manifest.json.sig"
printf 'y\n0\n\ny\n' | gpg --quiet --yes --command-fd 0 --output "$W/d.rev" --gen-revoke "$FPR_D" >/dev/null 2>&1
gpg --batch --quiet --import "$W/d.rev" 2>/dev/null
gpg --batch --armor --export "$FPR_D" >"$W/d.asc"
run "a manifest signed by a revoked key is refused" fail "gpgv rejected|GOODSIG status|REVKEYSIG" "$VERSION" "$SHA" "$W/d.asc" "$FPR_D"

fixture; : >"$FIX/manifest.json.sig"
run "an empty signature is refused" fail "gpgv rejected" "$VERSION" "$SHA" "$W/a.asc" "$FPR_A"

fixture; cat "$FIX/manifest.json.sig" "$FIX/manifest.json.sig" >"$W/sig2" && mv "$W/sig2" "$FIX/manifest.json.sig"
run "two signatures on the manifest are refused" fail "expected exactly one" "$VERSION" "$SHA" "$W/a.asc" "$FPR_A"

fixture
run "a validly signed manifest of another version is refused" fail "another version" "9.9.9" "$SHA" "$W/a.asc" "$FPR_A"

fixture; other=$(printf 'x' | sha256sum | awk '{ print $1 }')
run "a pin the manifest does not list is refused" fail "the manifest lists" "$VERSION" "$other" "$W/a.asc" "$FPR_A"

# The signed manifest lists another checksum than the pin and the binary, which agree with each other:
# only the check that ties the signature to the binary refuses this.
fixture; jq '.platforms["linux-x64"].checksum = "0000000000000000000000000000000000000000000000000000000000000000"' "$FIX/manifest.json" >"$W/m2" \
  && mv "$W/m2" "$FIX/manifest.json" && sign_with "$FPR_A" "$FIX/manifest.json" "$FIX/manifest.json.sig"
run "a signed manifest listing another checksum than the pin is refused" fail "the manifest lists" "$VERSION" "$SHA" "$W/a.asc" "$FPR_A"

fixture; printf 'a different binary\n' >"$FIX/claude"
run "a download that differs from the pin is refused" fail "the downloaded binary is" "$VERSION" "$SHA" "$W/a.asc" "$FPR_A"

fixture
run "a malformed version is refused" fail "plain x.y.z" "1.2" "$SHA" "$W/a.asc" "$FPR_A"
run "a malformed sha256 is refused" fail "lowercase sha256" "$VERSION" "ABC" "$W/a.asc" "$FPR_A"

echo "-- claude-fetch: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
