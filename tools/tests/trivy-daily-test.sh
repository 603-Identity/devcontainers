#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Offline tests for .github/scripts/trivy-daily.sh and the shape of trivy-daily.yml. Every scenario
# runs the real script against fake `curl`, `docker` and `gh` executables first on PATH in a scratch
# directory, each logging its calls; no network. Modelled on trivy-evidence-test.sh.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite trivy-daily

SRC="$ROOT_DIR/.github/scripts/trivy-daily.sh"
WF="$ROOT_DIR/.github/workflows/trivy-daily.yml"
MARK=SECRETMARKER
REPO=603-Identity/devcontainers
RUN=5550001
BOT="github-actions[bot]"
SHA_A=$(printf 'a%.0s' $(seq 64))
SHA_B=$(printf 'b%.0s' $(seq 64))
# The exact Trivy image and template, held here as their own constants (not read from the script).
TRIVY_IMG="aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969"
TEMPLATE='{{range .}}{{$t := .Target}}{{range .Vulnerabilities}}vuln{{"\t"}}{{.VulnerabilityID}}{{"\t"}}{{.PkgName}}{{"\t"}}{{.InstalledVersion}}{{"\t"}}{{.FixedVersion}}{{"\t"}}{{if .PkgPath}}{{.PkgPath}}{{else}}{{$t}}{{end}}{{"\n"}}{{end}}{{range .Secrets}}secret{{"\t"}}{{.RuleID}}{{"\t"}}{{$t}}{{"\n"}}{{end}}{{end}}'
FLAVORS=(base tofu node devapp devapp-tofu)

# --- the fake executables ------------------------------------------------------------------------

write_fakes() { # writes $S/bin/{curl,docker,gh}
  local b="$S/bin"
  mkdir -p "$b"
  cat >"$b/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl. Serves $DA_FIX; logs every call.
printf 'curl %s\n' "$*" >>"$DA_LOG"
[ -z "${DA_NOISE:-}" ] || { echo "$DA_NOISE"; echo "$DA_NOISE" >&2; }
url= hdr= head=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
    https://*) url=${args[i]} ;;
    -D) hdr=${args[i + 1]} ;;
    -*I*) [[ ${args[i]} == -fsSI || ${args[i]} == -I ]] && head=1 ;;
  esac
done
case $url in https://ghcr.io/*) ;; *) echo "request to $url" >>"$DA_STATE/violations"; exit 22 ;; esac
case $url in
  https://ghcr.io/token\?scope=repository:603-identity/*:pull)
    echo '{"token":"tok123"}' ;;
  https://ghcr.io/v2/603-identity/*/tags/list*)
    name=${url#https://ghcr.io/v2/603-identity/}; name=${name%%/*}
    page=1; case $url in *page=2*) page=2 ;; esac
    [ -f "$DA_FIX/tags.$name.$page" ] || exit 22
    cat "$DA_FIX/tags.$name.$page"
    if [ -n "$hdr" ]; then
      if [ -f "$DA_FIX/link.$name.$page" ]; then printf 'Link: %s\r\n' "$(cat "$DA_FIX/link.$name.$page")" >"$hdr"; else : >"$hdr"; fi
    fi ;;
  https://ghcr.io/v2/603-identity/*/manifests/*)
    name=${url#https://ghcr.io/v2/603-identity/}; name=${name%%/*}
    [ "$head" = 1 ] || exit 22
    if [ -f "$DA_FIX/digest.$name" ]; then printf 'HTTP/2 200\r\nDocker-Content-Digest: %s\r\n' "$(cat "$DA_FIX/digest.$name")"; else printf 'HTTP/2 200\r\n'; fi ;;
  *) exit 22 ;;
esac
EOF
  cat >"$b/docker" <<'EOF'
#!/usr/bin/env bash
# Fake docker. Logs every call; the DA_* variables choose what it does.
printf 'docker %s\n' "$*" >>"$DA_LOG"
[ -z "${DA_NOISE:-}" ] || { echo "$DA_NOISE"; echo "$DA_NOISE" >&2; }
sub=${1:-}; shift || true
case $sub in
  pull) exit 0 ;;
  save) [ "$1" = -o ] || exit 99; echo tar >"$2"; echo "$2" >>"$DA_STATE/tars"; exit 0 ;;
  rmi) exit 0 ;;
  run)
    tar=
    for a in "$@"; do case $a in *:/scan/image.tar:ro) tar=${a%:/scan/image.tar:ro} ;; esac; done
    [ -f "$tar" ] || { echo "scan of a missing tar" >>"$DA_STATE/violations"; exit 99; }
    echo "present $tar" >>"$DA_STATE/seen"
    f=${tar##*/}; f=${f%.tar}
    [ "${DA_TRIVY_RC:-0}" = 0 ] || exit "$DA_TRIVY_RC"
    [ ! -f "$DA_FIX/scan.$f" ] || cat "$DA_FIX/scan.$f"
    exit 0 ;;
  *) echo "unexpected docker $sub" >>"$DA_STATE/violations"; exit 99 ;;
esac
EOF
  cat >"$b/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh. Serves $DA_FIX; logs every call; saves each POST body.
printf 'gh %s\n' "$*" >>"$DA_LOG"
[ -z "${DA_NOISE:-}" ] || { echo "$DA_NOISE"; echo "$DA_NOISE" >&2; }
[ "${1:-}" = api ] || exit 99
shift
method=GET path=
while [ "$#" -gt 0 ]; do
  case $1 in
    --method) method=$2; shift ;;
    --input | --jq) shift ;;
    --paginate) ;;
    *) path=$1 ;;
  esac
  shift
done
if [ "$method" = POST ]; then
  [ "${DA_POST_FAIL:-}" != 1 ] || exit 1
  n=$(($(cat "$DA_STATE/posts" 2>/dev/null || echo 0) + 1)); echo "$n" >"$DA_STATE/posts"
  cat >"$DA_STATE/post.$n.json"; echo "$path" >"$DA_STATE/post.$n.path"
  case $path in
    */issues) echo "{\"number\": $((900 + n))}" ;;
    *) echo '{"id": 1}' ;;
  esac
  exit 0
fi
case $path in
  repos/*/releases/latest)
    r=${path#repos/}; r=${r%/releases/latest}; r=${r//\//_}
    [ -f "$DA_FIX/rel.$r" ] || exit 1
    cat "$DA_FIX/rel.$r" ;;
  repos/*/issues\?state=open*)
    echo "issues-list $path" >>"$DA_STATE/listings"
    cat "$DA_FIX/issues.1.json" "$DA_FIX/issues.2.json" 2>/dev/null || echo '[]' ;;
  repos/*/issues/*/comments*)
    n=${path#repos/*/issues/}; n=${n%%/*}
    cat "$DA_FIX/comments.$n.1.json" "$DA_FIX/comments.$n.2.json" 2>/dev/null || echo '[]' ;;
  repos/*/issues/*)
    n=${path##*/}
    [ -f "$DA_FIX/issue.$n.json" ] || exit 1
    cat "$DA_FIX/issue.$n.json" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$b/curl" "$b/docker" "$b/gh"
}

new_case() {
  S=$(mktemp -d)
  export DA_FIX="$S/fix" DA_STATE="$S/state" DA_LOG="$S/calls.log"
  mkdir -p "$DA_FIX" "$DA_STATE" "$S/scan"
  : >"$DA_LOG"
  write_fakes
  for v in GITHUB_ENV GITHUB_PATH GITHUB_OUTPUT GITHUB_STEP_SUMMARY; do : >"$S/$v"; done
  unset DA_NOISE DA_TRIVY_RC DA_POST_FAIL
}
end_case() { rm -rf "$S"; }

