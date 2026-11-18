#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Offline tests for tools/host/trivy-rescan.sh. Every scenario runs the real script against fake
# `git` and `docker` executables written into the scenario's scratch space and put first on PATH,
# with TMPDIR set to a fresh directory and tripwire `jq` and `gh` executables ahead of
# tools/tests/bin. The fixture tree the fake clone copies is built at run time from the
# checkout under test.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite trivy-rescan

SCRIPT="$TOOLS_DIR/host/trivy-rescan.sh"
COMMIT=0123456789abcdef0123456789abcdef01234567
# The exact template, held here as its own constant (not read from the script).
TEMPLATE='{{range .}}{{$t := .Target}}{{range .Vulnerabilities}}vuln{{"\t"}}{{.VulnerabilityID}}{{"\t"}}{{.PkgName}}{{"\t"}}{{.InstalledVersion}}{{"\t"}}{{.FixedVersion}}{{"\t"}}{{if .PkgPath}}{{.PkgPath}}{{else}}{{$t}}{{end}}{{"\n"}}{{end}}{{range .Secrets}}secret{{"\t"}}{{.RuleID}}{{"\t"}}{{$t}}{{"\n"}}{{end}}{{end}}'
MARK=SECRETMARKER

# --- the fake executables ----------------------------------------------------------------------

