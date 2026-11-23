#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Proves the reader search in docs/host-steps.md's Procedure B block (the lines between its two
# `reader-search` comment markers: Find-Readers and Assert-NoReaders) offline, against fixtures. The
# suite extracts only that region, runs it under `pwsh -NoProfile -NonInteractive` with a fake
# `docker` (written into a scratch folder at run time) as the Docker CLI path, and runs no other
# part of the block. Needs pwsh (preinstalled on ubuntu-latest), bash, jq and coreutils; with no
# pwsh it exits 1 instead of skipping. The committed fixtures under fixtures/reader-search are the
# hand-built base shapes (a container shaped like this repo's own dev container, its four volumes);
# the scenarios that vary them do so with jq here, and every inspect and volume fixture a scenario
# serves carries canaries (see the harness notes below).
set -uo pipefail
if ! command -v pwsh >/dev/null 2>&1; then
  echo "reader-search-test: pwsh is required" >&2
  exit 1
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
for t in jq awk grep; do
  command -v "$t" >/dev/null || { echo "reader-search-test: $t is required" >&2; exit 1; }
done
export LC_ALL=C
suite reader-search
pwsh --version

RSFIX="$FIXTURES/reader-search"
HOSTSTEPS="$ROOT_DIR/docs/host-steps.md"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# --- the region ------------------------------------------------------------------------

BEGIN_RE='^[[:space:]]*# reader-search: begin[[:space:]]*$'
END_RE='^[[:space:]]*# reader-search: end[[:space:]]*$'

