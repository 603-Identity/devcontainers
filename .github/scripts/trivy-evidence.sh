#!/usr/bin/env bash
# CI no-ignore Trivy re-scan: scans the five images the `publish` job of build.yml just built
# with NO Trivy exceptions applied, and writes one results file in the format
# tools/host/trivy-rescan.sh writes plus a `## Published digests` section, so a .trivyignore.yaml
# renewal can cite a workflow artifact instead of a host session (docs/trivy-renewal.md).
#
# Usage:      GITHUB_SHA=<40 hex> BASE_DIGEST=<d> TOFU_DIGEST=<d> NODE_DIGEST=<d> DEVAPP_DIGEST=<d> \
#             DEVAPP_TOFU_DIGEST=<d> [REGISTRY=<registry>] bash .github/scripts/trivy-evidence.sh TAG OUTPUT
#
#   TAG          the MAJOR.run_number value build-and-test.sh push mode tags the images with
#                (matches ^[0-9]+\.[0-9]+$).
#   GITHUB_SHA   must be set: 40 lowercase hex, the base commit the results file records.
#   *_DIGEST     the five registry digests the push step of build.yml outputs, one per flavour; each
#                must be set and match ^sha256:[0-9a-f]{64}$. The script checks that the local image of
#                the flavour carries REGISTRY/devcontainer-FLAVOR@DIGEST among its RepoDigests (local
#                image metadata, no registry call) and records the five references.
#   REGISTRY     default ghcr.io/603-identity, as in build-and-test.sh.
#   OUTPUT       follows trivy-rescan.sh's HOST_RESULTS contract: a path that does not exist (in an
#                existing directory), or an existing empty regular file that is not a symlink. The
#                script writes it once, at the very end, by moving the finished file over it.
#
# It reads the five LOCAL images (their ids and RepoDigests) under the refs build-and-test.sh push mode tags them with
# ($REGISTRY/devcontainer-<flavor>:TAG). It builds, pulls and pushes nothing, logs in to nothing,
# never reads the out/*.sarif files, and mounts no Docker socket into any container.
#
# Exit status:
#   0  success
#   2  usage error: argument count, TAG, GITHUB_SHA, one of the five digest variables or OUTPUT
#      breaking its contract; nothing touched
#   1  any other failure, a local image that does not carry its digest included; no results file is left (an empty OUTPUT that existed is removed)
# Each failure (1, 2) prints exactly one line on stdout, a fixed `::warning::` text that carries no
# scan-derived field, and the reason on stderr as plain text. The results file is published as a
# workflow artifact, so every field taken from scan output is checked before it can reach it.
set -Eeuo pipefail
export LC_ALL=C

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

# fd 3 is the script's own stdout: a failure inside a redirected function still reaches it.
exec 3>&1
WARNING='::warning::trivy-evidence: no renewal evidence written (see the step log)'
usage_error() { echo "trivy-evidence: usage error: $1" >&2; exit 2; }
die() { echo "trivy-evidence: $*" >&2; exit 1; }

tmp=
armed=0
results=
cleanup() {
  local rc=$?
  trap - ERR
  if [ "$rc" -ne 0 ]; then printf '%s\n' "$WARNING" >&3; fi
  if [ "$armed" -eq 1 ] && [ "$rc" -ne 0 ] \
     && [ -f "$results" ] && [ ! -L "$results" ] && [ ! -s "$results" ]; then
    rm -f -- "$results"
  fi
  if [ -n "$tmp" ]; then rm -rf -- "$tmp"; fi
  return 0
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
trap 'echo "trivy-evidence: line $LINENO: command failed: $BASH_COMMAND" >&2; exit 1' ERR

# --- usage checks: no docker call, nothing written ---------------------------------------------
[ "$#" -eq 2 ] || usage_error "expected exactly two arguments, TAG and OUTPUT"
tag=$1
results=$2
[[ $tag =~ ^[0-9]+\.[0-9]+$ ]] || usage_error "TAG must match ^[0-9]+\\.[0-9]+\$"
commit=${GITHUB_SHA-}
[[ $commit =~ ^[0-9a-f]{40}$ ]] || usage_error "GITHUB_SHA must be set to 40 lowercase hex characters"
digest_vars=(BASE_DIGEST TOFU_DIGEST NODE_DIGEST DEVAPP_DIGEST DEVAPP_TOFU_DIGEST)
digests=()
for v in "${digest_vars[@]}"; do
  d=${!v-}
  [[ $d =~ ^sha256:[0-9a-f]{64}$ ]] || usage_error "$v must be set to sha256: and 64 lowercase hex characters"
  digests+=("$d")
done
[ -n "$results" ] || usage_error "OUTPUT must name the results path"
case $results in */) usage_error "OUTPUT must name a file, not a directory" ;; esac
if [ -L "$results" ]; then
  usage_error "OUTPUT must not be a symlink"
