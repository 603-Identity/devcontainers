#!/usr/bin/env bash
# shellcheck disable=SC1091
# Tests for tools/check-self-pins.sh (#125): the committed self-pins agree, and each rule fires
# on the mutation it exists for. The release side runs against a local fixture upstream through
# CHECK_SELF_PINS_UPSTREAM, never the network.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
suite check-self-pins

CHECK="$TOOLS_DIR/check-self-pins.sh"
FILES=(
  tools/gate-template.yml.in
  .github/workflows/architect-review-gate.yml
  template/.github/workflows/architect-review-gate.yml
  template/.github/workflows/devcontainer-image.yml
  template/.github/workflows/secret-scan.yml
)
SYN_A='docker/dockerfile:9.1@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
SYN_B='docker/dockerfile:9.2@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

# run_check [upstream]: run the check in $TREE, exit code in RC, stderr in ERR.
run_check() {
  RC=0
  ERR="$(cd "$TREE" && CHECK_SELF_PINS_UPSTREAM="${1:-$UP}" bash "$CHECK" 2>&1 > /dev/null)" || RC=$?
}
expect() { # description expected-rc [stderr-substring]
  assert_rc "$1" "$2" "$RC"
  if [ -n "${3:-}" ]; then
    if [[ "$ERR" == *"$3"* ]]; then pass; else fail "$1 (message)" "wanted '$3' in: $ERR"; fi
  fi
}
refute_msg() { # description stderr-substring
  if [[ "$ERR" != *"$2"* ]]; then pass; else fail "$1" "did not want '$2' in: $ERR"; fi
}

# new_tree: a scratch copy of the files the check reads, from this checkout.
new_tree() {
  TREE="$(mktemp -d "$UPROOT/tree.XXXXXX")"
  local f
  for f in "${FILES[@]}" template/.devcontainer/Dockerfile; do
    mkdir -p "$TREE/$(dirname "$f")"
    cp "$ROOT_DIR/$f" "$TREE/$f"
  done
  # The fixture upstream's templates (below), not this checkout's: TMPL_B is v1.1's.
  printf '%s' "$TMPL_B" > "$TREE/template/.devcontainer/devcontainer.json"
  mkdir -p "$TREE/$(dirname "$SNAP")"
}
SNAP=tools/devc-verify/templates/previous.devcontainer.json
set_snapshot() { printf '%s' "$1" > "$TREE/$SNAP"; }
# pin_all SHA TAG: every self-pin in $TREE names SHA, labeled TAG.
pin_all() {
  local f
  for f in "${FILES[@]}"; do
    sed -i -E "/603-Identity\/devcontainers\/\.github\/workflows/s|@[0-9a-f]{40} # v[0-9.]+|@$1 # $2|" "$TREE/$f"
  done
}
set_syntax() { sed -i "1s|.*|# syntax=$1|" "$TREE/template/.devcontainer/Dockerfile"; }

# A fixture upstream. `main`: c1 (annotated tag v1.0; its verifier allows only A), c2
# (lightweight tag v1.1; current B, previous A), then a no-ff merge of `side` (s1: on main but
# not on its first-parent line). `fork` (f1) was never merged.
g() { git -c core.autocrlf=false -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false -c init.defaultBranch=main "$@"; }
go_file() { # current previous-literal-or-ident
  local p="$2"
  [ "$p" = CurrentSyntax ] || p="\"$p\""
  printf 'package dockerfile\n\nconst CurrentSyntax = "%s"\n\nconst PreviousSyntax = %s\n' "$1" "$p"
}
# Each release's template devcontainer.json; the second has no trailing newline, so a comparison
# that dropped one would call the two snapshots below equal.
TMPL_A=$'{ "release": "v1.0" }
'
TMPL_B='{ "release": "v1.1" }'
UPROOT="$(mktemp -d)"
trap 'rm -rf "$UPROOT"' EXIT
w="$UPROOT/work"
gof=tools/devc-verify/internal/dockerfile/dockerfile.go
g init -q "$w"
mkdir -p "$w/$(dirname "$gof")"
go_file "$SYN_A" CurrentSyntax > "$w/$gof"
mkdir -p "$w/template/.devcontainer"; printf '%s' "$TMPL_A" > "$w/template/.devcontainer/devcontainer.json"
g -C "$w" add -A; g -C "$w" commit -q -m c1; C1="$(g -C "$w" rev-parse HEAD)"; g -C "$w" tag -a v1.0 -m v1.0
g -C "$w" branch side; g -C "$w" branch fork
go_file "$SYN_B" "$SYN_A" > "$w/$gof"
printf '%s' "$TMPL_B" > "$w/template/.devcontainer/devcontainer.json"
g -C "$w" commit -q -am c2; C2="$(g -C "$w" rev-parse HEAD)"; g -C "$w" tag v1.1
g -C "$w" checkout -q side; g -C "$w" commit -q --allow-empty -m s1; S1="$(g -C "$w" rev-parse HEAD)"
g -C "$w" checkout -q fork; g -C "$w" commit -q --allow-empty -m f1; F1="$(g -C "$w" rev-parse HEAD)"
g -C "$w" checkout -q main; g -C "$w" merge -q --no-ff side -m join-side
g clone -q --bare "$w" "$UPROOT/up.git"
UP="$UPROOT/up.git"

