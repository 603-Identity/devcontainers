#!/usr/bin/env bash
# Writes one `.trivyignore.yaml` exception entry from a failing `build.yml` run on `main`
# (docs/trivy-renewal.md, "Adding an exception"). It reads the run, its jobs and the failing job's
# log with `gh api`, finds the finding in the flavour's Trivy table, checks that the tool's pin is
# the latest upstream release, and appends one entry in the existing layout.
#
# Usage:      tools/trivy-except.sh [--dry-run] RUN_ID FLAVOUR CVE PATH
#
#   RUN_ID   a failing `build.yml` run on `main` (a push, schedule or workflow_dispatch run)
#   FLAVOUR  base, tofu, node, devapp or devapp-tofu: the group of the job log whose scan failed
#   CVE      a CVE id (GHSA and GO ids are written by hand, under the same rules)
#   PATH     one in-image path of a binary in the script's table (gh, yq, uv, uvx, tofu, tflint)
#   --dry-run  does every check, prints the entry and the lines below, and writes nothing
#
# A `main` run's head commit must be reachable from `main`: checked against the main ref's commit (`origin/main` unless the test override `TRIVY_EXCEPT_MAIN_REF` names another; never fetched by the script), which the script prints for the code owner to confirm.
#
#   TRIVY_EXCEPT_ROOT       the git checkout it reads the Dockerfiles, the default ignore file and the
#                           ancestry from (default: the repo root above this script); tests only
#   TRIVY_EXCEPT_MAIN_REF   the ref in that checkout the ancestry check is made against (default
#                           origin/main); it exists so the suite can name a scratch branch
#   TRIVY_EXCEPT_FILE       the ignore file (default: .trivyignore.yaml under TRIVY_EXCEPT_ROOT)
#   TRIVY_EXCEPT_TODAY      overrides today (YYYY-MM-DD, a real date); tests only
#
# Exit status:
#   0  the entry was written (or, with --dry-run, would be)
#   1  every other refusal or failure, with one reason line on stderr; the ignore file is untouched
#   2  a usage error, before any gh call and touching nothing: the argument count, an unknown option,
#      a malformed argument, a path outside the table, a bad TRIVY_EXCEPT_TODAY, or an empty
#      TRIVY_EXCEPT_MAIN_REF or one starting with `-`
#
# It never fetches, never edits or removes an existing entry, never edits the header and writes no
# other file. The repo is the fixed string below. It needs gh (Actions runs, jobs and job logs of
# this repo, and the tools' upstream releases), git, jq, yq (mikefarah), awk and GNU date. Nothing
# read from the log is evaluated, and only fields cut to a fixed shape reach the file.
# These checks are self-attested by the lane that runs the script: the control of record is the
# code owner's check of the run on GitHub before approving.
set -euo pipefail
export LC_ALL=C

REPO=603-Identity/devcontainers
JOB_NAME='Build, test, push and attest'

usage_error() { echo "trivy-except: $1" >&2; exit 2; }
refuse() { echo "$1" >&2; exit 1; }

DRY=0
if [ "${1-}" = --dry-run ]; then DRY=1; shift; fi
case ${1-} in -*) usage_error "unknown option" ;; esac
[ "$#" -eq 4 ] || usage_error "usage: trivy-except.sh [--dry-run] RUN_ID FLAVOUR CVE PATH"
RUN_ID=$1 FLAVOUR=$2 CVE=$3 TPATH=$4

[[ $RUN_ID =~ ^[1-9][0-9]{0,19}$ ]] || usage_error "RUN_ID is not a run id"
case $FLAVOUR in base | tofu | node | devapp | devapp-tofu) ;; *) usage_error "FLAVOUR is not one of base, tofu, node, devapp, devapp-tofu" ;; esac
[[ $CVE =~ ^CVE-[0-9]{4}-[0-9]{4,7}$ ]] || usage_error "CVE is not a CVE id (other ids are written by hand: docs/trivy-renewal.md, Adding an exception)"

