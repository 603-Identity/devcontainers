#!/usr/bin/env bash
# Host re-scan: rebuild this repo's five images (base, tofu, node, devapp, devapp-tofu) from one
# commit on origin/main and scan each with NO Trivy exceptions applied, so a .trivyignore.yaml
# renewal can cite one results file as evidence. Runs only on the owner's host, through
# Procedure A of docs/host-steps.md, never in CI or the dev container.
#
# It mirrors .github/scripts/build-and-test.sh without running it: that script scans each image
# right after building it, and in push mode stops at the first finding, which would leave later
# images unbuilt and unscanned. (Its local mode scans every flavour before failing, but still with
# the ignore file applied, which this evidence must not use.)
#
# Usage:      HOST_RESULTS=<path> bash tools/host/trivy-rescan.sh <base commit>
#
#   <base commit>  exactly one argument: 40 lowercase hex characters, reachable from origin/main.
#   HOST_RESULTS   must be set and non-empty, and must name either a path that does not exist
#                  (in an existing directory) or an existing empty regular file that is not a
#                  symlink. Anything else (a dangling symlink, a directory, a non-empty file, a
#                  path whose directory does not exist) is a usage error. The script writes that
#                  path once, at the very end, by moving the finished results file over it. After
#                  any failure past the usage checks (status 1, 3 or 4) it leaves no results file:
#                  an empty regular file at that path is removed. A usage error touches nothing.
#
# Exit status:
#   0  success
#   2  usage error: argument count or shape wrong, or HOST_RESULTS breaking its contract
#   3  the base commit is not reachable from origin/main
#   4  drift guard: .github/scripts/build-and-test.sh changed since this script was written
#   1  any other failure (a command failing exits 1 through the ERR trap; the checks below that
#      print their own one-line message exit 1 as well)
# Each refusal (2, 3, 4) prints exactly one line to stderr naming its reason.
#
# It never pushes, publishes, logs in to a registry or GitHub, reads a token directory, mounts the
# Docker socket into any container, or uses any host tool beyond bash, git, docker, coreutils, sed,
# and cygpath on a Windows host only. Trivy's own template selects every field taken from scan
# output; the script checks each returned line before it can reach the results file, which is
# published in a public PR.
set -Eeuo pipefail
export LC_ALL=C

# The sha256 of .github/scripts/build-and-test.sh as it stands at the commit this script is
# written against. A clone whose copy differs stops with status 4 before any docker call. There
# is no way around it: update this constant in a reviewed PR when that script changes.
BUILD_SCRIPT_SHA256=60b8c49fac773f2c4c42aeb9aa2938ddae1ff17f36b5663467a9c9a9b323fe90

# The same image string as build-and-test.sh's TRIVY variable.
TRIVY="aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969"

# Trivy's template: one tab-separated line per vulnerability and per secret finding, and nothing
# else. It never selects a secret's matched text, code lines or title.
# shellcheck disable=SC2016 # a Go template: its $t is Trivy's, not the shell's
TEMPLATE='{{range .}}{{$t := .Target}}{{range .Vulnerabilities}}vuln{{"\t"}}{{.VulnerabilityID}}{{"\t"}}{{.PkgName}}{{"\t"}}{{.InstalledVersion}}{{"\t"}}{{.FixedVersion}}{{"\t"}}{{if .PkgPath}}{{.PkgPath}}{{else}}{{$t}}{{end}}{{"\n"}}{{end}}{{range .Secrets}}secret{{"\t"}}{{.RuleID}}{{"\t"}}{{$t}}{{"\n"}}{{end}}{{end}}'

# Characters a scan field may keep; every other one is written as `?`.
KEEP='[^A-Za-z0-9 ._:/@+~,=()-]'
MAX_FIELD=256
MAX_BINARY=536870912  # 512 MiB, the runbook's Rule 6 cap
MAX_RESULTS=1048576   # 1 MiB
BT=$'`'  # a backtick: every Trivy-derived field is written inside a code span