# extract_region FILE OUT: writes the lines strictly between the markers to OUT. Returns 1 when a
# marker is missing or repeated or they are out of order, 2 when the region mentions a word it must
# not, 3 when pwsh's own parser finds anything but exactly the two functions.
extract_region() {
  local f=$1 out=$2 b e
  b=$(grep -cE "$BEGIN_RE" "$f" || true)
  e=$(grep -cE "$END_RE" "$f" || true)
  [ "$b" = 1 ] || return 1
  [ "$e" = 1 ] || return 1
  [ "$(grep -nE "$BEGIN_RE" "$f" | cut -d: -f1)" -lt "$(grep -nE "$END_RE" "$f" | cut -d: -f1)" ] || return 1
  awk -v b="$BEGIN_RE" -v e="$END_RE" '$0 ~ e { on = 0 } on { print } $0 ~ b { on = 1 }' "$f" >"$out"
  if grep -Eq 'Read-Host|\$tokenFile|GH_TOKEN|\<gh\>|Get-Content' "$out"; then return 2; fi
  RS_REGION="$out" pwsh -NoProfile -NonInteractive -Command '
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($env:RS_REGION, [ref]$t, [ref]$e)
    if ($e.Count) { exit 3 }
    if ($ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or $ast.DynamicParamBlock) { exit 3 }
    $st = @($ast.EndBlock.Statements)
    if ($st.Count -ne 2) { exit 3 }
    foreach ($s in $st) { if ($s -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { exit 3 } }
    $names = (@($st | ForEach-Object { $_.Name }) | Sort-Object) -join ","
    if ($names -cne "Assert-NoReaders,Find-Readers") { exit 3 }
  ' >/dev/null 2>&1 || return 3
  return 0
}

REGION="$W/region.ps1"
extract_region "$HOSTSTEPS" "$REGION"
assert_eq "the region of docs/host-steps.md extracts and holds exactly the two functions" 0 "$?"

mkdir -p "$W/hs"
mod() { # name awk-body-using-ENVIRON["L"]: writes a modified copy of host-steps.md to $W/hs/<name>.md
  awk -v b="$BEGIN_RE" -v e="$END_RE" "$2" "$HOSTSTEPS" >"$W/hs/$1.md"
}
region_fails() { # name want-rc
  local rc=0
  extract_region "$W/hs/$1.md" "$W/hs/$1.ps1" || rc=$?
  assert_eq "region check refuses: $1" "$2" "$rc"
}
mod no-begin '$0 !~ b { print }'
region_fails no-begin 1
mod no-end '$0 !~ e { print }'
region_fails no-end 1
mod repeated-begin '{ print } $0 ~ b { print }'
region_fails repeated-begin 1
mod repeated-end '{ print } $0 ~ e { print }'
region_fails repeated-end 1
for w in 'Read-Host' '$tokenFile' 'GH_TOKEN' 'gh' 'Get-Content'; do
  n="word-$(printf '%s' "$w" | tr -c 'A-Za-z' '_')"
  W_LINE="   # $w" mod "$n" '{ print } $0 ~ b { print ENVIRON["W_LINE"] }'
  region_fails "$n" 2
done
W_LINE='   $x = 1' mod extra-statement '{ print } $0 ~ b { print ENVIRON["W_LINE"] }'
region_fails extra-statement 3
W_LINE='   function Extra { }' mod third-function '{ print } $0 ~ b { print ENVIRON["W_LINE"] }'
region_fails third-function 3
mod misnamed 'inr && /function Assert-NoReaders/ { sub(/Assert-NoReaders/, "Assert-NoReader") } { print } $0 ~ b { inr = 1 } $0 ~ e { inr = 0 }'
region_fails misnamed 3

# --- the fake docker and the harness ------------------------------------------------------

mkdir -p "$W/fake" "$W/fd" "$W/tmp"
FAKE="$W/fake/docker"
STDERR_CANARY="STDERRCANARY8Q"
cat >"$FAKE" <<'SHIM'
#!/usr/bin/env bash
# The fake docker: serves $FAKE_DIR's fixtures for the three call shapes the search makes and exits
# 97 on any other argv. It logs each call, whether the --config path existed when it ran, and the
# three Docker variables, and writes a canary of its own to standard error on every call.
d="$FAKE_DIR"
printf '%s\n' "stderr canary $FAKE_MARK" >&2
st() { if [ "${!1+x}" ]; then printf 'set:%s' "${!1}"; else printf unset; fi; }
envs="DC=$(st DOCKER_CONFIG) DH=$(st DOCKER_HOST) DX=$(st DOCKER_CONTEXT)"
if [ "${1:-}" != --config ] || [ "${3:-}" != --context ] || [ "${4:-}" != default ]; then
  echo "bad-prefix $envs" >>"$d/calls.log"
  exit 97
fi
cfg=$2
shift 4
ex=no
[ -e "$cfg" ] && ex=yes
shape=bad
name=
if [ "$*" = "ps --no-trunc --quiet" ]; then
  shape=ps
elif [ "${1:-}" = inspect ] && [ "${2:-}" = --type ] && [ "${3:-}" = volume ] && [ $# -eq 4 ]; then
  shape=volume
  name=$4
elif [ "${1:-}" = inspect ] && [ $# -ge 2 ]; then
  ok=1
  for a in "${@:2}"; do [[ $a =~ ^[0-9a-f]{64}$ ]] || ok=0; done
  [ "$ok" = 1 ] && shape=inspect
fi
echo "shape=$shape cfg=$cfg cfgexisted=$ex $envs" >>"$d/calls.log"
[ "$shape" = bad ] && exit 97
key=$shape
[ "$shape" = volume ] && key="vol-$name"
rc=0
[ -f "$d/$key.rc" ] && rc=$(cat "$d/$key.rc")
[ -f "$d/$key.out" ] && cat "$d/$key.out"
if [ -f "$d/create-on" ] && [ "$(cat "$d/create-on")" = "$shape" ]; then mkdir -p "$cfg"; fi
exit "$rc"
SHIM
chmod +x "$FAKE"

# The harness sets $PSStyle.OutputRendering to Ansi so pwsh strips no ESC sequence, sets
# $ErrorActionPreference to Stop as the block does, sets the console encoding to Latin-1 (a non-UTF-8
# code page, as a Windows console has), calls Assert-NoReaders inside its own try/catch and writes
# every line, the caught message included, with [Console]::Out.WriteLine, so PowerShell renders no
# error record of its own: the bytes on standard output are what the assertions read.
HARNESS="$W/harness.ps1"
cat >"$HARNESS" <<'PS'
$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'Ansi'
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(28591)
if ($env:RS_NEWGUID) { function New-Guid { [guid]$env:RS_NEWGUID } }
. ([scriptblock]::Create([IO.File]::ReadAllText($env:RS_REGION)))
$folders = @($env:RS_FOLDERS -split '\|')
try {
  Assert-NoReaders $env:RS_DOCKER $folders | ForEach-Object { [Console]::Out.WriteLine($_) }
  [Console]::Out.WriteLine('RESULT:ok')
} catch {
  [Console]::Out.WriteLine('THROW:' + $_.Exception.Message)
}
$e = foreach ($n in 'DOCKER_CONFIG', 'DOCKER_HOST', 'DOCKER_CONTEXT') {
  $v = [Environment]::GetEnvironmentVariable($n)
  if ($null -eq $v) { "$n=<unset>" } else { "$n=$v" }
}
[Console]::Out.WriteLine('ENV:' + ($e -join ','))
[Console]::Out.WriteLine('ENC:' + [Console]::OutputEncoding.CodePage)
PS

# --- scenario helpers --------------------------------------------------------------------

A=$(printf 'a%.0s' {1..64})
B=$(printf 'b%.0s' {1..64})
IH='C:\Users\tester\.config\603id-identity'
SN='C:\Users\tester\AppData\Local\Temp\wow-publish-1234'
FIXED_GUID='3f2504e0-4f89-41d3-9a0c-0305e82c3301'
SENT_C='sentinel-config'
SENT_H='tcp://sentinel-host'
SENT_X='sentinel-context'
N=0

sc() { # name: begins a scenario with clean fixtures and the defaults
  SCN="$1"
  N=$((N + 1))
  MARK="MK${N}ZQ"
  CANARY="$MARK"$'\n'$'\e[31m''reader: '"$MARK"
  FD="$W/fd/$N"
  TMPD="$W/tmp/$N"
  rm -rf "$FD" "$TMPD"
  mkdir -p "$FD" "$TMPD"
  : >"$FD/calls.log"
  : >"$FD/ps.out"
  DOCKER="$FAKE"
  FOLDERS="$IH|$SN"
  NEWGUID=""
  SENT=1
  unset TEMP_OVERRIDE
  EXPECT_NEWDIR=""
}

put_ps() { if [ $# -eq 0 ]; then : >"$FD/ps.out"; else printf '%s\n' "$@" >"$FD/ps.out"; fi; }
put_inspect() { printf '%s\n' "$@" | jq -cs '.' >"$FD/inspect.out"; } # records -> one JSON array
put_vol() { printf '%s\n' "$2" >"$FD/vol-$1.out"; }
rec() { # id mounts-json [hostconfig-json]
  local hc=${3-}
  [ -n "$hc" ] || hc='{}'
  jq -cn --arg id "$1" --arg c "$CANARY" --argjson m "$2" --argjson hc "$hc" \
    '{Id: $id, Name: ("/n" + $c), Config: {Labels: {note: $c}}, State: {Status: "running"}, Mounts: $m, HostConfig: $hc, Extra: $c}'
}
mnt() { # type source [name]
  jq -cn --arg t "$1" --arg s "$2" --arg n "${3-}" --arg c "$CANARY" \
    '{Type: $t, Source: $s, Destination: ("/d" + $c)} + (if $n != "" then {Name: $n} else {} end)'
}
vol() { # name driver options-json: a volume inspect output, canaries in unused fields
  jq -cn --arg n "$1" --arg d "$2" --argjson o "$3" --arg c "$CANARY" \
    '[{Name: $n, Driver: $d, Options: $o, Labels: {note: $c}, Mountpoint: ("/v/" + $n), Scope: "local"}]'
}
hit() { printf 'reader: %s %s %s' "$1" "$2" "$3"; }
one() { # source type: one container A with one mount of that type and source
  put_ps "$A"
  put_inspect "$(rec "$A" "[$(mnt "${2-bind}" "$1")]")"
}
fixture_clean() { # drive|desktop: the committed dev-container-shaped record, with canaries added
  put_ps "$A"
  jq -c --arg c "$CANARY" '.[0].Name = ("/n" + $c) | .[0].Config = {Labels: {note: $c}} | .[0].Extra = $c' "$RSFIX/clean-$1.inspect.json" >"$FD/inspect.out"
  local n
  for n in dc-home dc-cache dc-uv dc-claude; do
    jq -c --arg c "$CANARY" '.[0].Labels = {note: $c}' "$RSFIX/volume-$n.json" >"$FD/vol-$n.out"
  done
}

run_pwsh() {
  OUT="$FD/out"
  ERR="$FD/err"
  ls -A "$TMPD" >"$FD/ls.before"
  local -a ev=(FAKE_DIR="$FD" FAKE_MARK="$STDERR_CANARY" RS_REGION="$REGION" RS_DOCKER="$DOCKER" RS_FOLDERS="$FOLDERS" RS_NEWGUID="$NEWGUID")
  if [ "${TEMP_OVERRIDE+x}" ]; then ev+=(TEMP="$TEMP_OVERRIDE"); else ev+=(TEMP="$TMPD"); fi
  if [ "$SENT" = 1 ]; then
    ev+=(DOCKER_CONFIG="$SENT_C" DOCKER_HOST="$SENT_H" DOCKER_CONTEXT="$SENT_X")
    env "${ev[@]}" pwsh -NoProfile -NonInteractive -File "$HARNESS" >"$OUT" 2>"$ERR"
  else
    env -u DOCKER_CONFIG -u DOCKER_HOST -u DOCKER_CONTEXT "${ev[@]}" pwsh -NoProfile -NonInteractive -File "$HARNESS" >"$OUT" 2>"$ERR"
  fi
  RC=$?
  ls -A "$TMPD" >"$FD/ls.after"
}

# check HITS RESULT: runs the scenario. HITS is the exact `reader:` lines expected (newline
# separated, empty for none); RESULT is `ok` or the exact throw text. Beside the exact output it
# asserts what holds in every scenario: pwsh's standard error is empty, no marker token and no ESC
# byte reaches the output, the fake's own standard-error canary never surfaces, no call ran with a
# Docker variable set or in a shape other than the three, and the scratch TEMP listing is unchanged
# (except for EXPECT_NEWDIR, the config path a scenario makes the fake create).
check() {
  local hits=$1 res=$2 want envline
  run_pwsh
  if [ "$SENT" = 1 ]; then
    envline="ENV:DOCKER_CONFIG=$SENT_C,DOCKER_HOST=$SENT_H,DOCKER_CONTEXT=$SENT_X"
  else
    envline="ENV:DOCKER_CONFIG=<unset>,DOCKER_HOST=<unset>,DOCKER_CONTEXT=<unset>"
  fi
  want=""
  [ -z "$hits" ] || want="$hits"$'\n'
  if [ "$res" = ok ]; then want="${want}RESULT:ok"; else want="${want}THROW:$res"; fi
  want="$want"$'\n'"$envline"$'\n'"ENC:28591"
  assert_eq "$SCN: output" "$want" "$(cat "$OUT")"
  assert_eq "$SCN: pwsh exit code" 0 "$RC"
  assert_eq "$SCN: pwsh standard error is empty" "" "$(cat "$ERR")"
  if grep -qF "$MARK" "$OUT" "$ERR"; then fail "$SCN: a marker token reached the output"; else pass; fi
  if grep -q $'\e' "$OUT" "$ERR"; then fail "$SCN: an ESC byte reached the output"; else pass; fi
  if grep -qF "$STDERR_CANARY" "$OUT" "$ERR"; then fail "$SCN: the fake's standard-error canary surfaced"; else pass; fi
  if grep -qE 'DC=set|DH=set|DX=set|shape=bad|bad-prefix' "$FD/calls.log"; then fail "$SCN: a call ran with a Docker variable set or in an unknown shape" "$(cat "$FD/calls.log")"; else pass; fi
  if [ -n "$EXPECT_NEWDIR" ]; then
    assert_eq "$SCN: the scratch TEMP gained exactly the config path" "$EXPECT_NEWDIR" "$(cat "$FD/ls.after")"
  else
    assert_eq "$SCN: the scratch TEMP listing is unchanged" "$(cat "$FD/ls.before")" "$(cat "$FD/ls.after")"
  fi
}
shapes() { sed -n 's/^shape=\([a-z]*\) .*/\1/p' "$FD/calls.log" | tr '\n' ' ' | sed 's/ $//'; }

THROW1='reader search: 1 hit(s); stop'
THROW2='reader search: 2 hit(s); stop'
BAD='reader search: the list cannot be built'
FORM='reader search: a folder is not in long drive-letter form'
EXISTS='reader search: the config path exists'

# --- clean ----------------------------------------------------------------------------

sc "clean: no running containers"
check "" ok
assert_eq "$SCN: the call log shows ps only" "ps" "$(shapes)"

for form in drive desktop; do
  sc "clean: dev-container shape, $form form"
  fixture_clean "$form"
  check "" ok
  assert_eq "$SCN: calls" "ps inspect volume volume volume volume" "$(shapes)"
done

# --- the environment ---------------------------------------------------------------------

sc "environment: sentinels, clean run"
put_ps "$A"
put_inspect "$(rec "$A" '[]')"
check "" ok
assert_eq "$SCN: calls" "ps inspect" "$(shapes)"
assert_eq "$SCN: one config path under the scratch TEMP, never existing when a call ran" "2" "$(grep -c "^shape=[a-z]* cfg=$TMPD/[0-9a-f-]\{36\} cfgexisted=no DC=unset DH=unset DX=unset$" "$FD/calls.log")"
assert_eq "$SCN: both calls name the same path" "1" "$(sed -n 's/^shape=[a-z]* cfg=\([^ ]*\) .*/\1/p' "$FD/calls.log" | sort -u | wc -l | tr -d ' ')"

sc "environment: sentinels, Find-Readers throws after its first call"
put_ps "$A"
echo 1 >"$FD/inspect.rc"
check "" "$BAD"
assert_eq "$SCN: calls" "ps inspect" "$(shapes)"
assert_eq "$SCN: no call saw a Docker variable or an existing config path" "2" "$(grep -c 'cfgexisted=no DC=unset DH=unset DX=unset$' "$FD/calls.log")"

sc "environment: unset beforehand, clean run"
SENT=0
put_ps "$A"
put_inspect "$(rec "$A" '[]')"
check "" ok

sc "environment: unset beforehand, Find-Readers throws after its first call"
SENT=0
put_ps "$A"
echo 1 >"$FD/inspect.rc"
check "" "$BAD"

# --- the config path -----------------------------------------------------------------------

sc "config path appears during ps"
NEWGUID="$FIXED_GUID"
EXPECT_NEWDIR="$FIXED_GUID"
echo ps >"$FD/create-on"
check "" "$EXISTS"
assert_eq "$SCN: calls" "ps" "$(shapes)"

sc "config path appears during inspect"
NEWGUID="$FIXED_GUID"
EXPECT_NEWDIR="$FIXED_GUID"
echo inspect >"$FD/create-on"
put_ps "$A"
put_inspect "$(rec "$A" '[]')"
check "" "$EXISTS"
assert_eq "$SCN: calls" "ps inspect" "$(shapes)"

sc "config path already there"
NEWGUID="$FIXED_GUID"
mkdir -p "$TMPD/$FIXED_GUID"
check "" "$EXISTS"
assert_eq "$SCN: no call was made" "" "$(shapes)"

# --- bind hits -----------------------------------------------------------------------------

for src in \
  'C:\Users\Tester\.CONFIG\603id-identity\admin' \
  'c:/users/tester/.config/603id-identity/admin' \
  'C:\Users/tester\.config/603id-identity/admin' \
  '/run/desktop/mnt/host/c/Users/Tester/.config/603id-identity/admin' \
  '/host_mnt/C/users/tester/.config/603id-identity/admin' \
  '/mnt/host/c/Users/tester/.Config/603id-identity/admin'; do
  sc "bind inside the identity home: $src"
  one "$src"
  check "$(hit "$A" bind "$IH")" "$THROW1"
done
sc "bind equal to the identity home"
one "$IH"
check "$(hit "$A" bind "$IH")" "$THROW1"
sc "bind inside the snapshot folder"
one "$SN"'\01-file.yml'
check "$(hit "$A" bind "$SN")" "$THROW1"
for src in 'C:\Users\tester' 'C:\Users' "C:\\" 'C:/' \
  '/run/desktop/mnt/host/c' '/run/desktop/mnt/host/c/' '/host_mnt/c' '/host_mnt/c/' '/mnt/host/c' '/mnt/host/C/'; do
  sc "bind that is an ancestor of both folders: $src"
  one "$src"
  check "$(hit "$A" bind "$IH")"$'\n'"$(hit "$A" bind "$SN")" "$THROW2"
done

# --- no hit ------------------------------------------------------------------------------

for src in 'C:\Users\tester\.config\603id-identity-old' 'C:\Users\tester\AppData\Local\Temp\wow-publish-12345' 'C:\Work\project' 'D:\Users\tester\.config\603id-identity'; do
  sc "no hit: $src"
  one "$src"
  check "" ok
done

# --- unparsed-source -----------------------------------------------------------------------

for src in '/' '/run' '/run/desktop/mnt/host' '/host_mnt' '/mnt' '/var' '/var/run' '/host_mnt/cc/x' \
  '/run/desktop/mnt/host/wsl/docker-desktop-bind-mounts/Ubuntu/0a1b2c' \
  '/run/desktop/mnt/host/wslg' '/run/desktop/mnt/host/wslg/.X11-unix' \
  '/HOST_MNT/d/data' '/Mnt/Host/c/Work' '/RUN/desktop/mnt/host/c/x' \
  '\\server\share\x' '\\.\C:\x' 'C:' 'C:foo' 'C:\a\.\b' 'C:\a\..\b' 'C:\a\\b' 'C:\a.\b' 'C:\a \b' 'C:\a:b' 'C:\PROGRA~1\x' '/c/Users/tester'; do
  sc "unparsed-source: $src"
  one "$src"
  check "$(hit "$A" unparsed-source '*')" "$THROW1"
done

# --- socket, unknown type, empty source --------------------------------------------------------

sc "socket: bind of /var/run/docker.sock"
one '/var/run/docker.sock'
check "$(hit "$A" socket '*')" "$THROW1"
sc "socket: docker.sock.raw"
one '/var/run/docker.sock.raw'
check "$(hit "$A" socket '*')" "$THROW1"
sc "socket: the docker_engine pipe in mixed case"
one '\\.\pipe\Docker_Engine' npipe
check "$(hit "$A" socket '*')" "$THROW1"
sc "socket: a mount of type image (rule 1 over rule 2)"
one '/var/run/docker.sock' image
check "$(hit "$A" socket '*')" "$THROW1"
sc "npipe with another pipe"
one '\\.\pipe\other' npipe
check "$(hit "$A" unparsed-source '*')" "$THROW1"

sc "unknown-type: image"
one 'C:\Work\p' image
check "$(hit "$A" unknown-type '*')" "$THROW1"
sc "unknown-type: empty Type"
one 'C:\Work\p' ""
check "$(hit "$A" unknown-type '*')" "$THROW1"
sc "unknown-type: no Type key"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt bind 'C:\Work\p' | jq -c 'del(.Type)')]")"
check "$(hit "$A" unknown-type '*')" "$THROW1"

sc "empty-source: bind with an empty Source"
one "" bind
check "$(hit "$A" empty-source '*')" "$THROW1"
sc "empty-source: bind with no Source key"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt bind x | jq -c 'del(.Source)')]")"
check "$(hit "$A" empty-source '*')" "$THROW1"
sc "empty-source: npipe with an empty Source"
one "" npipe
check "$(hit "$A" empty-source '*')" "$THROW1"

# --- settings and tmpfs ------------------------------------------------------------------------

for sv in 'privileged|{"Privileged":true}' 'capadd|{"CapAdd":["SYS_ADMIN"]}' 'pidmode|{"PidMode":"host"}'; do
  sc "settings: ${sv%%|*}"
  put_ps "$A"
  put_inspect "$(rec "$A" '[]' "${sv#*|}")"
  check "$(hit "$A" "${sv%%|*}" '*')" "$THROW1"
done
for hc in '{"CapAdd":null}' '{"CapAdd":[]}' '{"Privileged":false,"PidMode":"","CapAdd":null}'; do
  sc "settings: no line for $hc"
  put_ps "$A"
  put_inspect "$(rec "$A" '[]' "$hc")"
  check "" ok
done
sc "tmpfs is ignored"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt tmpfs "" | jq -c 'del(.Source)')]")"
check "" ok

