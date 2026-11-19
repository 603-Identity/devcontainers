#!/usr/bin/env bash
# Daily Trivy scan of the five PUBLISHED images (trivy-daily.yml): finds what the build gate in
# build-and-test.sh would report against the images published now, restricted to library packages
# (pinned binaries and language packages), and files one issue per vulnerability id, or updates the
# open one, so the maintainer has the finding before a PR is blocked (docs/trivy-renewal.md).
#
# Usage: bash .github/scripts/trivy-daily.sh SUBCOMMAND ARGS
#
#   resolve OUT                          newest numeric tag and digest of each published image;
#                                        one `flavor<TAB>reference` line per image written to OUT
#   scan REFS SCANDIR                    pull each reference by digest, scan it with the pinned Trivy
#                                        image and .trivyignore.yaml, one scan-<flavor>.txt in SCANDIR
#   parse REFS SCANDIR FINDINGS SUMMARY  check every scan record, write the FINDINGS and SUMMARY files
#   file FINDINGS SUMMARY                open or update one issue per vulnerability id (needs
#                                        GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID; writes the step
#                                        summary to GITHUB_STEP_SUMMARY)
#
# Exit status: 0 success; 2 usage error (argument count, unknown subcommand, a missing input file);
# 1 any other failure, with one fixed plain-text reason on stderr.
#
# No subcommand writes a scan-derived or API-derived value to stdout, stderr, GITHUB_ENV, GITHUB_PATH
# or GITHUB_OUTPUT: such values go only to the intermediate files, the step summary file and the API
# request bodies, and the output of every child process goes to a file, so none can form a workflow
# command in the job log. Text read from an issue or a comment is compared, never copied.
set -Eeuo pipefail
export LC_ALL=C

# The same image string as build-and-test.sh's TRIVY variable.
TRIVY="aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969"

# The same template as trivy-evidence.sh: one tab-separated line per vulnerability and per secret.
# shellcheck disable=SC2016 # a Go template: its $t is Trivy's, not the shell's
TEMPLATE='{{range .}}{{$t := .Target}}{{range .Vulnerabilities}}vuln{{"\t"}}{{.VulnerabilityID}}{{"\t"}}{{.PkgName}}{{"\t"}}{{.InstalledVersion}}{{"\t"}}{{.FixedVersion}}{{"\t"}}{{if .PkgPath}}{{.PkgPath}}{{else}}{{$t}}{{end}}{{"\n"}}{{end}}{{range .Secrets}}secret{{"\t"}}{{.RuleID}}{{"\t"}}{{$t}}{{"\n"}}{{end}}{{end}}'

KEEP='[^A-Za-z0-9 ._:/@+~,=()-]'   # a scan field keeps these; every other character becomes `?`
KEEPQ='[^A-Za-z0-9 ._:/@+~,=()?-]' # what a re-validated field may hold (the keep set plus `?`)
MAX_FIELD=256
MAX_RULES=1024
BUDGET=50000        # bytes of the findings block, whatever the other lines hold
MAX_PAGES=50
OWNER=603-identity
THIS_REPO=603-Identity/devcontainers
BOT_LOGIN='github-actions[bot]'
FLAVORS=(base tofu node devapp devapp-tofu)
REF_CORE='ghcr\.io/603-identity/devcontainer-(base|tofu|node|devapp|devapp-tofu):[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}'
REF_RE="^${REF_CORE}\$"
ID_RE='^[A-Z][A-Z0-9]{1,9}(-[A-Za-z0-9]{1,24}){1,4}$'
NEXT_RE='^/v2/603-identity/devcontainer-[a-z-]+/tags/list\?[A-Za-z0-9=&%._-]+$'
TAG_RE='^v?[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$'
BT=$'`'
IMG_RE="^Image: ${BT}(base|tofu|node|devapp|devapp-tofu)${BT} ${BT}${REF_CORE}${BT}\$"
ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json'
UNMAPPED="not in this scan's pin table"

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmp=
cleanup() { if [ -n "$tmp" ]; then rm -rf -- "$tmp"; fi; return 0; }
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
# A command failed with no reason of its own: one fixed line, never $BASH_COMMAND (it can hold values).
trap '[ "$BASHPID" != "$$" ] || [ -e "${tmp:-/nonexistent}/died" ] || echo "trivy-daily: a step failed" >&2; exit 1' ERR