usage_error() { echo "trivy-rescan: usage error: $1" >&2; exit 2; }
die() { echo "trivy-rescan: $*" >&2; exit 1; }

# --- usage checks: no git or docker call, nothing written -------------------------------------
[ "$#" -eq 1 ] || usage_error "expected exactly one argument, the base commit (40 lowercase hex)"
commit=$1
[[ $commit =~ ^[0-9a-f]{40}$ ]] || usage_error "the base commit must be 40 lowercase hex characters"
results=${HOST_RESULTS-}
[ -n "$results" ] || usage_error "HOST_RESULTS must be set to the results path"
case $results in */) usage_error "HOST_RESULTS must name a file, not a directory" ;; esac
if [ -L "$results" ]; then
  usage_error "HOST_RESULTS must not be a symlink"
elif [ -e "$results" ]; then
  { [ -f "$results" ] && [ ! -s "$results" ]; } \
    || usage_error "HOST_RESULTS exists and is not an empty regular file"
else
  [ -d "$(dirname -- "$results")" ] || usage_error "the directory of HOST_RESULTS does not exist"
fi

# --- traps -------------------------------------------------------------------------------------
tmp=
armed=0
cleanup() {
  local rc=$?
  trap - ERR
  if [ "$armed" -eq 1 ] && [ "$rc" -ne 0 ] \
     && [ -f "$results" ] && [ ! -L "$results" ] && [ ! -s "$results" ]; then
    rm -f -- "$results"
  fi
  if [ -n "$tmp" ]; then rm -rf -- "$tmp"; fi
  return 0
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
trap 'echo "trivy-rescan: line $LINENO: command failed: $BASH_COMMAND" >&2; exit 1' ERR
armed=1

# --- Step 1: clone -----------------------------------------------------------------------------
tmp=$(mktemp -d)
# Git Bash on a Windows host: docker.exe and git.exe are native tools and need C:/... paths. $d is
# what docker and git are handed; $tmp is the script's own view of the same directory.
d=$tmp
if command -v cygpath >/dev/null 2>&1; then d=$(cygpath -m "$tmp"); export MSYS_NO_PATHCONV=1; fi
export GIT_TERMINAL_PROMPT=0

git -c credential.helper= clone --quiet https://github.com/603-Identity/devcontainers "$d/repo"
[ -d "$tmp/repo/.git" ] || die "the clone is not at the expected path, so the script cannot read it"
if ! git -C "$d/repo" merge-base --is-ancestor "$commit" origin/main 2>/dev/null; then
  echo "trivy-rescan: the base commit is not reachable from origin/main" >&2
  exit 3
fi
git -C "$d/repo" -c advice.detachedHead=false checkout --quiet --detach "$commit"

# --- Step 2: drift guard -----------------------------------------------------------------------
drift() {
  echo "trivy-rescan: drift guard: .github/scripts/build-and-test.sh changed, so tools/host/trivy-rescan.sh needs an update" >&2
  exit 4
}
[ -f "$tmp/repo/.github/scripts/build-and-test.sh" ] || drift
got=$(sha256sum "$tmp/repo/.github/scripts/build-and-test.sh")
[ "${got%% *}" = "$BUILD_SCRIPT_SHA256" ] || drift

# --- Step 3: pins ------------------------------------------------------------------------------
pin() { # pin <image dir> <ARG name>: the ARG's value, read the way build-and-test.sh's arg does
  local v
  v=$(sed -n "s/^ARG $2=//p" "$tmp/repo/images/$1/Dockerfile")
  v=${v%%$'\n'*}
  [ -n "$v" ] || die "could not read $2 from images/$1/Dockerfile"
  printf '%s' "$v"
}
pin_gh=$(pin base GH_VERSION)
pin_betterleaks=$(pin base BETTERLEAKS_VERSION)
pin_yq=$(pin base YQ_VERSION)
pin_tofu=$(pin tofu TOFU_VERSION)
pin_tflint=$(pin tofu TFLINT_VERSION)

# --- Step 4: build -----------------------------------------------------------------------------
flavors=(base tofu node devapp devapp-tofu)
ids=()
ref() { printf 'devcontainer-%s:rescan' "$1"; }
image_id() { # image_id <flavor>
  local v
  v=$(docker image inspect --format '{{.Id}}' "$(ref "$1")")
  [[ $v =~ ^sha256:[0-9a-f]{64}$ ]] || die "$1: docker returned an unexpected image id"
  ids+=("$v")
}

echo "trivy-rescan: building the five images, no cache"
docker build --no-cache --pull -t "$(ref base)" "$d/repo/images/base"
image_id base
mkdir -p "$tmp/claude-export"
docker build --no-cache --target claude-verify --build-arg "BASE_IMAGE=$(ref base)" \
  --output "type=local,dest=$d/claude-export" "$d/repo/images/devapp"
[ -s "$tmp/claude-export/claude" ] || die "claude-verify exported no claude binary"

build_flavor() { # build_flavor <flavor> <base image>
  local flavor=$1 from=$2 dir=$1 extra=() got
  case $flavor in
    devapp | devapp-tofu)
      dir=devapp
      extra=(--build-arg "REVISION=$commit" --build-context "claude-export=$d/claude-export") ;;
  esac
  docker build --no-cache -t "$(ref "$flavor")" --build-arg "BASE_IMAGE=$from" "${extra[@]}" "$d/repo/images/$dir"
  case $flavor in
    devapp | devapp-tofu)
      got=$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$(ref "$flavor")")
      [ "$got" = "$commit" ] || die "$flavor does not carry the base commit as its revision label" ;;
  esac
  image_id "$flavor"
}
build_flavor tofu "$(ref base)"
build_flavor node "$(ref base)"
build_flavor devapp "$(ref base)"
build_flavor devapp-tofu "$(ref tofu)"

