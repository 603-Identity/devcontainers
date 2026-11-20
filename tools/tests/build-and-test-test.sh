#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Offline tests for .github/scripts/build-and-test.sh. Every scenario runs a copy of the real
# script inside a scratch tree (the Dockerfiles it reads ARGs from and uv.lock, at their
# repo-relative paths) against a fake `docker` put first on PATH. The script's stdout and stderr
# go to scratch files, never to this suite's own output: its ::group:: and ::error:: lines would
# be live workflow commands in the selftest job. Modelled on trivy-evidence-test.sh.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite build-and-test

SRC="$ROOT_DIR/.github/scripts/build-and-test.sh"
FLAVORS="base tofu node devapp devapp-tofu"
USAGE='usage: build-and-test.sh local | push <TAG>'

write_fake_docker() { # writes $SCRATCH/bin/docker
  mkdir -p "$SCRATCH/bin"
  cat >"$SCRATCH/bin/docker" <<'EOF'
#!/usr/bin/env bash
# Fake docker. BT_GATE_FAIL ("flavor:status ..."), BT_BUILD_FAIL, BT_SMOKE_FAIL, BT_PULL_FAIL,
# BT_PUB_SCAN_FAIL and BT_RMI_FAIL (flavors) choose what fails. Every call it understands logs one
# normalized event to $BT_LOG, and every Trivy call its full argument list to $BT_STATE/trivy-args.
# The JSON scans write $BT_REPORTS/pr-<flavor>.json or pub-<flavor>.json (`{}` when absent). Calls
# whose output the script must keep out of its log (the JSON scans, pull, rmi) print BT-NOISE to
# both streams.
flavor_of() { local f="${1##*devcontainer-}"; f="${f%%[:@]*}"; echo "$f"; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
violation() { echo "$*" >> "$BT_STATE/violations"; echo "fake docker: unexpected call: $*" >&2; exit 99; }
status_for() { local p; for p in $BT_GATE_FAIL; do [ "${p%%:*}" = "$1" ] && { echo "${p##*:}"; return; }; done; echo 0; }
noise() { echo "BT-NOISE docker $1"; echo "BT-NOISE docker $1" >&2; }
cmd="${1:-}"; shift || true
case "$cmd" in
  pull)
    f="$(flavor_of "${*: -1}")"; echo "pull:$f" >> "$BT_LOG"; noise pull
    in_list "$f" "$BT_PULL_FAIL" && exit 1
    exit 0 ;;
  rmi)
    f="$(flavor_of "${*: -1}")"; echo "rmi:$f" >> "$BT_LOG"; noise rmi
    in_list "$f" "$BT_RMI_FAIL" && exit 1
    exit 0 ;;
  build)
    tag=; out=; target=
    while [ $# -gt 0 ]; do
      case "$1" in -t) tag="$2"; shift ;; --output) out="$2"; shift ;; --target) target="$2"; shift ;; esac
      shift
    done
    if [ "$target" = claude-verify ]; then
      echo claude-verify >> "$BT_LOG"
      dest="${out##*dest=}"; mkdir -p "$dest"; echo claude > "$dest/claude"
      exit 0
    fi
    [ -n "$tag" ] || violation build without -t
    f="$(flavor_of "$tag")"; echo "build:$f" >> "$BT_LOG"
    in_list "$f" "$BT_BUILD_FAIL" && exit 1
    exit 0 ;;
  inspect)
    last="${*: -1}"
    case "$*" in
      *Labels*) echo label >> "$BT_LOG"; printf '%s\n' "$GITHUB_SHA" ;;
      *RepoDigests*) echo "digest:$(flavor_of "$last")" >> "$BT_LOG"
        printf 'ghcr.io/603-identity/devcontainer-%s@sha256:%s\n' "$(flavor_of "$last")" "$(printf '%064d' 7)" ;;
      *) violation inspect "$@" ;;
    esac
    exit 0 ;;
  push)
    echo "push:$(flavor_of "${*: -1}")" >> "$BT_LOG"; exit 0 ;;
  run)
    case "$*" in
      *aquasec/trivy*)
        f="$(flavor_of "${*: -1}")"
        out=; i=0; a=("$@")
        for ((i = 0; i < ${#a[@]}; i++)); do [ "${a[i]}" = --output ] && out="${a[i + 1]}"; done
        case "$*" in
          *--exit-code*) echo "gate:$f" >> "$BT_LOG"; exit "$(status_for "$f")" ;;
          *cyclonedx*) echo "sbom:$f" >> "$BT_LOG"; exit 0 ;;
          *sarif*) echo "sarif:$f" >> "$BT_LOG"; exit 0 ;;
          *"--ignorefile /src/out/trivy-base-ignore.yaml"*"--format json"*)
            echo "published-scan:$f" >> "$BT_LOG"; echo "published-scan:$f $*" >> "$BT_STATE/trivy-args"; noise trivy
            in_list "$f" "$BT_PUB_SCAN_FAIL" && exit 1
            [ -f "$BT_REPORTS/pub-$f.json" ] && cp "$BT_REPORTS/pub-$f.json" "${out#/src/}" || echo '{}' > "${out#/src/}"
            exit 0 ;;
          *"--format json"*)
            echo "gate:$f" >> "$BT_LOG"; echo "gate:$f $*" >> "$BT_STATE/trivy-args"; noise trivy
            st="$(status_for "$f")"; [ "$st" -eq 0 ] || exit "$st"
            [ -f "$BT_REPORTS/pr-$f.json" ] && cp "$BT_REPORTS/pr-$f.json" "${out#/src/}" || echo '{}' > "${out#/src/}"
            exit 0 ;;
          *) violation trivy "$@" ;;
        esac ;;
      *" sh /tests/smoke-devapp.sh "*)
        echo "smokedevapp:$(flavor_of "$(printf '%s\n' "$@" | grep -B1 -x sh | head -n1)")" >> "$BT_LOG"; exit 0 ;;
      *" sh /tests/smoke.sh "*)
        img="$(printf '%s\n' "$@" | grep -B1 -x sh | head -n1)"; f="$(flavor_of "$img")"
        echo "smoke:$f" >> "$BT_LOG"
        in_list "$f" "$BT_SMOKE_FAIL" && exit 1
        exit 0 ;;
      *) violation run "$@" ;;
    esac ;;
  *) violation "$cmd" "$@" ;;