# --- volumes -----------------------------------------------------------------------------------

volcase() { # description options-json driver expected-hits(newline) result
  sc "volume: $1"
  put_ps "$A"
  put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/v1/_data' v1)]")"
  put_vol v1 "$(vol v1 "$3" "$2")"
  check "$4" "$5"
}
volcase "local, Options null" null local "" ok
volcase "local, empty Options" '{}' local "" ok
sc "volume: local, Options absent"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/v1/_data' v1)]")"
put_vol v1 "$(vol v1 local null | jq -c '.[0] |= del(.Options)')"
check "" ok
IHIN='C:\Users\tester\.config\603id-identity\admin'
volcase "bind-like o=bind inside the identity home" "$(jq -cn --arg d "$IHIN" '{type:"none",o:"bind",device:$d}')" local "$(hit "$A" bind "$IH")" "$THROW1"
volcase "bind-like o=rbind inside the identity home" "$(jq -cn --arg d "$IHIN" '{type:"none",o:"rbind",device:$d}')" local "$(hit "$A" bind "$IH")" "$THROW1"
volcase "bind-like device that is an ancestor of both" '{"type":"none","o":"bind","device":"C:\\Users"}' local "$(hit "$A" bind "$IH")"$'\n'"$(hit "$A" bind "$SN")" "$THROW2"
volcase "bind-like unrelated device" '{"type":"none","o":"bind","device":"C:\\Work\\p"}' local "" ok
volcase "bind-like device that does not parse" '{"type":"none","o":"bind","device":"/var"}' local "$(hit "$A" unparsed-source '*')" "$THROW1"
volcase "o=bind,ro" '{"type":"none","o":"bind,ro","device":"C:\\Work\\p"}' local "$(hit "$A" volume '*')" "$THROW1"
volcase "one extra option key" '{"type":"none","o":"bind","device":"C:\\Work\\p","extra":"x"}' local "$(hit "$A" volume '*')" "$THROW1"
volcase "cifs over the network" "$(jq -cn --arg d "//host/share/$IHIN" '{type:"cifs",o:"addr=10.0.0.1",device:$d}')" local "$(hit "$A" volume '*')" "$THROW1"
volcase "options with no device" '{"type":"none","o":"bind"}' local "$(hit "$A" volume '*')" "$THROW1"
volcase "type other than none" "$(jq -cn --arg d "$IHIN" '{type:"ext4",o:"bind",device:$d}')" local "$(hit "$A" volume '*')" "$THROW1"
volcase "no o" "$(jq -cn --arg d "$IHIN" '{type:"none",device:$d}')" local "$(hit "$A" volume '*')" "$THROW1"
volcase "no type" "$(jq -cn --arg d "$IHIN" '{o:"bind",device:$d}')" local "$(hit "$A" volume '*')" "$THROW1"
volcase "another driver" null other "$(hit "$A" volume '*')" "$THROW1"

