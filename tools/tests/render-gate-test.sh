#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2119,SC2120,SC2015,SC2016
# Tests for tools/render-gate.sh: the template's run blocks are byte-equal to the tested
# scripts, the render is deterministic, the check notices drift, and the job graph is the
# one the spec defines.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite render-gate

RENDER="$TOOLS_DIR/render-gate.sh"
TEMPLATE="$ROOT_DIR/template/.github/workflows/architect-review-gate.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$RENDER" > "$TMP/a.yml"
bash "$RENDER" > "$TMP/b.yml"
if cmp -s "$TMP/a.yml" "$TMP/b.yml"; then pass; else fail "render is deterministic"; fi

# The committed template is byte-equal to the render.
if cmp -s "$TMP/a.yml" "$TEMPLATE"; then pass; else fail "template is byte-equal to the rendered output"; fi
RC=0; bash "$RENDER" --check > /dev/null 2>&1 || RC=$?
assert_rc "--check on the committed template" 0 "$RC"

# The check notices drift of one byte, in the logic and in the header, and a missing file.
sed 's/--squash/--rebase/' "$TEMPLATE" > "$TMP/drift.yml"
RC=0; bash "$RENDER" --check "$TMP/drift.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check on a drifted template" 1 "$RC"
{ cat "$TEMPLATE"; echo "# x"; } > "$TMP/drift2.yml"
RC=0; bash "$RENDER" --check "$TMP/drift2.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check on a template with an extra line" 1 "$RC"
RC=0; bash "$RENDER" --check "$TMP/missing.yml" > /dev/null 2>&1 || RC=$?
if [ "$RC" -ne 0 ]; then pass; else fail "--check on a missing file must fail"; fi

# Each script, minus its shebang and indented ten spaces, appears verbatim in the template.
tmpl="$(cat "$TEMPLATE")"
for s in gate-resolve.sh gate-post.sh; do
  expected="$(tail -n +2 "$TOOLS_DIR/$s" | awk '{ if ($0 == "") print ""; else print "          " $0 }')"
  if [[ "$tmpl" == *"$expected"* ]]; then pass; else fail "$s is inlined verbatim"; fi
  first="$(head -n 1 "$TOOLS_DIR/$s")"
  assert_eq "$s shebang" '#!/usr/bin/env bash' "$first"
  if grep -q '^set -euo pipefail$' "$TOOLS_DIR/$s"; then pass; else fail "$s sets -euo pipefail"; fi
  if grep -qF '${{' "$TOOLS_DIR/$s"; then fail "$s contains an inline expression"; else pass; fi
done

# Hygiene: LF only, no trailing whitespace, no tabs in the generated file.
if grep -q "$(printf '\r')" "$TEMPLATE"; then fail "template has CR"; else pass; fi
if grep -n ' $' "$TEMPLATE" > /dev/null; then fail "template has trailing whitespace"; else pass; fi
if grep -q "$(printf '\t')" "$TEMPLATE"; then fail "template has a tab"; else pass; fi

# The job graph (spec section 4).
if grep -qE '^  (resolve|decide|post):$' "$TEMPLATE" && [ "$(grep -cE '^  [a-z-]+:$' <(sed -n '/^jobs:/,$p' "$TEMPLATE"))" -eq 3 ]; then pass; else fail "exactly the jobs resolve, decide, post"; fi
if grep -q 'architect-review:' <(sed -n '/^jobs:/,$p' "$TEMPLATE"); then fail "no job is named architect-review"; else pass; fi
if grep -qi 'workflow_run' <(grep -v '^ *#' "$TEMPLATE"); then fail "no workflow_run trigger"; else pass; fi
if [ "$(grep -c '^permissions: {}$' "$TEMPLATE")" -eq 1 ]; then pass; else fail "workflow-level permissions: {}"; fi
for t in 'types: \[opened, synchronize, reopened\]' 'types: \[created\]' 'types: \[submitted\]'; do
  if grep -q "$t" "$TEMPLATE"; then pass; else fail "trigger $t"; fi
done
# uses: appears once, in decide, as a reusable-workflow call pinned by a 40-hex SHA with a version comment.
assert_eq "exactly one uses:" 1 "$(grep -cE '^ *uses:' "$TEMPLATE")"
if grep -qE '^    uses: 603-Identity/devcontainers/\.github/workflows/devcontainer-bump-decision\.yml@[0-9a-f]{40} # v[0-9X]+\.[0-9Y]+$' "$TEMPLATE"; then pass; else fail "decide pin shape"; fi
decide_block="$(sed -n '/^  decide:/,/^  post:/p' "$TEMPLATE")"
[[ "$decide_block" == *"uses: 603-Identity"* ]] && pass || fail "uses: is in the decide job"
for want in "needs: resolve" "needs.resolve.outputs.act == 'true' && needs.resolve.outputs.candidate == 'true'" "head_sha: \${{ needs.resolve.outputs.head_sha }}" "candidate_pr: \${{ needs.resolve.outputs.candidate_pr }}"; do
  [[ "$decide_block" == *"$want"* ]] && pass || fail "decide has: $want"
done
resolve_block="$(sed -n '/^  resolve:/,/^  decide:/p' "$TEMPLATE")"
post_block="$(sed -n '/^  post:/,$p' "$TEMPLATE")"
for want in "contents: read" "pull-requests: read" "issues: read" "timeout-minutes: 5" \
  "github.event_name != 'issue_comment' || github.event.issue.pull_request != null" \
  "act: \${{ steps.resolve.outputs.act }}" "candidate_pr: \${{ steps.resolve.outputs.candidate_pr }}"; do
  [[ "$resolve_block" == *"$want"* ]] && pass || fail "resolve has: $want"
done
for want in "needs: [resolve, decide]" "statuses: write" "contents: write" "pull-requests: write" "issues: read" "timeout-minutes: 5" \
  "if: \${{ !cancelled() && needs.resolve.result == 'success' && needs.resolve.outputs.act == 'true' }}" \
  "group: architect-review-\${{ github.workflow }}-\${{ needs.resolve.outputs.head_sha }}" "cancel-in-progress: false"; do
  [[ "$post_block" == *"$want"* ]] && pass || fail "post has: $want"
done
if grep -qE "^ *(- )?uses:" <<< "$resolve_block"; then fail "resolve has no uses:"; else pass; fi
if grep -qE "^ *(- )?uses:" <<< "$post_block"; then fail "post has no uses:"; else pass; fi
# The only expressions inside run blocks' env are env values: no ${{ }} inside any run: body.
if awk '/^ +run: \|$/ { inrun = 1; next } /^ +[a-z-]+:/ && !/^          / { inrun = 0 } inrun && /\$\{\{/ { bad = 1 } END { exit bad }' "$TEMPLATE"; then pass; else fail "no \${{ }} inside a run block"; fi
# The old comment is gone and the per-consumer regions are marked.
if grep -q 'No concurrency group on purpose' "$TEMPLATE"; then fail "old concurrency comment removed"; else pass; fi
for region in "review values" "decide pin"; do
  grep -q ">>> CONSUMER: $region" "$TEMPLATE" && grep -q "<<< CONSUMER: $region" "$TEMPLATE" && pass || fail "region $region"
done
grep -q '>>> CONSUMER: code_paths' "$TEMPLATE" && grep -q '<<< CONSUMER: code_paths' "$TEMPLATE" && pass || fail "region code_paths"
if grep -q '^ *\.github/\*) touches=1 ;;$' "$TEMPLATE"; then pass; else fail "the .github/ rule is in the template"; fi

summary