esac
EOF
  chmod +x "$SCRATCH/bin/docker"
}

BASE_SHA=0123456789abcdef0123456789abcdef01234567
REF_BASE=ghcr.io/603-identity/devcontainer
DIGEST="$(printf '%064d' 3)"

write_fake_git() { # writes $SCRATCH/bin/git: only the fetch and show of the base commit
  cat >"$SCRATCH/bin/git" <<'EOF'
#!/usr/bin/env bash
# Fake git. BT_GIT_FAIL is `fetch` or `show`. Any call but those two is a violation.
[ "${1:-}" = -C ] && shift 2
noise() { echo "BT-NOISE git $1"; echo "BT-NOISE git $1" >&2; }
case "$*" in
  "fetch --no-tags --depth=1 origin $BT_BASE_SHA") echo "gitfetch" >> "$BT_LOG"; noise fetch
    [ "$BT_GIT_FAIL" = fetch ] && exit 1; exit 0 ;;
  "show $BT_BASE_SHA:.trivyignore.yaml") echo "gitshow" >> "$BT_LOG"; noise show
    [ "$BT_GIT_FAIL" = show ] && exit 1; echo "# base ignore file"; exit 0 ;;
  *) echo "fake git: unexpected call: $*" >> "$BT_STATE/violations"; exit 99 ;;
esac
EOF
  chmod +x "$SCRATCH/bin/git"
  cat >"$SCRATCH/.github/scripts/trivy-daily.sh" <<'EOF'