# --- Step 5: scan, with no Docker socket -------------------------------------------------------
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

check_scan() { # check_scan <flavor> <file>: the findings, as Markdown, on stdout
  local flavor=$1 file=$2 n=0 any=0 line c f
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ -n "${line//[$' \t']/}" ] || continue
    split_tabs "$line"
    case ${F[0]} in
      vuln) [ "${#F[@]}" -eq 6 ] || die "$flavor: scan output line $n has the wrong number of fields" ;;
      secret) [ "${#F[@]}" -eq 3 ] || die "$flavor: scan output line $n has the wrong number of fields" ;;
      *) die "$flavor: scan output line $n has an unknown record type" ;;
    esac
    for ((c = 1; c < ${#F[@]}; c++)); do
      f=${F[c]}
      [ -n "$f" ] || die "$flavor: scan output line $n has an empty field"
      [ "${#f}" -le "$MAX_FIELD" ] || die "$flavor: scan output line $n has an over-long field"
      case $f in *[][{}]*) die "$flavor: scan output line $n has a structure character in a field" ;; esac
      F[c]=${f//$KEEP/?}
    done
    any=1
    if [ "${F[0]}" = vuln ]; then
      printf -- "- vulnerability ${BT}%s${BT}, package ${BT}%s${BT}, installed ${BT}%s${BT}, fixed ${BT}%s${BT}, path ${BT}%s${BT}\n" \
        "${F[1]}" "${F[2]}" "${F[3]}" "${F[4]}" "${F[5]}"
    else
      printf -- "- secret rule ${BT}%s${BT}, path ${BT}%s${BT}\n" "${F[1]}" "${F[2]}"
    fi
  done <"$file"
  [ "$any" -eq 1 ] || printf -- '- none\n'
}

echo "trivy-rescan: scanning"
for i in "${!flavors[@]}"; do
  flavor=${flavors[i]}
  docker save -o "$d/$flavor.tar" "$(ref "$flavor")"
  docker run --rm -v devc-trivy-cache:/root/.cache/trivy -v "$d/$flavor.tar:/scan/image.tar:ro" \
    "$TRIVY" image --input /scan/image.tar --quiet --scanners vuln,secret --severity HIGH,CRITICAL \
    --ignore-unfixed --format template --template "$TEMPLATE" >"$tmp/scan-$flavor.txt"
  rm -f -- "$tmp/$flavor.tar"
  check_scan "$flavor" "$tmp/scan-$flavor.txt" >"$tmp/findings-$flavor.md"
done

docker run --rm -v devc-trivy-cache:/root/.cache/trivy "$TRIVY" --version >"$tmp/trivy-version.txt"
trivy_version='' db_version='' db_updated=''
seen_tv=0 seen_dbv=0 seen_dbu=0 in_db=0
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "${line//[$' \t']/}" ] || continue
  case $line in
    ' '* | $'\t'*)
      [ "$in_db" -eq 1 ] || continue
      t=${line#"${line%%[!$' \t']*}"}
      case $t in
        Version:*)
          if [ "$seen_dbv" -eq 0 ]; then
            seen_dbv=1; db_version=${t#Version:}
          fi ;;
        UpdatedAt:*)
          if [ "$seen_dbu" -eq 0 ]; then
            seen_dbu=1; db_updated=${t#UpdatedAt:}
          fi ;;
      esac ;;
    *)
      in_db=0
      case $line in
        Version:*)
          if [ "$seen_tv" -eq 0 ]; then
            seen_tv=1; trivy_version=${line#Version:}
          fi ;;
        'Vulnerability DB:'*) in_db=1 ;;
      esac ;;
  esac
