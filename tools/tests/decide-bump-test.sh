#!/usr/bin/env bash
# Tests for tools/decide-bump.sh and tools/fetch-consumer.sh against the fake `gh`, with a
# fake devc-verify whose exit code the test chooses. Hand-built fixtures, offline.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

R=glunk-works/app
BASE=1111111111111111111111111111111111111111
HEAD=$SHA

setup() { # sets FAKE_VERIFY and fixtures for a clean candidate
  new_scenario
  FAKE_VERIFY="$SCRATCH/devc-verify"
  cat > "$FAKE_VERIFY" <<'V'
#!/usr/bin/env bash
echo "devc-verify $*" >> "$FAKE_LOG"
exit "${FAKE_VERIFY_RC:-0}"
V
  chmod +x "$FAKE_VERIFY"
  export FAKE_VERIFY_RC=0
  printf '{"head":{"sha":"%s"},"base":{"sha":"%s"}}' "$HEAD" "$BASE" > "$FAKE_FIX/pulls__2.json"
  jq -n '{files:[{filename:".devcontainer/Dockerfile",status:"modified",additions:1,deletions:1,patch:"@@ -1 +1 @@\n-FROM x\n+FROM y"}]}' \
    > "$FAKE_FIX/compare__$BASE...$HEAD.json"
  printf '{"truncated":false,"tree":[{"path":".devcontainer/Dockerfile","type":"blob","mode":"100644"},{"path":".devcontainer/devcontainer.json","type":"blob","mode":"100644"}]}' \
    > "$FAKE_FIX/git__trees__$HEAD.json"
  printf 'FROM x\n' > "$FAKE_FIX/contents__.devcontainer__Dockerfile.json"
  printf '{}\n' > "$FAKE_FIX/contents__.devcontainer__devcontainer.json.json"
}
run_decide() { # [VAR=value ...] -> RC
  RC=0
  env REPO="$R" HEAD_SHA="$HEAD" CANDIDATE_PR=2 DEVC_VERIFY="$FAKE_VERIFY" WORK_DIR="$SCRATCH/work" \
    GH_TOKEN=t "$@" bash "$TOOLS_DIR/decide-bump.sh" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
}

suite "decide-bump.sh"

setup; run_decide
assert_rc "clean bump" 0 "$RC"; assert_eq "clean bump exempt" true "$(outv exempt)"; assert_eq "written once" 1 "$(outn exempt)"
assert_log_has "tool is called with decide" "devc-verify decide --consumer-dir"
end_scenario

setup; FAKE_VERIFY_RC=3; export FAKE_VERIFY_RC; run_decide
assert_rc "tool says no" 0 "$RC"; assert_eq "tool says no exempt" false "$(outv exempt)"
end_scenario

setup; FAKE_VERIFY_RC=2; export FAKE_VERIFY_RC; run_decide
assert_rc "tool error fails the job" 1 "$RC"; assert_eq "tool error writes nothing" 0 "$(outn exempt)"
end_scenario

setup; FAKE_VERIFY_RC=1; export FAKE_VERIFY_RC; run_decide
assert_rc "tool code 1 fails the job" 1 "$RC"; assert_eq "tool code 1 writes nothing" 0 "$(outn exempt)"
end_scenario

setup; mut pulls__2 '.head.sha = "2222222222222222222222222222222222222222"'; run_decide
assert_eq "head moved before start" false "$(outv exempt)"; assert_log_lacks "no verify after a moved head" "devc-verify"
end_scenario

setup; printf '{"head":{"sha":"%s"},"base":{"sha":"%s"}}' "2222222222222222222222222222222222222222" "$BASE" > "$FAKE_FIX/pulls__2.2.json"
cp "$FAKE_FIX/pulls__2.json" "$FAKE_FIX/pulls__2.1.json"; run_decide
assert_eq "head moved during the run" false "$(outv exempt)"
end_scenario

setup; mut "compare__$BASE...$HEAD" '.files += [.files[0]]'; run_decide
assert_eq "two files" false "$(outv exempt)"; assert_log_lacks "no verify for two files" "devc-verify"
end_scenario

setup; mut "compare__$BASE...$HEAD" '.files[0].previous_filename = "old"'; run_decide
assert_eq "rename" false "$(outv exempt)"
end_scenario

setup; mut "compare__$BASE...$HEAD" '.files[0].filename = ".github/workflows/x.yml"'; run_decide
assert_eq "other file" false "$(outv exempt)"
end_scenario