#!/usr/bin/env bash
# Stub of trivy-daily.sh: resolve writes the reference file the scenario chose, or fails.
[ "${1:-}" = resolve ] || { echo "stub trivy-daily: unexpected call: $*" >> "$BT_STATE/violations"; exit 99; }
echo resolve >> "$BT_LOG"; echo "BT-NOISE resolve"; echo "BT-NOISE resolve" >&2
[ -z "$BT_RESOLVE_FAIL" ] || exit 1
cp "$BT_REFS" "$2"
EOF
}

new_run() { # builds the scratch tree
  SCRATCH="$(mktemp -d)"
  mkdir -p "$SCRATCH/.github/scripts" "$SCRATCH/images/base/tools" "$SCRATCH/tests" "$SCRATCH/state" "$SCRATCH/reports"
  cp "$SRC" "$SCRATCH/.github/scripts/build-and-test.sh"
  cp "$ROOT_DIR/.github/scripts/trivy-diff.sh" "$SCRATCH/.github/scripts/trivy-diff.sh"
  EV_NAME=; EV_PATH=; BT_REFS="$SCRATCH/refs.tsv"
  local f
  for f in base tofu node devapp; do cp "$ROOT_DIR/images/$f/Dockerfile" "$SCRATCH/images/$f/Dockerfile" 2>/dev/null \
    || { mkdir -p "$SCRATCH/images/$f"; cp "$ROOT_DIR/images/$f/Dockerfile" "$SCRATCH/images/$f/Dockerfile"; }; done
  cp "$ROOT_DIR/images/base/tools/uv.lock" "$SCRATCH/images/base/tools/uv.lock"
  : > "$SCRATCH/calls"; : > "$SCRATCH/gho"
  write_fake_docker
  mkdir -p "$SCRATCH/bin"
  write_fake_git
  good_refs > "$BT_REFS"
}

good_refs() { local f; for f in $FLAVORS; do printf '%s\t%s-%s:1.2@sha256:%s\n' "$f" "$REF_BASE" "$f" "$DIGEST"; done; }

# pr_event: the scratch run is a pull request whose base commit is BASE_SHA.
pr_event() {
  printf '{"pull_request":{"base":{"sha":"%s"}}}\n' "${1:-$BASE_SHA}" > "$SCRATCH/event.json"
  EV_NAME=pull_request; EV_PATH="$SCRATCH/event.json"
}

# report <pr|pub> <flavor> <id>: a one-finding report in $SCRATCH/reports.
report() {
  jq -nc --arg id "$3" '{Results:[{Target:"tool (gobinary)",Class:"lang-pkgs",Vulnerabilities:[{VulnerabilityID:$id,PkgName:"stdlib",PkgPath:"usr/bin/tool",InstalledVersion:"1",FixedVersion:"2"}]}]}' > "$SCRATCH/reports/$1-$2.json"
}

run_script() { # run_script <args...>; sets RC; BT_* variables come from the caller
  RC=0
  (
    cd "$SCRATCH"
    export PATH="$SCRATCH/bin:$PATH" GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
    export GITHUB_OUTPUT="$SCRATCH/gho" BT_LOG="$SCRATCH/calls" BT_STATE="$SCRATCH/state"
    export BT_GATE_FAIL="${BT_GATE_FAIL:-}" BT_BUILD_FAIL="${BT_BUILD_FAIL:-}" BT_SMOKE_FAIL="${BT_SMOKE_FAIL:-}"
    export BT_PULL_FAIL="${BT_PULL_FAIL:-}" BT_PUB_SCAN_FAIL="${BT_PUB_SCAN_FAIL:-}" BT_RMI_FAIL="${BT_RMI_FAIL:-}"
    export BT_GIT_FAIL="${BT_GIT_FAIL:-}" BT_RESOLVE_FAIL="${BT_RESOLVE_FAIL:-}" BT_REFS BT_BASE_SHA="$BASE_SHA"
    export BT_REPORTS="$SCRATCH/reports"
    unset REGISTRY GITHUB_EVENT_NAME GITHUB_EVENT_PATH
    [ -z "$EV_NAME" ] || export GITHUB_EVENT_NAME="$EV_NAME"
    [ -z "$EV_PATH" ] || export GITHUB_EVENT_PATH="$EV_PATH"
    bash .github/scripts/build-and-test.sh "$@" >"$SCRATCH/stdout.txt" 2>"$SCRATCH/stderr.txt"
  ) || RC=$?
  LOG="$(cat "$SCRATCH/calls")"; OUT="$(cat "$SCRATCH/stdout.txt")"; ERR="$(cat "$SCRATCH/stderr.txt")"; GHO="$(cat "$SCRATCH/gho")"
  if [ -s "$SCRATCH/state/violations" ]; then
    fail "$DESC: the fake docker saw a call it does not know" "$(cat "$SCRATCH/state/violations")"
  fi
}