write_fakes() { # writes $SCRATCH/bin/{git,docker,jq,gh}
  local b="$SCRATCH/bin"
  mkdir -p "$b"
  cat >"$b/jq" <<'EOF'
#!/usr/bin/env bash
echo "jq $*" >> "$TR_STATE/tripwire"; exit 1
EOF
  cat >"$b/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$TR_STATE/tripwire"; exit 1
EOF
  cat >"$b/git" <<'EOF'
#!/usr/bin/env bash
# Fake git: the three call shapes the script may make, and nothing else.
printf 'git %s\n' "$*" >> "$TR_LOG"
if [ "$#" -eq 6 ] && [ "$1" = -c ] && [ "$2" = credential.helper= ] && [ "$3" = clone ] \
   && [ "$4" = --quiet ] && [ "$5" = https://github.com/603-Identity/devcontainers ]; then
  mkdir -p "$6" && cp -R "$TR_FIXTURE/." "$6/"; exit 0
fi
if [ "$#" -eq 6 ] && [ "$1" = -C ] && [ "$3" = merge-base ] && [ "$4" = --is-ancestor ] && [ "$6" = origin/main ]; then
  rc=${TR_MERGE_RC:-0}
  [ "$rc" -ne 128 ] || echo "fatal: Not a valid object name $5" >&2
  exit "$rc"
fi
if [ "$#" -eq 8 ] && [ "$1" = -C ] && [ "$3" = -c ] && [ "$4" = advice.detachedHead=false ] \
   && [ "$5" = checkout ] && [ "$6" = --quiet ] && [ "$7" = --detach ]; then
  exit 0
fi
echo "fake git: unexpected call: $*" >&2
exit 99
EOF
  cat >"$b/docker" <<'EOF'
#!/usr/bin/env bash
# Fake docker. See trivy-rescan-test.sh for what each TR_* variable does.
printf 'docker %s\n' "$*" >> "$TR_LOG"
printf '%s\n' "${MSYS_NO_PATHCONV-unset}" >> "$TR_STATE/msys"
violation() { echo "$*" >> "$TR_STATE/violations"; echo "fake docker: $*" >&2; exit 99; }
fake_id() { printf 'sha256:%s' "$(printf '%s' "$1" | sha256sum | cut -c1-64)"; }
flavor_of() { local f=${1#devcontainer-}; printf '%s' "${f%:rescan}"; }
TRIVY=$(sed -n 's/^TRIVY="\(.*\)"$/\1/p' "$TR_FIXTURE/.github/scripts/build-and-test.sh")
sub=${1:-}
shift || true
case $sub in
  build)
    target= out= tag= revision=
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      case ${args[i]} in
        --target) target=${args[i + 1]} ;;
        --output) out=${args[i + 1]} ;;
        -t) tag=${args[i + 1]} ;;
        --build-arg) case ${args[i + 1]} in REVISION=*) revision=${args[i + 1]#REVISION=} ;; esac ;;
      esac
    done
    if [ "$target" = claude-verify ]; then
      dest=${out#type=local,dest=}
      mkdir -p "$dest"
      case ${TR_CLAUDE:-ok} in
        ok) echo claude-binary >"$dest/claude" ;;
        empty) : >"$dest/claude" ;;
        none) ;;
      esac
      exit 0
    fi
    flavor=$(flavor_of "$tag")
    [ "${TR_BUILD_FAIL:-}" != "$flavor" ] || exit 17
    [ -z "$revision" ] || echo "$revision" >"$TR_STATE/revision"
    exit 0 ;;
  image | inspect)
    [ "$sub" != image ] || { sub2=${1:-}; shift; [ "$sub2" = inspect ] || violation "image $sub2"; }
    fmt=${2:-}
    ref=${3:-}
    case $fmt in
      *.Id*) fake_id "$(flavor_of "$ref")" ;;
      *Labels*)
        if [ "${TR_WRONG_REV:-}" = 1 ]; then echo deadbeef; else cat "$TR_STATE/revision"; fi ;;
      *) violation "inspect format $fmt" ;;
    esac
    exit 0 ;;
  save)
    [ "${1:-}" = -o ] || violation "save without -o"
    echo "tar" >"$2"
    echo "$2 $(flavor_of "$3")" >>"$TR_STATE/saves"
    exit 0 ;;
  create)
    cid=$(printf '%s' "$1$RANDOM" | sha256sum | cut -c1-64)
    echo "$cid $(flavor_of "$1")" >>"$TR_STATE/creates"
    echo "$cid"; exit 0 ;;
  rm) exit 0 ;;
  cp)
    src=${1%%:*}; path=${1#*:}; dest=$2
    name=${path##*/}; name=${name//-/_}
    mode_var=TR_BIN_$name; drop_var=TR_DROP_$name
    case ${!mode_var:-ok} in
      symlink) ln -s /etc/hostname "$dest"; exit 0 ;;
      dir) mkdir "$dest"; exit 0 ;;
      sparse) truncate -s 600M "$dest"; exit 0 ;;
    esac
    : >"$dest"
    for s in runtime.main main.main golang.org/x/net/html.Parse 'golang.org/x/net/html.(*parser)' \
             golang.org/x/net/html.fosterParent golang.org/x/net/html.NewTokenizer; do
      case " ${!drop_var:-} " in *" all "* | *" $s "*) continue ;; esac
      echo "pad $s pad" >>"$dest"
    done
    : "$src"
    exit 0 ;;
  run)
    args=("$@")
    # shape: the two Trivy runs and the grep run, compared argument for argument
    if [ "${args[0]:-}" = --rm ] && [ "${args[1]:-}" = -v ] && [ "${args[2]:-}" = devc-trivy-cache:/root/.cache/trivy ]; then
      if [ "${#args[@]}" -eq 5 ]; then
        [ "${args[3]}" = "$TRIVY" ] && [ "${args[4]}" = --version ] || violation "version run arguments"
        if [ -f "$TR_SCRATCH/version.txt" ]; then
          cat "$TR_SCRATCH/version.txt"
        else
          cat <<'V'
Version: 0.74.0
Vulnerability DB:
  Version: 2
  UpdatedAt: 2026-11-17 06:01:02.123456789 +0000 UTC
  NextUpdate: 2026-11-17 12:01:02.123456789 +0000 UTC
  DownloadedAt: 2026-11-17 07:00:00.000000000 +0000 UTC
Java DB:
  Version: 77
  UpdatedAt: 2001-02-03 04:05:06.000000000 +0000 UTC
Check Bundle:
  Digest: sha256:0000
