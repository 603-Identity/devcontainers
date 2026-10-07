#!/usr/bin/env bash
# Tests for .github/scripts/image-scope.sh, the docs-only scope decision behind both the PR
# build skip and the publish gate in build.yml. Each case builds a scratch repo with
# `git fast-import`, so a tree can hold paths a filesystem cannot (`"`, `\`, tab, newline).
# Offline; needs bash and git.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/image-scope.sh"

# commit_file REPO-FEED BRANCH-MSG path... is awkward; instead build a stream by hand.
# blen STRING: byte length (fast-import counts bytes; ${#s} counts characters in a UTF-8 locale).
blen() { printf "%s" "$1" | LC_ALL=C wc -c | tr -d " "; }

# stream_commit MSG OP... where OP is "M:path" (add/modify), "D:path", or "R:old:new".
stream_commit() {
  local msg="$1"; shift
  printf 'commit refs/heads/main\ncommitter t <t@example.test> 0 +0000\ndata %d\n%s\n' "$(blen "$msg")" "$msg"
  local op path blob
  for op in "$@"; do
    case "$op" in
      M:*) path="${op#M:}"; blob="content of $path"
           printf 'M 100644 inline %s\ndata %d\n%s\n' "$(quote "$path")" "$(blen "$blob")" "$blob" ;;
      D:*) printf 'D %s\n' "$(quote "${op#D:}")" ;;
      R:*) op="${op#R:}"; printf 'R %s %s\n' "$(quote "${op%%:*}")" "$(quote "${op#*:}")" ;;
    esac
  done
}
quote() { # fast-import C-style quoting for a path
  local p="$1" bs=$'\\' q='"' nl=$'\n' tab=$'\t'
  p="${p//"$bs"/"$bs$bs"}"; p="${p//"$q"/"$bs$q"}"
  p="${p//"$nl"/"${bs}n"}"; p="${p//"$tab"/"${bs}t"}"
  printf '"%s"' "$p"
}

# scope_case EVENT BASE-OPS-ARRAY-NAME HEAD-OPS... : builds repo with a base commit holding
# the files in BASE_OPS and a head commit holding HEAD_OPS; runs the script; sets RC, OUT.
BASE_OPS=(M:README.md M:images/base/Dockerfile M:docs/a.md)
run_scope() { # EVENT HEAD_OPS...   (BASE_OPS is the first commit)
  local event="$1"; shift
  local repo="$SCRATCH/repo"
  git init -q "$repo"   # protectNTFS off: Git for Windows refuses a `"` in a path otherwise
  { stream_commit base "${BASE_OPS[@]}"; stream_commit head "$@"; } | git -c core.protectNTFS=false -C "$repo" fast-import --quiet
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  git -C "$repo" remote add origin "$repo"
  : > "$GITHUB_OUTPUT"; : > "$SCRATCH/summary"
  mkdir -p "$SCRATCH/tmp"
  RC=0
  ( cd "$repo" && env EVENT_NAME="$event" BASE_SHA="${BASE_SHA_OVERRIDE:-$(git rev-parse main~1)}" \
      RUNNER_TEMP="$SCRATCH/tmp" GITHUB_STEP_SUMMARY="$SCRATCH/summary" \
      bash "$SCRIPT" ) > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
}
case_build() { # description expected-build event head-ops...
  local d="$1" want="$2"; shift 2
  new_scenario; run_scope "$@"
  assert_rc "$d" 0 "$RC"; assert_eq "$d: build" "$want" "$(outv build)"; assert_eq "$d: written once" 1 "$(outn build)"
  end_scenario
}

suite "image-scope.sh"

