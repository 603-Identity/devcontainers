#!/usr/bin/env bash
# shellcheck disable=SC1091
# Tests for tools/check-zizmor-pin.sh (#423): the committed zizmor container pins follow the
# version uv.lock gives the image, and each rule fires on the mutation it exists for. Offline.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite zizmor-pin

CHECK="$TOOLS_DIR/check-zizmor-pin.sh"
LOCK=images/base/tools/uv.lock
LINT=.github/workflows/lint.yml
PROJ=.ai/project.yml
PREFIX='check-zizmor-pin:'
REF='ghcr\.io/zizmorcore/zizmor:[0-9.]*@sha256:[0-9a-f]\{64\}'
DIG_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
DIG_UP=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA

# new_tree: SCRATCH holds copies of the three files the check reads.
new_tree() {
  SCRATCH="$(mktemp -d)"
  local f
  for f in "$LOCK" "$LINT" "$PROJ"; do
    mkdir -p "$SCRATCH/$(dirname "$f")"
    cp "$ROOT_DIR/$f" "$SCRATCH/$f"
  done
}
# run_check [args...]: run the check on $SCRATCH (or the given args), exit code in RC, stderr in ERR.
run_check() {
  RC=0
  if [ "$#" -gt 0 ]; then
    ERR="$(bash "$CHECK" "$@" 2>&1 > /dev/null)" || RC=$?
  else
    ERR="$(bash "$CHECK" "$SCRATCH" 2>&1 > /dev/null)" || RC=$?
  fi
}
expect() { # description expected-rc [stderr-substring...]
  local d="$1" want="$2"
  shift 2
  assert_rc "$d" "$want" "$RC"
  local s
  for s in "$@"; do
    if [[ "$ERR" == *"$s"* ]]; then pass; else fail "$d (message)" "wanted '$s' in: $ERR"; fi
  done
}
done_tree() { rm -rf "$SCRATCH"; }

# The version and digest the committed pins carry, read here so the mutations track them.
LOCKVER="$(sed -n '/^name = "zizmor"$/{n;s/^version = "\(.*\)"$/\1/p;q;}' "$ROOT_DIR/$LOCK")"
[ -n "$LOCKVER" ] || { echo "zizmor-pin-test: no zizmor entry in $LOCK" >&2; exit 1; }
OLDVER=0.0.1

# The real repository root.
RC=0
ERR="$(cd "$ROOT_DIR" && bash "$CHECK" 2>&1 > /dev/null)" || RC=$?
expect "the repository root is clean" 0
if [ -z "$ERR" ]; then pass; else fail "the repository root prints nothing" "$ERR"; fi
RC=0
ERR="$(cd "$ROOT_DIR" && bash "$CHECK" "$ROOT_DIR" 2>&1 > /dev/null)" || RC=$?
expect "the repository root as an argument is clean" 0

# The line-keyed ignore in .github/zizmor.yml (architect-review-gate.yml:65) must hide only the
# template's issue_comment trigger: zizmor matches the bare file name in both scanned trees.
GATE_LINE="$(sed -n 65p "$ROOT_DIR/template/.github/workflows/architect-review-gate.yml")"
assert_eq "template gate line 65 is the issue_comment trigger the zizmor ignore covers" "  issue_comment:" "$GATE_LINE"
if [ -e "$ROOT_DIR/.github/workflows/architect-review-gate.yml" ]; then
  fail "no architect-review-gate.yml under .github/workflows (the zizmor ignore would hide its line 65)"
else
  pass
fi

# A copy of the three files is clean.
new_tree; run_check; expect "a scratch copy is clean" 0; done_tree

# uv.lock moves and both pins stay.
new_tree
sed -i '/^name = "zizmor"$/{n;s/^version = ".*"$/version = "9.9.9"/;}' "$SCRATCH/$LOCK"
run_check
expect "uv.lock differs from both pins" 1 "$PREFIX" "$LINT" "$PROJ" "$LOCK" "same PR as the lock" "by digest"
done_tree

# A half move: only lint.yml follows the lock version.
new_tree
sed -i "s|zizmor:$LOCKVER@|zizmor:$OLDVER@|" "$SCRATCH/$PROJ"
run_check
expect "only lint.yml carries the lock version" 1 "$PREFIX" "$PROJ"
done_tree

# Same tag, different digests.
new_tree
sed -i "s|\(zizmor:$LOCKVER@sha256:\)[0-9a-f]\{64\}|\1$DIG_A|" "$SCRATCH/$LINT"
run_check
expect "lint.yml and project.yml digests differ" 1 "$PREFIX" "differ" "$LINT" "$PROJ"
done_tree

# A tag and no digest.
new_tree
sed -i "s|\(zizmor:$LOCKVER\)@sha256:[0-9a-f]\{64\}|\1|" "$SCRATCH/$LINT"
run_check
expect "a pin with a tag and no digest" 1 "$PREFIX" "$LINT"
done_tree

# A digest and no tag.
new_tree
sed -i "s|zizmor:$LOCKVER@sha256|zizmor@sha256|" "$SCRATCH/$PROJ"
run_check
expect "a pin with a digest and no tag" 1 "$PREFIX" "$PROJ"
done_tree

# A digest that is not 64 lowercase hex characters.
new_tree
sed -i "s|\(zizmor:$LOCKVER@sha256:\)[0-9a-f]\{64\}|\1$DIG_UP|" "$SCRATCH/$LINT"
sed -i "s|\(zizmor:$LOCKVER@sha256:\)[0-9a-f]\{64\}|\1$DIG_UP|" "$SCRATCH/$PROJ"
run_check
expect "a digest with uppercase hex" 1 "$PREFIX" "$LINT" "$PROJ"
done_tree

new_tree
sed -i "s|\(zizmor:$LOCKVER@sha256:[0-9a-f]\{63\}\)[0-9a-f]|\1|" "$SCRATCH/$LINT"
run_check
expect "a 63 character digest" 1 "$PREFIX" "$LINT"
done_tree

# A second reference in lint.yml.
new_tree
printf '      # again: ghcr.io/zizmorcore/zizmor:%s@sha256:%s\n' "$LOCKVER" "$DIG_A" >> "$SCRATCH/$LINT"
run_check
expect "a second zizmor reference in lint.yml" 1 "$PREFIX" "$LINT" "exactly one"
done_tree

# No reference in project.yml, the file kept.
new_tree
sed -i "s|$REF|gone|" "$SCRATCH/$PROJ"
run_check
expect "no zizmor reference in project.yml" 1 "$PREFIX" "$PROJ"
done_tree

# No zizmor entry in uv.lock.
new_tree
sed -i 's|^name = "zizmor"$|name = "zizmo"|' "$SCRATCH/$LOCK"
run_check
expect "no zizmor entry in uv.lock" 1 "$PREFIX" "$LOCK"
done_tree

# A missing file.
for f in "$LOCK" "$PROJ" "$LINT"; do
  new_tree
  rm "$SCRATCH/$f"
  run_check
  expect "$f missing" 1 "$PREFIX" "$f"
  done_tree
done

# A root that is not a directory.
run_check /nonexistent-zizmor-pin-root
expect "a root that is not a directory" 1 "$PREFIX" "$LOCK"

# Two arguments.
new_tree
run_check "$SCRATCH" "$SCRATCH"
expect "two arguments is a usage error" 2 "usage"
done_tree

summary
