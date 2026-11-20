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
# Fake docker. BT_GATE_FAIL ("flavor:status ..."), BT_BUILD_FAIL and BT_SMOKE_FAIL (flavors)
# choose what fails. Every call it understands logs one normalized event to $BT_LOG.
flavor_of() { local f="${1##*devcontainer-}"; f="${f%%[:@]*}"; echo "$f"; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
violation() { echo "$*" >> "$BT_STATE/violations"; echo "fake docker: unexpected call: $*" >&2; exit 99; }
status_for() { local p; for p in $BT_GATE_FAIL; do [ "${p%%:*}" = "$1" ] && { echo "${p##*:}"; return; }; done; echo 0; }
cmd="${1:-}"; shift || true
case "$cmd" in
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
        case "$*" in
          *--exit-code*) echo "gate:$f" >> "$BT_LOG"; exit "$(status_for "$f")" ;;
          *cyclonedx*) echo "sbom:$f" >> "$BT_LOG"; exit 0 ;;
          *sarif*) echo "sarif:$f" >> "$BT_LOG"; exit 0 ;;
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

new_run() { # builds the scratch tree
  SCRATCH="$(mktemp -d)"
  mkdir -p "$SCRATCH/.github/scripts" "$SCRATCH/images/base/tools" "$SCRATCH/tests" "$SCRATCH/state"
  cp "$SRC" "$SCRATCH/.github/scripts/build-and-test.sh"
  local f
  for f in base tofu node devapp; do cp "$ROOT_DIR/images/$f/Dockerfile" "$SCRATCH/images/$f/Dockerfile" 2>/dev/null \
    || { mkdir -p "$SCRATCH/images/$f"; cp "$ROOT_DIR/images/$f/Dockerfile" "$SCRATCH/images/$f/Dockerfile"; }; done
  cp "$ROOT_DIR/images/base/tools/uv.lock" "$SCRATCH/images/base/tools/uv.lock"
  : > "$SCRATCH/calls"; : > "$SCRATCH/gho"
  write_fake_docker
}

run_script() { # run_script <args...>; sets RC; BT_* variables come from the caller
  RC=0
  (
    cd "$SCRATCH"
    export PATH="$SCRATCH/bin:$PATH" GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
    export GITHUB_OUTPUT="$SCRATCH/gho" BT_LOG="$SCRATCH/calls" BT_STATE="$SCRATCH/state"
    export BT_GATE_FAIL="${BT_GATE_FAIL:-}" BT_BUILD_FAIL="${BT_BUILD_FAIL:-}" BT_SMOKE_FAIL="${BT_SMOKE_FAIL:-}"
    unset REGISTRY
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

summary