done_run() {
  if [ "$FAILED" -ne "$BEFORE" ]; then
    sed 's/^/  | out: /' "$SCRATCH/stdout.txt" >&2 || true; sed 's/^/  | err: /' "$SCRATCH/stderr.txt" >&2 || true
    sed 's/^/  | call: /' "$SCRATCH/calls" >&2 || true
  fi
  rm -rf "$SCRATCH"
}

grep_in() { # grep_in <text> <pattern> [-E]
  printf '%s\n' "$1" | grep -q ${3:+"$3"} -- "$2"
}
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
count() { printf '%s\n' "$1" | grep -cxF -- "$2" || true; }
log_has() { has "$LOG" "$1"; }
check() { # check <description> <command...>
  local d="$1"; shift
  if "$@"; then pass; else fail "$DESC: $d"; fi
}
check_not() { local d="$1"; shift; if "$@"; then fail "$DESC: $d"; else pass; fi; }
nonzero() { [ "$RC" -ne 0 ]; }

# 1. local, the gate failing for base (1) and tofu (125) ---------------------------------------
DESC="local, two gate failures"; BEFORE=$FAILED
new_run; BT_GATE_FAIL="base:1 tofu:125" run_script local
assert_eq "$DESC: exit status" 1 "$RC"
for f in $FLAVORS; do
  check "$f built" log_has "build:$f"
  check "$f smoke-tested" log_has "smoke:$f"
  check "$f gate-scanned" log_has "gate:$f"
  assert_eq "$DESC: ::group::$f once" 1 "$(count "$OUT" "::group::$f")"
done
check "base deferral line" has "$OUT" '::error::base: Trivy gate failed (exit 1); deferred to the end of the run'
check "tofu deferral line" has "$OUT" '::error::tofu: Trivy gate failed (exit 125); deferred to the end of the run'
assert_eq "$DESC: the last lines" \
  $'::endgroup::\n::error::Trivy gate failed for base\n::error::Trivy gate failed for tofu\nTrivy gate failed for: base tofu' \
  "$(printf '%s\n' "$OUT" | tail -n 4)"
check_not "no summary line for a passing flavour" grep_in "$OUT" '^::error::Trivy gate failed for (node|devapp)' -E
assert_eq "$DESC: stderr empty" "" "$ERR"
done_run

# 2. local, nothing failing --------------------------------------------------------------------
DESC="local, no failure"; BEFORE=$FAILED
new_run; run_script local
assert_eq "$DESC: exit status" 0 "$RC"
for f in $FLAVORS; do check "$f gate-scanned" log_has "gate:$f"; done
check_not "no deferral or summary line" grep_in "$OUT" 'Trivy gate failed'
done_run

# 3. local, a deferred gate failure then a smoke failure ---------------------------------------
DESC="local, gate failure then smoke failure"; BEFORE=$FAILED
new_run; BT_GATE_FAIL="base:1" BT_SMOKE_FAIL="tofu" run_script local
check "non-zero exit" nonzero
check "base deferral line" has "$OUT" '::error::base: Trivy gate failed (exit 1); deferred to the end of the run'
check_not "no summary line" grep_in "$OUT" 'Trivy gate failed for'
check_not "tofu gate scan absent" log_has "gate:tofu"
assert_eq "$DESC: smoke is the last call" "smoke:tofu" "$(printf '%s\n' "$LOG" | tail -n 1)"
done_run

