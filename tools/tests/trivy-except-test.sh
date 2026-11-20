#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2034
# Offline tests for tools/trivy-except.sh. The script runs against a scratch git repository (the
# TRIVY_EXCEPT_ROOT), with a stub `gh` first on PATH that serves recorded run, jobs, job-log and
# release responses and logs every call. Needs bash, jq, yq (mikefarah), git, awk and GNU date.
#
# Fixtures: tools/tests/fixtures/trivy-except/. The job log of build run 44532588047 is a verbatim
# excerpt of its base group (fetched with the dev token, timestamps included), which fixes the
# format. Every other log is built here by mkjoblog/block from that format and is CONSTRUCTED: its
# first line says so, outside any group. Every case that carries a fixed date pins TRIVY_EXCEPT_TODAY.
set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite trivy-except

SCRIPT="$ROOT_DIR/tools/trivy-except.sh"
FX="$FIXTURES/trivy-except"
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
REALGIT=$(command -v git)

# --- the stub gh ------------------------------------------------------------------------
mkdir -p "$S/bin" "$S/gitwrap"
cat >"$S/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: serves $FIX/{run,jobs,release}.json and $FIX/log.txt; $FIX/<name>.status makes that call fail.
printf 'gh %s\n' "$*" >>"$STUB_LOG"
[ "${1:-}" = api ] || { echo "stub gh: only api is supported" >&2; exit 2; }
shift
esc=0 ep=
for a in "$@"; do
  case $a in
    --allow-escape-sequences) esc=1 ;;
    -*) ;;
    *) ep=$a ;;
  esac
done
case $ep in
  repos/603-Identity/devcontainers/actions/runs/*/jobs | repos/603-Identity/devcontainers/actions/runs/*/jobs\?*) name=jobs ;;
  repos/603-Identity/devcontainers/actions/runs/*) name=run ;;
  repos/603-Identity/devcontainers/actions/jobs/*/logs) name=log ;;
  repos/*/*/releases/latest) name=release ;;
  *) echo "stub gh: unexpected endpoint" >&2; exit 2 ;;
esac
if [ -f "$FIX/$name.status" ]; then echo "gh: HTTP $(cat "$FIX/$name.status")" >&2; exit 1; fi
if [ "$name" = log ]; then
  # real gh refuses a log with terminal escapes unless asked
  [ "$esc" = 1 ] || { echo "the response contains terminal escape sequences; pass --allow-escape-sequences" >&2; exit 1; }
  cat "$FIX/log.txt"
else
  cat "$FIX/$name.json"
fi
STUB
chmod +x "$S/bin/gh"
cat >"$S/gitwrap/git" <<'WRAP'
#!/usr/bin/env bash
# Logging git: one line per call with its arguments and its GIT_* environment, then the real git.
printf 'CALL|%s|%s\n' "$*" "$(env | grep '^GIT_' | sort | tr '\n' ' ')" >>"$GITWRAP_LOG"
exec "$REALGIT" "$@"
WRAP
chmod +x "$S/gitwrap/git"
export REALGIT

# --- the scratch repository -------------------------------------------------------------
# Stand-ins for the two Dockerfiles carry only the ARG lines the script reads, so no case depends on
# the live pins. History on `trunk`: T0 (no ARGs), T1 (older pins), T2 (the pins below). HEAD is on
# `lane` (T2 plus L1, a lane commit); `side` is T2 plus S1, reachable from neither.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_AUTHOR_DATE='2026-11-01T00:00:00Z' GIT_COMMITTER_DATE='2026-11-01T00:00:00Z'
gt() { "$REALGIT" -C "$S/tmpl" "$@"; }
mkdir -p "$S/tmpl/images/base" "$S/tmpl/images/tofu"
"$REALGIT" init -q -b trunk "$S/tmpl"
printf 'FROM scratch\n' >"$S/tmpl/images/base/Dockerfile"; cp "$S/tmpl/images/base/Dockerfile" "$S/tmpl/images/tofu/Dockerfile"
gt add -A; gt commit -q -m T0; T0=$(gt rev-parse HEAD)
write_dockerfiles() { # write_dockerfiles gh yq uv tofu tflint
  printf 'FROM scratch\nARG GH_VERSION=%s\nARG YQ_VERSION=%s\nARG UV_VERSION=%s\n' "$1" "$2" "$3" >"$S/tmpl/images/base/Dockerfile"
  printf 'FROM scratch\nARG TOFU_VERSION=%s\nARG TFLINT_VERSION=%s\n' "$4" "$5" >"$S/tmpl/images/tofu/Dockerfile"
}
write_dockerfiles 2.104.0 4.54.2 0.13.7 1.13.8 0.65.0; gt add -A; gt commit -q -m T1; T1=$(gt rev-parse HEAD)
write_dockerfiles 2.105.0 4.54.3 0.13.8 1.13.9 0.66.0; gt add -A; gt commit -q -m T2; T2=$(gt rev-parse HEAD)
gt checkout -q -b side; echo s >"$S/tmpl/s.txt"; gt add -A; gt commit -q -m S1; S1=$(gt rev-parse HEAD)
gt checkout -q trunk; gt checkout -q -b lane; echo l >"$S/tmpl/l.txt"; gt add -A; gt commit -q -m L1; L1=$(gt rev-parse HEAD)

IGN_DEFAULT='# header
vulnerabilities:
  - id: CVE-2026-56864
    paths: ["usr/local/bin/tofu"]
    statement: "HIGH or CRITICAL in golang.org/x/mod v0.39.0 compiled into upstream tofu 1.13.9; no fixed upstream release."
    expired_at: 2026-12-17
  - id: CVE-2026-78661
    paths: ["usr/local/bin/betterleaks"]
    statement: "x"
    expired_at: 2026-12-17