usage_error() { echo "trivy-daily: usage error: $1" >&2; exit 2; }
die() { echo "trivy-daily: $1" >&2; : >"$tmp/died"; exit 1; }

split_tabs() { # split_tabs <line>: sets F, keeping empty fields
  local s=$1
  F=()
  while :; do
    case $s in
      *$'\t'*) F+=("${s%%$'\t'*}"); s=${s#*$'\t'} ;;
      *) F+=("$s"); break ;;
    esac
  done
}

is_flavor() { local f; for f in "${FLAVORS[@]}"; do [ "$f" = "$1" ] && return 0; done; return 1; }

# --- arguments -----------------------------------------------------------------------------------
[ "$#" -ge 1 ] || usage_error "expected a subcommand"
cmd=$1
shift
case $cmd in
  resolve) [ "$#" -eq 1 ] || usage_error "resolve takes OUT"
    [ -d "$(dirname -- "$1")" ] || usage_error "the directory of OUT does not exist" ;;
  scan) [ "$#" -eq 2 ] || usage_error "scan takes REFS and SCANDIR"
    [ -f "$1" ] || usage_error "REFS is not a file"
    [ -d "$2" ] || usage_error "SCANDIR is not a directory" ;;
  parse) [ "$#" -eq 4 ] || usage_error "parse takes REFS, SCANDIR, FINDINGS and SUMMARY"
    [ -f "$1" ] || usage_error "REFS is not a file"
    [ -d "$2" ] || usage_error "SCANDIR is not a directory"
    [ -d "$(dirname -- "$3")" ] && [ -d "$(dirname -- "$4")" ] || usage_error "the directory of an output does not exist" ;;
  file) [ "$#" -eq 2 ] || usage_error "file takes FINDINGS and SUMMARY"
    [ -f "$1" ] && [ -f "$2" ] || usage_error "FINDINGS and SUMMARY must be files" ;;
  *) usage_error "unknown subcommand" ;;
esac
tmp=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/trivy-daily.XXXXXX")
: >"$tmp/err.log"

read_refs() { # read_refs <file>: sets RFL (flavors) and RFR (references), each checked
  local line n=0
  RFL=() RFR=()
  while IFS= read -r line || [ -n "$line" ]; do
    split_tabs "$line"
    [ "${#F[@]}" -eq 2 ] || die "a reference line has the wrong number of fields"
    is_flavor "${F[0]}" || die "a reference line names an unknown flavor"
    [[ ${F[1]} =~ $REF_RE ]] || die "a reference fails the reference pattern"
    [ "${BASH_REMATCH[1]}" = "${F[0]}" ] || die "a reference does not belong to its flavor"
    RFL+=("${F[0]}")
    RFR+=("${F[1]}")
    n=$((n + 1))
  done <"$1"
  [ "$n" -ge 1 ] || die "the reference file is empty"
}

# --- resolve -------------------------------------------------------------------------------------
curl_q() { curl -fsS --retry 3 --retry-delay 2 --retry-all-errors --max-time 30 "$@" 2>>"$tmp/err.log"; }