# 4. local, a build failure ---------------------------------------------------------------------
DESC="local, build failure"; BEFORE=$FAILED
new_run; BT_BUILD_FAIL="node" run_script local
check "non-zero exit" nonzero
check "node build attempted" log_has "build:node"
for c in smoke:node gate:node build:devapp build:devapp-tofu; do check_not "$c absent" log_has "$c"; done
check_not "no summary" grep_in "$OUT" 'Trivy gate failed'
done_run

# 5. push, the gate failing for tofu ------------------------------------------------------------
DESC="push, tofu gate failure"; BEFORE=$FAILED
new_run; BT_GATE_FAIL="tofu:1" run_script push 1.2.3
check "non-zero exit" nonzero
check "base_digest written" grep_in "$GHO" '^base_digest='
check_not "no tofu_digest" grep_in "$GHO" '^tofu_digest='
for c in build:tofu smoke:tofu gate:tofu push:base; do check "$c" log_has "$c"; done
assert_eq "$DESC: the gate scan is the last call" "gate:tofu" "$(printf '%s\n' "$LOG" | tail -n 1)"
for c in sbom:tofu sarif:tofu push:tofu build:node build:devapp build:devapp-tofu; do check_not "$c absent" log_has "$c"; done
check_not "no ::error:: line" grep_in "$OUT" '^::error::'
check_not "no summary line" grep_in "$OUT" 'Trivy gate failed'
done_run

# 6. push, the gate failing for base ------------------------------------------------------------
DESC="push, base gate failure"; BEFORE=$FAILED
new_run; BT_GATE_FAIL="base:1" run_script push 1.2.3
check "non-zero exit" nonzero
check_not "no docker push" grep_in "$LOG" '^push:'
check_not "no base_digest" grep_in "$GHO" '^base_digest='
for c in sbom:base sarif:base build:tofu; do check_not "$c absent" log_has "$c"; done
done_run

# 7. usage errors -------------------------------------------------------------------------------
DESC="usage, no argument"; BEFORE=$FAILED
new_run; run_script
assert_rc "$DESC" 2 "$RC"; assert_eq "$DESC: stderr" "$USAGE" "$ERR"; assert_eq "$DESC: no docker call" "" "$LOG"; done_run
DESC="usage, empty argument"; BEFORE=$FAILED
new_run; run_script ""
assert_rc "$DESC" 2 "$RC"; assert_eq "$DESC: stderr" "$USAGE" "$ERR"; assert_eq "$DESC: no docker call" "" "$LOG"; done_run
DESC="usage, pushx"; BEFORE=$FAILED
new_run; run_script pushx
assert_rc "$DESC" 2 "$RC"; assert_eq "$DESC: stderr" "$USAGE" "$ERR"; assert_eq "$DESC: no docker call" "" "$LOG"; done_run

