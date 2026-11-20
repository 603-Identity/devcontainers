#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Offline tests for .github/scripts/trivy-diff.sh, on the hand-written reports under
# fixtures/trivy-diff/. The script's stdout and stderr go to scratch files, never to this suite's
# own output: its ::error:: lines would be live workflow commands in the selftest job.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite trivy-diff

SCRIPT="$ROOT_DIR/.github/scripts/trivy-diff.sh"
FX="$FIXTURES/trivy-diff"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

run() { # run <args...>; sets RC, OUT, ERR
  RC=0
  bash "$SCRIPT" "$@" >"$SCRATCH/out" 2>"$SCRATCH/err" || RC=$?
  OUT="$(cat "$SCRATCH/out")"; ERR="$(cat "$SCRATCH/err")"
}
has() { printf '%s\n' "$OUT" | grep -qxF -- "$1"; }
has_re() { printf '%s\n' "$OUT" | grep -qE -- "$1"; }
check() { local d="$1"; shift; if "$@"; then pass; else fail "$d" "out: $OUT"; fi; }
check_not() { local d="$1"; shift; if "$@"; then fail "$d" "out: $OUT"; else pass; fi; }

LOC='usr/local/bin/tool'
ADDED="::error::base: added CVE-2026-0001 stdlib $LOC installed 1.0 fixed 2.0"
PUBLISHED="trivy-diff: base: published CVE-2026-0001 stdlib $LOC installed 1.0 fixed 2.0"

# identical reports
run base "$FX/a.json" "$FX/a-same.json"
assert_rc "identical" 0 "$RC"
check "published line" has "$PUBLISHED"
check "count line" has "trivy-diff: base: 0 added, 1 published, 0 secret"
assert_eq "identical: stderr empty" "" "$ERR"

# only in the PR report
run base "$FX/a.json" "$FX/empty.json"
assert_rc "added" 1 "$RC"
check "added line" has "$ADDED"
check "count line" has "trivy-diff: base: 1 added, 0 published, 0 secret"
assert_eq "added: last line is the count" "trivy-diff: base: 1 added, 0 published, 0 secret" "$(printf '%s\n' "$OUT" | tail -n 1)"

# only in the published report
run base "$FX/empty.json" "$FX/a.json"
assert_rc "only published" 0 "$RC"
assert_eq "only published: output" "trivy-diff: base: 0 added, 0 published, 0 secret" "$OUT"

# key parts
run base "$FX/a.json" "$FX/a-other-path.json"
assert_rc "other PkgPath" 1 "$RC"
run base "$FX/a.json" "$FX/a-other-pkg.json"
assert_rc "other PkgName" 1 "$RC"
run base "$FX/a-other-version.json" "$FX/a.json"
assert_rc "InstalledVersion alone" 0 "$RC"
check "version line shows the PR version" has "trivy-diff: base: published CVE-2026-0001 stdlib $LOC installed 1.1 fixed 2.0"
run tofu "$FX/os-pr.json" "$FX/os-before.json"
assert_rc "os-pkgs with different Targets" 0 "$RC"
check "os-pkgs location prints as -" has "trivy-diff: tofu: published CVE-2026-0002 libc6 - installed 1.0 fixed 2.0"
run node "$FX/nonos-a.json" "$FX/nonos-b.json"
assert_rc "non-OS keyed by Target" 1 "$RC"
check "added line carries the Target" has "::error::node: added CVE-2026-0003 left-pad package-lock.json installed 1.0 fixed 2.0"
run node "$FX/nonos-a.json" "$FX/nonos-a.json"
assert_rc "non-OS same Target" 0 "$RC"

# keys equal after the cut and the keep set, different raw values
run base "$FX/raw-nl.json" "$FX/raw-pct.json"
assert_rc "raw values differ" 1 "$RC"
check "raw: one added" has "trivy-diff: base: 1 added, 0 published, 0 secret"

# secrets
run devapp "$FX/secret.json" "$FX/secret.json"
assert_rc "secret with the same one published" 1 "$RC"
check "secret line" has "::error::devapp: secret generic-rule in app.env"
check "secret count" has "trivy-diff: devapp: 0 added, 0 published, 1 secret"
check_not "no matched text, code or title" has_re 'MARKER'
run devapp "$FX/secret.json" none
assert_rc "secret against none" 1 "$RC"