setup; mut "compare__$BASE...$HEAD" '.files[0].additions = 2'; run_decide
assert_eq "not +1/-1" false "$(outv exempt)"
end_scenario

setup; status_of "compare__$BASE...$HEAD" 500; run_decide
assert_rc "API 500 fails the job" 1 "$RC"; assert_eq "API 500 writes nothing" 0 "$(outn exempt)"
end_scenario

setup; status_of pulls__2 neterr; run_decide
assert_rc "network error fails the job" 1 "$RC"; assert_eq "network error writes nothing" 0 "$(outn exempt)"
end_scenario

setup; run_decide HEAD_SHA=nothex
assert_rc "bad head_sha" 2 "$RC"; assert_eq "bad head_sha writes nothing" 0 "$(outn exempt)"
end_scenario

setup; run_decide CANDIDATE_PR='2;x'
assert_rc "bad candidate_pr" 2 "$RC"
end_scenario

suite "fetch-consumer.sh"

fetch() { RC=0; bash "$TOOLS_DIR/fetch-consumer.sh" "$R" "$HEAD" "$SCRATCH/out" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?; }

setup; fetch
assert_rc "clean fetch" 0 "$RC"
assert_eq "dockerfile written" "FROM x" "$(cat "$SCRATCH/out/.devcontainer/Dockerfile")"
assert_eq "no other-marker" no "$([ -e "$SCRATCH/out/_other" ] && echo yes || echo no)"
end_scenario

setup; mut "git__trees__$HEAD" '.tree += [{"path":"sub/devcontainer.json","type":"blob","mode":"100644"}]'; fetch
assert_rc "extra devcontainer.json" 0 "$RC"
assert_eq "other-marker written" yes "$([ -e "$SCRATCH/out/_other/devcontainer.json" ] && echo yes || echo no)"
end_scenario

setup; mut "git__trees__$HEAD" '.tree += [{"path":".devcontainer.json","type":"blob","mode":"100644"}]'; fetch
assert_eq "dotted devcontainer.json at root" yes "$([ -e "$SCRATCH/out/_other/devcontainer.json" ] && echo yes || echo no)"
end_scenario

setup; mut "git__trees__$HEAD" '.truncated = true'; fetch
assert_rc "truncated tree" 1 "$RC"
end_scenario

setup; mut "git__trees__$HEAD" '(.tree[] | select(.path==".devcontainer/Dockerfile") | .mode) = "120000"'; fetch
assert_rc "symlinked Dockerfile" 1 "$RC"
end_scenario

setup; mut "git__trees__$HEAD" '.tree |= map(select(.path != ".devcontainer/devcontainer.json"))'; fetch
assert_rc "missing devcontainer.json" 1 "$RC"
end_scenario

setup; mut "git__trees__$HEAD" '.tree += [{"path":"a/DevContainer.JSON","type":"blob","mode":"100644"}]'; fetch
assert_eq "mixed-case devcontainer.json elsewhere" yes "$([ -e "$SCRATCH/out/_other/devcontainer.json" ] && echo yes || echo no)"
end_scenario

setup; mut "git__trees__$HEAD" '.tree += [{"path":".devcontainer/dockerfile","type":"blob","mode":"100644"}]'; fetch
assert_rc "case-variant Dockerfile beside the real one" 1 "$RC"
end_scenario

setup; mut "git__trees__$HEAD" '.tree += [{"path":".devcontainer/DevContainer.json","type":"blob","mode":"100644"}]'; fetch
assert_rc "case-variant devcontainer.json beside the real one" 1 "$RC"
end_scenario

setup; mut "git__trees__$HEAD" '(.tree[] | select(.path==".devcontainer/Dockerfile") | .mode) = "100755"'; fetch
assert_rc "executable Dockerfile is still a regular file" 0 "$RC"
end_scenario

suite "decide-bump.sh API shapes"

setup; mut pulls__2 'del(.head.sha)'; run_decide
assert_rc "pulls response without head.sha fails the job" 1 "$RC"; assert_eq "no head.sha writes nothing" 0 "$(outn exempt)"
end_scenario

setup; mut "compare__$BASE...$HEAD" 'del(.files)'; run_decide
assert_rc "compare response without files fails the job" 1 "$RC"; assert_eq "no files writes nothing" 0 "$(outn exempt)"
end_scenario

setup; mut "compare__$BASE...$HEAD" 'del(.files[0].patch)'; run_decide
assert_rc "a file without a patch is a plain no" 0 "$RC"; assert_eq "no patch is false" false "$(outv exempt)"
end_scenario

echo "decide-bump: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
