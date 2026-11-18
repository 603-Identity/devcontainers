#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Offline tests for .github/scripts/trivy-evidence.sh. Every scenario runs a copy of the real
# script, inside a fixture tree built from the checkout under test, against a fake `docker` put
# first on PATH, with TMPDIR set to a fresh directory and tripwire `jq` and `gh` executables
# ahead of tools/tests/bin. Modelled on trivy-rescan-test.sh.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite trivy-evidence

SRC="$ROOT_DIR/.github/scripts/trivy-evidence.sh"
RESCAN="$TOOLS_DIR/host/trivy-rescan.sh"
COMMIT=0123456789abcdef0123456789abcdef01234567
TAG=4.12
WARNING='::warning::trivy-evidence: no renewal evidence written (see the step log)'
# The exact template, held here as its own constant (not read from the script).
TEMPLATE='{{range .}}{{$t := .Target}}{{range .Vulnerabilities}}vuln{{"\t"}}{{.VulnerabilityID}}{{"\t"}}{{.PkgName}}{{"\t"}}{{.InstalledVersion}}{{"\t"}}{{.FixedVersion}}{{"\t"}}{{if .PkgPath}}{{.PkgPath}}{{else}}{{$t}}{{end}}{{"\n"}}{{end}}{{range .Secrets}}secret{{"\t"}}{{.RuleID}}{{"\t"}}{{$t}}{{"\n"}}{{end}}{{end}}'
MARK=SECRETMARKER

# --- the fake executables ----------------------------------------------------------------------