# --- several hits ------------------------------------------------------------------------------

sc "two qualifying containers"
put_ps "$A" "$B"
put_inspect "$(rec "$A" "[$(mnt bind "$IH"'\admin')]")" "$(rec "$B" "[$(mnt bind "$IH"'\bin')]")"
check "$(hit "$A" bind "$IH")"$'\n'"$(hit "$B" bind "$IH")" "$THROW2"

sc "one container meeting two criteria"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt bind "$IH"'\admin')]" '{"Privileged":true}')"
check "$(hit "$A" privileged '*')"$'\n'"$(hit "$A" bind "$IH")" "$THROW2"

sc "de-duplication"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt bind "$IH"'\admin'), $(mnt bind /), $(mnt bind "$IH"'\bin'), $(mnt bind /run)]")"
check "$(hit "$A" bind "$IH")"$'\n'"$(hit "$A" unparsed-source '*')" "$THROW2"

# --- non-ASCII ---------------------------------------------------------------------------------

UIH='C:\Users\Zoë\.config\603id-identity'
USN='C:\Users\Zoë\AppData\Local\Temp\wow-publish-1234'
LATIN1_UIH="${UIH/ë/$'\xeb'}"
sc "non-ASCII: a hit found only when docker's output is decoded as UTF-8"
FOLDERS="$UIH|$USN"
one "$UIH"'\admin'
check "reader: $A bind $LATIN1_UIH" "$THROW1"
sc "non-ASCII: Latin-1 restored after a clean run"
FOLDERS="$UIH|$USN"
check "" ok
sc "non-ASCII: Latin-1 restored after Find-Readers throws"
FOLDERS="$UIH|$USN"
put_ps "$A"
echo 1 >"$FD/inspect.rc"
check "" "$BAD"