done <"$tmp/trivy-version.txt"
trim() { # trim <text>: without leading and trailing spaces and tabs
  local s=$1
  s=${s#"${s%%[!$' \t']*}"}
  s=${s%"${s##*[!$' \t']}"}
  printf '%s' "$s"
}
trivy_version=$(trim "$trivy_version")
db_version=$(trim "$db_version")
db_updated=$(trim "$db_updated")
version_value() { # version_value <name> <value>: checks one --version value
  [ -n "$2" ] || die "the Trivy --version output has no $1"
  [ "${#2}" -le "$MAX_FIELD" ] || die "the Trivy --version output has an over-long $1"
}
version_value "Trivy version" "$trivy_version"
version_value "vulnerability DB version" "$db_version"
version_value "vulnerability DB UpdatedAt" "$db_updated"

# --- Step 6: symbol check ----------------------------------------------------------------------
syms=(runtime.main main.main golang.org/x/net/html.Parse 'golang.org/x/net/html.(*parser)'
  golang.org/x/net/html.fosterParent golang.org/x/net/html.NewTokenizer)
found=
sym_check() { # sym_check <file>: sets found to the |-joined strings the file carries
  local rc=0 l s known
  docker run --rm -i --network none --entrypoint grep "${ids[0]}" -a -F -o \
    -e runtime.main -e main.main -e golang.org/x/net/html.Parse -e 'golang.org/x/net/html.(*parser)' \
    -e golang.org/x/net/html.fosterParent -e golang.org/x/net/html.NewTokenizer \
    <"$1" >"$tmp/grep.out" || rc=$?
  [ "$rc" -le 1 ] || die "the symbol search exited with status $rc"
  sort -u "$tmp/grep.out" >"$tmp/grep.uniq"
  found='|'
  while IFS= read -r l || [ -n "$l" ]; do
    known=0
    for s in "${syms[@]}"; do
      if [ "$l" = "$s" ]; then known=1; found="$found$s|"; fi
    done
    [ "$known" -eq 1 ] || die "the symbol search printed a line that is not one of the six strings"
  done <"$tmp/grep.uniq"
}
has_sym() { case $found in *"|$1|"*) return 0 ;; *) return 1 ;; esac; }