# run_sub <args...>: sets RC; GITHUB_REPOSITORY and the run id as the workflow has them
run_sub() {
  RC=0
  env PATH="$S/bin:$PATH" GH_TOKEN=test-token GITHUB_REPOSITORY="${REPO_OVERRIDE:-$REPO}" GITHUB_RUN_ID="${RUN_OVERRIDE:-$RUN}" \
    GITHUB_ENV="$S/GITHUB_ENV" GITHUB_PATH="$S/GITHUB_PATH" GITHUB_OUTPUT="$S/GITHUB_OUTPUT" \
    GITHUB_STEP_SUMMARY="$S/GITHUB_STEP_SUMMARY" \
    bash "$SRC" "$@" >"$S/stdout" 2>"$S/stderr" || RC=$?
}

# assert_quiet <description>: nothing scan- or API-derived on stdout, stderr or the GITHUB_* files
assert_quiet() {
  if grep -qF "$MARK" "$S/stderr" "$S/stdout" "$S/GITHUB_ENV" "$S/GITHUB_PATH" "$S/GITHUB_OUTPUT"; then
    fail "$1: a marker reached an output" "$(cat "$S/stderr")"
  else pass; fi
  assert_eq "$1: stdout is empty" "" "$(cat "$S/stdout")"
  assert_eq "$1: GITHUB_ENV is empty" "" "$(cat "$S/GITHUB_ENV")"
  assert_eq "$1: GITHUB_PATH is empty" "" "$(cat "$S/GITHUB_PATH")"
  assert_eq "$1: GITHUB_OUTPUT is empty" "" "$(cat "$S/GITHUB_OUTPUT")"
}
assert_no_violations() { assert_eq "$1 (no fake violation)" "" "$(cat "$DA_STATE/violations" 2>/dev/null || true)"; }
log_n() { grep -cF -- "$1" "$DA_LOG" || true; }

ref_of() { printf 'ghcr.io/603-identity/devcontainer-%s:1.10@sha256:%s' "$1" "${2:-$SHA_A}"; }

# --- resolve -------------------------------------------------------------------------------------

seed_registry() { # default fixtures for the five images
  local f
  for f in "${FLAVORS[@]}"; do
    printf '{"name":"x","tags":["latest","1.9","1.10","1.2","abc","1.10-rc"]}\n' >"$DA_FIX/tags.devcontainer-$f.1"
    printf 'sha256:%s\n' "$SHA_A" >"$DA_FIX/digest.devcontainer-$f"
  done
}
two_pages() { # two_pages <flavor>: the newest numeric tag is on page 2, behind a Link header
  local n=devcontainer-$1
  printf '{"tags":["latest","1.9","2.3"]}\n' >"$DA_FIX/tags.$n.1"
  printf '</v2/603-identity/%s/tags/list?n=200&page=2>; rel="next"\n' "$n" >"$DA_FIX/link.$n.1"
  printf '{"tags":["1.20","2.15","3"]}\n' >"$DA_FIX/tags.$n.2"
}

suite trivy-daily-usage
new_case
run_sub; assert_rc "no subcommand" 2 "$RC"
run_sub frobnicate; assert_rc "unknown subcommand" 2 "$RC"
run_sub resolve; assert_rc "resolve without OUT" 2 "$RC"
run_sub resolve a b; assert_rc "resolve with two arguments" 2 "$RC"
run_sub resolve "$S/nodir/out"; assert_rc "resolve into a missing directory" 2 "$RC"
run_sub scan "$S/refs"; assert_rc "scan with one argument" 2 "$RC"
run_sub scan "$S/missing" "$S/scan"; assert_rc "scan with a missing REFS" 2 "$RC"
: >"$S/refs"
run_sub scan "$S/refs" "$S/nodir"; assert_rc "scan with a missing SCANDIR" 2 "$RC"
run_sub parse "$S/refs" "$S/scan" "$S/f"; assert_rc "parse with three arguments" 2 "$RC"
run_sub parse "$S/missing" "$S/scan" "$S/f" "$S/s"; assert_rc "parse with a missing REFS" 2 "$RC"
run_sub file "$S/f"; assert_rc "file with one argument" 2 "$RC"
run_sub file "$S/missing" "$S/refs"; assert_rc "file with a missing FINDINGS" 2 "$RC"
run_sub file "$S/refs" "$S/missing"; assert_rc "file with a missing SUMMARY" 2 "$RC"
assert_eq "no external call on a usage error" "0" "$(wc -l <"$DA_LOG")"
end_case

suite trivy-daily-resolve
new_case; seed_registry
run_sub resolve "$S/refs.tsv"
assert_rc "resolve" 0 "$RC"
assert_eq "one line per image" "5" "$(wc -l <"$S/refs.tsv")"
assert_eq "the numerically newest tag, not the lexical one" "$(printf 'base\t%s' "$(ref_of base)")" "$(sed -n 1p "$S/refs.tsv")"
assert_eq "the last flavor" "$(printf 'devapp-tofu\t%s' "$(ref_of devapp-tofu)")" "$(sed -n 5p "$S/refs.tsv")"
assert_quiet "resolve"
assert_no_violations "resolve"
assert_eq "the manifest request carries the live-verify Accept header" "5" "$(grep -c 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json' "$DA_LOG")"
end_case

new_case; seed_registry; two_pages base
run_sub resolve "$S/refs.tsv"
assert_rc "resolve across two pages" 0 "$RC"
assert_eq "the newest tag on page two (2.15 over 1.20, 2.3 and the non-numeric 3)" "$(printf 'base\t%s' "$(ref_of base | sed 's/:1.10@/:2.15@/')")" "$(sed -n 1p "$S/refs.tsv")"
assert_eq "page two requested" "1" "$(grep -c 'tags/list?n=200&page=2' "$DA_LOG")"
end_case

new_case; seed_registry
printf '{"tags":["latest","edge","1.9-rc","v2"]}\n' >"$DA_FIX/tags.devcontainer-node.1"
run_sub resolve "$S/refs.tsv"
assert_rc "an image with no numeric tag" 1 "$RC"; assert_quiet "no numeric tag"
assert_eq "nothing written" "no" "$([ -e "$S/refs.tsv" ] && echo yes || echo no)"
end_case

new_case; seed_registry; two_pages base
printf 'https://evil.example/v2/603-identity/devcontainer-base/tags/list?n=200&page=2\n' >"$DA_FIX/link.devcontainer-base.1"
printf '<https://evil.example/v2/x/tags/list?page=2>; rel="next"\n' >"$DA_FIX/link.devcontainer-base.1"
run_sub resolve "$S/refs.tsv"
assert_rc "a next page on another host" 1 "$RC"; assert_quiet "another host"
assert_eq "no request to the other host" "0" "$(log_n evil.example)"
assert_no_violations "another host"
for bad in '</v2/603-identity/devcontainer-base/tags/list?n=200&page=2#x>; rel="next"' '</v2/other/devcontainer-base/tags/list?n=200>; rel="next"' '</../x/tags/list?n=1>; rel="next"'; do
  printf '%s\n' "$bad" >"$DA_FIX/link.devcontainer-base.1"
  run_sub resolve "$S/refs.tsv"
  assert_rc "a next page off the allowed pattern: $bad" 1 "$RC"
done
end_case

new_case; seed_registry
printf 'sha256:short\n' >"$DA_FIX/digest.devcontainer-tofu"
run_sub resolve "$S/refs.tsv"; assert_rc "a malformed digest" 1 "$RC"; assert_quiet "malformed digest"
rm -f "$DA_FIX/digest.devcontainer-tofu"
run_sub resolve "$S/refs.tsv"; assert_rc "no digest header" 1 "$RC"
end_case

# --- scan ----------------------------------------------------------------------------------------

mk_refs() { # mk_refs <file> [flavor...]
  local f=$1 fl; shift
  : >"$f"
  for fl in "${@:-${FLAVORS[@]}}"; do printf '%s\t%s\n' "$fl" "$(ref_of "$fl")" >>"$f"; done
}