V
        fi
        exit "${TR_VERSION_RC:-0}"
      fi
      tar=${args[4]%:/scan/image.tar:ro}
      flavor=$(awk -v t="$tar" '$1 == t { print $2 }' "$TR_STATE/saves")
      [ -n "$flavor" ] || violation "scan of a tar no save wrote"
      expect=(--rm -v devc-trivy-cache:/root/.cache/trivy -v "$tar:/scan/image.tar:ro" "$TRIVY" image
        --input /scan/image.tar --quiet --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed
        --format template --template "$TR_TEMPLATE")
      [ "${#args[@]}" -eq "${#expect[@]}" ] || violation "scan run has ${#args[@]} arguments"
      for ((i = 0; i < ${#expect[@]}; i++)); do
        [ "${args[i]}" = "${expect[i]}" ] || violation "scan run argument $i differs"
      done
      if [ -f "$TR_SCRATCH/scan.$flavor" ]; then
        cat "$TR_SCRATCH/scan.$flavor"
      elif [ "${TR_NONE:-}" != "$flavor" ]; then
        printf '\n \t \nvuln\tCVE-2026-1111\tlibfoo\t1.0.0-1\t1.0.1-1\t/home/vscode/.cache/pre_commit/x/lib/foo.so\nsecret\taws-access-key-id\tapp/config.yml\n'
      fi
      exit "${TR_SCAN_RC:-0}"
    fi
    base_id=$(fake_id base)
    expect=(--rm -i --network none --entrypoint grep "$base_id" -a -F -o -e runtime.main -e main.main
      -e golang.org/x/net/html.Parse -e 'golang.org/x/net/html.(*parser)' -e golang.org/x/net/html.fosterParent
      -e golang.org/x/net/html.NewTokenizer)
    [ "${#args[@]}" -eq "${#expect[@]}" ] || violation "run has ${#args[@]} arguments"
    for ((i = 0; i < ${#expect[@]}; i++)); do
      [ "${args[i]}" = "${expect[i]}" ] || violation "grep run argument $i differs"
    done
    if [ -f "$TR_SCRATCH/grep.out" ]; then cat "$TR_SCRATCH/grep.out"; cat >/dev/null; exit "${TR_GREP_RC:-0}"; fi
    if [ -n "${TR_GREP_RC:-}" ]; then cat >/dev/null; exit "$TR_GREP_RC"; fi
    exec grep "${args[@]:8}" ;;
  *) violation "unexpected docker subcommand $sub" ;;
esac
EOF
  cat >"$b/cygpath.real" <<'EOF'
#!/usr/bin/env bash
printf 'cygpath %s\n' "$*" >> "$TR_STATE/cygpath.log"
for a in "$@"; do
  case $a in -*) ;; /*) printf '/.%s\n' "$a" ;; *) printf '%s\n' "$a" ;; esac
done
EOF
  chmod +x "$b"/*
}

# --- scenario plumbing -------------------------------------------------------------------------

begin() {
  SCRATCH="$(mktemp -d)"
  export TR_SCRATCH="$SCRATCH" TR_STATE="$SCRATCH/state" TR_LOG="$SCRATCH/calls.log"
  export TR_FIXTURE="$SCRATCH/fixture" TR_TEMPLATE="$TEMPLATE"
  unset TR_MERGE_RC TR_BUILD_FAIL TR_CLAUDE TR_WRONG_REV TR_SCAN_RC TR_VERSION_RC TR_GREP_RC TR_NONE
  while read -r v; do unset "$v"; done < <(compgen -v | grep -E '^TR_(BIN|DROP)_' || true)
  mkdir -p "$TR_STATE" "$SCRATCH/tmp" "$SCRATCH/out" "$SCRATCH/cwd"
  : >"$TR_LOG"
  mkdir -p "$TR_FIXTURE/.github/scripts" "$TR_FIXTURE/images/base" "$TR_FIXTURE/images/tofu"
  cp "$ROOT_DIR/.github/scripts/build-and-test.sh" "$TR_FIXTURE/.github/scripts/"
  cp "$ROOT_DIR/images/base/Dockerfile" "$TR_FIXTURE/images/base/"
  cp "$ROOT_DIR/images/tofu/Dockerfile" "$TR_FIXTURE/images/tofu/"
  write_fakes
  RESULTS="$SCRATCH/out/results.md"
}
finish() { rm -rf "$SCRATCH"; }

# go <HOST_RESULTS value | @unset> [args...]: runs the script, sets RC
go() {
  local hr=$1
  shift
  local -a envs=()
  if [ "$hr" = @unset ]; then envs+=(-u HOST_RESULTS); fi
  envs+=(PATH="$SCRATCH/bin:$PATH" TMPDIR="$SCRATCH/tmp")
  if [ "$hr" != @unset ]; then envs+=(HOST_RESULTS="$hr"); fi
  RC=0
  (cd "$SCRATCH/cwd" && env "${envs[@]}" bash "$SCRIPT" "$@") >"$SCRATCH/stdout" 2>"$SCRATCH/stderr" || RC=$?
  [ -z "${TR_DEBUG:-}" ] || sed 's/^/  stderr: /' "$SCRATCH/stderr" >&2
}
stderr_lines() { wc -l <"$SCRATCH/stderr" | tr -d ' '; }
stderr_has() { grep -qF -- "$1" "$SCRATCH/stderr"; }
calls() { grep -c "^$1 " "$TR_LOG" || true; }
tmp_empty() { [ -z "$(ls -A "$SCRATCH/tmp")" ]; }
common_checks() { # description: the checks every scenario makes
  assert_eq "$1: the fake docker saw no mismatched argument" "" "$(cat "$TR_STATE/violations" 2>/dev/null || true)"
  assert_eq "$1: the jq and gh tripwires never ran" "" "$(cat "$TR_STATE/tripwire" 2>/dev/null || true)"
  if tmp_empty; then pass; else fail "$1: TMPDIR is empty afterwards" "$(ls -A "$SCRATCH/tmp")"; fi
}
use_cygpath() { cp "$SCRATCH/bin/cygpath.real" "$SCRATCH/bin/cygpath"; }
rep() { # rep <char> <n>
  local s=
  local i
  for ((i = 0; i < $2; i++)); do s+=$1; done
  printf '%s' "$s"
}
vuln_line() { printf 'vuln\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5"; }
VALID_VULN=$(vuln_line CVE-2026-1 pkg 1.0 1.1 /usr/lib/x)

# --- usage errors ------------------------------------------------------------------------------

usage_case() { # usage_case <description> <HOST_RESULTS value | @unset> [args...]
  local desc=$1 hr=$2
  shift 2
  begin
  go "$hr" "$@"
  assert_rc "usage: $desc" 2 "$RC"
  assert_eq "usage: $desc (stderr lines)" 1 "$(stderr_lines)"
  assert_eq "usage: $desc (no git or docker call)" 0 "$(wc -c <"$TR_LOG" | tr -d ' ')"
  common_checks "usage: $desc"
}
R() { printf '%s' "$SCRATCH/out/results.md"; }

begin; usage_hr="$RESULTS"; finish
usage_case "no argument" "$usage_hr"; finish
usage_case "two arguments" "$usage_hr" "$COMMIT" "$COMMIT"; finish
usage_case "a non-hex commit" "$usage_hr" zzzz456789abcdef0123456789abcdef01234567; finish
usage_case "a 39-character commit" "$usage_hr" "${COMMIT:0:39}"; finish
usage_case "an uppercase-hex commit" "$usage_hr" "${COMMIT^^}"; finish
usage_case "HOST_RESULTS unset" @unset "$COMMIT"; finish
usage_case "HOST_RESULTS empty" "" "$COMMIT"; finish

begin; echo precious >"$RESULTS"; go "$RESULTS" "$COMMIT"
assert_rc "usage: a non-empty HOST_RESULTS" 2 "$RC"
assert_eq "usage: a non-empty HOST_RESULTS (stderr lines)" 1 "$(stderr_lines)"
assert_eq "usage: a non-empty HOST_RESULTS (left unchanged)" precious "$(cat "$RESULTS")"
assert_eq "usage: a non-empty HOST_RESULTS (no call)" 0 "$(wc -c <"$TR_LOG" | tr -d ' ')"
common_checks "usage: a non-empty HOST_RESULTS"; finish

begin; : >"$SCRATCH/out/empty"; ln -s empty "$RESULTS"; go "$RESULTS" "$COMMIT"
assert_rc "usage: a symlink to an empty file" 2 "$RC"
assert_eq "usage: a symlink to an empty file (stderr lines)" 1 "$(stderr_lines)"
if [ -L "$RESULTS" ] && [ ! -s "$SCRATCH/out/empty" ]; then pass; else fail "usage: the symlink case left things unchanged"; fi
assert_eq "usage: a symlink (no call)" 0 "$(wc -c <"$TR_LOG" | tr -d ' ')"
common_checks "usage: a symlink"; finish

begin; ln -s "$SCRATCH/out/nowhere" "$RESULTS"; go "$RESULTS" "$COMMIT"
assert_rc "usage: a dangling symlink" 2 "$RC"
assert_eq "usage: a dangling symlink (stderr lines)" 1 "$(stderr_lines)"
if [ ! -e "$SCRATCH/out/nowhere" ]; then pass; else fail "usage: a dangling symlink was written through"; fi
common_checks "usage: a dangling symlink"; finish

begin; mkdir "$RESULTS"; go "$RESULTS" "$COMMIT"
assert_rc "usage: a directory" 2 "$RC"
assert_eq "usage: a directory (stderr lines)" 1 "$(stderr_lines)"
common_checks "usage: a directory"; finish

begin; go "$SCRATCH/nodir/results.md" "$COMMIT"
assert_rc "usage: a path whose directory does not exist" 2 "$RC"
assert_eq "usage: a missing directory (stderr lines)" 1 "$(stderr_lines)"
assert_eq "usage: a missing directory (no call)" 0 "$(wc -c <"$TR_LOG" | tr -d ' ')"
common_checks "usage: a missing directory"; finish

# --- unreachable base commit -------------------------------------------------------------------

for rc in 1 128; do
  begin; export TR_MERGE_RC=$rc; go "$RESULTS" "$COMMIT"
  assert_rc "unreachable commit (merge-base $rc)" 3 "$RC"
  assert_eq "unreachable commit ($rc): one stderr line" 1 "$(stderr_lines)"
  assert_eq "unreachable commit ($rc): no docker call" 0 "$(calls docker)"
  if [ ! -e "$RESULTS" ]; then pass; else fail "unreachable commit ($rc): no results file"; fi
  common_checks "unreachable commit ($rc)"; finish
done
begin; export TR_MERGE_RC=128; : >"$RESULTS"; go "$RESULTS" "$COMMIT"
assert_rc "unreachable commit with a pre-created results file" 3 "$RC"
if [ ! -e "$RESULTS" ]; then pass; else fail "unreachable commit: the empty results file is removed"; fi
common_checks "unreachable commit, pre-created file"; finish

# --- drift guard -------------------------------------------------------------------------------

begin; echo "# changed" >>"$TR_FIXTURE/.github/scripts/build-and-test.sh"; : >"$RESULTS"; go "$RESULTS" "$COMMIT"
assert_rc "drift guard" 4 "$RC"
assert_eq "drift guard: one stderr line" 1 "$(stderr_lines)"
if stderr_has tools/host/trivy-rescan.sh; then pass; else fail "drift guard: the line names tools/host/trivy-rescan.sh"; fi
assert_eq "drift guard: no docker call" 0 "$(calls docker)"
if [ ! -e "$RESULTS" ]; then pass; else fail "drift guard: the empty results file is removed"; fi
common_checks "drift guard"; finish

begin; rm "$TR_FIXTURE/.github/scripts/build-and-test.sh"
mkdir -p "$TR_FIXTURE/.github/scripts"; echo 'TRIVY="x"' >"$TR_FIXTURE/.github/scripts/other.sh"
go "$RESULTS" "$COMMIT"
assert_rc "drift guard: a clone without build-and-test.sh" 4 "$RC"
assert_eq "drift guard: a clone without it (no docker call)" 0 "$(calls docker)"
common_checks "drift guard: a clone without build-and-test.sh"; finish

# --- mid-run failures --------------------------------------------------------------------------

fails() { # fails <description> : the scenario just ran; it must be status 1 with no results file
  assert_rc "$1" 1 "$RC"
  if [ ! -e "$RESULTS" ]; then pass; else fail "$1: no results file"; fi
  common_checks "$1"
}

begin; export TR_BUILD_FAIL=node; : >"$RESULTS"; go "$RESULTS" "$COMMIT"
fails "the node build fails"
if stderr_has "line "; then pass; else fail "node build failure: stderr carries the trap's line number"; fi
if stderr_has "docker build"; then pass; else fail "node build failure: stderr carries the command"; fi
finish

begin; sed -i '/^ARG TFLINT_VERSION=/d' "$TR_FIXTURE/images/tofu/Dockerfile"; go "$RESULTS" "$COMMIT"
fails "an empty pin"
if stderr_has TFLINT_VERSION && stderr_has images/tofu/Dockerfile; then pass; else fail "empty pin: stderr names the ARG and the Dockerfile"; fi
finish

begin; export TR_CLAUDE=none; go "$RESULTS" "$COMMIT"; fails "no claude export"; finish
begin; export TR_CLAUDE=empty; go "$RESULTS" "$COMMIT"; fails "an empty claude export"; finish
begin; export TR_WRONG_REV=1; go "$RESULTS" "$COMMIT"; fails "a wrong devapp revision label"; finish

for mode in symlink dir sparse; do
  begin; export TR_BIN_gh=$mode; go "$RESULTS" "$COMMIT"; fails "a copied binary that is a $mode"; finish
done

bad_scan() { # bad_scan <description> <line 2>
  begin
  printf '%s\n%s\n' "$VALID_VULN" "$2" >"$SCRATCH/scan.base"
  go "$RESULTS" "$COMMIT"
  fails "scan output: $1"
  if stderr_has "line 2"; then pass; else fail "scan output: $1: the message names line 2"; fi
  if stderr_has "$MARK"; then fail "scan output: $1: the message carries the bad line"; else pass; fi
  finish
}
bad_scan "an unknown leading word" "$(printf '%s\tCVE-1\tpkg\t1\t2\tp' "$MARK")"
bad_scan "a wrong field count" "$(printf 'vuln\tCVE-1\tpkg%s\t1\t2' "$MARK")"
bad_scan "a 257-character field" "$(vuln_line CVE-1 "$MARK$(rep a 245)" 1 2 p)"
bad_scan "an empty package name" "$(vuln_line CVE-1 '' 1 2 "p$MARK")"
bad_scan "an empty fixed version" "$(vuln_line CVE-1 pkg 1 '' "p$MARK")"
bad_scan "a { in a field" "$(vuln_line CVE-1 "pkg{$MARK" 1 2 p)"
bad_scan "a ] in a field" "$(vuln_line CVE-1 "pkg]$MARK" 1 2 p)"
bad_scan "a secret line with three fields" "$(printf 'secret\tr1\tt1\t%s' "$MARK")"
bad_scan "a [ in a secret rule id" "$(printf 'secret\trule[%s\ttarget' "$MARK")"

begin; export TR_SCAN_RC=125; go "$RESULTS" "$COMMIT"; fails "the Trivy template run exits 125 after valid output"; finish
begin; export TR_VERSION_RC=125; go "$RESULTS" "$COMMIT"; fails "the --version run exits 125 after valid output"; finish

bad_version() { # bad_version <description> <version text>
  begin
  printf '%s' "$2" >"$SCRATCH/version.txt"
  go "$RESULTS" "$COMMIT"
  fails "--version: $1"
  finish
}
JAVA_DB=$'Java DB:\n  Version: 77\n  UpdatedAt: 2001-02-03 04:05:06 +0000 UTC\n'
bad_version "no Trivy Version: line" $'Vulnerability DB:\n  Version: 2\n  UpdatedAt: 2026-11-17\n'"$JAVA_DB"
bad_version "no vulnerability DB Version: line" $'Version: 0.74.0\nVulnerability DB:\n  UpdatedAt: 2026-11-17\n'"$JAVA_DB"
bad_version "no vulnerability DB UpdatedAt" $'Version: 0.74.0\nVulnerability DB:\n  Version: 2\n'"$JAVA_DB"
bad_version "an empty UpdatedAt value" $'Version: 0.74.0\nVulnerability DB:\n  Version: 2\n  UpdatedAt:\n'"$JAVA_DB"
bad_version "a 257-character Trivy version" "Version: $(rep 9 257)"$'\nVulnerability DB:\n  Version: 2\n  UpdatedAt: 2026-11-17\n'
bad_version "a section that closes the window" $'Version: 0.74.0\nVulnerability DB:\n  Version: 2\nJava DB:\n  UpdatedAt: 2001-02-03\n'

begin; printf 'pkg' >/dev/null; echo "bogus-line" >"$SCRATCH/grep.out"; go "$RESULTS" "$COMMIT"
fails "a grep output line that is not one of the six strings"; finish
begin; export TR_GREP_RC=2; go "$RESULTS" "$COMMIT"; fails "a grep exit code of 2"; finish

begin
big=$(vuln_line "$(rep c 256)" "$(rep p 256)" "$(rep i 256)" "$(rep f 256)" "$(rep x 256)")
{ yes "$big" || true; } | head -n 1000 >"$SCRATCH/scan.base"
go "$RESULTS" "$COMMIT"
fails "a Trivy output that pushes the results over 1 MiB"
if stderr_has "1 MiB"; then pass; else fail "oversize results: the message says why"; fi
finish

# --- clean runs --------------------------------------------------------------------------------

section_order() { # prints the level-2 headings of the results file, one line
  grep '^## ' "$1" | tr '\n' '|'
}
EXPECTED_SECTIONS='## Base commit|## Pins|## Images|## Trivy|## Findings: base|## Findings: tofu|## Findings: node|## Findings: devapp|## Findings: devapp-tofu|## Binaries|'

clean_checks() { # clean_checks <description> <results file>
  local d=$1 f=$2 log
  assert_rc "$d" 0 "$RC"
  assert_eq "$d: the level-2 sections, in order" "$EXPECTED_SECTIONS" "$(section_order "$f")"
  assert_eq "$d: no stderr noise" 0 "$(stderr_lines)"
  if grep -qF '`/home/vscode/.cache/pre_commit/x/lib/foo.so`' "$f"; then pass; else fail "$d: the pre_commit path is written unchanged"; fi
  if grep -qF 'secret rule `aws-access-key-id`, path `app/config.yml`' "$f"; then pass; else fail "$d: the secret's rule id and path"; fi
  if awk '/^## Findings: node/{f=1;next} /^## /{f=0} f' "$f" | grep -qx -- '- none'; then pass; else fail "$d: a none line for the flavor with no findings"; fi
  if grep -qF "$SCRATCH" "$f"; then fail "$d: the scratch directory's path appears in the file"; else pass; fi
  if grep -qF "$COMMIT" "$f"; then pass; else fail "$d: the base commit is recorded"; fi
  log=$(cat "$TR_LOG")
  case $log in *docker.sock*) fail "$d: the call log has docker.sock" ;; *) pass ;; esac
  if grep -qE '^docker (push|login)' "$TR_LOG"; then fail "$d: no push or login"; else pass; fi
  assert_eq "$d: one clone, with the exact URL" 1 "$(grep -c '^git -c credential.helper= clone --quiet https://github.com/603-Identity/devcontainers /[^ ]*$' "$TR_LOG")"
  assert_eq "$d: six builds with --no-cache" 6 "$(grep -c '^docker build --no-cache ' "$TR_LOG")"
  assert_eq "$d: only base carries --pull" 1 "$(grep -c -- ' --pull ' "$TR_LOG")"
  assert_eq "$d: no :local tag" 0 "$(grep -c ':local' "$TR_LOG")"
  assert_eq "$d: the devapp builds carry the revision" 2 "$(grep -c -- '--build-arg REVISION='"$COMMIT" "$TR_LOG")"
  # the symbol check on each binary: gh and betterleaks and tofu unchecked, gh-real checked
  assert_eq "$d: three unchecked binaries" 3 "$(grep -c 'unchecked' "$f")"
  assert_eq "$d: three symbols present, for gh-real only" 3 "$(grep -c ': present$' "$f")"
  assert_eq "$d: one symbol absent" 1 "$(grep -c ': absent$' "$f")"
  if grep -qF '`golang.org/x/net/html.fosterParent`: absent' "$f"; then pass; else fail "$d: fosterParent is reported absent"; fi
  if grep -qF '`golang.org/x/net/html.Parse`: present' "$f"; then pass; else fail "$d: Parse is reported present"; fi
  if grep -q 'sha256 `[0-9a-f]\{64\}`' "$f"; then pass; else fail "$d: the binaries' sha256 are recorded"; fi
  common_checks "$d"
}
clean_env() { # the binary variations of the spec
  export TR_DROP_gh=all
  export TR_DROP_betterleaks=main.main
  export TR_DROP_tofu=runtime.main
  export TR_DROP_gh_real=golang.org/x/net/html.fosterParent
  export TR_NONE=node
  printf '%s\n%s\n%s\n' "$(vuln_line CVE-2026-2 pkg-a 1.0 1.1 '/opt/a`b#c/lib')" \
    "$(vuln_line CVE-2026-3 pkg-b "$(rep 7 256)" 1.1 /opt/b)" \
    "$(vuln_line CVE-2026-4 pkg-c 1.0 1.1 'C:\x\y')" >"$SCRATCH/scan.tofu"
}

begin; clean_env; go "$RESULTS" "$COMMIT"
clean_checks "clean run, HOST_RESULTS absent" "$RESULTS"
if grep -qF 'path `/opt/a?b?c/lib`' "$RESULTS"; then pass; else fail "clean run: a backtick and a # become ?"; fi
if grep -qF "installed \`$(rep 7 256)\`" "$RESULTS"; then pass; else fail "clean run: a 256-character field is written in full"; fi
if grep -qF 'path `C:?x?y`' "$RESULTS"; then pass; else fail "clean run: a backslash becomes ?"; fi
if grep -qF 'Vulnerability DB version: `2`' "$RESULTS" && grep -qF 'UpdatedAt: `2026-11-17 06:01:02.123456789 +0000 UTC`' "$RESULTS"; then pass; else fail "clean run: the vulnerability DB's values"; fi
if grep -qF 'Trivy version: `0.74.0`' "$RESULTS"; then pass; else fail "clean run: the Trivy version"; fi
if grep -qE '2001-02-03|`77`' "$RESULTS"; then fail "clean run: the Java DB's values appear"; else pass; fi
assert_eq "clean run: the results file is the only file left" "results.md" "$(ls "$SCRATCH/out")"
finish

begin; clean_env; : >"$RESULTS"
printf 'Version: 0.74`0\nVulnerability DB:\n  Version: 3\n  UpdatedAt: 2026-12-01 00:00:00 +0000 UTC' >"$SCRATCH/version.txt"
go "$RESULTS" "$COMMIT"
clean_checks "clean run, HOST_RESULTS pre-created" "$RESULTS"
if grep -qF 'Trivy version: `0.74?0`' "$RESULTS"; then pass; else fail "clean run: a backtick in the Trivy version becomes ?"; fi
if grep -qF 'Vulnerability DB version: `3`' "$RESULTS" && grep -qF 'UpdatedAt: `2026-12-01 00:00:00 +0000 UTC`' "$RESULTS"; then pass; else fail "clean run: the last section's values are recorded"; fi
finish

begin; clean_env; use_cygpath; go "$RESULTS" "$COMMIT"
clean_checks "clean run with cygpath" "$RESULTS"
if [ -s "$TR_STATE/cygpath.log" ]; then pass; else fail "cygpath run: the cygpath log is not empty"; fi
assert_eq "cygpath run: the fake docker saw MSYS_NO_PATHCONV=1 on every call" "" "$(grep -vx 1 "$TR_STATE/msys" || true)"
dlog=$(grep '^docker ' "$TR_LOG")
stripped=${dlog//"/.$SCRATCH"/}
case $stripped in *"$SCRATCH"*) fail "cygpath run: a raw scratch path reached docker" ;; *) pass ;; esac
for pat in "docker build --no-cache --pull -t devcontainer-base:rescan /./" \
           "dest=/./" "claude-export=/./" "docker save -o /./" "-v /./" "docker cp "; do
  case $dlog in *"$pat"*) pass ;; *) fail "cygpath run: the docker log has '$pat'" ;; esac
done
if grep '^docker cp ' "$TR_LOG" | grep -qv ' /\./'; then fail "cygpath run: a cp target is not converted"; else pass; fi
finish

# --- the drift-guard constant -------------------------------------------------------------------

want=$(sha256sum "$ROOT_DIR/.github/scripts/build-and-test.sh")
if grep -qF "BUILD_SCRIPT_SHA256=${want%% *}" "$SCRIPT"; then pass; else fail "the drift-guard constant is the sha256 of the current build-and-test.sh"; fi
if grep -qF "TEMPLATE='$TEMPLATE'" "$SCRIPT"; then pass; else fail "the script's template is byte for byte the spec's"; fi

summary