# The table: path -> the binary's paths (all of them), its word, Dockerfile, ARG and upstream repo.
case $TPATH in
  usr/local/bin/gh | usr/local/libexec/gh-real)
    TPATHS=(usr/local/bin/gh usr/local/libexec/gh-real) WORD=gh DOCKERFILE=images/base/Dockerfile ARGNAME=GH_VERSION UPSTREAM=cli/cli ;;
  usr/local/bin/yq)
    TPATHS=(usr/local/bin/yq) WORD=yq DOCKERFILE=images/base/Dockerfile ARGNAME=YQ_VERSION UPSTREAM=mikefarah/yq ;;
  usr/local/bin/uv)
    TPATHS=(usr/local/bin/uv) WORD=uv DOCKERFILE=images/base/Dockerfile ARGNAME=UV_VERSION UPSTREAM=astral-sh/uv ;;
  usr/local/bin/uvx)
    TPATHS=(usr/local/bin/uvx) WORD=uvx DOCKERFILE=images/base/Dockerfile ARGNAME=UV_VERSION UPSTREAM=astral-sh/uv ;;
  usr/local/bin/tofu)
    TPATHS=(usr/local/bin/tofu) WORD=tofu DOCKERFILE=images/tofu/Dockerfile ARGNAME=TOFU_VERSION UPSTREAM=opentofu/opentofu ;;
  usr/local/bin/tflint)
    TPATHS=(usr/local/bin/tflint) WORD=tflint DOCKERFILE=images/tofu/Dockerfile ARGNAME=TFLINT_VERSION UPSTREAM=terraform-linters/tflint ;;
  *) usage_error "PATH is not in the table: write the entry by hand under docs/trivy-renewal.md, Adding an exception" ;;
esac

DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
real_date() { # real_date <text>: succeeds for a real YYYY-MM-DD calendar date
  local d=$1
  [[ $d =~ $DATE_RE ]] || return 1
  [ "$(date -u -d "$d" +%F 2>/dev/null)" = "$d" ]
}
if [ -n "${TRIVY_EXCEPT_TODAY+x}" ]; then
  today=$TRIVY_EXCEPT_TODAY
  real_date "$today" || usage_error "TRIVY_EXCEPT_TODAY is not a real YYYY-MM-DD date"
else
  today=$(date -u +%F)
fi
if [ -n "${TRIVY_EXCEPT_MAIN_REF+x}" ]; then
  case $TRIVY_EXCEPT_MAIN_REF in '' | -*) usage_error "TRIVY_EXCEPT_MAIN_REF is empty or starts with '-'" ;; esac
fi
MAINREF=${TRIVY_EXCEPT_MAIN_REF-origin/main}

# --- git hygiene (defence in depth; the printed commit and the code owner's check are the control)
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NAMESPACE \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
  GIT_EXEC_PATH GIT_TEST_COMMIT_GRAPH
export GIT_NO_REPLACE_OBJECTS=1 GIT_NO_LAZY_FETCH=1