suite trivy-daily-scan
new_case; mk_refs "$S/refs" base tofu
printf 'vuln\tCVE-2026-1\tfoo\t1\t2\t/x\n' >"$DA_FIX/scan.base"
run_sub scan "$S/refs" "$S/scan"
assert_rc "scan" 0 "$RC"; assert_quiet "scan"; assert_no_violations "scan"
assert_eq "base output written" "$(printf 'vuln\tCVE-2026-1\tfoo\t1\t2\t/x')" "$(cat "$S/scan/scan-base.txt")"
assert_eq "tofu output written (empty)" "" "$(cat "$S/scan/scan-tofu.txt")"
assert_eq "one pull per image, by digest" "1" "$(log_n "docker pull $(ref_of base)")"
assert_eq "the tofu pull" "1" "$(log_n "docker pull $(ref_of tofu)")"
runs=$(grep '^docker run' "$DA_LOG" | head -n1)
exp="docker run --rm -v devc-trivy-cache:/root/.cache/trivy -v $S/scan/base.tar:/scan/image.tar:ro -v $ROOT_DIR/.trivyignore.yaml:/scan/.trivyignore.yaml:ro $TRIVY_IMG image --input /scan/image.tar --quiet --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed --ignorefile /scan/.trivyignore.yaml --pkg-types library --format template --template $TEMPLATE"
assert_eq "the exact Trivy command" "$exp" "$runs"
case $runs in *--exit-code*) fail "--exit-code present" ;; *) pass ;; esac
case $runs in *--pkg-types\ library*) pass ;; *) fail "--pkg-types library absent" ;; esac
case $runs in *:/scan/.trivyignore.yaml:ro*) pass ;; *) fail "ignore file not read-only" ;; esac
assert_eq "no Docker socket mounted" "0" "$(grep -c 'docker.sock' "$DA_LOG" || true)"
assert_eq "the Trivy image matches build-and-test.sh" "$TRIVY_IMG" "$(sed -n 's/^TRIVY="\(.*\)"$/\1/p' "$ROOT_DIR/.github/scripts/build-and-test.sh")"
assert_eq "every tar removed" "no" "$(ls "$S/scan"/*.tar >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "the pulled image removed by digest" "1" "$(log_n "docker rmi $(ref_of base)")"
assert_eq "the tar existed while Trivy ran" "2" "$(wc -l <"$DA_STATE/seen")"
order=$(grep -n 'docker pull\|docker save\|docker run\|docker rmi' "$DA_LOG" | sed 's/^[0-9]*://' | awk '{print $2}' | tr '\n' ' ')
assert_eq "pull, save, run, rmi per flavor in order" "pull save run rmi pull save run rmi " "$order"
end_case

new_case
printf 'base\tghcr.io/603-identity/devcontainer-base:1.10\n' >"$S/refs"
run_sub scan "$S/refs" "$S/scan"
assert_rc "a reference with no digest" 1 "$RC"
printf 'base\tghcr.io/evil/devcontainer-base:1.10@sha256:%s\n' "$SHA_A" >"$S/refs"
run_sub scan "$S/refs" "$S/scan"; assert_rc "a reference to another owner" 1 "$RC"
printf 'tofu\t%s\n' "$(ref_of base)" >"$S/refs"
run_sub scan "$S/refs" "$S/scan"; assert_rc "a reference of another flavor" 1 "$RC"
mk_refs "$S/refs" base; printf 'node\tghcr.io/603-identity/devcontainer-node:1.10@sha256:zz\n' >>"$S/refs"
run_sub scan "$S/refs" "$S/scan"; assert_rc "a bad reference after a good one" 1 "$RC"
assert_eq "refused before any docker call" "0" "$(log_n docker)"
end_case

new_case; mk_refs "$S/refs" base
RC=0; env PATH="$S/bin:$PATH" DA_TRIVY_RC=3 DA_NOISE=$MARK bash "$SRC" scan "$S/refs" "$S/scan" >"$S/stdout" 2>"$S/stderr" || RC=$?
assert_rc "a non-zero Trivy exit" 1 "$RC"; assert_quiet "trivy failure"
assert_eq "the tar is removed after the failure" "no" "$(ls "$S/scan"/*.tar >/dev/null 2>&1 && echo yes || echo no)"
end_case

# --- parse ---------------------------------------------------------------------------------------

parse_case() { # parse_case <scan-base content>  (the other flavors are clean)
  new_case; mk_refs "$S/refs"
  local f
  for f in "${FLAVORS[@]}"; do : >"$S/scan/scan-$f.txt"; done
  printf '%b' "$1" >"$S/scan/scan-base.txt"
  run_sub parse "$S/refs" "$S/scan" "$S/findings.tsv" "$S/summary.tsv"
}

suite trivy-daily-parse
parse_case 'vuln\tCVE-2026-1111\tlibfoo\t1.0.0-1\t1.0.1-1\t/usr/local/bin/gh\n'
assert_rc "a well-formed record" 0 "$RC"
assert_eq "findings line" "$(printf 'CVE-2026-1111\tbase\t%s\t/usr/local/bin/gh\tlibfoo\t1.0.0-1\t1.0.1-1' "$(ref_of base)")" "$(cat "$S/findings.tsv")"
assert_eq "summary has a line per flavor" "5" "$(wc -l <"$S/summary.tsv")"
assert_eq "summary base line" "$(printf 'base\t%s\t1\t-' "$(ref_of base)")" "$(sed -n 1p "$S/summary.tsv")"
assert_eq "summary clean line" "$(printf 'tofu\t%s\t0\t-' "$(ref_of tofu)")" "$(sed -n 2p "$S/summary.tsv")"
assert_quiet "parse"
end_case

for id in CVE-2026-1111 GHSA-abcd-1234-wxyz GO-2026-4321 PYSEC-2026-12; do
  parse_case "vuln\t$id\tp\t1\t2\t/x\n"
  assert_rc "id $id accepted" 0 "$RC"; end_case
done
base20=$(printf 'A%.0s' $(seq 20))
id65=GHSA-$base20-$base20-$(printf 'B%.0s' $(seq 10))-$(printf 'C%.0s' $(seq 7)); [ "${#id65}" -eq 65 ]
id64=GHSA-$base20-$base20-$(printf 'B%.0s' $(seq 10))-$(printf 'C%.0s' $(seq 6)); [ "${#id64}" -eq 64 ]
parse_case "vuln\t$id65\tp\t1\t2\t/x\n"; assert_rc "an id of the right shape, 65 characters" 1 "$RC"; end_case
parse_case "vuln\t$id64\tp\t1\t2\t/x\n"; assert_rc "the same shape at 64 characters" 0 "$RC"; end_case
long=$(printf 'x%.0s' $(seq 257))
for bad in "vuln\tCVE-2026-1\tp\t1\t2\n" "vuln\tCVE-2026-1\tp\t\t2\t/x\n" "vuln\tCVE-2026-1\t$long\t1\t2\t/x\n" \
           "vuln\tCVE-2026-1\tp[0]\t1\t2\t/x\n" "vuln\tCVE-2026-1\tp{\t1\t2\t/x\n" "weird\tCVE-2026-1\tp\t1\t2\t/x\n" \
           "vuln\tcve-2026-1\tp\t1\t2\t/x\n" "vuln\tCVE\tp\t1\t2\t/x\n" "vuln\tCVE-2026-1;rm\tp\t1\t2\t/x\n" \
           "secret\tR\n" "secret\tR\t/x\textra\n" "vuln\tCVE-2026-1\t$MARK\t1\n"; do
  parse_case "$bad"
  assert_rc "a bad record fails the run: ${bad:0:40}" 1 "$RC"; assert_quiet "bad record"
  assert_eq "no output left on failure" "no" "$([ -e "$S/findings.tsv" ] && echo yes || echo no)"
  end_case