# --- hostile output ----------------------------------------------------------------------------

sc "hostile (a): canaries in names, labels and an unparsed source"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt bind "$CANARY")]")"
check "$(hit "$A" unparsed-source '*')" "$THROW1"

sc "hostile (b): a ps line that is not an id and holds ESC and reader:"
printf '%s\n' $'\e[31mreader: x' >"$FD/ps.out"
check "" "$BAD"
assert_eq "$SCN: no reader: line" "0" "$(grep -c '^reader:' "$OUT")"
sc "hostile (b): a volume name the check refuses"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/x/_data' "plain${N}marker/")]")"
check "" "$BAD"
assert_eq "$SCN: no volume call" "ps inspect" "$(shapes)"
assert_eq "$SCN: no reader: line" "0" "$(grep -c '^reader:' "$OUT")"

c_inspect() { # description jq-filter-on-the-base-array
  sc "hostile (c): $1"
  put_ps "$A"
  rec "$A" "[$(mnt bind 'C:\Work\p')]" | jq -cs "$2" >"$FD/inspect.out"
  check "" "$BAD"
}
sc "hostile (c): inspect output that is not JSON"
put_ps "$A"
printf 'not json %s\n' "$CANARY" >"$FD/inspect.out"
check "" "$BAD"
sc "hostile (c): two keys that differ only in case"
put_ps "$A"
k1=$(jq -n --arg c "$CANARY" '$c | tojson'); k1=${k1:1:-1}
k2=$(jq -n --arg c "$CANARY" '$c | ascii_upcase | tojson'); k2=${k2:1:-1}
printf '[{"Id":"%s","%s":"%s","%s":"%s","Mounts":[],"HostConfig":{}}]\n' "$A" "$k1" "$k1" "$k2" "$k2" >"$FD/inspect.out"
check "" "$BAD"
c_inspect "Mounts as a string" '.[0].Mounts = "x"'
c_inspect "Mounts null" '.[0].Mounts = null'
c_inspect "HostConfig null" '.[0].HostConfig = null'
c_inspect "a mount Source as an object" '.[0].Mounts[0].Source = {}'
c_inspect "CapAdd as a string" '.[0].HostConfig.CapAdd = "x"'
c_inspect "Privileged as a string" '.[0].HostConfig.Privileged = "true"'
sc "hostile (c): a bare JSON object"
put_ps "$A"
rec "$A" '[]' >"$FD/inspect.out"
check "" "$BAD"
sc "hostile (c): Id as an array holding a listed id and a canary"
put_ps "$A"
rec "$A" '[]' | jq -cs --arg a "$A" --arg c "$CANARY" '.[0].Id = [$a, $c]' >"$FD/inspect.out"
check "" "$BAD"
c_inspect "Id as a number" '.[0].Id = 5'
c_inspect "a record that is not an object" '.[0] = "x"'
c_inspect "a Mounts element that is not an object" '.[0].Mounts = ["x"]'
c_inspect "HostConfig present but not an object" '.[0].HostConfig = "x"'
c_inspect "a mount Type that is not a string" '.[0].Mounts[0].Type = 5'
c_inspect "a mount Name that is not a string" '.[0].Mounts[0].Name = 5'
c_inspect "PidMode as an array holding host" '.[0].HostConfig.PidMode = ["host"]'
c_inspect "a CapAdd element that is not a string" '.[0].HostConfig.CapAdd = [5]'

