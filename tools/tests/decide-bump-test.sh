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
# The template at this pin and the repository the token mount must name (#418).
assert_log_has "decide gets the template dir" "--template-dir $TOOLS_DIR/../template"
assert_log_has "decide gets the repo" "--repo $R"
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

# --- the extras under .devcontainer/ (#418) ------------------------------------------------
there() { [ -e "$SCRATCH/out/$1" ] && echo yes || echo no; }
extra() { # path [mode] [size]: add a tree entry and its served contents
  local p="$1" m="${2:-100644}" z="${3:-4}"
  mut "git__trees__$HEAD" ".tree += [{\"path\":\"$p\",\"type\":\"blob\",\"mode\":\"$m\",\"size\":$z}]"
  printf 'x\n' > "$FAKE_FIX/contents__${p//\//__}.json"
}

setup; fetch
assert_eq "no extras, no irregular marker" no "$(there _irregular)"
end_scenario

setup; extra .devcontainer/tools.txt; extra .devcontainer/scripts/setup.sh 100755; fetch
assert_rc "extras fetch" 0 "$RC"
assert_eq "a top-level extra is written" x "$(cat "$SCRATCH/out/.devcontainer/tools.txt")"
assert_eq "a nested extra is written" x "$(cat "$SCRATCH/out/.devcontainer/scripts/setup.sh")"
assert_eq "regular extras leave no marker" no "$(there _irregular)"
end_scenario

for c in "symlink:.devcontainer/link:120000:4" "submodule:.devcontainer/sub:160000:4" \
         "unsafe name:.devcontainer/a b:100644:4" "dot-dot segment:.devcontainer/x/../y:100644:4" \
         "oversize:.devcontainer/big:100644:1048577" "case-variant dir:.DevContainer/x:100644:4"; do
  IFS=: read -r what p m z <<< "$c"
  setup; extra "$p" "$m" "$z"; fetch
  assert_rc "$what extra" 0 "$RC"
  assert_eq "$what extra is marked" yes "$(there _irregular/.devcontainer)"
  assert_eq "$what extra is not written" no "$(there "$p")"
  end_scenario
done

setup
for i in $(seq 1 65); do extra ".devcontainer/f$i"; done
fetch
assert_rc "65 extras" 0 "$RC"
assert_eq "the 64th is written" yes "$(there .devcontainer/f64)"
assert_eq "the 65th is not" no "$(there .devcontainer/f65)"
assert_eq "too many extras are marked" yes "$(there _irregular/.devcontainer)"
end_scenario

# --- --mode-only, the lenient base and tip read --------------------------------------------
fetch_mode() { RC=0; bash "$TOOLS_DIR/fetch-consumer.sh" --mode-only "$R" "$HEAD" "$SCRATCH/out" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?; }

setup; extra .devcontainer/tools.txt; mut "git__trees__$HEAD" '.tree += [{"path":"sub/devcontainer.json","type":"blob","mode":"100644"}]'; fetch_mode
assert_rc "mode-only fetch" 0 "$RC"
assert_eq "mode-only writes the Dockerfile" "FROM x" "$(cat "$SCRATCH/out/.devcontainer/Dockerfile")"
assert_eq "mode-only writes devcontainer.json" yes "$(there .devcontainer/devcontainer.json)"
assert_eq "mode-only fetches no extras" no "$(there .devcontainer/tools.txt)"
assert_eq "mode-only marks nothing" no "$(there _other)"
assert_eq "mode-only writes the sentinel" yes "$(there _listed)"
end_scenario

setup; mut "git__trees__$HEAD" '.tree |= map(select(.path | startswith(".devcontainer") | not))'; fetch_mode
assert_rc "mode-only, nothing there" 0 "$RC"
assert_eq "mode-only, nothing written" no "$(there .devcontainer/Dockerfile)"
assert_eq "mode-only, an empty tree still writes the sentinel" yes "$(there _listed)"
end_scenario

setup; mut "git__trees__$HEAD" '(.tree[] | select(.path==".devcontainer/Dockerfile") | .mode) = "120000"'; fetch_mode
assert_rc "mode-only, a symlinked Dockerfile" 0 "$RC"
assert_eq "mode-only, a symlink counts as absent" no "$(there .devcontainer/Dockerfile)"
end_scenario

setup; mut "git__trees__$HEAD" '.truncated = true'; fetch_mode
assert_rc "mode-only, a truncated tree is an error" 1 "$RC"
assert_eq "mode-only, a truncated tree leaves no sentinel" no "$(there _listed)"
end_scenario

setup; status_of "git__trees__$HEAD" 500; fetch_mode
assert_rc "mode-only, an API error is an error" 1 "$RC"
assert_eq "mode-only, an API error leaves no sentinel" no "$(there _listed)"
end_scenario

setup; status_of contents__.devcontainer__Dockerfile 403; fetch_mode
assert_rc "mode-only, a failed file read is an error" 1 "$RC"
assert_eq "mode-only, a failed file read leaves no sentinel" no "$(there _listed)"
end_scenario

setup; RC=0; bash "$TOOLS_DIR/fetch-consumer.sh" --mode-only "$R" "$HEAD" "$SCRATCH/out" extra > /dev/null 2>&1 || RC=$?
assert_rc "a stray argument" 2 "$RC"
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