done
parse_case "vuln\tCVE-2026-1\tp\"q\\\\r<b>\t1\$x\t2\`y\t/a b\n"
assert_rc "characters outside the keep set" 0 "$RC"
assert_eq "written as ?" "$(printf 'CVE-2026-1\tbase\t%s\t/a b\tp?q?r?b?\t1?x\t2?y' "$(ref_of base)")" "$(cat "$S/findings.tsv")"
end_case
parse_case "vuln\tCVE-2026-1\tp\t1\t2\t/x\nvuln\tCVE-2026-1\tp\t1\t2\t/x\n"
assert_eq "a duplicate record kept once" "1" "$(wc -l <"$S/findings.tsv")"; end_case

parse_case "secret\taws-access-key-id\t/home/vscode/$MARK/config.yml\nsecret\tgeneric,key\t/other/path\n"
assert_rc "secrets alone: parse still exits 0" 0 "$RC"
assert_eq "findings empty" "0" "$(wc -c <"$S/findings.tsv")"
assert_eq "the summary keeps flavor and rule ids" "$(printf 'base\t%s\t0\taws-access-key-id,generic?key' "$(ref_of base)")" "$(sed -n 1p "$S/summary.tsv")"
if grep -qF -e "$MARK" -e '/other/path' -e config.yml "$S/findings.tsv" "$S/summary.tsv"; then fail "a secret path leaked"; else pass; fi
end_case

# --- file ----------------------------------------------------------------------------------------

fl() { # fl <id> <flavor> <path> <pkg> <installed> <fixed> [ref]
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${7:-$(ref_of "$2")}" "$3" "$4" "$5" "$6"
}
mk_summary() { # mk_summary [flavor=rules ...]: a line per flavor, "-" rules unless given
  local fl rules kv
  : >"$S/summary.tsv"
  for fl in "${FLAVORS[@]}"; do
    rules=-
    for kv in "$@"; do [ "${kv%%=*}" = "$fl" ] && rules=${kv#*=}; done
    printf '%s\t%s\t0\t%s\n' "$fl" "$(ref_of "$fl")" "$rules" >>"$S/summary.tsv"
  done
}
TITLE() { printf 'Trivy daily scan: %s in the published images' "$1"; }

# issue_entry <number> <login> <type> <title> [pull_request]
issue_entry() {
  jq -n --argjson n "$1" --arg l "$2" --arg t "$3" --arg title "$4" --arg pr "${5:-}" \
    '{number:$n, title:$title, user:{login:$l, type:$t}} + (if $pr == "" then {} else {pull_request:{}} end)'
}
list_issues() { jq -s '.' >"$DA_FIX/issues.${PAGE:-1}.json"; }
# set_issue <number> <body file> <created_at> [login]
set_issue() {
  jq -n --argjson n "$1" --rawfile b "$2" --arg c "$3" --arg l "${4:-$BOT}" \
    '{number:$n, body:$b, created_at:$c, user:{login:$l, type:"Bot"}}' >"$DA_FIX/issue.$1.json"
}
# add_comment <issue> <page> <body file> <created_at> <updated_at> [login] [type]
add_comment() {
  local f="$DA_FIX/comments.$1.$2.json"
  [ -f "$f" ] || echo '[]' >"$f"
  jq --rawfile b "$3" --arg c "$4" --arg u "$5" --arg l "${6:-$BOT}" --arg t "${7:-Bot}" \
    '. + [{body:$b, created_at:$c, updated_at:$u, user:{login:$l, type:$t}}]' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}
post_n() { cat "$DA_STATE/posts" 2>/dev/null || echo 0; }
post_body() { jq -r '.body' "$DA_STATE/post.$1.json"; }
post_title() { jq -r '.title' "$DA_STATE/post.$1.json"; }

# capture_body <id>: runs `file` against an empty repo and keeps the body it would post
capture_body() {
  rm -f "$DA_FIX"/issues.*.json "$DA_STATE/posts"
  run_sub file "$S/findings.tsv" "$S/summary.tsv"
  [ "$RC" -eq 0 ] || { echo "capture failed" >&2; return 1; }
  post_body 1 >"$S/current.md"
  rm -f "$DA_STATE"/post.* "$DA_STATE/posts"
  : >"$DA_LOG"
}
# bot_issue <number> <id> : lists one open bot issue for the id
bot_issue() { issue_entry "$1" "$BOT" Bot "$(TITLE "$2")" | list_issues; }

ID1=CVE-2026-1111
simple_case() { # a case with one finding in base and a captured current body
  new_case
  fl $ID1 base /usr/local/bin/gh libfoo 1.0 1.1 >"$S/findings.tsv"
  mk_summary
  capture_body
}

suite trivy-daily-file-inputs
new_case; : >"$S/findings.tsv"; mk_summary
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a clean scan" 0 "$RC"
assert_eq "no gh call at all" "0" "$(log_n gh)"
assert_contains() { case $2 in *"$3"*) pass ;; *) fail "$1" "missing: $3" ;; esac; }
assert_contains "the summary lists the five flavors" "$(cat "$S/GITHUB_STEP_SUMMARY")" "- \`base\`: \`$(ref_of base)\`, 0 vulnerabilities"
assert_contains "the summary says no issues" "$(cat "$S/GITHUB_STEP_SUMMARY")" "### Issues"
end_case

bad_findings() { # bad_findings <description> <line>
  new_case; printf '%b\n' "$2" >"$S/findings.tsv"; mk_summary
  run_sub file "$S/findings.tsv" "$S/summary.tsv"
  assert_rc "findings: $1" 1 "$RC"; assert_eq "findings: $1 (no gh call)" "0" "$(log_n gh)"; assert_quiet "findings: $1"
  end_case
}
R1=$(ref_of base)
bad_findings "wrong field count" "CVE-2026-1\tbase\t$R1\t/x\tp\t1"
bad_findings "a quote" "CVE-2026-1\tbase\t$R1\t/x\tp\"q\t1\t2"
bad_findings "a backslash" "CVE-2026-1\tbase\t$R1\t/x\tp\\\\q\t1\t2"
bad_findings "a backtick" "CVE-2026-1\tbase\t$R1\t/x\tp\`q\t1\t2"
bad_findings "an over-long field" "CVE-2026-1\tbase\t$R1\t/$(printf 'x%.0s' $(seq 257))\tp\t1\t2"
bad_findings "an empty field" "CVE-2026-1\tbase\t$R1\t/x\t\t1\t2"
bad_findings "a bad id" "cve-2026-1\tbase\t$R1\t/x\tp\t1\t2"
bad_findings "an id of 65 characters" "CVE-2026-$(printf '1%.0s' $(seq 54))\tbase\t$R1\t/x\tp\t1\t2"
bad_findings "an unknown flavor" "CVE-2026-1\tother\t$R1\t/x\tp\t1\t2"
bad_findings "a bad reference" "CVE-2026-1\tbase\tghcr.io/evil/x:1.1@sha256:$SHA_A\t/x\tp\t1\t2"
bad_findings "a reference of another flavor" "CVE-2026-1\ttofu\t$R1\t/x\tp\t1\t2"
bad_findings "a tag-only reference" "CVE-2026-1\tbase\tghcr.io/603-identity/devcontainer-base:1.10\t/x\tp\t1\t2"

bad_summary() { # bad_summary <description> <line>
  new_case; fl CVE-2026-1 base /x p 1 2 >"$S/findings.tsv"; printf '%b\n' "$2" >"$S/summary.tsv"
  run_sub file "$S/findings.tsv" "$S/summary.tsv"
  assert_rc "summary: $1" 1 "$RC"; assert_eq "summary: $1 (no gh call)" "0" "$(log_n gh)"
  end_case
}
bad_summary "wrong field count" "base\t$R1\t0"
bad_summary "a character outside the keep set" "base\t$R1\t0\trule\"x"
bad_summary "an unknown flavor" "other\t$R1\t0\t-"
bad_summary "a bad reference" "base\tnot-a-ref\t0\t-"
bad_summary "a bad count" "base\t$R1\tmany\t-"
bad_summary "an over-long rule field" "base\t$R1\t0\t$(printf 'r%.0s' $(seq 1025))"
bad_summary "an empty rule field" "base\t$R1\t0\t"