do_resolve() {
  local out=$1 flavor name body token url pages tags next pick digest hdr="$tmp/hdr"
  : >"$tmp/refs.out"
  for flavor in "${FLAVORS[@]}"; do
    name=devcontainer-$flavor
    body=$(curl_q "https://ghcr.io/token?scope=repository:${OWNER}/${name}:pull")
    token=$(jq -r '.token // empty' <<<"$body" 2>>"$tmp/err.log")
    [[ $token =~ ^[A-Za-z0-9._~+/=-]{1,4096}$ ]] || die "the registry token is missing or malformed"
    tags=
    url="https://ghcr.io/v2/${OWNER}/${name}/tags/list?n=200"
    pages=0
    while [ -n "$url" ]; do
      pages=$((pages + 1))
      [ "$pages" -le "$MAX_PAGES" ] || die "the tag list has too many pages"
      : >"$hdr"
      body=$(curl_q -D "$hdr" -H "Authorization: Bearer ${token}" "$url")
      tags+=$(jq -r '.tags[]?' <<<"$body" 2>>"$tmp/err.log")$'\n'
      next=$(grep -i '^link:' "$hdr" | sed -n 's/.*<\([^>]*\)>; *rel="next".*/\1/p' | tr -d '\r' || true)
      if [ -z "$next" ]; then
        url=
      else
        case $next in *$'\n'*) die "the tag list names more than one next page" ;; esac
        [[ $next =~ $NEXT_RE ]] || die "the tag list names a next page outside the registry path"
        url="https://ghcr.io${next}"
      fi
    done
    pick=$(printf '%s' "$tags" | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1nr -k2,2nr | sed -n 1p || true)
    [[ $pick =~ ^[0-9]+\.[0-9]+$ ]] || die "an image has no numeric tag"
    digest=$(curl_q -I -H "Authorization: Bearer ${token}" -H "Accept: ${ACCEPT}" \
      "https://ghcr.io/v2/${OWNER}/${name}/manifests/${pick}" \
      | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }')
    [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || die "an image has no valid digest"
    printf '%s\t%s\n' "$flavor" "ghcr.io/${OWNER}/${name}:${pick}@${digest}" >>"$tmp/refs.out"
  done
  mv -f -- "$tmp/refs.out" "$out"
}

# --- scan ----------------------------------------------------------------------------------------
do_scan() {
  local refs=$1 scandir i flavor ref tar
  scandir=$(cd "$2" && pwd)
  read_refs "$refs" # every reference is re-checked before any docker call
  for i in "${!RFL[@]}"; do
    flavor=${RFL[i]}
    ref=${RFR[i]}
    tar="$scandir/$flavor.tar"
    docker pull "$ref" >/dev/null 2>>"$tmp/err.log"
    docker save -o "$tar" "$ref" >/dev/null 2>>"$tmp/err.log"
    docker run --rm -v devc-trivy-cache:/root/.cache/trivy -v "$tar:/scan/image.tar:ro" \
      -v "$root/.trivyignore.yaml:/scan/.trivyignore.yaml:ro" \
      "$TRIVY" image --input /scan/image.tar --quiet --scanners vuln,secret --severity HIGH,CRITICAL \
      --ignore-unfixed --ignorefile /scan/.trivyignore.yaml --pkg-types library \
      --format template --template "$TEMPLATE" >"$scandir/scan-$flavor.txt" 2>>"$tmp/err.log" \
      || { rm -f -- "$tar"; die "a Trivy run failed"; }
    rm -f -- "$tar"
    docker rmi "$ref" >/dev/null 2>>"$tmp/err.log"
  done
}