write_fakes() { # writes $SCRATCH/bin/{docker,jq,gh}
  local b="$SCRATCH/bin"
  mkdir -p "$b"
  cat >"$b/jq" <<'EOF'
#!/usr/bin/env bash
echo "jq $*" >> "$TE_STATE/tripwire"; exit 1
EOF
  cat >"$b/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$TE_STATE/tripwire"; exit 1
EOF
  cat >"$b/docker" <<'EOF'
#!/usr/bin/env bash
# Fake docker. The TE_* variables set by the test choose what it does.
printf 'docker %s\n' "$*" >> "$TE_LOG"
violation() { echo "$*" >> "$TE_STATE/violations"; echo "fake docker: $*" >&2; exit 99; }
fake_id() { printf 'sha256:%s' "$(printf '%s' "$1" | sha256sum | cut -c1-64)"; }
flavor_of() { # flavor_of <ref>: only the push-mode ref shape is accepted
  local r=${1:-} p="${TE_REGISTRY:-ghcr.io/603-identity}/devcontainer-"
  case $r in
    "$p"*":$TE_TAG") r=${r#"$p"}; printf '%s' "${r%":$TE_TAG"}" ;;
    *) violation "image ref $r" ;;
  esac
}
TRIVY=$(sed -n 's/^TRIVY="\(.*\)"$/\1/p' "$TE_BUILD_SCRIPT")
sub=${1:-}
shift || true
case $sub in
  image)
    [ "${1:-}" = inspect ] && [ "${2:-}" = --format ] && [ "${3:-}" = '{{.Id}}' ] && [ "$#" -eq 4 ] || violation "image arguments: $*"
    f=$(flavor_of "$4")
    [ "${TE_MISSING:-}" != "$f" ] || { echo "Error: No such image: $4" >&2; exit 1; }
    if [ "${TE_BADID:-}" = "$f" ]; then echo sha256:short; else fake_id "$f"; fi
    exit 0 ;;
  save)
    [ "${1:-}" = -o ] || violation "save without -o"
    echo "tar" >"$2"
    echo "$2 $(flavor_of "$3")" >>"$TE_STATE/saves"
    exit 0 ;;
  create)
    if [ "${TE_BADCID:-}" = 1 ]; then echo 'not-hex!'; exit 0; fi
    cid=$(printf '%s' "$1$RANDOM" | sha256sum | cut -c1-64)
    echo "$cid $(flavor_of "$1")" >>"$TE_STATE/creates"
    echo "$cid"; exit 0 ;;
  rm) exit 0 ;;
  cp)
    [ "${TE_CPFAIL:-}" != 1 ] || { echo "Error: no such path" >&2; exit 1; }
    path=${1#*:}; dest=$2
    name=${path##*/}; name=${name//-/_}
    mode_var=TE_BIN_$name; drop_var=TE_DROP_$name
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
    exit 0 ;;
  run)
    args=("$@")
    if [ "${args[0]:-}" = --rm ] && [ "${args[1]:-}" = -v ] && [ "${args[2]:-}" = devc-trivy-cache:/root/.cache/trivy ]; then
      if [ "${#args[@]}" -eq 5 ]; then
        [ "${args[3]}" = "$TRIVY" ] && [ "${args[4]}" = --version ] || violation "version run arguments"
        if [ -f "$TE_SCRATCH/version.txt" ]; then
          cat "$TE_SCRATCH/version.txt"
        else
          cat <<'V'
Version: 0.74.0
Vulnerability DB:
  Version: 2
  UpdatedAt: 2026-11-17 06:01:02.123456789 +0000 UTC
  NextUpdate: 2026-11-17 12:01:02.123456789 +0000 UTC
Java DB:
  Version: 77
  UpdatedAt: 2001-02-03 04:05:06.000000000 +0000 UTC
V
        fi
        exit "${TE_VERSION_RC:-0}"
      fi
      tar=${args[4]%:/scan/image.tar:ro}
      flavor=$(awk -v t="$tar" '$1 == t { print $2 }' "$TE_STATE/saves")
      [ -n "$flavor" ] || violation "scan of a tar no save wrote"
      expect=(--rm -v devc-trivy-cache:/root/.cache/trivy -v "$tar:/scan/image.tar:ro" "$TRIVY" image
        --input /scan/image.tar --quiet --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed
        --format template --template "$TE_TEMPLATE")
      [ "${#args[@]}" -eq "${#expect[@]}" ] || violation "scan run has ${#args[@]} arguments"
      for ((i = 0; i < ${#expect[@]}; i++)); do
        [ "${args[i]}" = "${expect[i]}" ] || violation "scan run argument $i differs"
      done
      if [ -f "$TE_SCRATCH/scan.$flavor" ]; then
        cat "$TE_SCRATCH/scan.$flavor"
      elif [ "${TE_NONE:-}" != "$flavor" ]; then
        printf '\n \t \nvuln\tCVE-2026-1111\tlibfoo\t1.0.0-1\t1.0.1-1\t/home/vscode/.cache/pre_commit/x/lib/foo.so\nsecret\taws-access-key-id\tapp/config.yml\n'
      fi
      exit "${TE_SCAN_RC:-0}"
    fi
    base_id=$(fake_id base)
    expect=(--rm -i --network none --entrypoint grep "$base_id" -a -F -o -e runtime.main -e main.main
      -e golang.org/x/net/html.Parse -e 'golang.org/x/net/html.(*parser)' -e golang.org/x/net/html.fosterParent
      -e golang.org/x/net/html.NewTokenizer)
    [ "${#args[@]}" -eq "${#expect[@]}" ] || violation "run has ${#args[@]} arguments"
    for ((i = 0; i < ${#expect[@]}; i++)); do
      [ "${args[i]}" = "${expect[i]}" ] || violation "grep run argument $i differs"
    done
    if [ -f "$TE_SCRATCH/grep.out" ]; then cat "$TE_SCRATCH/grep.out"; cat >/dev/null; exit "${TE_GREP_RC:-0}"; fi
    if [ -n "${TE_GREP_RC:-}" ]; then cat >/dev/null; exit "$TE_GREP_RC"; fi
    exec grep "${args[@]:8}" ;;
  *) violation "unexpected docker subcommand $sub" ;;
esac
EOF
  chmod +x "$b"/*
}

# --- scenario plumbing -------------------------------------------------------------------------

begin() {
  SCRATCH="$(mktemp -d)"
  export TE_SCRATCH="$SCRATCH" TE_STATE="$SCRATCH/state" TE_LOG="$SCRATCH/calls.log"
  export TE_TEMPLATE="$TEMPLATE" TE_TAG="$TAG" TE_BUILD_SCRIPT="$ROOT_DIR/.github/scripts/build-and-test.sh"
  unset TE_MISSING TE_BADID TE_BADCID TE_CPFAIL TE_SCAN_RC TE_VERSION_RC TE_GREP_RC TE_NONE TE_REGISTRY REGISTRY
  while read -r v; do unset "$v"; done < <(compgen -v | grep -E '^TE_(BIN|DROP)_' || true)
  mkdir -p "$TE_STATE" "$SCRATCH/tmp" "$SCRATCH/out" "$SCRATCH/cwd"
  : >"$TE_LOG"
  FIX="$SCRATCH/fixture"
  mkdir -p "$FIX/.github/scripts" "$FIX/images/base" "$FIX/images/tofu"
  cp "$SRC" "$FIX/.github/scripts/trivy-evidence.sh"
  cp "$ROOT_DIR/images/base/Dockerfile" "$FIX/images/base/"
  cp "$ROOT_DIR/images/tofu/Dockerfile" "$FIX/images/tofu/"
  write_fakes
  RESULTS="$SCRATCH/out/results.md"
}
finish() { rm -rf "$SCRATCH"; }

# go <TAG> <OUTPUT> [VAR=value ...]: runs the script with GITHUB_SHA set, sets RC
go() {
  local t=$1 o=$2
  shift 2
  RC=0
  (cd "$SCRATCH/cwd" && env GITHUB_SHA="$COMMIT" PATH="$SCRATCH/bin:$PATH" TMPDIR="$SCRATCH/tmp" "$@" \
    bash "$FIX/.github/scripts/trivy-evidence.sh" "$t" "$o") >"$SCRATCH/stdout" 2>"$SCRATCH/stderr" || RC=$?
  [ -z "${TE_DEBUG:-}" ] || sed 's/^/  stderr: /' "$SCRATCH/stderr" >&2
}
# go_raw <env -u/VAR=value words...> -- <args...>: for the usage cases that change the environment
go_raw() {
  local -a envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  RC=0
  (cd "$SCRATCH/cwd" && env "${envs[@]}" PATH="$SCRATCH/bin:$PATH" TMPDIR="$SCRATCH/tmp" \
    bash "$FIX/.github/scripts/trivy-evidence.sh" "$@") >"$SCRATCH/stdout" 2>"$SCRATCH/stderr" || RC=$?
}
stderr_has() { grep -qF -- "$1" "$SCRATCH/stderr"; }
tmp_empty() { [ -z "$(ls -A "$SCRATCH/tmp")" ]; }
warning_only() { # description: stdout is exactly the one fixed warning line
  assert_eq "$1: stdout is exactly the fixed warning line" "$WARNING" "$(cat "$SCRATCH/stdout")"
}
common_checks() { # description
  assert_eq "$1: the fake docker saw no mismatched argument" "" "$(cat "$TE_STATE/violations" 2>/dev/null || true)"
  assert_eq "$1: the jq and gh tripwires never ran" "" "$(cat "$TE_STATE/tripwire" 2>/dev/null || true)"
  if tmp_empty; then pass; else fail "$1: TMPDIR is empty afterwards" "$(ls -A "$SCRATCH/tmp")"; fi
}
rep() { # rep <char> <n>
  local s='' i
  for ((i = 0; i < $2; i++)); do s+=$1; done
  printf '%s' "$s"
}
vuln_line() { printf 'vuln\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5"; }
VALID_VULN=$(vuln_line CVE-2026-1 pkg 1.0 1.1 /usr/lib/x)

# --- usage errors ------------------------------------------------------------------------------

usage_done() { # usage_done <description>: rc 2, the fixed line, no docker call
  assert_rc "usage: $1" 2 "$RC"
  warning_only "usage: $1"
  assert_eq "usage: $1 (one stderr line)" 1 "$(wc -l <"$SCRATCH/stderr" | tr -d ' ')"
  assert_eq "usage: $1 (no docker call)" 0 "$(wc -c <"$TE_LOG" | tr -d ' ')"
  common_checks "usage: $1"
}

begin; go_raw GITHUB_SHA="$COMMIT" --; usage_done "no argument"; finish
begin; go_raw GITHUB_SHA="$COMMIT" -- "$TAG"; usage_done "one argument"; finish
begin; go_raw GITHUB_SHA="$COMMIT" -- "$TAG" "$RESULTS" extra; usage_done "three arguments"; finish
for t in 4 4. .12 4.x v4.12 4.12.1 "4.12 " ""; do
  begin; go "$t" "$RESULTS"; usage_done "TAG '$t'"
  if [ ! -e "$RESULTS" ]; then pass; else fail "usage: TAG '$t': OUTPUT created"; fi
  finish
done
begin; go_raw -u GITHUB_SHA -- "$TAG" "$RESULTS"; usage_done "GITHUB_SHA unset"; finish
begin; go_raw GITHUB_SHA= -- "$TAG" "$RESULTS"; usage_done "GITHUB_SHA empty"; finish
begin; go_raw GITHUB_SHA="${COMMIT:0:39}" -- "$TAG" "$RESULTS"; usage_done "a 39-character GITHUB_SHA"; finish
begin; go_raw GITHUB_SHA="${COMMIT^^}" -- "$TAG" "$RESULTS"; usage_done "an uppercase GITHUB_SHA"; finish
begin; go_raw GITHUB_SHA="zzzz${COMMIT:4}" -- "$TAG" "$RESULTS"; usage_done "a non-hex GITHUB_SHA"; finish

begin; echo precious >"$RESULTS"; go "$TAG" "$RESULTS"; usage_done "a non-empty OUTPUT"
assert_eq "usage: a non-empty OUTPUT (left unchanged)" precious "$(cat "$RESULTS")"; finish
begin; : >"$SCRATCH/out/empty"; ln -s empty "$RESULTS"; go "$TAG" "$RESULTS"; usage_done "a symlink OUTPUT"
if [ -L "$RESULTS" ] && [ ! -s "$SCRATCH/out/empty" ]; then pass; else fail "usage: the symlink case left things unchanged"; fi; finish
begin; ln -s "$SCRATCH/out/nowhere" "$RESULTS"; go "$TAG" "$RESULTS"; usage_done "a dangling symlink OUTPUT"
if [ ! -e "$SCRATCH/out/nowhere" ]; then pass; else fail "usage: a dangling symlink was written through"; fi; finish
begin; mkdir "$RESULTS"; go "$TAG" "$RESULTS"; usage_done "a directory OUTPUT"; finish
begin; go "$TAG" "$SCRATCH/nodir/results.md"; usage_done "an OUTPUT whose directory does not exist"; finish
begin; go "$TAG" ""; usage_done "an empty OUTPUT"; finish

# --- failures past the usage checks ------------------------------------------------------------

fails() { # fails <description>: the scenario just ran; status 1, the fixed line, no results file
  assert_rc "$1" 1 "$RC"
  warning_only "$1"
  if [ ! -e "$RESULTS" ]; then pass; else fail "$1: no results file"; fi
  common_checks "$1"
}
# run a failing scenario twice: OUTPUT absent, and OUTPUT a pre-existing empty file (which must go)
fail_case() { # fail_case <description> <setup command...>
  local d=$1 pre
  shift
  for pre in absent empty; do
    begin
    "$@"
    if [ "$pre" = empty ]; then : >"$RESULTS"; fi
    go "$TAG" "$RESULTS"
    fails "$d ($pre OUTPUT)"
    finish
  done
}
set_env() { local kv; for kv in "$@"; do export "${kv?}"; done; }
no_pin() { sed -i "/^ARG $1=/d" "$FIX/images/$2/Dockerfile"; }
write_scan() { printf '%s\n%s\n' "$VALID_VULN" "$2" >"$SCRATCH/scan.$1"; }
write_version() { printf '%s' "$1" >"$SCRATCH/version.txt"; }

fail_case "an empty TFLINT_VERSION pin" no_pin TFLINT_VERSION tofu
fail_case "a missing GH_VERSION pin" no_pin GH_VERSION base
fail_case "a local image missing under its push-mode ref" set_env TE_MISSING=devapp-tofu
fail_case "an image id of the wrong shape" set_env TE_BADID=node
fail_case "the scan run exiting non-zero" set_env TE_SCAN_RC=125
fail_case "the --version run exiting non-zero" set_env TE_VERSION_RC=125
fail_case "a docker create id of the wrong shape" set_env TE_BADCID=1
fail_case "a failed docker cp" set_env TE_CPFAIL=1
for mode in symlink dir sparse; do
  fail_case "a copied binary that is a $mode" set_env TE_BIN_gh=$mode
done
fail_case "a grep exit code of 2" set_env TE_GREP_RC=2
bogus_grep() { echo "bogus-line" >"$SCRATCH/grep.out"; }
fail_case "a grep output line that is not one of the six strings" bogus_grep

bad_scan() { # bad_scan <description> <line 2>
  local line=$2
  begin
  write_scan base "$line"
  go "$TAG" "$RESULTS"
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

bad_version() { # bad_version <description> <version text>
  begin
  write_version "$2"
  go "$TAG" "$RESULTS"
  fails "--version: $1"
  finish
}
JAVA_DB=$'Java DB:\n  Version: 77\n  UpdatedAt: 2001-02-03 04:05:06 +0000 UTC\n'
bad_version "no Trivy Version: line" $'Vulnerability DB:\n  Version: 2\n  UpdatedAt: 2026-11-17\n'"$JAVA_DB"
bad_version "no vulnerability DB Version: line" $'Version: 0.74.0\nVulnerability DB:\n  UpdatedAt: 2026-11-17\n'"$JAVA_DB"
bad_version "no vulnerability DB UpdatedAt" $'Version: 0.74.0\nVulnerability DB:\n  Version: 2\n'"$JAVA_DB"
bad_version "an empty UpdatedAt value" $'Version: 0.74.0\nVulnerability DB:\n  Version: 2\n  UpdatedAt:\n'"$JAVA_DB"
bad_version "a 257-character Trivy version" "Version: $(rep 9 257)"$'\nVulnerability DB:\n  Version: 2\n  UpdatedAt: 2026-11-17\n'

begin
big=$(vuln_line "$(rep c 256)" "$(rep p 256)" "$(rep i 256)" "$(rep f 256)" "$(rep x 256)")
{ yes "$big" || true; } | head -n 1000 >"$SCRATCH/scan.base"
go "$TAG" "$RESULTS"
fails "a Trivy output that pushes the results over 1 MiB"
if stderr_has "1 MiB"; then pass; else fail "oversize results: the message says why"; fi
finish

# --- clean runs --------------------------------------------------------------------------------

section_order() { grep '^## ' "$1" | tr '\n' '|'; }

clean_env() { # the binary variations of the spec
  export TE_DROP_gh=all
  export TE_DROP_betterleaks=main.main
  export TE_DROP_tofu=runtime.main
  export TE_DROP_gh_real=golang.org/x/net/html.fosterParent
  export TE_NONE=node
  printf '%s\n%s\n%s\n' "$(vuln_line CVE-2026-2 pkg-a 1.0 1.1 '/opt/a`b#c/lib')" \
    "$(vuln_line CVE-2026-3 pkg-b "$(rep 7 256)" 1.1 /opt/b)" \
    "$(vuln_line CVE-2026-4 pkg-c 1.0 1.1 'C:\x\y')" >"$SCRATCH/scan.tofu"
}

clean_checks() { # clean_checks <description> <results file>
  local d=$1 f=$2 flavor id
  assert_rc "$d" 0 "$RC"
  assert_eq "$d: no stdout (no warning line)" "" "$(cat "$SCRATCH/stdout")"
  assert_eq "$d: the level-2 sections, in order" "$EXPECTED_SECTIONS" "$(section_order "$f")"
  assert_eq "$d: the title" "# Trivy re-scan results" "$(head -n 1 "$f")"
  for flavor in base tofu node devapp devapp-tofu; do
    id="sha256:$(printf '%s' "$flavor" | sha256sum | cut -c1-64)"
    if grep -qF -- "- $flavor \`$id\`" "$f"; then pass; else fail "$d: the $flavor image id is recorded"; fi
  done
  for pin in GH_VERSION BETTERLEAKS_VERSION YQ_VERSION; do
    if grep -qF -- "- $pin \`$(sed -n "s/^ARG $pin=//p" "$ROOT_DIR/images/base/Dockerfile" | head -n 1)\`" "$f"; then pass; else fail "$d: pin $pin"; fi
  done
  for pin in TOFU_VERSION TFLINT_VERSION; do
    if grep -qF -- "- $pin \`$(sed -n "s/^ARG $pin=//p" "$ROOT_DIR/images/tofu/Dockerfile" | head -n 1)\`" "$f"; then pass; else fail "$d: pin $pin"; fi
  done
  if grep -qF "\`$COMMIT\`" "$f"; then pass; else fail "$d: GITHUB_SHA is the recorded base commit"; fi
  if grep -qF 'Trivy version: `0.74.0`' "$f"; then pass; else fail "$d: the Trivy version"; fi
  if grep -qF 'Vulnerability DB version: `2`' "$f" && grep -qF 'UpdatedAt: `2026-11-17 06:01:02.123456789 +0000 UTC`' "$f"; then pass; else fail "$d: the vulnerability DB's values"; fi
  if grep -qE '2001-02-03|`77`' "$f"; then fail "$d: the Java DB's values appear"; else pass; fi
  if grep -qF '`/home/vscode/.cache/pre_commit/x/lib/foo.so`' "$f"; then pass; else fail "$d: the pre_commit path is written unchanged"; fi
  if awk '/^## Findings: base/{f=1;next} /^## /{f=0} f' "$f" | grep -qF 'vulnerability `CVE-2026-1111`'; then pass; else fail "$d: a fake vulnerability lands in Findings: base"; fi
  if awk '/^## Findings: base/{f=1;next} /^## /{f=0} f' "$f" | grep -qF 'secret rule `aws-access-key-id`, path `app/config.yml`'; then pass; else fail "$d: a fake secret's rule id and path land in Findings: base"; fi
  if awk '/^## Findings: node/{f=1;next} /^## /{f=0} f' "$f" | grep -qx -- '- none'; then pass; else fail "$d: a none line for the flavor with no findings"; fi
  assert_eq "$d: three unchecked binaries" 3 "$(grep -c 'unchecked' "$f")"
  assert_eq "$d: three symbols present, for gh-real only" 3 "$(grep -c ': present$' "$f")"
  assert_eq "$d: one symbol absent" 1 "$(grep -c ': absent$' "$f")"
  if grep -qF '`golang.org/x/net/html.fosterParent`: absent' "$f"; then pass; else fail "$d: fosterParent is reported absent"; fi
  if grep -q 'sha256 `[0-9a-f]\{64\}`' "$f"; then pass; else fail "$d: the binaries' sha256 are recorded"; fi
  if grep -qF "$SCRATCH" "$f"; then fail "$d: the scratch directory's path appears in the file"; else pass; fi
  # no matched secret text anywhere: not in the file, stdout or stderr
  if grep -rqF "$MARK" "$f" "$SCRATCH/stdout" "$SCRATCH/stderr"; then fail "$d: a secret's matched text appears"; else pass; fi
  # the docker calls the pass made
  if grep -qE '^docker (build|pull|push|login|logout) ' "$TE_LOG"; then fail "$d: no build, pull, push or login"; else pass; fi
  if grep -qF -- '--ignorefile' "$TE_LOG"; then fail "$d: no --ignorefile"; else pass; fi
  if grep -qF 'docker.sock' "$TE_LOG"; then fail "$d: no docker.sock mount"; else pass; fi
  assert_eq "$d: five saves" 5 "$(grep -c '^docker save ' "$TE_LOG")"
  assert_eq "$d: five scans, each with --scanners vuln,secret" 5 "$(grep -c -- ' image --input /scan/image.tar --quiet --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed ' "$TE_LOG")"
  assert_eq "$d: four symbol searches" 4 "$(grep -c -- '--entrypoint grep' "$TE_LOG")"
  assert_eq "$d: every symbol search runs with --network none" 4 "$(grep -c -- '--rm -i --network none --entrypoint grep' "$TE_LOG")"
  assert_eq "$d: the results file is the only file left" "results.md" "$(ls "$SCRATCH/out")"
  common_checks "$d"
}

begin; clean_env; go "$TAG" "$RESULTS"
clean_checks "clean run, OUTPUT absent" "$RESULTS"
if grep -qF 'path `/opt/a?b?c/lib`' "$RESULTS"; then pass; else fail "clean run: a backtick and a # become ?"; fi
if grep -qF "installed \`$(rep 7 256)\`" "$RESULTS"; then pass; else fail "clean run: a 256-character field is written in full"; fi
if grep -qF 'path `C:?x?y`' "$RESULTS"; then pass; else fail "clean run: a backslash becomes ?"; fi
finish

begin; clean_env; : >"$RESULTS"
printf 'Version: 0.74`0\nVulnerability DB:\n  Version: 3\n  UpdatedAt: 2026-12-01 00:00:00 +0000 UTC' >"$SCRATCH/version.txt"
go "$TAG" "$RESULTS"
assert_rc "clean run, OUTPUT pre-created" 0 "$RC"
assert_eq "clean run, pre-created: the section order" "$EXPECTED_SECTIONS" "$(section_order "$RESULTS")"
if grep -qF 'Trivy version: `0.74?0`' "$RESULTS"; then pass; else fail "clean run: a backtick in the Trivy version becomes ?"; fi
if grep -qF 'Vulnerability DB version: `3`' "$RESULTS" && grep -qF 'UpdatedAt: `2026-12-01 00:00:00 +0000 UTC`' "$RESULTS"; then pass; else fail "clean run: the last section's values are recorded"; fi
common_checks "clean run, pre-created OUTPUT"; finish

# a REGISTRY override is honoured, and no ref outside it is read
begin; clean_env; export TE_REGISTRY=registry.example/team
go "$TAG" "$RESULTS" REGISTRY=registry.example/team
clean_checks "clean run with REGISTRY" "$RESULTS"
finish

# --- the drift guards ---------------------------------------------------------------------------

for name in TRIVY TEMPLATE KEEP MAX_FIELD MAX_BINARY MAX_RESULTS; do
  want=$(grep -m1 "^$name=" "$RESCAN" || true)
  got=$(grep -m1 "^$name=" "$SRC" || true)
  if [ -n "$want" ] && [ "$want" = "$got" ]; then pass; else fail "the $name line is byte-identical to trivy-rescan.sh's" "want: $want / got: $got"; fi
done
want=$(grep -m1 '^TRIVY=' "$ROOT_DIR/.github/scripts/build-and-test.sh" || true)
got=$(grep -m1 '^TRIVY=' "$SRC" || true)
if [ -n "$want" ] && [ "$want" = "$got" ]; then pass; else fail "TRIVY equals build-and-test.sh's"; fi
if grep -qF "TEMPLATE='$TEMPLATE'" "$SRC"; then pass; else fail "the script's template is byte for byte the spec's"; fi
if grep -v '^[[:space:]]*#' "$SRC" | grep -qF '.sarif'; then fail "the script never reads out/*.sarif"; else pass; fi

summary