new_case; fl CVE-2026-1 base /x 'p?q' '1?' '2?' >"$S/findings.tsv"; mk_summary
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a field holding ? is still filed" 0 "$RC"; assert_eq "one issue opened" "1" "$(post_n)"
end_case

suite trivy-daily-file-filing
new_case
{ fl $ID1 base /usr/local/bin/gh libfoo 1.0 1.1; fl $ID1 tofu /usr/local/bin/tofu libfoo 1.0 1.1; fl CVE-2026-2222 node /usr/local/bin/node libbar 2 3; } >"$S/findings.tsv"
mk_summary
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a new id opens issues" 0 "$RC"; assert_quiet "filing"; assert_no_violations "filing"
assert_eq "two ids, two issues" "2" "$(post_n)"
assert_eq "the first issue's path" "repos/$REPO/issues" "$(cat "$DA_STATE/post.1.path")"
assert_eq "the first issue's title" "$(TITLE $ID1)" "$(post_title 1)"
assert_eq "the second issue's title" "$(TITLE CVE-2026-2222)" "$(post_title 2)"
b=$(post_body 1)
assert_eq "line 1: the id line" "Vulnerability: \`$ID1\`" "$(sed -n 1p <<<"$b")"
assert_eq "line 2 blank" "" "$(sed -n 2p <<<"$b")"
assert_eq "line 3: the base images line" "Image: \`base\` \`$(ref_of base)\`" "$(sed -n 3p <<<"$b")"
assert_eq "line 4: the tofu images line" "Image: \`tofu\` \`$(ref_of tofu)\`" "$(sed -n 4p <<<"$b")"
assert_eq "line 5 blank" "" "$(sed -n 5p <<<"$b")"
assert_eq "line 6: Rows:" "Rows:" "$(sed -n 6p <<<"$b")"
assert_eq "one id across several flavors: two rows" "2" "$(grep -c '^- flavor ' <<<"$b")"
assert_eq "the other id has no row of this one" "0" "$(grep -c 'libbar' <<<"$b")"
assert_eq "End of rows., blank, run line" "$(printf 'End of rows.\n\nRun: %s https://github.com/%s/actions/runs/%s' "$RUN" "$REPO" "$RUN")" "$(tail -n 3 <<<"$b")"
assert_eq "the last line of the block is the fingerprint" "1" "$(tail -n 4 <<<"$b" | head -n 1 | grep -cE '^Fingerprint: [0-9a-f]{64}$')"
assert_eq "the row" "- flavor \`base\`, path \`/usr/local/bin/gh\`, package \`libfoo\`, installed \`1.0\`, fixed \`1.1\`" "$(grep '^- flavor `base`' <<<"$b")"
assert_eq "the listing asked for open issues" "1" "$(grep -c 'state=open' "$DA_STATE/listings")"
assert_contains "the summary names the first issue" "$(cat "$S/GITHUB_STEP_SUMMARY")" "- \`$ID1\`: issue #901, opened"
assert_contains "the summary names the second" "$(cat "$S/GITHUB_STEP_SUMMARY")" "- \`CVE-2026-2222\`: issue #902, opened"
assert_eq "gh api POST with --input -" "2" "$(grep -c 'gh api --method POST repos/603-Identity/devcontainers/issues --input -' "$DA_LOG")"
end_case

simple_case
{ issue_entry 40 "$BOT" Bot "$(TITLE $ID1)"; issue_entry 12 "$BOT" Bot "$(TITLE $ID1)"; } | list_issues
set_issue 12 "$S/current.md" 2026-01-01T00:00:00Z
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "two matching bot issues" 0 "$RC"
assert_eq "the lowest-numbered one is used (here it matches: nothing posted)" "0" "$(post_n)"
assert_eq "issue 12 read" "1" "$(grep -c 'issues/12$' "$DA_LOG")"
assert_eq "issue 40 never read" "0" "$(grep -c 'issues/40' "$DA_LOG")"
end_case

simple_case
{ issue_entry 3 "$BOT" Bot "$(TITLE $ID1)" pr; issue_entry 5 someone User "$(TITLE $ID1)"; issue_entry 6 "$BOT" Bot "$(TITLE CVE-2026-9)"; issue_entry 7 "$BOT" User "$(TITLE $ID1)"; } | list_issues
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "no match: a PR, a non-bot author, another id, a User-type login" 0 "$RC"
assert_eq "a new issue opened" "1" "$(post_n)"; assert_eq "as an issue" "repos/$REPO/issues" "$(cat "$DA_STATE/post.1.path")"
assert_eq "no issue read" "0" "$(grep -c 'gh api repos/603-Identity/devcontainers/issues/[0-9]' "$DA_LOG")"
end_case

simple_case
PAGE=1 bot_issue 99 CVE-2026-9; PAGE=2 bot_issue 17 $ID1
set_issue 17 "$S/current.md" 2026-01-01T00:00:00Z
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "the listing is read across two pages (a match on page 2 posts nothing)" "0" "$(post_n)"
assert_eq "issue 17 read" "1" "$(grep -c 'issues/17$' "$DA_LOG")"
end_case

suite trivy-daily-file-matching
# unchanged_case <mutator>: the newest text is the captured body passed through a sed script
match_case() { # match_case <description> <expected posts> <sed script for the body> [comment]
  simple_case
  bot_issue 7 $ID1
  sed "$3" "$S/current.md" >"$S/text.md"
  if [ "${4:-}" = comment ]; then
    set_issue 7 "$S/current.md" 2026-01-01T00:00:00Z
    add_comment 7 1 "$S/text.md" 2026-02-01T00:00:00Z 2026-02-01T00:00:00Z
  else
    set_issue 7 "$S/text.md" 2026-01-01T00:00:00Z
  fi
  run_sub file "$S/findings.tsv" "$S/summary.tsv"
  assert_rc "$1" 0 "$RC"
  assert_eq "$1 (posts)" "$2" "$(post_n)"
  if [ "$2" = 1 ]; then assert_eq "$1 (a comment on 7)" "repos/$REPO/issues/7/comments" "$(cat "$DA_STATE/post.1.path")"; fi
  end_case
}
match_case "the current text" 0 's/NOPE//'
match_case "only digest, tag and run id changed" 0 "s/$SHA_A/$SHA_B/; s/:1\.10@/:1.1000@/; s/runs\/$RUN/runs\/777/; s/^Run: $RUN/Run: 777/"
match_case "an images line changed to another well-formed reference (the recorded residual)" 0 "s/devcontainer-base:1\.10@sha256:$SHA_A/devcontainer-base:9.9@sha256:$SHA_B/"
match_case "a changed row" 1 's/fixed `1.1`/fixed `1.2`/'
match_case "a line added outside the block" 1 's/^End of rows\.$/End of rows.\nextra line/'
match_case "a line changed outside the block" 1 's/^Vulnerability: /Vulnerability (edited): /'
match_case "a line added before Rows:" 1 's/^Rows:$/hello\nRows:/'
match_case "no Rows: line" 1 '/^Rows:$/d'
match_case "no End of rows. line" 1 '/^End of rows\.$/d'
match_case "End of rows. before Rows:" 1 's/^Rows:$/End of rows./; s/^End of rows\.$/Rows:/'
match_case "two block pairs" 1 's/^End of rows\.$/End of rows.\nRows:\nEnd of rows./'
match_case "the run line with another URL" 1 's#https://github.com/603-Identity#https://example.com/603-Identity#'
match_case "a bad run id" 1 's/^Run: [0-9]*/Run: x/'
match_case "a newest bot comment whose rows were edited, body block equal" 1 's/package `libfoo`/package `libedited`/' comment
match_case "a newest bot comment equal to the current text" 0 's/NOPE//' comment