ROOT=${TRIVY_EXCEPT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
[ -d "$ROOT" ] || refuse "the root is not a directory"
ROOT=$(cd "$ROOT" && pwd -P)
g() { git --no-replace-objects -c core.commitGraph=false -C "$ROOT" "$@"; }

top=$(g rev-parse --show-toplevel 2>/dev/null) || refuse "the root is not a git repository"
[ "$top" = "$ROOT" ] || refuse "the root is not the top of a git repository"
[ "$(g rev-parse --is-shallow-repository 2>/dev/null)" = false ] || refuse "the root is a shallow checkout"
graft=$(g rev-parse --git-path info/grafts 2>/dev/null) || refuse "cannot locate the grafts file"
case $graft in /*) ;; *) graft=$ROOT/$graft ;; esac
[ ! -e "$graft" ] || refuse "the root has a grafts file"
[ -z "$(g config --get extensions.partialClone 2>/dev/null || true)" ] || refuse "the root is a partial clone"

MAINSHA=$(g rev-parse --verify --end-of-options "${MAINREF}^{commit}" 2>/dev/null) || refuse "the main ref does not resolve"
[[ $MAINSHA =~ ^[0-9a-f]{40}$ ]] || refuse "the main ref did not resolve to a commit"

T=$(mktemp -d)
COPY=
cleanup() { rm -rf "$T"; [ -z "$COPY" ] || rm -f "$COPY"; }
trap cleanup EXIT

# gh api, with the call named on failure. Output goes to a file; a failed call is a refusal.
ghget() { # ghget <name> <outfile> <gh api args...>
  local name=$1 out=$2
  shift 2
  gh api "$@" >"$out" 2>/dev/null || refuse "gh call failed or was refused: $name"
}
jfield() { # jfield <file> <name> <jq path>: a non-null string or number field, else a refusal
  local v
  v=$(jq -er "$3 | select(type == \"string\" or type == \"number\") | tostring" "$1" 2>/dev/null) || v=
  [ -n "$v" ] || refuse "missing field $3 in $2"
  printf '%s' "$v"
}
expect() { # expect <file> <name> <jq path> <want> <reason>: the field equals the value, else a refusal
  local v
  v=$(jfield "$1" "$2" "$3")
  [ "$v" = "$4" ] || refuse "$5"
}
isjson() { jq -e . "$1" >/dev/null 2>&1 || refuse "$2 did not return JSON"; }

# --- the run
ghget "run" "$T/run.json" "repos/$REPO/actions/runs/$RUN_ID"
isjson "$T/run.json" "run"
expect "$T/run.json" run .path .github/workflows/build.yml "the run is not a build.yml run"
event=$(jfield "$T/run.json" run .event)
case $event in
  push | schedule | workflow_dispatch) ;;
  *) refuse "not a main run: its event is not push, schedule or workflow_dispatch" ;;
esac
expect "$T/run.json" run .head_branch main "not a main run: its head_branch is not main"
expect "$T/run.json" run .head_repository.full_name "$REPO" "the run's head repository is not this repo"
expect "$T/run.json" run .status completed "the run has not completed"
expect "$T/run.json" run .conclusion failure "the run did not fail"
HEAD_SHA=$(jfield "$T/run.json" run .head_sha)
[[ $HEAD_SHA =~ ^[0-9a-f]{40}$ ]] || refuse "the run's head_sha is not 40 lowercase hex"
g cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || refuse "the run's head commit is not in the checkout"
rc=0
g merge-base --is-ancestor "$HEAD_SHA" "$MAINSHA" 2>/dev/null || rc=$?
case $rc in
  0) ;;
  1) refuse "the run's head commit is not reachable from the main ref" ;;
  *) refuse "the ancestry check failed" ;;
esac

# the pin named is the pin scanned: the ARG at the head commit equals the working tree's
PIN_RE='^[0-9][A-Za-z0-9.+-]{0,63}$'
arg_value() { # arg_value <dockerfile text on stdin>: the single ARG's value, or empty
  awk -v n="$ARGNAME" 'index($0, "ARG " n "=") == 1 { c++; v = substr($0, length(n) + 6) } END { if (c == 1) print v; else if (c > 1) print "@many" }'
}
head_df=$(g show "${HEAD_SHA}:${DOCKERFILE}" 2>/dev/null) || refuse "the head commit has no $DOCKERFILE"
head_pin=$(printf '%s\n' "$head_df" | arg_value)
[ -n "$head_pin" ] || refuse "the Dockerfile at the head commit has no $ARGNAME"
[ -f "$ROOT/$DOCKERFILE" ] || refuse "the root has no $DOCKERFILE"
pin=$(arg_value <"$ROOT/$DOCKERFILE")
[ -n "$pin" ] || refuse "the root's Dockerfile has no $ARGNAME"
[ "$head_pin" != @many ] && [ "$pin" != @many ] || refuse "$ARGNAME is declared more than once"
[ "$head_pin" = "$pin" ] || refuse "the pin at the head commit differs from the root's"
[[ $pin =~ $PIN_RE ]] || refuse "the pin is not a plain version"

# --- the job and its log
ghget "jobs" "$T/jobs.json" "repos/$REPO/actions/runs/$RUN_ID/jobs?per_page=100"
isjson "$T/jobs.json" "jobs"
jq -e '.jobs | type == "array"' "$T/jobs.json" >/dev/null 2>&1 || refuse "missing field .jobs in jobs"
njobs=$(jq -r --arg n "$JOB_NAME" '[.jobs[] | select(.name == $n)] | length' "$T/jobs.json" 2>/dev/null) || refuse "the jobs response is malformed"
[ "$njobs" = 1 ] || refuse "the run does not have exactly one job named $JOB_NAME"
jq --arg n "$JOB_NAME" '[.jobs[] | select(.name == $n)][0]' "$T/jobs.json" >"$T/job.json"
expect "$T/job.json" jobs .conclusion failure "the $JOB_NAME job did not fail"
JOB_ID=$(jfield "$T/job.json" jobs .id)
[[ $JOB_ID =~ ^[1-9][0-9]{0,19}$ ]] || refuse "the job id is not digits"
# --allow-escape-sequences: gh refuses a log holding terminal escapes (the real build log has some outside the scan group)
ghget "job log" "$T/log.txt" --allow-escape-sequences "repos/$REPO/actions/jobs/$JOB_ID/logs"

# Parse contract: the awk program below is the contract. The log is untrusted text and nothing from it is evaluated.
parsed=$(awk -v flav="$FLAVOUR" -v path="$TPATH" -v cve="$CVE" '
function trim(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
function fail(msg) { print "refuse"; print msg; exit 0 }
function istarget(l,   t) {
  if (index(l, path " (") != 1 || substr(l, length(l)) != ")") return 0
  t = substr(l, length(path) + 3, length(l) - length(path) - 3)
  return length(t) > 0 && t !~ /[ ()]/
}
function isborder(l,   i) { for (i = 1; i <= nb; i++) if (index(l, B[i])) return 1; return 0 }
function cells(l, c,   rest, n, p) {
  rest = substr(l, 4); n = 0
  while ((p = index(rest, V)) > 0) { c[++n] = trim(substr(rest, 1, p - 1)); rest = substr(rest, p + 3) }
  return n
}
BEGIN {
  V = "\342\224\202"; TL = "\342\224\214"; BL = "\342\224\224"; TJ = "\342\224\234"
  nb = split("\342\224\214 \342\224\254 \342\224\220 \342\224\234 \342\224\274 \342\224\244 \342\224\224 \342\224\264 \342\224\230 \342\224\200", B, " ")
}
{
  line = $0
  sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]+Z /, "", line)
  if (line == "##[group]" flav) { groups++; ing = 1; next }
  if (substr(line, 1, 9) == "##[group]" || line == "##[endgroup]") { ing = 0; next }
  if (ing) G[++n] = line
}
END {
  if (groups == 0) fail("the log has no group line for the flavour")
  if (groups > 1) fail("the log has the flavour group line more than once")
  tc = 0
  for (i = 1; i <= n; i++) if (istarget(G[i])) { tc++; ti = i }
  if (tc == 0) fail("the flavour group has no target line for the path")
  if (tc > 1) fail("the target line appears more than once in the group")
  top = 0
  for (j = ti + 1; ; j++) {
    if (j > n) fail("no table border between the target line and the group end")
    l = G[j]
    if (substr(l, 1, 3) == TL) { top = j; break }
    if (l ~ /^=+$/ || l ~ /^Total: / || l == "") continue
    fail("an unexpected line between the target line and its table")
  }
  bot = 0; hdr = 0; havel = 0; havev = 0; m = 0
  for (k = top + 1; k <= n; k++) {
    l = G[k]
    if (substr(l, 1, 3) == BL) { bot = k; break }
    if (substr(l, 1, 3) != V && substr(l, 1, 3) != TJ) fail("the target table has no bottom border before the next target line")
    if (isborder(l)) continue
    nc = cells(l, c)
    if (!hdr) {
      hdr = 1
      for (x = 1; x <= nc; x++) {
        if (c[x] == "Library") { lc++; lcol = x }
        else if (c[x] == "Vulnerability") { vc++; vcol = x }
        else if (c[x] == "Installed Version") { ic++; icol = x }
      }
      if (lc != 1 || vc != 1 || ic != 1) fail("the table header lacks or repeats Library, Vulnerability or Installed Version")
      continue
    }
    vuln = (vcol <= nc) ? c[vcol] : ""
    if (vuln == "") continue
    lib = (lcol <= nc) ? c[lcol] : ""
    ver = (icol <= nc) ? c[icol] : ""
    if (lib == "") { if (!havel) fail("the first data row has an empty Library cell"); lib = lastl }
    if (ver == "") { if (!havev) fail("the first data row has an empty Installed Version cell"); ver = lastv }
    lastl = lib; havel = 1; lastv = ver; havev = 1
    if (vuln == cve) { m++; ml = lib; mv = ver }
  }
  if (!bot) fail("the target table has no bottom border before the group end")
  if (!hdr) fail("the target table has no header row")
  if (m == 0) fail("no row for the id under the target")
  if (m > 1) fail("more than one row for the id under the target")
  print "ok"; print ml; print mv
}' "$T/log.txt") || refuse "the log could not be parsed"
mapfile -t P <<<"$parsed"
[ "${P[0]-}" = ok ] || refuse "the log: ${P[1]:-unparseable}"
LIB=${P[1]} VER=${P[2]}
[[ $LIB =~ ^[A-Za-z0-9][A-Za-z0-9._~/_-]{0,255}$ ]] || refuse "the library name in the log has an unexpected shape"
[[ $VER =~ ^v?[0-9]+(\.[0-9]+){1,3}[A-Za-z0-9.+-]{0,64}$ ]] || refuse "the installed version in the log has an unexpected shape"

# --- the pin is the latest upstream release
ghget "release" "$T/rel.json" "repos/$UPSTREAM/releases/latest"
isjson "$T/rel.json" "release"
tag=$(jfield "$T/rel.json" release .tag_name)
latest=${tag#v}
[[ $latest =~ $PIN_RE ]] || refuse "the latest release tag is not a plain version"
[ "$latest" = "$pin" ] || refuse "the pin is not the latest upstream release (re-pinning is its own task)"

# --- the ignore file
FILE=${TRIVY_EXCEPT_FILE:-$ROOT/.trivyignore.yaml}
[ -f "$FILE" ] || refuse "the ignore file is missing"
yq -e '.' "$FILE" >/dev/null 2>&1 || refuse "yq cannot parse the ignore file"
[ "$(yq -r '[.. | select(anchor != "" or tag == "!!merge" or kind == "alias")] | length' "$FILE")" = 0 ] || refuse "the ignore file uses anchors, aliases or merge keys"
[ "$(yq -r 'has("vulnerabilities")' "$FILE")" = true ] || refuse "the ignore file has no vulnerabilities key"
[ "$(yq -r 'keys | .[-1]' "$FILE")" = vulnerabilities ] || refuse "vulnerabilities is not the last top-level key"
case $(yq -r '.vulnerabilities | tag' "$FILE") in '!!null' | '!!seq') ;; *) refuse "vulnerabilities is not a list" ;; esac
nentries=$(yq -r '(.vulnerabilities // []) | length' "$FILE")
export CVE_ID=$CVE
for tp in "${TPATHS[@]}"; do
  export TP=$tp
  [ "$(yq -r '[(.vulnerabilities // [])[] | select(.id == strenv(CVE_ID)) | (.paths // [])[] | select(. == strenv(TP))] | length' "$FILE")" = 0 ] \
    || refuse "an entry for this id already covers a path of this binary"
done
[ "$(yq -r '[(.vulnerabilities // [])[] | select(((.expired_at // "") | tostring) == "")] | length' "$FILE")" = 0 ] || refuse "an entry has no expired_at"
[ "$(yq -r '[(.vulnerabilities // [])[] | .expired_at | tostring] | unique | length' "$FILE")" -le 1 ] || refuse "the entries carry more than one expired_at"
if [ "$nentries" -eq 0 ]; then
  EXPIRY=$(date -u -d "$today + 30 days" +%F)
else
  EXPIRY=$(yq -r '.vulnerabilities[0].expired_at | tostring' "$FILE")
  real_date "$EXPIRY" || refuse "the shared expired_at is not a real date"
  if [[ $EXPIRY < $today || $EXPIRY == "$today" ]]; then refuse "the shared expired_at is today or earlier (a lapsed file is the maintainer's decision)"; fi
fi

# --- the entry, and the copy-check-rename write
paths_flow=
for tp in "${TPATHS[@]}"; do paths_flow+="${paths_flow:+, }\"$tp\""; done
STATEMENT="HIGH or CRITICAL in $LIB $VER compiled into upstream $WORD $pin; no fixed upstream release."
ENTRY="  - id: $CVE
    paths: [$paths_flow]
    statement: \"$STATEMENT\"
    expired_at: $EXPIRY"

if [ "$DRY" -eq 1 ]; then copydir=$T; else copydir=$(dirname "$FILE"); fi
COPY=$(mktemp "$copydir/.trivy-except.XXXXXX") || refuse "cannot make a copy next to the ignore file"
cp -p "$FILE" "$COPY"
if [ "$nentries" -eq 0 ] && grep -qx 'vulnerabilities: \[\]' "$COPY"; then
  sed -i 's/^vulnerabilities: \[\]$/vulnerabilities:/' "$COPY"
fi
[ -z "$(tail -c1 "$COPY")" ] || printf '\n' >>"$COPY"
printf '%s\n' "$ENTRY" >>"$COPY"

yq -e '.' "$COPY" >/dev/null 2>&1 || refuse "the written copy does not parse"
[ "$(yq -r '.vulnerabilities | length' "$COPY")" = $((nentries + 1)) ] || refuse "the written copy does not have exactly one more entry"
export WANT_PATHS WANT_STATEMENT=$STATEMENT WANT_EXPIRY=$EXPIRY
WANT_PATHS=$(printf '%s\n' "${TPATHS[@]}")
got=$(yq -r '.vulnerabilities[-1] | [.id, (.paths | join("|")), .statement, (.expired_at | tostring)] | join("\n")' "$COPY") || refuse "the written copy does not parse"
want=$(printf '%s\n%s\n%s\n%s' "$CVE" "$(printf '%s' "$WANT_PATHS" | tr '\n' '|')" "$STATEMENT" "$EXPIRY")
[ "$got" = "$want" ] || refuse "the last entry of the written copy is not the intended one"
[ "$(yq -r '.vulnerabilities[-1].paths | length' "$COPY")" = "${#TPATHS[@]}" ] || refuse "the last entry of the written copy is not the intended one"

if [ "$DRY" -eq 0 ]; then
  mv -f "$COPY" "$FILE"
  COPY=
fi

printf '%s\n' "$ENTRY"
echo "run: $RUN_ID"
echo "event: $event"
echo "head: $HEAD_SHA"
echo "job: $JOB_NAME ($JOB_ID)"
echo "main ref: $MAINREF $MAINSHA"