# 8. pull requests: the differential gate -------------------------------------------------------
DIFF_LINE='Trivy gate: differential against the published images'
order() { # order <first> <second>: both logged, the first one earlier
  local a b
  a="$(printf '%s\n' "$LOG" | grep -nxF -- "$1" | head -n1 | cut -d: -f1)"
  b="$(printf '%s\n' "$LOG" | grep -nxF -- "$2" | head -n1 | cut -d: -f1)"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
no_noise() { ! printf '%s\n%s\n' "$OUT" "$ERR" | grep -q 'BT-NOISE'; }
args_of() { grep -F -- "$1" "$SCRATCH/state/trivy-args" | head -n1; }

DESC="pr, a published finding"; BEFORE=$FAILED
new_run; pr_event; report pr node CVE-2026-0001; report pub node CVE-2026-0001
run_script local
assert_eq "$DESC: exit status" 0 "$RC"
check "decision line" has "$OUT" "$DIFF_LINE"
check "published line" has "$OUT" 'trivy-diff: node: published CVE-2026-0001 stdlib usr/bin/tool installed 1 fixed 2'
for f in $FLAVORS; do
  check "$f: pulled" log_has "pull:$f"
  check "$f: published scan" log_has "published-scan:$f"
  check "$f: removal after the scan" order "published-scan:$f" "rmi:$f"
  check "$f: count line" grep_in "$OUT" "^trivy-diff: $f: 0 added, [01] published, 0 secret\$" -E
done
assert_eq "$DESC: five pulls" 5 "$(printf '%s\n' "$LOG" | grep -c '^pull:')"
check "git fetch and show once" bash -c '[ "$(printf "%s\n" "$1" | grep -c "^git")" -eq 2 ]' _ "$LOG"
check_not "no deferral" grep_in "$OUT" 'Trivy gate failed'
check "output free of the fakes' noise" no_noise
assert_eq "$DESC: stderr empty" "" "$ERR"
check "PR scan flags" bash -c 'a="$1"; for w in "--scanners vuln,secret" "--severity HIGH,CRITICAL" "--ignore-unfixed" "--ignorefile /src/.trivyignore.yaml" "--format json"; do case "$a" in *"$w"*) ;; *) exit 1;; esac; done; case "$a" in *--exit-code*) exit 1;; esac' _ "$(args_of 'gate:node')"
check "published scan flags" bash -c 'a="$1"; for w in "--scanners vuln " "--severity HIGH,CRITICAL" "--ignore-unfixed" "--ignorefile /src/out/trivy-base-ignore.yaml" "--format json"; do case "$a" in *"$w"*) ;; *) exit 1;; esac; done; case "$a" in *--exit-code*|*vuln,secret*) exit 1;; esac' _ "$(args_of 'published-scan:node')"
done_run

DESC="pr, an added finding"; BEFORE=$FAILED
new_run; pr_event; report pr node CVE-2026-0001; report pub tofu CVE-2026-0001
run_script local
assert_eq "$DESC: exit status" 1 "$RC"
check "added line" has "$OUT" '::error::node: added CVE-2026-0001 stdlib usr/bin/tool installed 1 fixed 2'
check "deferral line" has "$OUT" '::error::node: Trivy gate failed (exit 1); deferred to the end of the run'
assert_eq "$DESC: the last lines" $'::error::Trivy gate failed for node\nTrivy gate failed for: node' "$(printf '%s\n' "$OUT" | tail -n 2)"
for f in $FLAVORS; do check "$f scanned" log_has "gate:$f"; done
check "no noise" no_noise
done_run

DESC="pr, a secret"; BEFORE=$FAILED
new_run; pr_event
jq -nc '{Results:[{Target:"app.env",Class:"secret",Secrets:[{RuleID:"generic-rule"}]}]}' | tee "$SCRATCH/reports/pr-devapp.json" > "$SCRATCH/reports/pub-devapp.json"
run_script local
assert_eq "$DESC: exit status" 1 "$RC"
check "secret line" has "$OUT" '::error::devapp: secret generic-rule in app.env'
check "deferral line" has "$OUT" '::error::devapp: Trivy gate failed (exit 1); deferred to the end of the run'
done_run

# the full gate for every flavour, one scenario per decision word; node holds a published finding
full_gate() { # full_gate <description> <word>: the run before this call already set up the scenario
  report pr node CVE-2026-0001; report pub node CVE-2026-0001
  run_script local
  assert_eq "$1: exit status" 1 "$RC"
  check "$1: warning line" has "$OUT" "::warning::Trivy gate: full gate for every flavour ($2)"
  check_not "$1: no decision line" has "$OUT" "$DIFF_LINE"
  check "$1: node fails with its added line" has "$OUT" '::error::node: added CVE-2026-0001 stdlib usr/bin/tool installed 1 fixed 2'
  check "$1: node deferral (exit 1)" has "$OUT" '::error::node: Trivy gate failed (exit 1); deferred to the end of the run'
  check "$1: every flavour scanned" bash -c 'for f in '"$FLAVORS"'; do printf "%s\n" "$1" | grep -qxF "gate:$f" || exit 1; done' _ "$LOG"
  check_not "$1: no docker pull" grep_in "$LOG" '^pull:'
  check_not "$1: no published scan" grep_in "$LOG" '^published-scan:'
  check "$1: no noise" no_noise
  assert_eq "$1: stderr empty" "" "$ERR"
  done_run
}
DESC="word no-event"; BEFORE=$FAILED; new_run; full_gate "$DESC" no-event
DESC="word not-pull-request"; BEFORE=$FAILED; new_run; pr_event; EV_NAME=push; full_gate "$DESC" not-pull-request
DESC="word bad-base (short)"; BEFORE=$FAILED; new_run; pr_event 0123abc; full_gate "$DESC" bad-base
DESC="word bad-base (upper case)"; BEFORE=$FAILED; new_run; pr_event "$(printf '%s' "$BASE_SHA" | tr a-f A-F)"; full_gate "$DESC" bad-base
DESC="word bad-base (no payload file)"; BEFORE=$FAILED; new_run; pr_event; EV_PATH="$SCRATCH/missing.json"; full_gate "$DESC" bad-base
DESC="word bad-base (payload not JSON)"; BEFORE=$FAILED; new_run; pr_event; echo nope > "$SCRATCH/event.json"; full_gate "$DESC" bad-base
DESC="word bad-base (no payload path)"; BEFORE=$FAILED; new_run; pr_event; EV_PATH=; full_gate "$DESC" bad-base
DESC="word fetch-failed"; BEFORE=$FAILED; new_run; pr_event; BT_GIT_FAIL=fetch full_gate "$DESC" fetch-failed
DESC="word ignorefile-failed"; BEFORE=$FAILED; new_run; pr_event; BT_GIT_FAIL=show full_gate "$DESC" ignorefile-failed
DESC="word resolve-failed"; BEFORE=$FAILED; new_run; pr_event; BT_RESOLVE_FAIL=1 full_gate "$DESC" resolve-failed
bad_refs() { # bad_refs <description> <file content, from stdin>
  DESC="word bad-refs ($1)"; BEFORE=$FAILED; new_run; pr_event; cat > "$BT_REFS"; full_gate "$DESC" bad-refs
}
good_refs | sed '/^devapp-tofu/d' | bad_refs "a missing flavour"
good_refs | sed 's/^devapp-tofu\t/base\t/' | bad_refs "a duplicated flavour"
good_refs | sed 's/^node\t\(.*\)devcontainer-node:/node\t\1devcontainer-tofu:/' | bad_refs "a reference of another flavour"
good_refs | sed 's#ghcr.io/603-identity#ghcr.example/603-identity#' | bad_refs "another host"
good_refs | sed 's#ghcr.io/603-identity#ghcr.io/other-org#' | bad_refs "another organisation"
good_refs | sed 's/@sha256:.*//' | bad_refs "a tag without a digest"
good_refs | sed 's/$/\textra/' | bad_refs "three fields"
{ good_refs; printf 'base\t%s-base:1.3@sha256:%s\n' "$REF_BASE" "$DIGEST"; } | bad_refs "a sixth line"
: | bad_refs "an empty file"
good_refs | sed 's/$/\r/' | bad_refs "carriage returns"

DESC="pr, a failed pull"; BEFORE=$FAILED
new_run; pr_event; report pr node CVE-2026-0001; report pub node CVE-2026-0001
BT_PULL_FAIL=node run_script local
assert_eq "$DESC: exit status" 1 "$RC"
check "warning line" has "$OUT" '::warning::Trivy gate: full gate for node (pull-failed)'
check "decision line" has "$OUT" "$DIFF_LINE"
check "node added line" has "$OUT" '::error::node: added CVE-2026-0001 stdlib usr/bin/tool installed 1 fixed 2'
check "node deferral (exit 1)" has "$OUT" '::error::node: Trivy gate failed (exit 1); deferred to the end of the run'
check_not "no published scan for node" log_has "published-scan:node"
check_not "no removal for node" log_has "rmi:node"
check "the other flavours compared" log_has "published-scan:devapp"
assert_eq "$DESC: only node fails" 'Trivy gate failed for: node' "$(printf '%s\n' "$OUT" | tail -n 1)"
check "no noise" no_noise
done_run

DESC="pr, a failed published scan"; BEFORE=$FAILED
new_run; pr_event; report pr node CVE-2026-0001; report pub node CVE-2026-0001
BT_PUB_SCAN_FAIL=node run_script local
assert_eq "$DESC: exit status" 1 "$RC"
check "warning line" has "$OUT" '::warning::Trivy gate: full gate for node (scan-failed)'
check "node added line" has "$OUT" '::error::node: added CVE-2026-0001 stdlib usr/bin/tool installed 1 fixed 2'
check "node deferral (exit 1)" has "$OUT" '::error::node: Trivy gate failed (exit 1); deferred to the end of the run'
check "the pulled image is still removed" order "published-scan:node" "rmi:node"
assert_eq "$DESC: only node fails" 'Trivy gate failed for: node' "$(printf '%s\n' "$OUT" | tail -n 1)"
check "no noise" no_noise
done_run

DESC="pr, a failed removal"; BEFORE=$FAILED
new_run; pr_event; report pr node CVE-2026-0001; report pub node CVE-2026-0001
BT_RMI_FAIL=node run_script local
assert_eq "$DESC: exit status" 0 "$RC"
check "warning line" has "$OUT" '::warning::Trivy gate: could not remove the published node image'
check "the run went on to devapp-tofu" log_has "rmi:devapp-tofu"
check "no noise" no_noise
done_run

DESC="pr, a failed PR scan"; BEFORE=$FAILED
new_run; pr_event
BT_GATE_FAIL="tofu:3" run_script local
assert_eq "$DESC: exit status" 1 "$RC"
check "deferral line with the status" has "$OUT" '::error::tofu: Trivy gate failed (exit 3); deferred to the end of the run'
check_not "no pull for tofu" log_has "pull:tofu"
check_not "no published scan for tofu" log_has "published-scan:tofu"
check "the other flavours compared" log_has "published-scan:node"
done_run

DESC="pr, a malformed PR report"; BEFORE=$FAILED
new_run; pr_event; echo 'not json' > "$SCRATCH/reports/pr-devapp.json"
run_script local
assert_eq "$DESC: exit status" 1 "$RC"
check "deferral line (exit 2)" has "$OUT" '::error::devapp: Trivy gate failed (exit 2); deferred to the end of the run'
assert_eq "$DESC: stderr is trivy-diff's one line" 'trivy-diff: a report is not well formed' "$ERR"
done_run

DESC="pr, a malformed published report"; BEFORE=$FAILED
new_run; pr_event; echo 'not json' > "$SCRATCH/reports/pub-node.json"
run_script local
assert_eq "$DESC: exit status" 1 "$RC"
check "deferral line (exit 2)" has "$OUT" '::error::node: Trivy gate failed (exit 2); deferred to the end of the run'
done_run

DESC="push, an event that looks like a pull request"; BEFORE=$FAILED
new_run; pr_event
run_script push 1.2.3
assert_eq "$DESC: exit status" 0 "$RC"
check_not "no decision line" grep_in "$OUT" 'Trivy gate:'
check_not "no git, resolve, pull or published scan" grep_in "$LOG" '^(git|resolve|pull:|published-scan:)' -E
check "the full gate ran for base" log_has "gate:base"
done_run

# drift guard: the reference pattern is byte-equal to trivy-daily.sh's REF_RE
core="$(sed -n "s/^REF_CORE='\(.*\)'\$/\1/p" "$ROOT_DIR/.github/scripts/trivy-daily.sh")"
mine="$(sed -n "s/^PUBLISHED_REF_RE='\(.*\)'\$/\1/p" "$SRC")"
assert_eq "the reference pattern is in step with trivy-daily.sh" "^${core}\$" "$mine"
if [ -n "$core" ]; then pass; else fail "the reference core was found"; fi

summary