simple_case
bot_issue 7 $ID1
sed 's/$/\r/' "$S/current.md" >"$S/text.md"
set_issue 7 "$S/text.md" 2026-01-01T00:00:00Z
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "a CRLF text that otherwise matches posts nothing" "0" "$(post_n)"
end_case

simple_case # the newest text is chosen by created_at, not updated_at, across two comment pages
bot_issue 7 $ID1
sed 's/fixed `1.1`/fixed `0.5`/' "$S/current.md" >"$S/old.md"
set_issue 7 "$S/old.md" 2026-01-01T00:00:00Z
add_comment 7 1 "$S/current.md" 2026-03-01T00:00:00Z 2026-03-02T00:00:00Z
add_comment 7 2 "$S/old.md" 2026-02-01T00:00:00Z 2026-04-01T00:00:00Z
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "the newest by created_at matches: nothing posted" "0" "$(post_n)"
assert_eq "both comment pages were read (concatenated by --paginate)" "1" "$(grep -c 'issues/7/comments?per_page=100 --paginate' "$DA_LOG")"
add_comment 7 2 "$S/old.md" 2026-05-01T00:00:00Z 2026-05-01T00:00:00Z
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "a newer stale text posts a comment" "1" "$(post_n)"
end_case

simple_case # a non-bot comment newer than every bot text, carrying a copy of the current text, is ignored
bot_issue 7 $ID1
sed 's/fixed `1.1`/fixed `0.5`/' "$S/current.md" >"$S/old.md"
set_issue 7 "$S/old.md" 2026-01-01T00:00:00Z
add_comment 7 1 "$S/current.md" 2026-06-01T00:00:00Z 2026-06-01T00:00:00Z someone User
add_comment 7 1 "$S/current.md" 2026-06-02T00:00:00Z 2026-06-02T00:00:00Z "$BOT" User
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "the stale bot text still wins: one comment posted" "1" "$(post_n)"
end_case

simple_case # the budget: a body near it, digests changed
new_case
: >"$S/findings.tsv"
for i in $(seq 1 300); do fl $ID1 base "/p/$(printf '%04d' "$i")/$(printf 'x%.0s' $(seq 100))" libfoo 1.0 1.1; done >>"$S/findings.tsv"
mk_summary; capture_body
bot_issue 7 $ID1
sed "s/$SHA_A/$SHA_B/; s/:1\.10@/:1.1000@/" "$S/current.md" >"$S/text.md"
set_issue 7 "$S/text.md" 2026-01-01T00:00:00Z
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "near the 50000-byte budget, only digests changed: nothing posted" "0" "$(post_n)"
end_case

new_case # over the budget: rows cut, the count line inside the block, the fingerprint over all rows
: >"$S/findings.tsv"
for i in $(seq 1 600); do fl $ID1 base "/p/$(printf '%04d' "$i")/$(printf 'x%.0s' $(seq 100))" libfoo 1.0 1.1; done >>"$S/findings.tsv"
mk_summary; capture_body
rows_shown=$(grep -c '^- flavor ' "$S/current.md")
block=$(sed -n '/^Rows:$/,/^End of rows\.$/p' "$S/current.md" | sed '1d;$d')
bytes=$(printf '%s' "$block" | wc -c)
if [ "$bytes" -le 50000 ] && [ "$rows_shown" -lt 600 ]; then pass; else fail "the block is within the budget with rows cut" "bytes=$bytes rows=$rows_shown"; fi
assert_eq "the count line, inside the block" "Rows left out: $((600 - rows_shown))" "$(grep '^Rows left out: ' "$S/current.md")"
assert_eq "the count line sits just before the fingerprint" "1" "$(grep -B1 '^Fingerprint: ' "$S/current.md" | grep -c '^Rows left out')"
assert_eq "the body is under 65536 bytes" "1" "$([ "$(wc -c <"$S/current.md")" -lt 65536 ] && echo 1 || echo 0)"
bot_issue 7 $ID1; set_issue 7 "$S/current.md" 2026-01-01T00:00:00Z
sed -i '$ s/.*/&/' "$S/findings.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==600 { $7="9.9" } { print }' "$S/findings.tsv" >"$S/f2.tsv"
run_sub file "$S/f2.tsv" "$S/summary.tsv"
assert_eq "a change only in a row the budget left out changes the fingerprint: one comment" "1" "$(post_n)"
end_case

suite trivy-daily-file-copying
simple_case
bot_issue 7 $ID1
printf '%s stale bot text\n' "$MARK" >"$S/old.md"
set_issue 7 "$S/old.md" 2026-01-01T00:00:00Z
add_comment 7 1 "$S/old.md" 2026-01-02T00:00:00Z 2026-01-02T00:00:00Z someone User
{ printf '%s\n' "$MARK"; cat "$S/current.md"; } >"$S/other.md"
add_comment 7 1 "$S/other.md" 2026-01-03T00:00:00Z 2026-01-03T00:00:00Z "$BOT" User
issue_entry 8 someone User "$(TITLE $ID1) $MARK" >"$S/e8.json"
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "a comment posted" "1" "$(post_n)"
if grep -qF "$MARK" "$DA_STATE"/post.*.json; then fail "a marker from issue or comment text reached a request body"; else pass; fi
assert_quiet "copying"
end_case

new_case
fl CVE-2026-1 base '/a/b@1+2~3(x)=y,z:w' 'pkg/name' '1.0+dfsg~1' '2:3.0-1' >"$S/findings.tsv"; mk_summary
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "special characters of the keep set reach the request JSON intact" "- flavor \`base\`, path \`/a/b@1+2~3(x)=y,z:w\`, package \`pkg/name\`, installed \`1.0+dfsg~1\`, fixed \`2:3.0-1\`; pin: not in this scan's pin table" "$(post_body 1 | grep '^- flavor ')"
end_case

suite trivy-daily-file-pins
pin_case() { # pin_case <path> ...: the body of one issue holding a row per path
  new_case
  : >"$S/findings.tsv"
  local p; for p in "$@"; do fl $ID1 base "$p" libfoo 1 2 >>"$S/findings.tsv"; done
  mk_summary
}
argv() { sed -n "s/^ARG $2=//p" "$ROOT_DIR/images/$1/Dockerfile" | sed -n 1p; }
GHV=$(argv base GH_VERSION)
pin_case usr/local/bin/gh /usr/local/libexec/gh-real
printf 'v%s\n' "$GHV" >"$DA_FIX/rel.cli_cli"
run_sub file "$S/findings.tsv" "$S/summary.tsv"
b=$(post_body 1)
assert_eq "paths with and without a leading slash share one entry; a v-prefixed equal tag" "Pin: \`GH_VERSION\` \`$GHV\`; upstream: equals the pin" "$(grep '^Pin: ' <<<"$b")"
assert_eq "one pin line only" "1" "$(grep -c '^Pin: ' <<<"$b")"
assert_eq "no unmapped note on mapped paths" "0" "$(grep -c "pin table" <<<"$b")"
end_case

pin_case usr/local/bin/gh; echo v99.0.0 >"$DA_FIX/rel.cli_cli"
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "a newer tag" "Pin: \`GH_VERSION\` \`$GHV\`; upstream: latest release is \`v99.0.0\`" "$(post_body 1 | grep '^Pin: ')"
end_case

pin_case usr/local/bin/gh; echo 'v1;rm -rf' >"$DA_FIX/rel.cli_cli"
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a tag outside the pattern" 0 "$RC"
assert_eq "reads unknown" "Pin: \`GH_VERSION\` \`$GHV\`; upstream: unknown" "$(post_body 1 | grep '^Pin: ')"
end_case
pin_case usr/local/bin/gh
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a failed lookup does not fail the run" 0 "$RC"
assert_eq "reads unknown" "Pin: \`GH_VERSION\` \`$GHV\`; upstream: unknown" "$(post_body 1 | grep '^Pin: ')"
end_case