'
RUN=44559619691
JOB_ID=135589525128
YQ_ST='HIGH or CRITICAL in stdlib v1.27.3 compiled into upstream yq 4.54.3; no fixed upstream release.'

# --- log builders (constructed fixtures) ------------------------------------------------
TS=2026-11-19T13:24:06.8111239Z
HDR_DEFAULT='Library|Vulnerability|Severity|Status|Installed Version|Fixed Version|Title'
TOP='┌─────────┬────────────────┬──────────┬────────┬───────────────────┬─────────────────┬───────┐'
SEP='├─────────┼────────────────┼──────────┼────────┼───────────────────┼─────────────────┼───────┤'
BOT='└─────────┴────────────────┴──────────┴────────┴───────────────────┴─────────────────┴───────┘'
vrow() { # vrow a|b|c...: a Trivy-style row
  local out='│' f r=$1'|'
  while [ -n "$r" ]; do f=${r%%|*}; r=${r#*|}; out+=" $f │"; done
  printf '%s\n' "$out"
}
block() { # block PATH TYPE ROW...  (ROW is lib|cve|ver|title; BLK_HDR and BLK_NOBOTTOM adjust it)
  local p=$1 ty=$2 n=$(($# - 2)) r first=1 line
  shift 2
  printf '\n%s (%s)\n' "$p" "$ty"
  line=$(printf '=%.0s' $(seq 1 $((${#p} + ${#ty} + 3)))); printf '%s\n' "$line"
  printf 'Total: %s (HIGH: %s, CRITICAL: 0)\n\n' "$n" "$n"
  printf '%s\n' "$TOP"
  [ "${BLK_NOHDR:-0}" = 1 ] || { vrow "${BLK_HDR:-$HDR_DEFAULT}"; printf '%s\n' "$SEP"; }
  for r in "$@"; do
    [ "$first" = 1 ] || printf '%s\n' "$SEP"
    first=0
    local lib=${r%%|*} rest=${r#*|}
    local cve=${rest%%|*}; rest=${rest#*|}
    local ver=${rest%%|*} title=${rest#*|}
    vrow "$lib|$cve|HIGH|fixed|$ver|9.9.9|$title"
  done
  [ "${BLK_NOBOTTOM:-0}" = 1 ] || printf '%s\n' "$BOT"
}
mkjoblog() { { echo "constructed fixture, not a real log"; cat; } | sed "s/^/$TS /" >"$FIX/log.txt"; }
yqlog() { { echo '##[group]base'; block usr/local/bin/yq gobinary 'stdlib|CVE-2026-97054|v1.27.3|t'; } | mkjoblog; }

# --- cases ------------------------------------------------------------------------------
declare -a ENVX=()
new_case() {
  C=$(mktemp -d -p "$S"); FIX=$C/fix; mkdir "$FIX"; STUBLOG=$C/calls.log; : >"$STUBLOG"
  cp -a "$S/tmpl" "$C/repo"; IGN=$C/repo/.trivyignore.yaml
  printf '%s' "$IGN_DEFAULT" >"$IGN"; cp "$IGN" "$C/ign.orig"
  D_ROOT=$C/repo D_REF=trunk D_TODAY=2026-11-19 ENVX=()
  jq -n --arg sha "$T2" '{path:".github/workflows/build.yml",event:"push",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"failure",head_repository:{full_name:"603-Identity/devcontainers"}}' >"$FIX/run.json"
  jq -n --argjson id "$JOB_ID" '{jobs:[{id:$id,name:"Build, test, push and attest",conclusion:"failure"},{id:1,name:"Did the push change an image?",conclusion:"skipped"}]}' >"$FIX/jobs.json"
  echo '{"tag_name":"v4.54.3"}' >"$FIX/release.json"
  yqlog
}
mut() { jq "$2" "$FIX/$1.json" >"$FIX/$1.tmp" && mv "$FIX/$1.tmp" "$FIX/$1.json"; } # mut run|jobs|release <filter>
run_s() { # run_s args...: sets RC; stdout in $C/out, stderr in $C/err
  local -a e=(PATH="$S/bin:$PATH" FIX="$FIX" STUB_LOG="$STUBLOG")
  [ "$D_ROOT" = @unset ] || e+=(TRIVY_EXCEPT_ROOT="$D_ROOT")
  [ "$D_REF" = @unset ] || e+=(TRIVY_EXCEPT_MAIN_REF="$D_REF")
  [ "$D_TODAY" = @unset ] || e+=(TRIVY_EXCEPT_TODAY="$D_TODAY")
  LS0=$(ls -A "$(dirname "$IGN")")
  RC=0
  env -u TRIVY_EXCEPT_ROOT -u TRIVY_EXCEPT_MAIN_REF -u TRIVY_EXCEPT_TODAY -u TRIVY_EXCEPT_FILE "${e[@]}" ${ENVX[@]+"${ENVX[@]}"} \
    bash "${SCRIPT_UNDER_TEST:-$SCRIPT}" "$@" >"$C/out" 2>"$C/err" || RC=$?
  LS1=$(ls -A "$(dirname "$IGN")")
}
ncalls() { grep -c '^gh ' "$STUBLOG" || true; }
unchanged() { cmp -s "$IGN" "$C/ign.orig"; }
entry() { # entry ID PATHS-FLOW STATEMENT EXPIRY
  printf '  - id: %s\n    paths: [%s]\n    statement: "%s"\n    expired_at: %s\n' "$1" "$2" "$3" "$4"
}
YQ_ENTRY=$(entry CVE-2026-97054 '"usr/local/bin/yq"' "$YQ_ST" 2026-12-17)
accepted() { # accepted <name> <expected entry text...>: exit 0 and the file is the original plus the entries, byte for byte
  local name=$1 want
  shift
  want=$(cat "$C/ign.orig"; printf '%s\n' "$@")
  assert_rc "$name" 0 "$RC"
  if [ "$(cat "$IGN"; echo x)" = "$(printf '%s\nx\n' "$want")" ]; then pass; else fail "$name: file bytes" "$(diff <(printf '%s\n' "$want") "$IGN" | head -5)"; fi
}
refused() { # refused <name> [stderr substring]: exit 1, file and directory unchanged, one reason line
  assert_rc "$1" 1 "$RC"
  if unchanged && [ "$LS0" = "$LS1" ]; then pass; else fail "$1: the ignore file or its directory changed"; fi
  assert_eq "$1: one stderr line" 1 "$(wc -l <"$C/err" | tr -d ' ')"
  [ -z "${2:-}" ] || { if grep -qF -- "$2" "$C/err"; then pass; else fail "$1: stderr lacks '$2'" "$(cat "$C/err")"; fi; }
}
usage() { # usage <name>: exit 2, nothing touched, no gh call
  assert_rc "$1" 2 "$RC"
  if unchanged && [ "$LS0" = "$LS1" ]; then pass; else fail "$1: changed something"; fi
  assert_eq "$1: no gh call" 0 "$(ncalls)"
}
GOOD=("$RUN" base CVE-2026-97054 usr/local/bin/yq)

# ===== accepted ==============================================================================
new_case; run_s "${GOOD[@]}"
accepted "yq finding, shared expiry taken" "$YQ_ENTRY"
sed -e "s/@HEAD@/$T2/" -e "s/@MAIN@/$T2/" "$FX/expected-stdout.tmpl" >"$C/want-out"
if cmp -s "$C/want-out" "$C/out"; then pass; else fail "yq finding: standard output bytes" "$(diff "$C/want-out" "$C/out" | head -5)"; fi

for ev in push schedule workflow_dispatch; do
  new_case; mut run ".event=\"$ev\""; run_s "${GOOD[@]}"
  accepted "yq finding from a $ev run" "$YQ_ENTRY"
  assert_eq "$ev run: event printed" "event: $ev" "$(grep '^event:' "$C/out")"
done

# the #625 case: the verbatim excerpt under a constructed main-run response, the ignore file as it was before #628
new_case; cp "$FX/run-44532588047-base-group.log" "$FIX/log.txt"
cp "$FX/trivyignore-before-628.yaml" "$IGN"; cp "$IGN" "$C/ign.orig"
D_TODAY=2026-11-19; run_s 44532588047 base CVE-2026-97054 usr/local/bin/yq
accepted "#625 case: verbatim excerpt of run 44532588047" "$YQ_ENTRY"
# the entry #625 adds, in id, paths and expired_at (literal, so a later renewal cannot break the case)
assert_eq "#625 case: id, paths, expired_at" "CVE-2026-97054|usr/local/bin/yq|2026-12-17" "$(yq -r '.vulnerabilities[-1] | [.id, (.paths | join(",")), (.expired_at | tostring)] | join("|")' "$IGN")"

# two targets in one group, the right target's row picked
new_case; { echo '##[group]base'; block usr/local/bin/uv rustbinary 'liba|CVE-2026-97054|v1.0.0|t'; block usr/local/bin/uvx rustbinary 'libb|CVE-2026-97054|v2.0.0|t'; } | mkjoblog
echo '{"tag_name":"0.13.8"}' >"$FIX/release.json"; run_s "$RUN" base CVE-2026-97054 usr/local/bin/uvx
accepted "uvx row picked, tag without v" "$(entry CVE-2026-97054 '"usr/local/bin/uvx"' 'HIGH or CRITICAL in libb v2.0.0 compiled into upstream uvx 0.13.8; no fixed upstream release.' 2026-12-17)"
new_case; { echo '##[group]base'; block usr/local/bin/uv rustbinary 'liba|CVE-2026-97054|v1.0.0|t'; block usr/local/bin/uvx rustbinary 'libb|CVE-2026-97054|v2.0.0|t'; } | mkjoblog
echo '{"tag_name":"0.13.8"}' >"$FIX/release.json"; run_s "$RUN" base CVE-2026-97054 usr/local/bin/uv
accepted "uv row picked" "$(entry CVE-2026-97054 '"usr/local/bin/uv"' 'HIGH or CRITICAL in liba v1.0.0 compiled into upstream uv 0.13.8; no fixed upstream release.' 2026-12-17)"

# one CVE failing both uv and uvx in the same group: a uv run, then a uvx run against its result
new_case; { echo '##[group]base'; block usr/local/bin/uv rustbinary 'liba|CVE-2026-97054|v1.0.0|t'; block usr/local/bin/uvx rustbinary 'liba|CVE-2026-97054|v1.0.0|t'; } | mkjoblog
echo '{"tag_name":"0.13.8"}' >"$FIX/release.json"
run_s "$RUN" base CVE-2026-97054 usr/local/bin/uv; rc1=$RC
run_s "$RUN" base CVE-2026-97054 usr/local/bin/uvx
assert_rc "uv then uvx: first run" 0 "$rc1"
accepted "uv then uvx: both entries" \
  "$(entry CVE-2026-97054 '"usr/local/bin/uv"' 'HIGH or CRITICAL in liba v1.0.0 compiled into upstream uv 0.13.8; no fixed upstream release.' 2026-12-17)" \
  "$(entry CVE-2026-97054 '"usr/local/bin/uvx"' 'HIGH or CRITICAL in liba v1.0.0 compiled into upstream uv 0.13.8; no fixed upstream release.' 2026-12-17 | sed 's/upstream uv /upstream uvx /')"

# MAIN_REF unset (origin/main), and TRIVY_EXCEPT_ROOT unset with the script inside the scratch repository
new_case; "$REALGIT" -C "$C/repo" update-ref refs/remotes/origin/main "$T2"; D_REF=@unset; run_s "${GOOD[@]}"
accepted "main ref unset: origin/main" "$YQ_ENTRY"
assert_eq "main ref unset: the output names origin/main" "main ref: origin/main $T2" "$(grep '^main ref:' "$C/out")"
new_case; mkdir "$C/repo/tools"; cp "$SCRIPT" "$C/repo/tools/trivy-except.sh"; D_ROOT=@unset; SCRIPT_UNDER_TEST=$C/repo/tools/trivy-except.sh; run_s "${GOOD[@]}"; unset SCRIPT_UNDER_TEST
accepted "root unset: the repository above the script" "$YQ_ENTRY"

# gh, both paths in the entry
GH2='"usr/local/bin/gh", "usr/local/libexec/gh-real"'
new_case; { echo '##[group]base'; block usr/local/bin/gh gobinary 'stdlib|CVE-2026-97054|v1.27.3|t'; } | mkjoblog; echo '{"tag_name":"v2.105.0"}' >"$FIX/release.json"
run_s "$RUN" base CVE-2026-97054 usr/local/bin/gh
accepted "gh finding in the base group" "$(entry CVE-2026-97054 "$GH2" 'HIGH or CRITICAL in stdlib v1.27.3 compiled into upstream gh 2.105.0; no fixed upstream release.' 2026-12-17)"
new_case; { echo '##[group]devapp'; block usr/local/libexec/gh-real gobinary 'stdlib|CVE-2026-97054|v1.27.3|t'; } | mkjoblog; echo '{"tag_name":"v2.105.0"}' >"$FIX/release.json"
run_s "$RUN" devapp CVE-2026-97054 usr/local/libexec/gh-real
accepted "gh-real finding in the devapp group" "$(entry CVE-2026-97054 "$GH2" 'HIGH or CRITICAL in stdlib v1.27.3 compiled into upstream gh 2.105.0; no fixed upstream release.' 2026-12-17)"

# tofu after a complete base group, the pin from the tofu Dockerfile
new_case; { echo '##[group]base'; block usr/local/bin/yq gobinary 'stdlib|CVE-2026-0001|v1.0.0|t'; echo '##[endgroup]'; echo '##[group]tofu'; block usr/local/bin/tofu gobinary 'golang.org/x/net|CVE-2026-97054|v0.57.0|t'; } | mkjoblog
echo '{"tag_name":"v1.13.9"}' >"$FIX/release.json"; run_s "$RUN" tofu CVE-2026-97054 usr/local/bin/tofu
accepted "tofu finding after a complete base group" "$(entry CVE-2026-97054 '"usr/local/bin/tofu"' 'HIGH or CRITICAL in golang.org/x/net v0.57.0 compiled into upstream tofu 1.13.9; no fixed upstream release.' 2026-12-17)"

# merged cells, row-separator lines, a wrapped title: the second CVE takes library and version from the row above
new_case; { echo '##[group]base'; block usr/local/bin/yq gobinary 'github.com/foo/bar|CVE-2026-1111|v1.2.3|first' '||v1.2.3|wrapped title' '|CVE-2026-97054||second' '|||wrapped again'; } | mkjoblog
run_s "$RUN" base CVE-2026-97054 usr/local/bin/yq
accepted "merged library and version cell" "$(entry CVE-2026-97054 '"usr/local/bin/yq"' 'HIGH or CRITICAL in github.com/foo/bar v1.2.3 compiled into upstream yq 4.54.3; no fixed upstream release.' 2026-12-17)"

# a group that runs to the end of the log (the default fixture), and an underscore in a library name
new_case; { echo '##[group]base'; block usr/local/bin/yq gobinary 'github.com/foo_bar/baz|CVE-2026-97054|v1.2.3|t'; } | mkjoblog; run_s "${GOOD[@]}"
accepted "a library name with an underscore" "$(entry CVE-2026-97054 '"usr/local/bin/yq"' 'HIGH or CRITICAL in github.com/foo_bar/baz v1.2.3 compiled into upstream yq 4.54.3; no fixed upstream release.' 2026-12-17)"

# an empty list, both forms, taking today plus 30 days
for form in 'vulnerabilities:' 'vulnerabilities: []'; do
  new_case; printf '# header\n%s\n' "$form" >"$IGN"; cp "$IGN" "$C/ign.orig"; run_s "${GOOD[@]}"
  assert_rc "empty list '$form'" 0 "$RC"
  want=$(printf '# header\nvulnerabilities:\n'; entry CVE-2026-97054 '"usr/local/bin/yq"' "$YQ_ST" 2026-12-19)
  if [ "$(cat "$IGN"; echo x)" = "$(printf '%s\nx\n' "$want")" ]; then pass; else fail "empty list '$form': file bytes" "$(cat "$IGN")"; fi
done

# an existing entry with the same id but only another tool's path
new_case; printf 'vulnerabilities:\n  - id: CVE-2026-97054\n    paths: ["usr/local/bin/tofu"]\n    statement: "x"\n    expired_at: 2026-12-17\n' >"$IGN"; cp "$IGN" "$C/ign.orig"; run_s "${GOOD[@]}"
accepted "same id, another tool's path" "$YQ_ENTRY"
# a shared expiry of tomorrow is taken as it is
new_case; printf 'vulnerabilities:\n  - id: CVE-2026-1\n    paths: ["usr/local/bin/tofu"]\n    statement: "x"\n    expired_at: 2026-11-20\n' >"$IGN"; cp "$IGN" "$C/ign.orig"; run_s "${GOOD[@]}"
accepted "shared expiry of tomorrow" "$(entry CVE-2026-97054 '"usr/local/bin/yq"' "$YQ_ST" 2026-11-20)"
# --dry-run prints the entry and leaves the file alone
new_case; run_s --dry-run "${GOOD[@]}"
assert_rc "dry run" 0 "$RC"
if unchanged && [ "$LS0" = "$LS1" ]; then pass; else fail "dry run changed the file or directory"; fi
assert_eq "dry run: the entry is printed" "$YQ_ENTRY" "$(head -4 "$C/out")"
# TRIVY_EXCEPT_FILE outside the root
new_case; cp "$IGN" "$C/other.yaml"; ENVX=(TRIVY_EXCEPT_FILE="$C/other.yaml"); run_s "${GOOD[@]}"
assert_rc "ignore file outside the root" 0 "$RC"
assert_eq "ignore file outside the root: the root's own file is untouched" yes "$(unchanged && echo yes || echo no)"
if [ "$(cat "$C/other.yaml"; echo x)" = "$(printf '%s%s\nx\n' "$IGN_DEFAULT" "$YQ_ENTRY")" ]; then pass; else fail "ignore file outside the root: the other file's bytes"; fi

# ===== usage errors (exit 2) =================================================================
for bad in 0 abc 012 123456789012345678901 ''; do new_case; run_s "$bad" base CVE-2026-97054 usr/local/bin/yq; usage "malformed run id '$bad'"; done
new_case; run_s "$RUN" node2 CVE-2026-97054 usr/local/bin/yq; usage "unknown flavour"
for bad in GHSA-xxxx-xxxx-xxxx CVE-26-1 cve-2026-97054 'CVE-2026-97054;x' CVE-2026-123456789; do new_case; run_s "$RUN" base "$bad" usr/local/bin/yq; usage "malformed CVE '$bad'"; done
for bad in usr/bin/x 'usr/local/bin/yq ' /usr/local/bin/yq usr/local/bin/yqq; do new_case; run_s "$RUN" base CVE-2026-97054 "$bad"; usage "path outside the table '$bad'"; done
new_case; run_s "$RUN" base CVE-2026-97054; usage "argument count three"
new_case; run_s "$RUN" base CVE-2026-97054 usr/local/bin/yq extra; usage "argument count five"
new_case; run_s --wat "${GOOD[@]}"; usage "unknown option"
new_case; run_s -x "${GOOD[@]}"; usage "unknown short option"
new_case; D_TODAY=tomorrow; run_s "${GOOD[@]}"; usage "malformed TRIVY_EXCEPT_TODAY"
new_case; D_TODAY=2026-02-30; run_s "${GOOD[@]}"; usage "unreal TRIVY_EXCEPT_TODAY"
new_case; D_TODAY=''; run_s "${GOOD[@]}"; usage "empty TRIVY_EXCEPT_TODAY"
new_case; D_REF=''; run_s "${GOOD[@]}"; usage "empty TRIVY_EXCEPT_MAIN_REF"
new_case; D_REF=-x; run_s "${GOOD[@]}"; usage "TRIVY_EXCEPT_MAIN_REF starting with '-'"
new_case; run_s "$RUN" base CVE-2026-97054 usr/local/bin/betterleaks; usage "path outside the table (betterleaks)"
assert_eq "betterleaks: stderr names the by-hand route" yes "$(grep -q 'Adding an exception' "$C/err" && echo yes || echo no)"

# ===== not a main run ========================================================================
nmr() { # nmr <name>: exit 1, 'not a main run' first on stderr, only the run call made
  refused "$1" "not a main run"
  assert_eq "$1: starts with the words" "not a main run" "$(cut -c1-14 "$C/err")"
  assert_eq "$1: only the run call" 1 "$(ncalls)"
}
new_case; mut run '.event="pull_request" | .head_branch="fix/377-x"'; run_s "${GOOD[@]}"; nmr "a pull_request run"
new_case; mut run '.head_branch="feature"'; run_s "${GOOD[@]}"; nmr "a push run on another branch"
new_case; mut run '.event="workflow_run"'; run_s "${GOOD[@]}"; nmr "a workflow_run run"
new_case; mut run '.event="pull_request" | .head_branch="x" | .status="in_progress" | .head_sha="ZZ" | .head_repository.full_name="fork/devcontainers"'; run_s "${GOOD[@]}"; nmr "a fork-headed in-progress pull_request run with a bad head_sha"
new_case; mut run '.path=".github/workflows/lint.yml"'; run_s "${GOOD[@]}"; refused "workflow path is not build.yml (main run)" "not a build.yml run"
new_case; mut run '.path=".github/workflows/lint.yml" | .event="pull_request" | .head_branch="x"'; run_s "${GOOD[@]}"; refused "workflow path is not build.yml (pull_request run)" "not a build.yml run"
new_case; mut run '.head_repository.full_name="fork/devcontainers"'; run_s "${GOOD[@]}"; refused "fork-headed main run" "head repository"
new_case; mut run '.status="in_progress"'; run_s "${GOOD[@]}"; refused "run not completed"
new_case; mut run '.conclusion="success"'; run_s "${GOOD[@]}"; refused "run concluded success"

# ===== API shapes ============================================================================
new_case; echo 'not json' >"$FIX/run.json"; run_s "${GOOD[@]}"; refused "run response not JSON" "run"
new_case; mut run 'del(.head_branch)'; run_s "${GOOD[@]}"; refused "head_branch missing" "run"
new_case; mut run '.head_repository=null'; run_s "${GOOD[@]}"; refused "head_repository null" "run"
new_case; mut jobs 'del(.jobs[0].conclusion)'; run_s "${GOOD[@]}"; refused "job with no conclusion" "jobs"
new_case; echo 'not json' >"$FIX/release.json"; run_s "${GOOD[@]}"; refused "release not JSON" "release"
new_case; echo '{"tag_name":null}' >"$FIX/release.json"; run_s "${GOOD[@]}"; refused "release tag_name null" "release"
new_case; mut run '.head_sha="ABCDEF0123456789ABCDEF0123456789ABCDEF01"'; run_s "${GOOD[@]}"; refused "head_sha not lowercase hex"
assert_eq "bad head_sha: no gh call after the run" 1 "$(ncalls)"
new_case; mut run '.head_sha="abc123"'; run_s "${GOOD[@]}"; refused "head_sha too short"
new_case; mut jobs '.jobs[0].id="12;ab"'; run_s "${GOOD[@]}"; refused "job id not digits"
assert_eq "bad job id: no gh call after the jobs call" 2 "$(ncalls)"
for call in run jobs log release; do
  new_case; echo 403 >"$FIX/$call.status"; run_s "${GOOD[@]}"
  refused "gh call '$call' refused (403)" "$( [ "$call" = log ] && echo 'job log' || echo "$call")"
done
assert_eq "the log call passes --allow-escape-sequences" yes "$(new_case; run_s "${GOOD[@]}"; grep -q -- '--allow-escape-sequences' "$STUBLOG" && echo yes || echo no)"

# ===== ancestry and the checkout =============================================================
new_case; mut run ".head_sha=\"$S1\""; run_s "${GOOD[@]}"; refused "head commit not reachable from the main ref" "not reachable"
new_case; mut run ".head_sha=\"$L1\""; run_s "${GOOD[@]}"; refused "head commit is a lane commit (an ancestor of HEAD, not of the main ref)" "not reachable"
new_case; mut run '.head_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'; run_s "${GOOD[@]}"; refused "head commit the checkout does not have" "not in the checkout"
new_case; D_REF=nope; run_s "${GOOD[@]}"; refused "main ref that does not resolve" "does not resolve"
new_case; mkdir "$C/plain"; D_ROOT=$C/plain; run_s "${GOOD[@]}"; refused "root that is not a git repository" "not a git repository"
new_case; echo "$T1" >"$C/repo/.git/shallow"; run_s "${GOOD[@]}"; refused "shallow root" "shallow"
new_case; printf '%s %s\n' "$T2" "$T1" >"$C/repo/.git/info/grafts"; run_s "${GOOD[@]}"; refused "root with a grafts file" "grafts"
new_case; "$REALGIT" -C "$C/repo" worktree add -q -b wtb "$C/wt" trunk; printf '%s %s\n' "$T2" "$T1" >"$C/repo/.git/info/grafts"; D_ROOT=$C/wt; run_s "${GOOD[@]}"
refused "linked worktree, grafts file in the common git directory" "grafts"
new_case; "$REALGIT" -C "$C/repo" config extensions.partialClone origin; run_s "${GOOD[@]}"; refused "partial clone" "partial"
REPL=$("$REALGIT" -C "$S/tmpl" commit-tree "$T2^{tree}" -p "$T1" -p "$S1" -m replacement)
new_case; "$REALGIT" -C "$C/repo" update-ref "refs/replace/$T2" "$REPL"; mut run ".head_sha=\"$S1\""; run_s "${GOOD[@]}"; refused "a replace ref that would make the head look reachable" "not reachable"

# each redirecting git variable, set in turn, with an unreachable head, still refused as unreachable
mkdir "$S/other"; cp -a "$S/tmpl/." "$S/other/"; "$REALGIT" -C "$S/other" branch -qf trunk "$S1"
printf '%s %s %s\n' "$T2" "$T1" "$S1" >"$S/grafts"
printf '[core]\n\tcommitGraph = true\n' >"$S/gitconfig"
for kv in "GIT_DIR=$S/other/.git" "GIT_WORK_TREE=$S/other" "GIT_COMMON_DIR=$S/other/.git" "GIT_INDEX_FILE=$S/idx" \
  "GIT_OBJECT_DIRECTORY=$S/other/.git/objects" "GIT_ALTERNATE_OBJECT_DIRECTORIES=$S/other/.git/objects" "GIT_GRAFT_FILE=$S/grafts" \
  "GIT_REPLACE_REF_BASE=refs/ns/" "GIT_NAMESPACE=ns" "GIT_CONFIG_PARAMETERS='core.useReplaceRefs=true'" "GIT_CONFIG_COUNT=1" \
  "GIT_CONFIG_GLOBAL=$S/gitconfig" "GIT_CONFIG_SYSTEM=$S/gitconfig" "GIT_CONFIG_NOSYSTEM=1" "GIT_EXEC_PATH=/nonexistent" "GIT_TEST_COMMIT_GRAPH=1"; do
  new_case; mut run ".head_sha=\"$S1\""
  "$REALGIT" -C "$C/repo" update-ref "refs/ns/$T2" "$REPL"; "$REALGIT" -C "$C/repo" update-ref "refs/replace/$T2" "$REPL"
  ENVX=("$kv"); [ "${kv%%=*}" != GIT_CONFIG_COUNT ] || ENVX=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.useReplaceRefs GIT_CONFIG_VALUE_0=true)
  run_s "${GOOD[@]}"; refused "variable ${kv%%=*} set, head unreachable" "not reachable"
done
# a logging git wrapper first on PATH: no call sees a variable from the list, every call carries the hygiene
new_case; export GITWRAP_LOG=$C/git.log; : >"$GITWRAP_LOG"
ENVX=(PATH="$S/gitwrap:$S/bin:$PATH" GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent GIT_COMMON_DIR=/nonexistent GIT_INDEX_FILE=/nonexistent GIT_OBJECT_DIRECTORY=/nonexistent \
  GIT_ALTERNATE_OBJECT_DIRECTORIES=/nonexistent GIT_GRAFT_FILE=/nonexistent GIT_REPLACE_REF_BASE=refs/x/ GIT_NAMESPACE=x GIT_CONFIG_PARAMETERS=x GIT_CONFIG_COUNT=0 GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_EXEC_PATH=/nonexistent GIT_TEST_COMMIT_GRAPH=1)
run_s "${GOOD[@]}"; accepted "git wrapper case still succeeds" "$YQ_ENTRY"
ncall=$(grep -c '^CALL|' "$GITWRAP_LOG")
if [ "$ncall" -gt 0 ]; then pass; else fail "git wrapper: no git call logged"; fi
assert_eq "git wrapper: no call sees a variable from the list" 0 "$(grep -cE '(^|[| ])(GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_GRAFT_FILE|GIT_REPLACE_REF_BASE|GIT_NAMESPACE|GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|GIT_EXEC_PATH|GIT_TEST_COMMIT_GRAPH)=' "$GITWRAP_LOG" || true)"
assert_eq "git wrapper: every call has --no-replace-objects and core.commitGraph=false" "$ncall" "$(grep -c -- '--no-replace-objects -c core.commitGraph=false' "$GITWRAP_LOG" || true)"
assert_eq "git wrapper: every call has GIT_NO_REPLACE_OBJECTS=1" "$ncall" "$(grep -c 'GIT_NO_REPLACE_OBJECTS=1' "$GITWRAP_LOG" || true)"
assert_eq "git wrapper: every call has GIT_NO_LAZY_FETCH=1" "$ncall" "$(grep -c 'GIT_NO_LAZY_FETCH=1' "$GITWRAP_LOG" || true)"
unset GITWRAP_LOG

# the pin at the head commit
new_case; mut run ".head_sha=\"$T1\""; run_s "${GOOD[@]}"; refused "pin at the head commit differs from the root's" "differs"
new_case; mut run ".head_sha=\"$T0\""; run_s "${GOOD[@]}"; refused "Dockerfile at the head commit has no such ARG" "head commit has no"
new_case; sed -i '/YQ_VERSION/d' "$C/repo/images/base/Dockerfile"; run_s "${GOOD[@]}"; refused "root Dockerfile has no such ARG" "root's Dockerfile has no"
new_case; echo '{"tag_name":"v4.55.0"}' >"$FIX/release.json"; run_s "${GOOD[@]}"; refused "pin behind the latest release" "latest upstream release"

# ===== jobs ==================================================================================
new_case; mut jobs '.jobs=[{"id":2,"name":"Build and smoke-test (no push)","conclusion":"failure"}]'; run_s "${GOOD[@]}"; refused "no job named Build, test, push and attest" "exactly one job"
new_case; mut jobs '.jobs += [{"id":3,"name":"Build, test, push and attest","conclusion":"failure"}]'; run_s "${GOOD[@]}"; refused "two such jobs" "exactly one job"
new_case; mut jobs '.jobs[0].conclusion="success" | .jobs[1].conclusion="failure"'; run_s "${GOOD[@]}"; refused "such job did not fail" "did not fail"

# ===== the log ===============================================================================
LOGROW='stdlib|CVE-2026-97054|v1.27.3|t'
logcase() { # logcase <name> <reason substring> ; body on stdin
  new_case; mkjoblog; run_s "${GOOD[@]}"; refused "$1" "$2"
}
{ block usr/local/bin/yq gobinary "$LOGROW"; } | logcase "no group line for the flavour" "group line"
{ echo '##[group]base'; block usr/local/bin/yq gobinary "$LOGROW"; echo '##[endgroup]'; echo '##[group]base'; } | logcase "group line twice" "more than once"
{ echo '##[group]devapp-tofu'; block usr/local/bin/yq gobinary "$LOGROW"; } | { new_case; mkjoblog; run_s "$RUN" devapp CVE-2026-97054 usr/local/bin/yq; refused "devapp against a log with only devapp-tofu" "group line"; }
{ echo '##[group]base'; echo '##[endgroup]'; block usr/local/bin/yq gobinary "$LOGROW"; } | logcase "CVE row after the group's endgroup" "no target line"
{ echo '##[group]base'; block usr/local/bin/yq gobinary 'x|CVE-2026-1|v1.0.0|t' | head -4; echo '##[group]other'; block usr/local/bin/yq gobinary "$LOGROW" | tail -n +5; } | logcase "CVE row after the next group line, no endgroup" "group end"
{ echo '##[group]base'; block usr/local/bin/yq gobinary 'x|CVE-2026-1|v1.0.0|t'; block usr/local/bin/uv rustbinary "$LOGROW"; } | logcase "CVE row only under the next target" "no row for the id"
{ echo '##[group]base'; block usr/local/bin/yq gobinary 'x|CVE-2026-1|v1.0.0|t' | head -3; echo 'some other line'; block usr/local/bin/yq gobinary "$LOGROW" | tail -n +4; } | logcase "a stray line between the target line and its table" "unexpected line"
{ echo '##[group]base'; printf '\nusr/local/bin/yq (gobinary)\n===========================\n'; block usr/local/bin/uv rustbinary "$LOGROW"; } | logcase "a target with no table" "unexpected line"
{ echo '##[group]base'; BLK_NOBOTTOM=1 block usr/local/bin/yq gobinary "$LOGROW"; block usr/local/bin/uv rustbinary 'x|CVE-2026-1|v1.0.0|t'; } | logcase "table with no bottom border before the next target line" "no bottom border"
{ echo '##[group]base'; BLK_NOBOTTOM=1 block usr/local/bin/yq gobinary "$LOGROW"; } | logcase "table with no bottom border before the group's end" "no bottom border"
{ echo '##[group]base'; block usr/local/bin/yq gobinary 'stdlib|CVE-2026-97054||t'; } | logcase "first data row with an empty Installed Version" "Installed Version"
{ echo '##[group]base'; block usr/local/bin/yq gobinary '|CVE-2026-97054|v1.27.3|t'; } | logcase "first data row with an empty Library" "Library"
{ echo '##[group]base'; BLK_NOHDR=1 block usr/local/bin/yq gobinary "$LOGROW"; } | logcase "table with no header row" "header"
{ echo '##[group]base'; BLK_HDR='Library|Vulnerability|Severity|Status|Fixed Version|Title' block usr/local/bin/yq gobinary "$LOGROW"; } | logcase "header lacking Installed Version" "header"
{ echo '##[group]base'; BLK_HDR='Library|Library|Vulnerability|Installed Version' block usr/local/bin/yq gobinary "$LOGROW"; } | logcase "header repeating Library" "header"
{ echo '##[group]base'; block usr/local/bin/yq gobinary 'stdlib|CVE-2026-1|v1.27.3|t'; } | logcase "no matching row" "no row for the id"
{ echo '##[group]base'; block usr/local/bin/yq gobinary "$LOGROW" 'stdlib|CVE-2026-97054|v1.27.3|t'; } | logcase "two matching rows" "more than one row"
{ echo '##[group]tofu'; block usr/local/bin/yq gobinary "$LOGROW"; echo '##[endgroup]'; echo '##[group]base'; block usr/local/bin/yq gobinary 'stdlib|CVE-2026-1|v1.0.0|t'; } | logcase "CVE only in another flavour's group" "no row for the id"
{ echo '##[group]base'; block usr/local/bin/yq gobinary "$LOGROW"; block usr/local/bin/yq gobinary "$LOGROW"; } | logcase "target line twice in the group" "more than once"
for bad in 'a"b' 'a\b' 'a:b' 'a#b' 'a b'; do
  { echo '##[group]base'; block usr/local/bin/yq gobinary "$bad|CVE-2026-97054|v1.27.3|t"; } | logcase "library with '$bad'" "library"
  { echo '##[group]base'; block usr/local/bin/yq gobinary "stdlib|CVE-2026-97054|v1$bad|t"; } | logcase "version with '$bad'" "version"
done

# ===== the ignore file =======================================================================
igncase() { # igncase <name> <reason> <file text>
  new_case; printf '%b' "$3" >"$IGN"; cp "$IGN" "$C/ign.orig"; run_s "${GOOD[@]}"; refused "$1" "$2"
}
new_case; rm "$IGN"; run_s "${GOOD[@]}"; assert_rc "missing ignore file" 1 "$RC"; assert_eq "missing ignore file: one line" 1 "$(wc -l <"$C/err" | tr -d ' ')"
igncase "unparseable ignore file" "parse" 'vulnerabilities: [\n'
igncase "vulnerabilities absent" "vulnerabilities" 'foo: bar\n'
igncase "vulnerabilities not last" "last" 'vulnerabilities:\n  - id: CVE-1\n    paths: ["x"]\n    statement: "x"\n    expired_at: 2026-12-17\nother: 1\n'
igncase "same id with the path among others" "already covers" 'vulnerabilities:\n  - id: CVE-2026-97054\n    paths: ["usr/local/bin/tofu", "usr/local/bin/yq"]\n    statement: "x"\n    expired_at: 2026-12-17\n'
igncase "an entry with no expired_at" "expired_at" 'vulnerabilities:\n  - id: CVE-1\n    paths: ["x"]\n    statement: "x"\n'
igncase "two distinct expired_at values" "more than one" 'vulnerabilities:\n  - id: CVE-1\n    paths: ["x"]\n    statement: "x"\n    expired_at: 2026-12-17\n  - id: CVE-2\n    paths: ["y"]\n    statement: "x"\n    expired_at: 2026-12-18\n'
igncase "shared expiry of today" "today or earlier" 'vulnerabilities:\n  - id: CVE-1\n    paths: ["x"]\n    statement: "x"\n    expired_at: 2026-11-19\n'
igncase "shared expiry already past" "today or earlier" 'vulnerabilities:\n  - id: CVE-1\n    paths: ["x"]\n    statement: "x"\n    expired_at: 2026-11-01\n'
igncase "shared expiry not a real date" "real date" 'vulnerabilities:\n  - id: CVE-1\n    paths: ["x"]\n    statement: "x"\n    expired_at: "2026-02-30"\n'
igncase "entries indented other than two spaces (the write check)" "written copy" 'vulnerabilities:\n    - id: CVE-1\n      paths: ["x"]\n      statement: "x"\n      expired_at: 2026-12-17\n'
igncase "YAML anchors" "anchors" 'vulnerabilities:\n  - &a\n    id: CVE-1\n    paths: ["x"]\n    statement: "x"\n    expired_at: 2026-12-17\n'
# the gh entry whose paths list holds only the other gh path still counts as the same binary
new_case; { echo '##[group]base'; block usr/local/bin/gh gobinary "$LOGROW"; } | mkjoblog; echo '{"tag_name":"v2.105.0"}' >"$FIX/release.json"
printf 'vulnerabilities:\n  - id: CVE-2026-97054\n    paths: ["usr/local/libexec/gh-real"]\n    statement: "x"\n    expired_at: 2026-12-17\n' >"$IGN"; cp "$IGN" "$C/ign.orig"
run_s "$RUN" base CVE-2026-97054 usr/local/bin/gh; refused "same id, only the other gh path" "already covers"
# after a write-check failure no copy is left behind (checked through the directory listing in `refused`)
new_case; printf 'vulnerabilities:\n    - id: CVE-1\n      paths: ["x"]\n      statement: "x"\n      expired_at: 2026-12-17\n' >"$IGN"; cp "$IGN" "$C/ign.orig"; run_s "${GOOD[@]}"
assert_eq "write-check failure: no copy left" "$LS0" "$LS1"

summary