vc() { # description volume-output-text-or-jq (raw text written as is)
  sc "hostile (c), volume: $1"
  put_ps "$A"
  put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/v1/_data' v1)]")"
  printf '%s\n' "$2" >"$FD/vol-v1.out"
  check "" "$BAD"
}
vc "not JSON" "not json $CANARY"
vc "a bare object" "$(vol v1 local null | jq -c '.[0]')"
vc "an empty list" '[]'
vc "two records" "$(vol v1 local null | jq -c '. + .')"
vc "one record with another name" "$(vol v2 local null)"
vc "Name as an array holding the name asked for" "$(vol v1 local null | jq -c '.[0].Name = ["v1"]')"
vc "Driver missing" "$(vol v1 local null | jq -c '.[0] |= del(.Driver)')"
vc "Driver not a string" "$(vol v1 local null | jq -c '.[0].Driver = 5')"
vc "Options not an object" "$(vol v1 local '"x"')"
vc "an Options value that is an array" "$(vol v1 local '{"device":["x"]}')"
vc "an Options value that is an object" "$(vol v1 local '{"device":{}}')"
vc "a record that is not an object" '["x"]'
sc "hostile (c), volume: a volume mount whose Name is missing"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/v1/_data')]")"
check "" "$BAD"
sc "hostile (c), volume: a volume mount whose Name is null"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/v1/_data' | jq -c '.Name = null')]")"
check "" "$BAD"