BLV=$(argv base BETTERLEAKS_VERSION)
pin_case usr/local/bin/betterleaks
run_sub file "$S/findings.tsv" "$S/summary.tsv"
if [[ $BLV == *-rc.* ]]; then
  assert_eq "a release-candidate betterleaks pin is not compared" "Pin: \`BETTERLEAKS_VERSION\` \`$BLV\`; upstream: not compared (pinned to a release candidate)" "$(post_body 1 | grep '^Pin: ')"
  assert_eq "and makes no lookup" "0" "$(grep -c 'betterleaks/betterleaks' "$DA_LOG")"
fi
end_case

# a betterleaks GA pin is compared like the others: run on a copy of the tree with a GA pin
new_case
mkdir -p "$S/tree/.github/scripts" "$S/tree/images/base" "$S/tree/images/tofu" "$S/tree/images/node" "$S/tree/images/devapp"
cp "$SRC" "$S/tree/.github/scripts/"
for d in base tofu node devapp; do cp "$ROOT_DIR/images/$d/Dockerfile" "$S/tree/images/$d/"; done
sed -i 's/^ARG BETTERLEAKS_VERSION=.*/ARG BETTERLEAKS_VERSION=2.0.0/' "$S/tree/images/base/Dockerfile"
fl $ID1 base usr/local/bin/betterleaks libfoo 1 2 >"$S/findings.tsv"; mk_summary
echo v2.0.0 >"$DA_FIX/rel.betterleaks_betterleaks"
RC=0; env PATH="$S/bin:$PATH" GH_TOKEN=t GITHUB_REPOSITORY="$REPO" GITHUB_RUN_ID=$RUN GITHUB_STEP_SUMMARY="$S/GITHUB_STEP_SUMMARY" \
  bash "$S/tree/.github/scripts/trivy-daily.sh" file "$S/findings.tsv" "$S/summary.tsv" >"$S/stdout" 2>"$S/stderr" || RC=$?
assert_rc "a betterleaks GA pin" 0 "$RC"
assert_eq "is compared like the others" "Pin: \`BETTERLEAKS_VERSION\` \`2.0.0\`; upstream: equals the pin" "$(post_body 1 | grep '^Pin: ')"
end_case

pin_case usr/local/bin/claude
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "claude: not looked up" "Pin: \`CLAUDE_VERSION\` \`$(argv devapp CLAUDE_VERSION)\`; upstream not looked up" "$(post_body 1 | grep '^Pin: ')"
assert_eq "claude makes no upstream call" "0" "$(grep -c 'releases/latest' "$DA_LOG")"
end_case
pin_case usr/local/lib/node_modules/npm/lib/x.js usr/local/bin/node
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "the npm prefix and node" "2" "$(post_body 1 | grep -c '^Pin: ')"
assert_eq "npm" "Pin: \`NPM_VERSION\` \`$(argv node NPM_VERSION)\`; upstream not looked up" "$(post_body 1 | grep NPM_VERSION)"
end_case
pin_case opt/devc/tools/uv/lib/python3.12/site-packages/x.py
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "the lock-file prefix" "Pin: \`images/base/tools/uv.lock\`: pinned by images/base/tools/uv.lock" "$(post_body 1 | grep '^Pin: ')"
end_case
pin_case usr/lib/x/other.so
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_eq "an unmapped path" "1" "$(post_body 1 | grep -c "; pin: not in this scan's pin table")"
assert_eq "and no pin line" "0" "$(post_body 1 | grep -c '^Pin: ')"
end_case

# the upstream words are resolved once per tool, in the parent shell, before the per-id loop
ID2=CVE-2026-2222
GH_CALLS="repos/cli/cli/releases/latest"
YQ_CALLS="repos/mikefarah/yq/releases/latest"
new_case
fl $ID1 base usr/local/bin/gh libfoo 1 2 >"$S/findings.tsv"; fl $ID2 base usr/local/bin/gh libbar 1 2 >>"$S/findings.tsv"; mk_summary
echo v99.0.0 >"$DA_FIX/rel.cli_cli"
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "two ids on one tool" 0 "$RC"
assert_eq "two ids on one tool: one releases/latest call" "1" "$(log_n "$GH_CALLS")"
assert_eq "two ids on one tool: two issues opened" "2" "$(cat "$DA_STATE/posts")"
assert_eq "two ids on one tool: the same Pin line in both bodies" "$(post_body 1 | grep '^Pin: ')" "$(post_body 2 | grep '^Pin: ')"
assert_eq "two ids on one tool: the word is the latest release" "Pin: \`GH_VERSION\` \`$GHV\`; upstream: latest release is \`v99.0.0\`" "$(post_body 1 | grep '^Pin: ')"
assert_quiet "two ids on one tool"
assert_no_violations "two ids on one tool"
end_case

new_case
fl $ID1 base usr/local/bin/gh libfoo 1 2 >"$S/findings.tsv"; fl $ID2 base usr/local/bin/gh libbar 1 2 >>"$S/findings.tsv"; mk_summary
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "two ids, the one lookup fails" 0 "$RC"
assert_eq "two ids, the one lookup fails: one call" "1" "$(log_n "$GH_CALLS")"
assert_eq "two ids, the one lookup fails: unknown in both bodies" "2" "$( { post_body 1; post_body 2; } | grep -c "^Pin: .*upstream: unknown\$")"
assert_quiet "two ids, the one lookup fails"
end_case

new_case # each id has rows on both tools: one call per tool, not per id
for id in $ID1 $ID2; do
  fl "$id" base usr/local/bin/gh libfoo 1 2 >>"$S/findings.tsv"; fl "$id" base usr/local/bin/yq libbar 1 2 >>"$S/findings.tsv"
done
mk_summary
echo v99.0.0 >"$DA_FIX/rel.cli_cli"; echo v99.0.0 >"$DA_FIX/rel.mikefarah_yq"
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "two ids on two tools" 0 "$RC"
assert_eq "two ids on two tools: one call for gh" "1" "$(log_n "$GH_CALLS")"
assert_eq "two ids on two tools: one call for yq" "1" "$(log_n "$YQ_CALLS")"
assert_eq "two ids on two tools: the same Pin lines in both bodies" "$(post_body 1 | grep '^Pin: ')" "$(post_body 2 | grep '^Pin: ')"
assert_quiet "two ids on two tools"
end_case

# an unreadable pin of a looked-up tool fails the run before any issue is touched
new_case
mkdir -p "$S/tree/.github/scripts" "$S/tree/images/base" "$S/tree/images/tofu" "$S/tree/images/node" "$S/tree/images/devapp"
cp "$SRC" "$S/tree/.github/scripts/"
for d in base tofu node devapp; do cp "$ROOT_DIR/images/$d/Dockerfile" "$S/tree/images/$d/"; done
sed -i '/^ARG YQ_VERSION=/d' "$S/tree/images/base/Dockerfile"
fl $ID1 base usr/local/bin/gh libfoo 1 2 >"$S/findings.tsv"; fl $ID2 base usr/local/bin/yq libbar 1 2 >>"$S/findings.tsv"; mk_summary
echo v99.0.0 >"$DA_FIX/rel.cli_cli"
RC=0; env PATH="$S/bin:$PATH" GH_TOKEN=t GITHUB_REPOSITORY="$REPO" GITHUB_RUN_ID=$RUN GITHUB_STEP_SUMMARY="$S/GITHUB_STEP_SUMMARY" \
  bash "$S/tree/.github/scripts/trivy-daily.sh" file "$S/findings.tsv" "$S/summary.tsv" >"$S/stdout" 2>"$S/stderr" || RC=$?