elif [ -e "$results" ]; then
  { [ -f "$results" ] && [ ! -s "$results" ]; } \
    || usage_error "OUTPUT exists and is not an empty regular file"
else
  [ -d "$(dirname -- "$results")" ] || usage_error "the directory of OUTPUT does not exist"
fi
armed=1

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
registry=${REGISTRY:-ghcr.io/603-identity}
tmp=$(mktemp -d)

# --- pins --------------------------------------------------------------------------------------
pin() { # pin <image dir> <ARG name>: the ARG's value, read the way build-and-test.sh's arg does
  local v
  v=$(sed -n "s/^ARG $2=//p" "$root/images/$1/Dockerfile")
  v=${v%%$'\n'*}
  [ -n "$v" ] || die "could not read $2 from images/$1/Dockerfile"
  printf '%s' "$v"
}
pin_gh=$(pin base GH_VERSION)
pin_betterleaks=$(pin base BETTERLEAKS_VERSION)
pin_yq=$(pin base YQ_VERSION)
pin_tofu=$(pin tofu TOFU_VERSION)
pin_tflint=$(pin tofu TFLINT_VERSION)

# --- images: the local ones push mode tagged ----------------------------------------------------
flavors=(base tofu node devapp devapp-tofu)
ids=()
ref() { printf '%s/devcontainer-%s:%s' "$registry" "$1" "$tag"; }
pub_refs=()
for i in "${!flavors[@]}"; do
  flavor=${flavors[i]}
  v=$(docker image inspect --format '{{.Id}}' "$(ref "$flavor")")
  [[ $v =~ ^sha256:[0-9a-f]{64}$ ]] || die "$flavor: docker returned an unexpected image id"
  ids+=("$v")
  # the same RepoDigests template push_and_digest in build-and-test.sh reads
  rd=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$(ref "$flavor")")
  want="$registry/devcontainer-$flavor@${digests[i]}"
  case $'\n'"$rd"$'\n' in
    *$'\n'"$want"$'\n'*) ;;
    *) die "$flavor: the local image does not carry the pushed digest among its RepoDigests" ;;
  esac
  pub_refs+=("$want")
done

# --- scan, with no Docker socket and no ignore file ---------------------------------------------
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

echo "trivy-evidence: scanning" >&2
for i in "${!flavors[@]}"; do
  flavor=${flavors[i]}
  docker save -o "$tmp/$flavor.tar" "$(ref "$flavor")"
  docker run --rm -v devc-trivy-cache:/root/.cache/trivy -v "$tmp/$flavor.tar:/scan/image.tar:ro" \
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

# --- symbol check ------------------------------------------------------------------------------
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
  docker cp "$cid:$path" "$f" || rc=$?
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

# --- results -----------------------------------------------------------------------------------
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
  printf '\n## Published digests\n\n'
  for i in "${!flavors[@]}"; do
    printf -- "- %s ${BT}%s${BT}\n" "${flavors[i]}" "$(clean "${pub_refs[i]}")"
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
echo "trivy-evidence: done" >&2