for ev in pull_request push; do
  case_build "$ev: image file" 1 "$ev" M:images/base/Dockerfile.new
  case_build "$ev: template file" 1 "$ev" M:template/.devcontainer/devcontainer.json
  case_build "$ev: test file" 1 "$ev" M:tests/smoke.sh
  case_build "$ev: build script" 1 "$ev" M:.github/scripts/build-and-test.sh
  case_build "$ev: build.yml" 1 "$ev" M:.github/workflows/build.yml
  case_build "$ev: .trivyignore.yaml" 1 "$ev" M:.trivyignore.yaml
  case_build "$ev: .gitattributes" 1 "$ev" M:.gitattributes
  case_build "$ev: docs only" 0 "$ev" M:README.md M:docs/b.md
  case_build "$ev: docs only, non-ASCII name" 0 "$ev" 'M:docs/café.md'
  case_build "$ev: other workflow only" 0 "$ev" M:.github/workflows/lint.yml
  case_build "$ev: quoted names under images/" 1 "$ev" 'M:images/we"ird.sh' 'M:images/back\slash' $'M:images/tab\there' $'M:images/new\nline'
  case_build "$ev: quoted name outside scope" 0 "$ev" 'M:docs/we"ird.md' $'M:docs/new\nline.md'
  case_build "$ev: delete under images/" 1 "$ev" D:images/base/Dockerfile
  case_build "$ev: rename out of images/" 1 "$ev" R:images/base/Dockerfile:docs/Dockerfile
  case_build "$ev: scope file among docs" 1 "$ev" M:docs/b.md M:images/x M:README.md
done

# Events with no base to diff always build, and an unknown event fails toward building.
for ev in schedule workflow_dispatch some_new_event; do
  new_scenario; run_scope "$ev" M:README.md
  assert_rc "$ev builds" 0 "$RC"; assert_eq "$ev: build" 1 "$(outv build)"; end_scenario
done

# An all-zero base (a push that created the branch, or no last successful publish found).
new_scenario; BASE_SHA_OVERRIDE=0000000000000000000000000000000000000000 run_scope push M:README.md
assert_rc "zero before" 0 "$RC"; assert_eq "zero before: build" 1 "$(outv build)"; end_scenario

# The base has HEAD's tree (a revert of everything since the last publish, or the base is HEAD):
# the diff is empty for a legitimate reason, so skip rather than fail closed.
new_scenario
repo="$SCRATCH/repo"; git init -q "$repo"
{ stream_commit base M:README.md M:images/base/Dockerfile; stream_commit change M:images/base/Dockerfile.new; stream_commit revert D:images/base/Dockerfile.new; }   | git -c core.protectNTFS=false -C "$repo" fast-import --quiet
git -C "$repo" symbolic-ref HEAD refs/heads/main; git -C "$repo" remote add origin "$repo"
for base in "$(git -C "$repo" rev-parse main)" "$(git -C "$repo" rev-parse main~2)"; do
  : > "$GITHUB_OUTPUT"; : > "$SCRATCH/summary"; mkdir -p "$SCRATCH/tmp"; RC=0
  ( cd "$repo" && env EVENT_NAME=push BASE_SHA="$base" RUNNER_TEMP="$SCRATCH/tmp"       GITHUB_STEP_SUMMARY="$SCRATCH/summary" bash "$SCRIPT" ) > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
  assert_rc "same tree as $base" 0 "$RC"; assert_eq "same tree as $base: build" 0 "$(outv build)"
done
end_scenario

# Failing closed: an unfetchable base and a missing base fail the step. (An empty diff only happens
# for an equal tree, handled above; git cannot list nothing for two different trees.)
new_scenario
repo="$SCRATCH/repo"; git init -q "$repo"
stream_commit base M:README.md | git -c core.protectNTFS=false -C "$repo" fast-import --quiet
git -C "$repo" symbolic-ref HEAD refs/heads/main; git -C "$repo" remote add origin "$repo"
: > "$GITHUB_OUTPUT"; : > "$SCRATCH/summary"; mkdir -p "$SCRATCH/tmp"
RC=0; ( cd "$repo" && env EVENT_NAME=push BASE_SHA=1111111111111111111111111111111111111111 RUNNER_TEMP="$SCRATCH/tmp" \
  GITHUB_STEP_SUMMARY="$SCRATCH/summary" bash "$SCRIPT" ) > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
if [ "$RC" -ne 0 ]; then pass; else fail "unfetchable base must fail"; fi
assert_eq "unfetchable base writes no build=" 0 "$(outn build)"
RC=0; ( cd "$repo" && env EVENT_NAME=push RUNNER_TEMP="$SCRATCH/tmp" GITHUB_STEP_SUMMARY="$SCRATCH/summary" \
  bash "$SCRIPT" ) > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
if [ "$RC" -ne 0 ]; then pass; else fail "missing BASE_SHA must fail"; fi
end_scenario

summary
