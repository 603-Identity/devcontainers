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

# --- --check-masked: a consumer's own copy, CONSUMER regions excluded (#233) -----------------
OWN="$ROOT_DIR/.github/workflows/architect-review-gate.yml"
# This repo's own gate is the rendered template outside its CONSUMER regions.
RC=0; bash "$RENDER" --check-masked "$OWN" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on this repo's own gate" 0 "$RC"
# A region body may differ: a different decide pin passes.
sed 's/devcontainer-bump-decision\.yml@[0-9a-f]\{40\} # v[0-9.]*/devcontainer-bump-decision.yml@0000000000000000000000000000000000000000 # v9.9/' "$TEMPLATE" > "$TMP/pin.yml"
if cmp -s "$TMP/pin.yml" "$TEMPLATE"; then fail "the pin edit changed nothing"; else pass; fi
RC=0; bash "$RENDER" --check-masked "$TMP/pin.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked ignores a different decide pin" 0 "$RC"
# ...and so may the code_paths and review values regions.
sed 's#images/\*|template/\*#docs/*|x/*#; s/REVIEWER_IDS: "[0-9 ]*"/REVIEWER_IDS: "1 2"/' "$TEMPLATE" > "$TMP/vals.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/vals.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked ignores code_paths and review values" 0 "$RC"
# Drift outside a region still fails, in the logic and in a line added after a region.
RC=0; bash "$RENDER" --check-masked "$TMP/drift.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on drifted logic" 1 "$RC"
RC=0; bash "$RENDER" --check-masked "$TMP/drift2.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on an extra line" 1 "$RC"
# A line smuggled into a region's marker line (the marker is kept, so it is compared).
sed '/^# >>> CONSUMER: review values$/s/$/ x/' "$TEMPLATE" > "$TMP/marker.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/marker.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on an altered marker line" 1 "$RC"
# Markers must be paired: missing close, missing open, misnamed close, nested open.
sed '/<<< CONSUMER: decide pin/d' "$TEMPLATE" > "$TMP/noclose.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/noclose.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on an unclosed region" 1 "$RC"
sed '/>>> CONSUMER: decide pin/d' "$TEMPLATE" > "$TMP/noopen.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/noopen.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on a close with no open" 1 "$RC"
sed 's/<<< CONSUMER: decide pin/<<< CONSUMER: other/' "$TEMPLATE" > "$TMP/misname.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/misname.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on a misnamed close" 1 "$RC"
sed '/^# <<< CONSUMER: review values$/i # >>> CONSUMER: inner' "$TEMPLATE" > "$TMP/nested.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/nested.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on a nested region" 1 "$RC"
# A region deleted whole is also drift: its marker lines are part of the compared text.
sed '/CONSUMER: decide pin/,/<<< CONSUMER: decide pin/d' "$TEMPLATE" > "$TMP/gone.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/gone.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on a deleted region" 1 "$RC"
RC=0; bash "$RENDER" --check-masked "$TMP/missing.yml" > /dev/null 2>&1 || RC=$?
if [ "$RC" -ne 0 ]; then pass; else fail "--check-masked on a missing file must fail"; fi
RC=0; bash "$RENDER" --check-masked > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked with no file" 2 "$RC"
sed "s/\$/$(printf '')/" "$TEMPLATE" > "$TMP/crlf.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/crlf.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on a CRLF file" 1 "$RC"
head -c -1 "$TEMPLATE" > "$TMP/nonl.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/nonl.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on a file with no final newline" 1 "$RC"