# none
run base "$FX/a.json" none
assert_rc "none" 1 "$RC"
check "none: added" has "$ADDED"

# null or absent Results and Vulnerabilities
for f in null-results absent-results null-vulns absent-vulns; do
  run base "$FX/$f.json" "$FX/$f.json"
  assert_rc "$f" 0 "$RC"
  assert_eq "$f: output" "trivy-diff: base: 0 added, 0 published, 0 secret" "$OUT"
  run base "$FX/a.json" "$FX/$f.json"
  assert_rc "$f as before" 1 "$RC"
done

# usage errors: exit 2, nothing on stdout
U='trivy-diff: usage error'
usage() { # usage <description> <args...>
  local d="$1"; shift
  run "$@"
  assert_rc "usage: $d" 2 "$RC"; assert_eq "usage: $d: stdout" "" "$OUT"; assert_eq "usage: $d: stderr" "$U" "$ERR"
}
usage "no argument"
usage "two arguments" base "$FX/a.json"
usage "four arguments" base "$FX/a.json" none none
usage "unknown flavour" other "$FX/a.json" none
usage "BEFORE neither file nor none" base "$FX/a.json" "$FX/missing.json"
usage "BEFORE a directory" base "$FX/a.json" "$FX"

# malformed reports: exit 2, nothing on stdout, one fixed line, no fixture text (PR report and BEFORE alike)
R='trivy-diff: a report is not well formed'
for f in missing.json not-json.txt not-object.json results-object.json result-not-object.json empty-target.json \
  two-docs.json empty-file.json no-class.json no-id.json empty-id.json no-pkg.json empty-pkg.json secret-no-rule.json; do
  run base "$FX/$f" none
  assert_rc "malformed PR report $f" 2 "$RC"; assert_eq "malformed PR report $f: stdout" "" "$OUT"; assert_eq "malformed PR report $f: stderr" "$R" "$ERR"
  [ "$f" = missing.json ] && continue
  run base "$FX/a.json" "$FX/$f"
  assert_rc "malformed BEFORE $f" 2 "$RC"; assert_eq "malformed BEFORE $f: stdout" "" "$OUT"; assert_eq "malformed BEFORE $f: stderr" "$R" "$ERR"
done

# hostile fields: replaced, never a line start, no field in a command's properties
run base "$FX/hostile.json" none
assert_rc "hostile" 1 "$RC"
check_not "no percent sign" has_re '%'
check_not "no carriage return" grep -q "$(printf '\r')" "$SCRATCH/out"
assert_eq "hostile: line count (no field holds a newline)" 2 "$(wc -l <"$SCRATCH/out" | tr -d ' ')"
check "fixed prefixes" bash -c '[ "$(grep -cE "^(::error::base: added |trivy-diff: base: )" "$1")" -eq 2 ]' _ "$SCRATCH/out"
check "double colon kept inside the message" has '::error::base: added ::error::forged p?q?41 /a?b installed 1.0?::warning::x fixed 2.0'
check_not "no properties part" has_re '^::error [^:]*::'

# an over-long field is cut to 256 characters
run base "$FX/long.json" none
assert_rc "long" 1 "$RC"
loc="$(printf '%s\n' "$OUT" | sed -n 's/^::error::base: added CVE-2026-0005 stdlib \(\/a*\) installed .*/\1/p')"
assert_eq "long: location length" 256 "${#loc}"

# drift guard: the keep set is byte-equal to trivy-daily.sh's
daily_keep="$(sed -n "s/^KEEP='\(.*\)'   #.*/\1/p" "$ROOT_DIR/.github/scripts/trivy-daily.sh")"
mine_keep="$(sed -n "s/^KEEP_JQ='\(.*\)'\$/\1/p" "$SCRIPT")"
assert_eq "keep set in step with trivy-daily.sh" "$daily_keep" "$mine_keep"
if [ -n "$mine_keep" ]; then pass; else fail "keep set was found"; fi

summary