# --- folders not in long drive-letter form ----------------------------------------------------

for f in 'C:\Users\PROGRA~1\x' 'foo\bar' '\\srv\share\a' '/run/desktop/mnt/host/c/Users/x' '/host_mnt/c/Users/x' '/mnt/host/c/Users/x'; do
  sc "folder not in form (snapshot): $f"
  FOLDERS="$IH|$f"
  check "" "$FORM"
  assert_eq "$SCN: no call was made" "" "$(shapes)"
done
sc "folder not in form (identity home): 8.3"
FOLDERS='C:\Users\JOHNDO~1\.config\603id-identity|'"$SN"
check "" "$FORM"
assert_eq "$SCN: no call was made" "" "$(shapes)"

# --- the list cannot be built ----------------------------------------------------------------

sc "cannot be built: the Docker CLI path names no file"
DOCKER="$W/fake/none"
check "" "$BAD"
sc "cannot be built: the Docker CLI path names a folder"
DOCKER="$W/fake"
check "" "$BAD"
sc "cannot be built: the Docker CLI path names a symbolic link"
ln -sf "$FAKE" "$W/fake-link"
DOCKER="$W/fake-link"
check "" "$BAD"
sc "cannot be built: TEMP is empty"
TEMP_OVERRIDE=""
check "" "$BAD"
sc "cannot be built: ps exits non-zero"
echo 1 >"$FD/ps.rc"
check "" "$BAD"
sc "cannot be built: ps prints a line that is not an id"
printf '%s\n' "short" >"$FD/ps.out"
check "" "$BAD"
sc "cannot be built: ps prints an uppercase id"
printf '%s\n' "$(printf 'A%.0s' {1..64})" >"$FD/ps.out"
check "" "$BAD"
sc "cannot be built: inspect exits non-zero"
put_ps "$A"
echo 1 >"$FD/inspect.rc"
check "" "$BAD"
sc "cannot be built: inspect prints text that is not JSON"
put_ps "$A"
echo "not json" >"$FD/inspect.out"
check "" "$BAD"
sc "cannot be built: inspect returns one record too few"
put_ps "$A" "$B"
put_inspect "$(rec "$A" '[]')"
check "" "$BAD"
sc "cannot be built: inspect returns one record too many"
put_ps "$A"
put_inspect "$(rec "$A" '[]')" "$(rec "$B" '[]')"
check "" "$BAD"
sc "cannot be built: inspect returns two records with the same Id"
put_ps "$A" "$B"
put_inspect "$(rec "$A" '[]')" "$(rec "$A" '[]')"
check "" "$BAD"
sc "cannot be built: a record whose Id was not listed"
put_ps "$A"
put_inspect "$(rec "$B" '[]')"
check "" "$BAD"
sc "cannot be built: a record lacking Mounts"
put_ps "$A"
put_inspect "$(rec "$A" '[]' | jq -c 'del(.Mounts)')"
check "" "$BAD"
sc "cannot be built: a record lacking HostConfig"
put_ps "$A"
put_inspect "$(rec "$A" '[]' | jq -c 'del(.HostConfig)')"
check "" "$BAD"
sc "cannot be built: the volume inspect exits non-zero"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/v1/_data' v1)]")"
echo 1 >"$FD/vol-v1.rc"
check "" "$BAD"
sc "cannot be built: the volume inspect prints text that is not JSON"
put_ps "$A"
put_inspect "$(rec "$A" "[$(mnt volume '/var/lib/docker/volumes/v1/_data' v1)]")"
echo "not json" >"$FD/vol-v1.out"
check "" "$BAD"

# --- no pwsh -------------------------------------------------------------------------------

mkdir -p "$W/emptybin"
nopwsh_out=$(env PATH="$W/emptybin" "$BASH" "$HERE/reader-search-test.sh" 2>&1)
nopwsh_rc=$?
assert_eq "with no pwsh on PATH the suite exits 1" 1 "$nopwsh_rc"
assert_eq "with no pwsh on PATH the suite says so" "reader-search-test: pwsh is required" "$nopwsh_out"

summary
