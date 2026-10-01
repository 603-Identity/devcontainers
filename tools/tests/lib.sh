# shellcheck shell=bash
# shellcheck disable=SC2034
# Shared helpers for the gate tests. Sourced, never run. Needs bash, jq, and coreutils.
#
# Every scenario gets a scratch fixture directory (a copy of a committed one under
# fixtures/, then edited), a fresh call log, and a fresh GITHUB_OUTPUT. The fake `gh` on
# PATH serves the fixtures and records the calls. All fixtures are hand-built from the
# GitHub REST shapes and the facts recorded in the design spec's appendices.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
ROOT_DIR="$(cd "$TOOLS_DIR/.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
export PATH="$TESTS_DIR/bin:$PATH"

SHA=3865d58e1f2a4b7c9d0e1f2a3b4c5d6e7f8091a2
REPO_NAME=glunk-works/app
REVIEWER=281693088
HEADER='**Opus/Architect HITL review (automated)**'
ATTESTATION='*Fresh-session review: this session did not author the diff.*'

PASSED=0
FAILED=0
SUITE=""

suite() { SUITE="$1"; echo "== $SUITE"; }
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL [$SUITE] $1" >&2; [ -z "${2:-}" ] || echo "     $2" >&2; }

assert_eq() { # description expected actual
  if [ "$2" = "$3" ]; then pass; else fail "$1" "expected '$2', got '$3'"; fi
}
assert_rc() { assert_eq "$1 (exit code)" "$2" "$3"; }

# --- scenarios ------------------------------------------------------------------------

new_scenario() { # base-fixture-dir...
  SCRATCH="$(mktemp -d)"
  export FAKE_FIX="$SCRATCH/fix" FAKE_LOG="$SCRATCH/calls.log" FAKE_STATE="$SCRATCH/state"
  export GITHUB_OUTPUT="$SCRATCH/output"
  mkdir -p "$FAKE_FIX" "$FAKE_STATE"
  : > "$FAKE_LOG"
  : > "$GITHUB_OUTPUT"
  unset FAKE_MERGE_RC FAKE_DISARM_RC FAKE_POST_RC
  overlay "$@"
}
overlay() { # fixture-dir...  (later ones win)
  local d
  for d in "$@"; do cp -R "$FIXTURES/$d/." "$FAKE_FIX/"; done
}
end_scenario() { rm -rf "$SCRATCH"; }

put() { # fixture-name source-file-under-fixtures  (replace a served response)
  cp "$FIXTURES/$2" "$FAKE_FIX/$1.json"
}
mut() { # fixture-name jq-filter  (edit a served response in place)
  local f="$FAKE_FIX/$1.json"
  jq "$2" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
drop() { rm -f "$FAKE_FIX/$1.json" "$FAKE_FIX/$1.status"; }
status_of() { printf '%s\n' "$2" > "$FAKE_FIX/$1.status"; } # fixture-name http-code|neterr

# --- outputs and the call log ---------------------------------------------------------

outv() { # key  -> last value written to GITHUB_OUTPUT, or empty
  grep "^$1=" "$GITHUB_OUTPUT" | tail -n 1 | cut -d= -f2- || true
}
outn() { grep -c "^$1=" "$GITHUB_OUTPUT" || true; } # times a key was written

status_calls() { grep -F 'statuses/' "$FAKE_LOG" || true; }
states() { status_calls | sed -n 's/.* -f state=\([a-z]*\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//'; }
last_state() { status_calls | sed -n 's/.* -f state=\([a-z]*\) .*/\1/p' | tail -n 1; }
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
assert_log_has() { if log_has "$2"; then pass; else fail "$1" "call log lacks: $2"; fi; }
assert_log_lacks() { if log_has "$2"; then fail "$1" "call log has: $2"; else pass; fi; }
assert_states() { assert_eq "$1 (statuses posted)" "$2" "$(states)"; }

# --- running the scripts under test ---------------------------------------------------

# run_resolve [VAR=value ...]  -> sets RC; defaults describe a pull_request event on PR 2.
run_resolve() {
  RC=0
  env REPO="$REPO_NAME" EVENT_NAME=pull_request PR_NUMBER=2 ACTOR_ID= \
    REVIEWER_IDS="$REVIEWER" GH_TOKEN=test-token "$@" \
    bash "${RESOLVE_SCRIPT:-$TOOLS_DIR/gate-resolve.sh}" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
}

# run_post [VAR=value ...]  -> sets RC; defaults describe a plain non-candidate PR 2.
run_post() {
  RC=0
  env REPO="$REPO_NAME" HEAD_SHA="$SHA" PR=2 CANDIDATE=false CANDIDATE_PR= \
    DECIDE_RESULT=skipped EXEMPT= RUN_URL=https://example.test/run/1 GH_TOKEN=test-token \
    REVIEWER_IDS="$REVIEWER" HEADER="$HEADER" ATTESTATION="$ATTESTATION" CONTEXT=architect-review \
    "$@" bash "${POST_SCRIPT:-$TOOLS_DIR/gate-post.sh}" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
}

# with_case_block 'case arms' -> writes a copy of gate-post.sh whose CONSUMER code_paths
# region holds the given arms, and prints its path.
with_case_block() {
  local out="$SCRATCH/gate-post-custom.sh"
  awk -v arms="$1" '
    /# >>> CONSUMER: code_paths/ { print; print arms; skip = 1; next }
    /# <<< CONSUMER: code_paths/ { skip = 0 }
    !skip { print }
  ' "$TOOLS_DIR/gate-post.sh" > "$out"
  printf '%s\n' "$out"
}

summary() {
  echo "-- $SUITE: $PASSED passed, $FAILED failed"
  [ "$FAILED" -eq 0 ]
}