assert_rc "an unreadable pin on the second id's tool" 1 "$RC"
assert_eq "an unreadable pin: exactly the fixed reason line on stderr" "trivy-daily: a pinned version could not be read from a Dockerfile" "$(cat "$S/stderr")"
assert_eq "an unreadable pin: no issue opened or commented on" "0" "$(cat "$DA_STATE/posts" 2>/dev/null || echo 0)"
assert_eq "an unreadable pin: the open issues were never listed" "0" "$(log_n 'issues?state=open')"
end_case

# the pre-pass runs only after the input checks: no gh call on a bad summary, repository or run id
new_case
fl $ID1 base usr/local/bin/gh libfoo 1 2 >"$S/findings.tsv"; mk_summary; echo v99.0.0 >"$DA_FIX/rel.cli_cli"
printf 'not a summary line\n' >>"$S/summary.tsv"
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a malformed summary line" 1 "$RC"
assert_eq "a malformed summary line: no gh call" "0" "$(log_n 'gh ')"
end_case
new_case
fl $ID1 base usr/local/bin/gh libfoo 1 2 >"$S/findings.tsv"; mk_summary; echo v99.0.0 >"$DA_FIX/rel.cli_cli"
REPO_OVERRIDE=other/repo run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a GITHUB_REPOSITORY that is not this repository" 1 "$RC"
assert_eq "a foreign repository: no gh call" "0" "$(log_n 'gh ')"
end_case
new_case
fl $ID1 base usr/local/bin/gh libfoo 1 2 >"$S/findings.tsv"; mk_summary; echo v99.0.0 >"$DA_FIX/rel.cli_cli"
RUN_OVERRIDE=abc run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a non-numeric GITHUB_RUN_ID" 1 "$RC"
assert_eq "a non-numeric run id: no gh call" "0" "$(log_n 'gh ')"
end_case

suite trivy-daily-file-ends
new_case # a secret in SUMMARY with a vulnerability in FINDINGS
fl $ID1 base /usr/local/bin/gh libfoo 1 2 >"$S/findings.tsv"; mk_summary base=aws-access-key-id
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "files the vulnerability, then exits 1" 1 "$RC"
assert_eq "the vulnerability was filed" "1" "$(post_n)"
assert_contains "the summary names flavor and rule id only" "$(cat "$S/GITHUB_STEP_SUMMARY")" "- \`base\`: rule ids \`aws-access-key-id\`"
assert_contains "and the issue" "$(cat "$S/GITHUB_STEP_SUMMARY")" "- \`$ID1\`: issue #901, opened"
assert_quiet "secret with vulnerability"
end_case
new_case
: >"$S/findings.tsv"; mk_summary base=aws-access-key-id
run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a secret alone exits 1" 1 "$RC"; assert_eq "with no gh call" "0" "$(log_n gh)"
end_case
new_case
fl $ID1 base /x p 1 2 >"$S/findings.tsv"; mk_summary
DA_POST_FAIL=1 run_sub file "$S/findings.tsv" "$S/summary.tsv"
RC=0; env PATH="$S/bin:$PATH" DA_POST_FAIL=1 DA_NOISE=$MARK GH_TOKEN=t GITHUB_REPOSITORY="$REPO" GITHUB_RUN_ID=$RUN bash "$SRC" file "$S/findings.tsv" "$S/summary.tsv" >"$S/stdout" 2>"$S/stderr" || RC=$?
assert_rc "an issues API failure" 1 "$RC"; assert_quiet "api failure"
end_case
new_case
fl $ID1 base /x p 1 2 >"$S/findings.tsv"; mk_summary
REPO_OVERRIDE=evil/repo run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "GITHUB_REPOSITORY other than this repo" 1 "$RC"; assert_eq "refused with no gh call" "0" "$(log_n gh)"
RUN_OVERRIDE=abc run_sub file "$S/findings.tsv" "$S/summary.tsv"
assert_rc "a non-numeric run id" 1 "$RC"
end_case

# --- the workflow's shape ------------------------------------------------------------------------
suite trivy-daily-workflow
JOB='.jobs.trivy-daily'
assert_eq "the trigger keys, exactly (no push, no pull_request)" "schedule,workflow_dispatch" "$(yq -r '.on | keys | join(",")' "$WF")"
assert_eq "one schedule entry" "1" "$(yq -r '.on.schedule | length' "$WF")"
cron=$(yq -r '.on.schedule[0].cron' "$WF")
if [[ $cron =~ ^[0-9]+\ [0-9]+\ \*\ \*\ \*$ ]]; then pass; else fail "the cron runs daily" "$cron"; fi
assert_eq "not the Monday 06:17 slot" "no" "$([ "$cron" = "17 6 * * 1" ] && echo yes || echo no)"
assert_eq "workflow-level permissions" '{}' "$(yq -o=json -I=0 '.permissions' "$WF")"
assert_eq "the concurrency group" '{"group":"trivy-daily","cancel-in-progress":false}' "$(yq -o=json -I=0 '.concurrency' "$WF")"
assert_eq "the job's permissions, exactly" '{"contents":"read","issues":"write"}' "$(yq -o=json -I=0 "$JOB.permissions" "$WF")"
assert_eq "the job's name" 'Trivy daily scan (not required)' "$(yq -r "$JOB.name" "$WF")"
case $(yq -r "$JOB.if" "$WF") in *"github.ref == 'refs/heads/main'"*) pass ;; *) fail "the main guard" ;; esac
assert_eq "runs-on" "ubuntu-latest" "$(yq -r "$JOB.runs-on" "$WF")"
t=$(yq -r "$JOB.\"timeout-minutes\"" "$WF"); if [ "$t" -le 60 ]; then pass; else fail "timeout-minutes at most 60" "$t"; fi
assert_eq "one job" "trivy-daily" "$(yq -r '.jobs | keys | join(",")' "$WF")"
assert_eq "the checkout pin is trivy-expiry.yml's" "$(yq -r '.jobs.trivy-expiry.steps[0].uses' "$ROOT_DIR/.github/workflows/trivy-expiry.yml")" "$(yq -r "$JOB.steps[0].uses" "$WF")"
assert_eq "the checkout does not persist credentials" "false" "$(yq -r "$JOB.steps[0].with.\"persist-credentials\"" "$WF")"
assert_eq "three steps" "3" "$(yq -r "$JOB.steps | length" "$WF")"
assert_eq "the scan step's id" "scan" "$(yq -r "$JOB.steps[1].id" "$WF")"
assert_eq "the scan step has no env" "null" "$(yq -r "$JOB.steps[1].env" "$WF")"
assert_eq "the file step has no if" "null" "$(yq -r "$JOB.steps[2].if" "$WF")"
assert_eq "GH_TOKEN comes from github.token in the file step" '{"GH_TOKEN":"${{ github.token }}"}' "$(yq -o=json -I=0 "$JOB.steps[2].env" "$WF")"
assert_eq "no other step has env" "null" "$(yq -r "$JOB.steps[0].env" "$WF")"
assert_eq "GH_TOKEN appears once" "1" "$(grep -c 'GH_TOKEN' "$WF")"
assert_eq "github.token appears once" "1" "$(grep -c 'github\.token' "$WF")"
assert_eq "no inline expression in any run:" "0" "$(yq -r '.jobs[].steps[].run // ""' "$WF" | grep -c '\${{' || true)"
assert_eq "the scan step runs the four subcommands in order" "resolve scan parse" "$(yq -r "$JOB.steps[1].run" "$WF" | sed -n 's/^bash .github\/scripts\/trivy-daily.sh \([a-z]*\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
assert_eq "the file step runs file" "1" "$(yq -r "$JOB.steps[2].run" "$WF" | grep -c 'trivy-daily.sh file ')"
if grep -qF 'Trivy daily scan (not required)' "$ROOT_DIR/.ai/project.yml"; then fail "the job name is in .ai/project.yml"; else pass; fi

summary