# --- parse ---------------------------------------------------------------------------------------
do_parse() {
  local refs=$1 scandir=$2 findings=$3 summary=$4
  local i flavor ref file line n c f nvuln rules
  read_refs "$refs"
  : >"$tmp/findings.out"
  : >"$tmp/summary.out"
  for i in "${!RFL[@]}"; do
    flavor=${RFL[i]}
    ref=${RFR[i]}
    file="$scandir/scan-$flavor.txt"
    [ -f "$file" ] || die "a scan output file is missing"
    n=0 nvuln=0 rules=
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      [ -n "${line//[$' \t']/}" ] || continue
      split_tabs "$line"
      case ${F[0]} in
        vuln) [ "${#F[@]}" -eq 6 ] || die "a scan record has the wrong number of fields" ;;
        secret) [ "${#F[@]}" -eq 3 ] || die "a scan record has the wrong number of fields" ;;
        *) die "a scan record has an unknown type" ;;
      esac
      for ((c = 1; c < ${#F[@]}; c++)); do
        f=${F[c]}
        [ -n "$f" ] || die "a scan record has an empty field"
        [ "${#f}" -le "$MAX_FIELD" ] || die "a scan record has an over-long field"
        case $f in *[][{}]*) die "a scan record has a structure character in a field" ;; esac
      done
      if [ "${F[0]}" = vuln ]; then
        [ "${#F[1]}" -le 64 ] && [[ ${F[1]} =~ $ID_RE ]] || die "a scan record has a malformed vulnerability id"
        for ((c = 1; c < 6; c++)); do F[c]=${F[c]//$KEEP/?}; done
        nvuln=$((nvuln + 1))
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${F[1]}" "$flavor" "$ref" "${F[5]}" "${F[2]}" "${F[3]}" "${F[4]}" \
          >>"$tmp/findings.out"
      else
        f=${F[1]//$KEEP/?}
        f=${f//,/?}
        if [ -z "$rules" ]; then rules=$f; else rules="$rules,$f"; fi
      fi
    done <"$file"
    [ "${#rules}" -le "$MAX_RULES" ] || die "the rule ids of a flavor are over-long"
    printf '%s\t%s\t%s\t%s\n' "$flavor" "$ref" "$nvuln" "${rules:--}" >>"$tmp/summary.out"
  done
  sort -u "$tmp/findings.out" >"$tmp/findings.sorted"
  mv -f -- "$tmp/findings.sorted" "$findings"
  mv -f -- "$tmp/summary.out" "$summary"
}

# --- file ----------------------------------------------------------------------------------------
check_field() { # check_field <value>: non-empty, short, in the keep set or `?`
  [ -n "$1" ] || die "an input line has an empty field"
  [ "${#1}" -le "$MAX_FIELD" ] || die "an input line has an over-long field"
  # shellcheck disable=SC2254 # KEEPQ is a bracket pattern on purpose
  case $1 in *$KEEPQ*) die "an input line has a character outside the keep set" ;; esac
}

declare -A UPSTREAM_CACHE=()
# pin_key <path>: the pin-table entry of an in-image path, or empty
pin_key() {
  local p=${1#/}
  case $p in
    usr/local/bin/gh | usr/local/libexec/gh-real) echo gh ;;
    usr/local/bin/yq) echo yq ;;
    usr/local/bin/betterleaks) echo betterleaks ;;
    usr/local/bin/uv | usr/local/bin/uvx) echo uv ;;
    usr/local/bin/tofu) echo tofu ;;
    usr/local/bin/tflint) echo tflint ;;
    usr/local/bin/claude) echo claude ;;
    usr/local/bin/node) echo node ;;
    usr/local/lib/node_modules/npm/*) echo npm ;;
    opt/devc/tools/*) echo lock ;;
    *) echo ;;
  esac
}

dockerfile_arg() { # dockerfile_arg <image dir> <ARG name>: its value in the checkout, cleaned
  local v
  v=$(sed -n "s/^ARG $2=//p" "$root/images/$1/Dockerfile" | sed -n 1p)
  [ -n "$v" ] || die "a pinned version could not be read from a Dockerfile"
  printf '%s' "${v//$KEEP/?}"
}

upstream_word() { # upstream_word <repo> <pin>: the comparison with the latest release tag
  local key="$1 $2" tag
  if [ -z "${UPSTREAM_CACHE[$key]+x}" ]; then
    if gh api "repos/$1/releases/latest" --jq .tag_name >"$tmp/tag.txt" 2>>"$tmp/err.log" \
       && tag=$(sed -n 1p "$tmp/tag.txt") && [ "${#tag}" -le 64 ] && [[ $tag =~ $TAG_RE ]]; then
      if [ "${tag#v}" = "$2" ]; then
        UPSTREAM_CACHE[$key]='equals the pin'
      else
        UPSTREAM_CACHE[$key]="latest release is ${BT}${tag}${BT}"
      fi
    else
      UPSTREAM_CACHE[$key]=unknown
    fi
  fi
  printf '%s' "${UPSTREAM_CACHE[$key]}"
}

pin_line() { # pin_line <key>: the one line for a pin-table entry
  local arg dir repo=
  case $1 in
    gh) arg=GH_VERSION dir=base repo=cli/cli ;;
    yq) arg=YQ_VERSION dir=base repo=mikefarah/yq ;;
    betterleaks) arg=BETTERLEAKS_VERSION dir=base repo=betterleaks/betterleaks ;;
    uv) arg=UV_VERSION dir=base repo=astral-sh/uv ;;
    tofu) arg=TOFU_VERSION dir=tofu repo=opentofu/opentofu ;;
    tflint) arg=TFLINT_VERSION dir=tofu repo=terraform-linters/tflint ;;
    claude) arg=CLAUDE_VERSION dir=devapp ;;
    node) arg=NODE_VERSION dir=node ;;
    npm) arg=NPM_VERSION dir=node ;;
    lock) printf 'Pin: %simages/base/tools/uv.lock%s: pinned by images/base/tools/uv.lock' "$BT" "$BT"; return 0 ;;
  esac
  local val word
  val=$(dockerfile_arg "$dir" "$arg")
  if [ -z "$repo" ]; then
    word='upstream not looked up'
  elif [ "$1" = betterleaks ] && [[ $val == *-rc.* ]]; then
    word='upstream: not compared (pinned to a release candidate)'
  else
    word="upstream: $(upstream_word "$repo" "$val")"
  fi
  printf 'Pin: %s%s%s %s%s%s; %s' "$BT" "$arg" "$BT" "$BT" "$val" "$BT" "$word"
}

# render <id> <rows file>: writes $tmp/block.txt (the findings block) and $tmp/body.md
render() {
  local id=$1 rows=$2 line flavor ref path pkg inst fixed key row fp reserve used left=0 kept=0
  local -a R=() P=() K=() pins=()
  local -A seen=()
  while IFS= read -r line; do
    split_tabs "$line"
    flavor=${F[1]} path=${F[3]} pkg=${F[4]} inst=${F[5]} fixed=${F[6]}
    row="- flavor ${BT}${flavor}${BT}, path ${BT}${path}${BT}, package ${BT}${pkg}${BT}, installed ${BT}${inst}${BT}, fixed ${BT}${fixed}${BT}"
    key=$(pin_key "$path")
    if [ -z "$key" ]; then
      row="$row; pin: $UNMAPPED"
    elif [ -z "${seen[$key]+x}" ]; then
      seen[$key]=1
      K+=("$key")
    fi
    R+=("$row")
  done <"$rows"
  mapfile -t R < <(printf '%s\n' "${R[@]}" | sort -u)
  for key in "${K[@]}"; do pins+=("$(pin_line "$key")"); done
  if [ "${#pins[@]}" -gt 0 ]; then mapfile -t pins < <(printf '%s\n' "${pins[@]}" | sort -u); fi
  P=("${R[@]}" "${pins[@]}")
  # LF-joined, no trailing LF: the last newline is stripped by the command substitution
  fp=$(printf '%s' "$(printf '%s\n' "${P[@]}")" | sha256sum)
  fp=${fp%% *}
  reserve=$(( 14 + 64 + 1 + 40 ))
  for line in "${pins[@]}"; do reserve=$(( reserve + ${#line} + 1 )); done
  used=0
  : >"$tmp/block.rows"
  for row in "${R[@]}"; do
    if [ $(( used + ${#row} + 1 + reserve )) -le "$BUDGET" ]; then
      printf '%s\n' "$row" >>"$tmp/block.rows"
      used=$(( used + ${#row} + 1 ))
      kept=$(( kept + 1 ))
    fi
  done
  left=$(( ${#R[@]} - kept ))
  {
    cat "$tmp/block.rows"
    for line in "${pins[@]}"; do printf '%s\n' "$line"; done
    if [ "$left" -gt 0 ]; then printf 'Rows left out: %s\n' "$left"; fi
    printf 'Fingerprint: %s' "$fp"
  } >"$tmp/block.txt"
  {
    printf 'Vulnerability: %s%s%s\n\n' "$BT" "$id" "$BT"
    for flavor in "${FLAVORS[@]}"; do
      ref=$(awk -F'\t' -v f="$flavor" '$2 == f { print $3; exit }' "$rows")
      [ -z "$ref" ] || printf 'Image: %s%s%s %s%s%s\n' "$BT" "$flavor" "$BT" "$BT" "$ref" "$BT"
    done
    printf '\nRows:\n'
    cat "$tmp/block.txt"
    printf '\nEnd of rows.\n\n'
    printf 'Run: %s https://github.com/%s/actions/runs/%s\n' "$GITHUB_RUN_ID" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
  } >"$tmp/body.md"
}

# text_matches <text file> <id>: 0 when the text has the fixed line shape for <id> and a findings
# block byte-identical to $tmp/block.txt
text_matches() {
  local -a L=()
  local i n ro=-1 re=-1 nr=0 ne=0 pre='' post='' tok line block
  mapfile -t L <"$1"
  n=${#L[@]}
  for ((i = 0; i < n; i++)); do
    L[i]=${L[i]%$'\r'}
    if [ "${L[i]}" = 'Rows:' ]; then nr=$((nr + 1)); ro=$i; fi
    if [ "${L[i]}" = 'End of rows.' ]; then ne=$((ne + 1)); re=$i; fi
  done
  [ "$nr" -eq 1 ] && [ "$ne" -eq 1 ] && [ "$ro" -lt "$re" ] || return 1
  for ((i = 0; i < n; i++)); do
    [ "$i" -lt "$ro" ] || [ "$i" -gt "$re" ] || continue
    line=${L[i]}
    if [ -z "$line" ]; then tok=B
    elif [ "$line" = "Vulnerability: ${BT}$2${BT}" ]; then tok=I
    elif [[ $line =~ $IMG_RE ]]; then tok=M
    elif [[ $line =~ ^Run:\ [0-9]+\ https://github\.com/603-Identity/devcontainers/actions/runs/[0-9]+$ ]]; then tok=R
    else return 1; fi
    if [ "$i" -lt "$ro" ]; then pre+=$tok; else post+=$tok; fi
  done
  [[ $pre =~ ^IBM+B$ ]] && [[ $post =~ ^BRB*$ ]] || return 1
  block=
  for ((i = ro + 1; i < re; i++)); do
    if [ -z "$block" ] && [ "$i" -eq $((ro + 1)) ]; then block=${L[i]}; else block+=$'\n'"${L[i]}"; fi
  done
  [ "$block" = "$(cat "$tmp/block.txt")" ]
}

gh_get() { gh api "$@" 2>>"$tmp/err.log"; }

do_file() {
  local findings=$1 summary=$2 line c f id flavor n
  local -a ids=() sec_flavors=() sec_rules=()
  local nfind=0 nsec=0 opened_n out
  # 1. validate every line of both files before any gh call
  while IFS= read -r line || [ -n "$line" ]; do
    split_tabs "$line"
    [ "${#F[@]}" -eq 7 ] || die "a findings line has the wrong number of fields"
    for f in "${F[@]}"; do check_field "$f"; done
    [ "${#F[0]}" -le 64 ] && [[ ${F[0]} =~ $ID_RE ]] || die "a findings line has a malformed vulnerability id"
    is_flavor "${F[1]}" || die "a findings line names an unknown flavor"
    [[ ${F[2]} =~ $REF_RE ]] && [ "${BASH_REMATCH[1]}" = "${F[1]}" ] || die "a findings line has a bad image reference"
    nfind=$((nfind + 1))
  done <"$findings"
  : >"$tmp/summary.lines"
  while IFS= read -r line || [ -n "$line" ]; do
    split_tabs "$line"
    [ "${#F[@]}" -eq 4 ] || die "a summary line has the wrong number of fields"
    for ((c = 0; c < 3; c++)); do check_field "${F[c]}"; done
    [ -n "${F[3]}" ] && [ "${#F[3]}" -le "$MAX_RULES" ] || die "a summary line has a bad rule field"
    # shellcheck disable=SC2254
    case ${F[3]} in *$KEEPQ*) die "a summary line has a character outside the keep set" ;; esac
    is_flavor "${F[0]}" || die "a summary line names an unknown flavor"
    [[ ${F[1]} =~ $REF_RE ]] && [ "${BASH_REMATCH[1]}" = "${F[0]}" ] || die "a summary line has a bad image reference"
    [[ ${F[2]} =~ ^[0-9]{1,6}$ ]] || die "a summary line has a bad count"
    if [ "${F[3]}" != - ]; then
      sec_flavors+=("${F[0]}")
      sec_rules+=("${F[3]}")
      nsec=$((nsec + 1))
    fi
    printf -- '- %s%s%s: %s%s%s, %s vulnerabilities\n' "$BT" "${F[0]}" "$BT" "$BT" "${F[1]}" "$BT" "${F[2]}" >>"$tmp/summary.lines"
  done <"$summary"
  [ "${GITHUB_REPOSITORY-}" = "$THIS_REPO" ] || die "GITHUB_REPOSITORY is not this repository"
  [[ ${GITHUB_RUN_ID-} =~ ^[0-9]{1,20}$ ]] || die "GITHUB_RUN_ID is not a number"

  # 2. file one issue per vulnerability id
  : >"$tmp/results.lines"
  if [ "$nfind" -gt 0 ]; then
    mapfile -t ids < <(cut -f1 "$findings" | sort -u)
    gh_get "repos/$GITHUB_REPOSITORY/issues?state=open&per_page=100" --paginate >"$tmp/issues.json"
    for id in "${ids[@]}"; do
      awk -F'\t' -v id="$id" '$1 == id' "$findings" >"$tmp/rows.tsv"
      render "$id" "$tmp/rows.tsv"
      local title="Trivy daily scan: ${id} in the published images" num
      num=$(jq -s -r --arg t "$title" --arg b "$BOT_LOGIN" \
        '[.[][] | select(.pull_request == null) | select(.user.login == $b and .user.type == "Bot") | select(.title == $t) | .number] | sort | .[0] // empty' \
        "$tmp/issues.json" 2>>"$tmp/err.log")
      if [ -z "$num" ]; then
        jq -n --arg title "$title" --rawfile body "$tmp/body.md" '{title: $title, body: $body}' >"$tmp/req.json"
        gh api --method POST "repos/$GITHUB_REPOSITORY/issues" --input - <"$tmp/req.json" >"$tmp/resp.json" 2>>"$tmp/err.log"
        opened_n=$(jq -r '.number' "$tmp/resp.json" 2>>"$tmp/err.log")
        [[ $opened_n =~ ^[0-9]+$ ]] || die "the issues API returned no issue number"
        printf -- '- %s%s%s: issue #%s, opened\n' "$BT" "$id" "$BT" "$opened_n" >>"$tmp/results.lines"
        continue
      fi
      [[ $num =~ ^[0-9]+$ ]] || die "the issue listing holds a malformed number"
      gh_get "repos/$GITHUB_REPOSITORY/issues/$num" >"$tmp/issue.json"
      gh_get "repos/$GITHUB_REPOSITORY/issues/$num/comments?per_page=100" --paginate >"$tmp/comments.json"
      jq -s -j --arg b "$BOT_LOGIN" \
        '(.[0]) as $i | ([{t: ($i.body // ""), c: $i.created_at}] + [.[1:][][] | select(.user.login == $b and .user.type == "Bot") | {t: (.body // ""), c: .created_at}]) | sort_by(.c) | last | .t' \
        "$tmp/issue.json" "$tmp/comments.json" >"$tmp/newest.txt" 2>>"$tmp/err.log"
      if text_matches "$tmp/newest.txt" "$id"; then
        printf -- '- %s%s%s: issue #%s, unchanged\n' "$BT" "$id" "$BT" "$num" >>"$tmp/results.lines"
      else
        jq -n --rawfile body "$tmp/body.md" '{body: $body}' >"$tmp/req.json"
        gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$num/comments" --input - <"$tmp/req.json" >"$tmp/resp.json" 2>>"$tmp/err.log"
        printf -- '- %s%s%s: issue #%s, commented on\n' "$BT" "$id" "$BT" "$num" >>"$tmp/results.lines"
      fi
    done
  fi

  # 3. the step summary, then fail on any secret record
  {
    printf '## Trivy daily scan\n\n### Scanned\n\n'
    cat "$tmp/summary.lines"
    printf '\n### Issues\n\n'
    if [ -s "$tmp/results.lines" ]; then cat "$tmp/results.lines"; else printf -- '- none\n'; fi
    if [ "$nsec" -gt 0 ]; then
      printf '\n### Secret records\n\n'
      for n in "${!sec_flavors[@]}"; do
        flavor=${sec_flavors[n]}
        printf -- '- %s%s%s: rule ids %s%s%s\n' "$BT" "$flavor" "$BT" "$BT" "${sec_rules[n]}" "$BT"
      done
    fi
  } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
  out=0
  [ "$nsec" -eq 0 ] || out=1
  [ "$out" -eq 0 ] || die "a scan holds a secret record (see the step summary)"
}

case $cmd in
  resolve) do_resolve "$1" ;;
  scan) do_scan "$1" "$2" ;;
  parse) do_parse "$1" "$2" "$3" "$4" ;;
  file) do_file "$1" "$2" ;;
esac