# The values --check-masked cannot see, pinned for this repo's own gate (#233).
assert_eq "own gate has one REVIEWER_IDS" 1 "$(grep -c '^  REVIEWER_IDS: ' "$OWN")"
assert_eq "own gate CONTEXT" 1 "$(grep -c '^  CONTEXT: architect-review$' "$OWN")"
assert_eq "own gate HEADER matches project.yml" "$(yq -r '.review.ci_gate.header' "$ROOT_DIR/.ai/project.yml")" "$(sed -n '/^  HEADER: "/{s/^  HEADER: "//;s/"$//;p}' "$OWN")"
assert_eq "own gate ATTESTATION matches project.yml" "$(yq -r '.review.ci_gate.attestation' "$ROOT_DIR/.ai/project.yml")" "$(sed -n '/^  ATTESTATION: "/{s/^  ATTESTATION: "//;s/"$//;p}' "$OWN")"
if grep -qE '^    uses: 603-Identity/devcontainers/\.github/workflows/devcontainer-bump-decision\.yml@[0-9a-f]{40} # v[0-9]+\.[0-9]+$' "$OWN"; then pass; else fail "own gate decide pin shape"; fi
# The code_paths arms are the repo's own list, every one setting touches=1.
own_arms="$(awk '/^[[:space:]]*# <<< CONSUMER: code_paths$/ { on = 0 } on { print } /^[[:space:]]*# >>> CONSUMER: code_paths$/ { on = 1 }' "$OWN")"
if [ -n "$own_arms" ] && ! grep -q 'touches=0' <<< "$own_arms" && ! grep -vq 'touches=1 ;;$' <<< "$own_arms"; then pass; else fail "own gate code_paths arms all set touches=1"; fi
# The other regions hold only what they should: --check-masked does not look inside them.
# Anchored exactly as mask_consumer is, so a decoy marker inside a body cannot hide lines.
region() { awk -v n="$1" '$0 ~ "^[[:space:]]*# <<< CONSUMER: " n "$" { on = 0 } on { print } $0 ~ "^[[:space:]]*# >>> CONSUMER: " n "$" { on = 1 }' "${2:-$OWN}"; }
bad="$(region 'review values' | grep -avE '^ *#[ -~]*$|^env:$|^  (REVIEWER_IDS: "281693088"|HEADER: ".*"|ATTESTATION: ".*"|CONTEXT: architect-review)$' || true)"
assert_eq "own gate review values region holds only the env keys" "" "$bad"
bad="$(region 'decide pin' | grep -avE '^ *#[ -~]*$|^    uses: 603-Identity/devcontainers/\.github/workflows/devcontainer-bump-decision\.yml@[0-9a-f]{40} # v[0-9]+\.[0-9]+$' || true)"
assert_eq "own gate decide pin region holds only comments and the pin" "" "$bad"
bad="$(region 'code_paths' | grep -avE '^ {18}#[ -~]*$|^ {18}[A-Za-z0-9_./*|-]+\) touches=1 ;;$' || true)"
assert_eq "own gate code_paths region holds only touches=1 arms" "" "$bad"
# A decoy marker comment inside a body must not hide lines from the region checks.
awk '{ print } /^# >>> CONSUMER: review values$/ { print "# x # <<< CONSUMER: review values"; print "  EVIL: yes"; print "# y # >>> CONSUMER: review values" }' "$OWN" > "$TMP/decoy.yml"
RC=0; bash "$RENDER" --check-masked "$TMP/decoy.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked ignores a decoy-marker body" 0 "$RC"
if region 'review values' "$TMP/decoy.yml" | grep -q 'EVIL'; then pass; else fail "region() sees a body line behind a decoy marker"; fi

# A NEL or U+2028 hides a line from awk and grep but a YAML parser splits on it (#233).
for nb in $'\302\205' $'\342\200\250'; do
  awk -v b="$nb" '{ print } /^# >>> CONSUMER: review values$/ { print "  # note" b "  EVIL: yes" }' "$OWN" > "$TMP/nel.yml"
  RC=0; bash "$RENDER" --check-masked "$TMP/nel.yml" > /dev/null 2>&1 || RC=$?
  assert_rc "--check-masked on a non-ASCII byte in a region body" 1 "$RC"
  if region 'review values' "$TMP/nel.yml" | grep -avE '^ *#[ -~]*$|^env:$|^  (REVIEWER_IDS: "281693088"|HEADER: ".*"|ATTESTATION: ".*"|CONTEXT: architect-review)$' | grep -q .; then pass; else fail "the region shape check lets a non-ASCII comment through"; fi
done

# A NUL byte hides from grep's line mode (binary file): -a catches it.
awk '{ print } /^# >>> CONSUMER: review values$/ { print "  # note" sprintf("%c", 0) }' "$OWN" > "$TMP/nul.yml"
if LC_ALL=C grep -aq '[^ -~]' "$TMP/nul.yml"; then pass; else fail "the NUL fixture holds no NUL (awk cannot emit it here)"; fi
RC=0; bash "$RENDER" --check-masked "$TMP/nul.yml" > /dev/null 2>&1 || RC=$?
assert_rc "--check-masked on a NUL byte in a region body" 1 "$RC"

summary