binaries="$tmp/binaries.md"
: >"$binaries"
check_binary() { # check_binary <flavor> <image> <in-image path>
  local flavor=$1 path=$3 cid rc=0 f size sum s
  f="$tmp/bin-$flavor-${path##*/}"
  cid=$(docker create "$2")
  [[ $cid =~ ^[0-9a-f]+$ ]] || die "docker create returned an unexpected container id"
  docker cp "$cid:$path" "$d/${f##*/}" || rc=$?
  docker rm "$cid" >/dev/null
  [ "$rc" -eq 0 ] || die "could not copy $path out of the $flavor image"
  { [ -f "$f" ] && [ ! -L "$f" ]; } || die "$path from the $flavor image is not a regular file"
  size=$(wc -c <"$f")
  [ "$size" -le "$MAX_BINARY" ] || die "$path from the $flavor image is over 512 MiB"
  sum=$(sha256sum "$f")
  sum=${sum%% *}
  sym_check "$f"
  if has_sym runtime.main && has_sym main.main; then
    printf -- "- %s ${BT}%s${BT}, sha256 ${BT}%s${BT}\n" "$flavor" "$path" "$sum" >>"$binaries"
    for s in "${syms[@]:2}"; do
      if has_sym "$s"; then
        printf -- "  - ${BT}%s${BT}: present\n" "$s" >>"$binaries"
      else
        printf -- "  - ${BT}%s${BT}: absent\n" "$s" >>"$binaries"
      fi
    done
  else
    printf -- "- %s ${BT}%s${BT}, sha256 ${BT}%s${BT}: unchecked (runtime.main and main.main were not both found)\n" \
      "$flavor" "$path" "$sum" >>"$binaries"
  fi
  rm -f -- "$f"
}
check_binary base "$(ref base)" /usr/local/bin/gh
check_binary base "$(ref base)" /usr/local/bin/betterleaks
check_binary tofu "$(ref tofu)" /usr/local/bin/tofu
check_binary devapp "$(ref devapp)" /usr/local/libexec/gh-real

# --- Step 7: results ---------------------------------------------------------------------------
clean() { printf '%s' "${1//$KEEP/?}"; }
{
  printf '# Trivy re-scan results\n\n'
  printf "## Base commit\n\n${BT}%s${BT}\n\n" "$commit"
  printf '## Pins\n\n'
  printf -- "- GH_VERSION ${BT}%s${BT}\n" "$(clean "$pin_gh")"
  printf -- "- BETTERLEAKS_VERSION ${BT}%s${BT}\n" "$(clean "$pin_betterleaks")"
  printf -- "- YQ_VERSION ${BT}%s${BT}\n" "$(clean "$pin_yq")"
  printf -- "- TOFU_VERSION ${BT}%s${BT}\n" "$(clean "$pin_tofu")"
  printf -- "- TFLINT_VERSION ${BT}%s${BT}\n\n" "$(clean "$pin_tflint")"
  printf '## Images\n\n'
  for i in "${!flavors[@]}"; do
    printf -- "- %s ${BT}%s${BT}\n" "${flavors[i]}" "${ids[i]}"
  done
  printf '\n## Trivy\n\n'
  printf -- "- Trivy version: ${BT}%s${BT}\n" "$(clean "$trivy_version")"
  printf -- "- Vulnerability DB version: ${BT}%s${BT}\n" "$(clean "$db_version")"
  printf -- "- Vulnerability DB UpdatedAt: ${BT}%s${BT}\n\n" "$(clean "$db_updated")"
  for flavor in "${flavors[@]}"; do
    printf '## Findings: %s\n\n' "$flavor"
    cat "$tmp/findings-$flavor.md"
    printf '\n'
  done
  printf '## Binaries\n\n'
  cat "$binaries"
} >"$tmp/results.md"
size=$(wc -c <"$tmp/results.md")
[ "$size" -lt "$MAX_RESULTS" ] || die "the results file is over 1 MiB"
mv -f -- "$tmp/results.md" "$results"
echo "trivy-rescan: done"