# --- the committed tree --------------------------------------------------------------------
# Offline rules only: an unreachable upstream exits 3 when they pass.
new_tree
run_check "$UPROOT/does-not-exist.git"
expect "the committed self-pins agree (offline rules)" 3 "could not read the pinned release"

# --- the release side ----------------------------------------------------------------------
new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_B"
run_check; expect "newest release, current syntax" 0 "CHECK_SELF_PINS_UPSTREAM is set"
refute_msg "no staleness warning on the newest release" "is the newest release"

new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_A"
run_check; expect "newest release, its previous syntax" 0

new_tree; pin_all "$C1" v1.0; set_syntax "$SYN_A"
run_check; expect "an older release only warns" 0 "v1.1 is the newest release"

new_tree; pin_all "$C1" v1.0; set_syntax "$SYN_B"
run_check; expect "a syntax newer than the pinned verifier" 1 "is not accepted by the verifier at the pinned v1.0"

new_tree; pin_all "$C2" v1.0; set_syntax "$SYN_B"
run_check; expect "a tag that peels elsewhere" 1 "tag v1.0 points at $C1"

new_tree; pin_all "$C2" v9.9; set_syntax "$SYN_B"
run_check; expect "a tag the upstream lacks" 1 "has no tag v9.9"

new_tree; pin_all "$S1" v1.1; set_syntax "$SYN_B"
run_check; expect "a pin off main's first-parent line" 1 "not on 603-Identity/devcontainers main's first-parent line"

new_tree; pin_all "$F1" v1.1; set_syntax "$SYN_B"
run_check; expect "a fork-only pin" 1 "not on 603-Identity/devcontainers main's first-parent line"
# f1 branched from c1, whose verifier allows only A, so reading its syntax would add an "is not
# accepted" finding. It must not be read at all: in the filtered clone that read would fetch
# the fork's commit from origin by object ID.
refute_msg "a fork-only pin's syntax is never read" "is not accepted by the verifier"

# --- the template snapshot (#418 owner decision 5) -----------------------------------------
new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_B"
run_check; expect "no snapshot only warns" 0 "previous.devcontainer.json is missing"
refute_msg "main's template equals the pinned one" "differs from the pinned"

new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_B"; set_snapshot "$TMPL_B"
run_check; expect "the snapshot is the pinned release's template" 0
refute_msg "a snapshot present draws no missing warning" "is missing"

new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_B"; set_snapshot "$TMPL_A"
run_check; expect "a snapshot of another release" 1 "is not template/.devcontainer/devcontainer.json at the pinned v1.1"

new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_B"; set_snapshot "$TMPL_B"$'
'
run_check; expect "a snapshot one newline off" 1 "byte for byte"

new_tree; pin_all "$C1" v1.0; set_syntax "$SYN_A"; set_snapshot "$TMPL_A"
run_check; expect "main's template ahead of the pin only warns" 0 "differs from the pinned v1.0's"

new_tree; pin_all "$F1" v1.1; set_syntax "$SYN_B"; set_snapshot "$TMPL_B"
run_check; expect "a fork-only pin, with a snapshot" 1 "not on 603-Identity/devcontainers main's first-parent line"
refute_msg "a fork-only pin's template is never read" "byte for byte"

run_check "$UPROOT/does-not-exist.git"; expect "an unreachable upstream" 3 "never ok"
run_check "https://example.invalid/x.git"; expect "a network override" 2 "absolute local path"

# --- the offline rules ---------------------------------------------------------------------
new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_B"
sed -i -E "s|@[0-9a-f]{40} # v1\.1|@$C1 # v1.0|" "$TREE/template/.github/workflows/secret-scan.yml"
run_check; expect "one file pins another release" 1 "bump every self-pin together"

new_tree; pin_all "$C2" v1.1
sed -i -E "s|@[0-9a-f]{40} # v1\.1|@$C2|" "$TREE/template/.github/workflows/devcontainer-image.yml"
run_check; expect "a pin without its # vX.Y" 1 "has no '603-Identity/devcontainers/.github/workflows/<file>@<40-hex sha> # vX.Y' pin"

new_tree; pin_all "$C2" v1.1
sed -i -E "s|(@[0-9a-f]{40} # v1\.1)|\1 extra|" "$TREE/tools/gate-template.yml.in"
run_check; expect "trailing text after a pin" 1 "not '@<40-hex sha> # vX.Y' at the end of the line"

new_tree; rm "$TREE/template/.github/workflows/secret-scan.yml"
run_check; expect "a missing file" 1 "secret-scan.yml is missing"

new_tree; pin_all "$C2" v1.1; sed -i '1s|.*|FROM x|' "$TREE/template/.devcontainer/Dockerfile"
run_check; expect "a template Dockerfile without a syntax line" 1 "is not a '# syntax=' line"

run_check_args() { RC=0; ERR="$(cd "$TREE" && bash "$CHECK" extra 2>&1 > /dev/null)" || RC=$?; }
run_check_args; expect "an argument is a usage error" 2 "usage"

summary
