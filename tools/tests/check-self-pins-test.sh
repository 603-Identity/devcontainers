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
  # This repo's own caller, as a copy of the scratch template caller (never the checkout's
  # .github/workflows/, so the suite passes whether or not the checkout has one).
  mkdir -p "$TREE/.github/workflows"
  cp "$TREE/template/.github/workflows/devcontainer-image.yml" "$TREE/$CALLER_F"
  # The fixture upstream's templates (below), not this checkout's: TMPL_B is v1.1's.
  printf '%s' "$TMPL_B" > "$TREE/template/.devcontainer/devcontainer.json"
  mkdir -p "$TREE/$(dirname "$SNAP")"
}
CALLER_F=.github/workflows/devcontainer-image.yml
SNAP=tools/devc-verify/templates/previous.devcontainer.json
set_snapshot() { printf '%s' "$1" > "$TREE/$SNAP"; }
# pin_all SHA TAG: every self-pin in $TREE names SHA, labeled TAG.
pin_all() {
  local f
  for f in "${FILES[@]}"; do
    sed -i -E "/603-Identity\/devcontainers\/\.github\/workflows/s|@[0-9a-f]{40} # v[0-9.]+|@$1 # $2|" "$TREE/$f"
  done
  pin_caller "$1" "$2"
}
# pin_caller SHA TAG: re-pin only this repo's own caller in $TREE.
pin_caller() {
  sed -i -E "/603-Identity\/devcontainers\/\.github\/workflows/s|@[0-9a-f]{40} # v[0-9.]+|@$1 # $2|" "$TREE/$CALLER_F"
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

# --- this repo's own caller ----------------------------------------------------------------
CK="caller '$CALLER_F'"
WL="is not the template caller's fixed lines"
BY="must be non-empty, end in a line feed and hold only line feeds and printable ASCII"
clean_tree() { new_tree; pin_all "$C2" v1.1; set_syntax "$SYN_B"; }
CF() { printf '%s' "$TREE/$CALLER_F"; }
# caller_sed EXPR: edit the scratch caller. caller_tail: replace its pin line with stdin.
caller_sed() { sed -i -E "$1" "$(CF)"; }
caller_tail() { grep -v '^    uses:' "$(CF)" > "$(CF).t"; cat >> "$(CF).t"; mv "$(CF).t" "$(CF)"; }
PINTXT='603-Identity/devcontainers/.github/workflows/verify-devcontainer-image.yml'

clean_tree
run_check; expect "the caller as pin_all leaves it (the header's uses: text draws no finding)" 0
refute_msg "a clean caller draws no caller message" "caller '"

clean_tree; printf '   \n' >> "$(CF)"
run_check; expect "a spaces-only line is dropped" 0; refute_msg "a spaces-only line draws no caller finding" "caller '"
clean_tree; printf '    # indented comment\n' >> "$(CF)"
run_check; expect "an indented comment line is dropped" 0; refute_msg "an indented comment draws no caller finding" "caller '"
clean_tree; printf '# a comment after the pin\n' >> "$(CF)"
run_check; expect "a comment line after the pin line is dropped" 0; refute_msg "a trailing comment draws no caller finding" "caller '"

# The pin is read from the pin line only: a comment carrying a pin to the fork-only commit.
clean_tree; caller_sed "/^    uses:/i # uses: $PINTXT@$F1 # v9.9"
run_check; expect "the pin is read from the pin line only" 0
refute_msg "a commented pin draws no off-main finding" "not on 603-Identity"
refute_msg "a commented pin draws no tag finding" "v9.9"

clean_tree; rm "$(CF)"
run_check; expect "a missing caller" 1 "$CK is missing"

# The byte rule, one case each; each refutes the whitelist finding.
byte_case() { # description (the caller is already mutated)
  run_check; expect "$1" 1 "$CK $BY"
  refute_msg "$1 (the whitelist runs only after the byte rule)" "$WL"
}
clean_tree; : > "$(CF)"; byte_case "an empty caller"
clean_tree; head -c -1 "$(CF)" > "$(CF).t"; mv "$(CF).t" "$(CF)"; byte_case "a caller with no final LF"
clean_tree; sed -i '1s/$/\r/' "$(CF)"; byte_case "a CR (one CRLF line)"
clean_tree; sed -i '1s/$/\t/' "$(CF)"; byte_case "a tab"
clean_tree; printf '# a\0b\n' >> "$(CF)"; byte_case "a NUL byte inside a comment line"
clean_tree; printf '# a\177b\n' >> "$(CF)"; byte_case "a DEL"
clean_tree; { printf '\357\273\277'; cat "$(CF)"; } > "$(CF).t"; mv "$(CF).t" "$(CF)"; byte_case "a byte-order mark"
clean_tree; printf '# caf\303\251\n' >> "$(CF)"; byte_case "a byte of 0x80 or above in a comment line"

# The whitelist, one case each.
wl_case() { run_check; expect "$1" 1 "$CK $WL"; }
clean_tree; caller_sed "/^    uses:/s|@[0-9a-f]{40} # v1\.1|@v1.1|"; wl_case "the pin line as a bare tag"
clean_tree; caller_sed "/^    uses:/s| # v1\.1\$||"; wl_case "the pin line with no version comment"
clean_tree; caller_sed "/^    uses:/s|# v1\.1\$|# v1|"; wl_case "a version comment of # v1"
clean_tree; caller_sed "/^    uses:/s|# v1\.1\$|# v1.10.1|"; wl_case "a version comment of # v1.10.1"
clean_tree; caller_sed "/^    uses:/s|# v1\.1\$|#v1.1|"; wl_case "a version comment of #v1.1"
clean_tree; caller_sed "/^    uses:/s|@([0-9a-f]{40})|@\U\1|"; wl_case "an upper-case SHA"
clean_tree; caller_sed "/^    uses:/s|@([0-9a-f]{39})[0-9a-f]|@\1|"; wl_case "a SHA of 39 hex"
clean_tree; caller_sed "/^    uses:/s|@([0-9a-f]{40})|@\1a|"; wl_case "a SHA of 41 hex"
clean_tree; caller_sed "s|^    uses:|  uses:|"; wl_case "the pin line indented two spaces"
clean_tree; caller_sed "s|^    uses:|      uses:|"; wl_case "the pin line indented six spaces"
clean_tree; caller_sed "/^    uses:/s|verify-devcontainer-image\.yml|build.yml|"; wl_case "another workflow of this repo"
clean_tree; caller_sed "s|^    uses: .*|    uses: ./.github/workflows/verify-devcontainer-image.yml|"; wl_case "a local workflow reference"
clean_tree; caller_sed "/^    uses:/s|uses: 603-Identity|uses: 603-identity|"; wl_case "the owner spelled 603-identity"
clean_tree; caller_sed "/^    uses:/s|\$| extra|"; wl_case "text after the version comment"
clean_tree; caller_sed "/^    uses:/d"; wl_case "the pin line removed"
clean_tree; caller_sed "/^    uses:/p"; wl_case "a second pin line"
clean_tree; caller_tail <<EOF
    "uses": ./local.yml
    with: |
      uses: $PINTXT@$C2 # v1.1
EOF
wl_case "a quoted uses key with a block-scalar decoy"
clean_tree; caller_tail <<EOF
    uses: "\x36""03-Identity/devcontainers/.github/workflows/verify-devcontainer-image.yml@$C2 # v1.1"
EOF
wl_case "an escaped value"
clean_tree; caller_tail <<EOF
    uses: $PINTXT@$C2 # v1.1
  decoy:
    uses: ./local.yml
EOF
wl_case "a decoy second job after verify"
clean_tree; cat > "$(CF)" <<EOF
name: Devcontainer image
on:
  pull_request:
permissions: {}
jobs:
  verify: {permissions: {contents: read}, uses: $PINTXT@$C2 # v1.1}
EOF
wl_case "the verify job as a flow mapping"
clean_tree; caller_sed "s|^  pull_request:|&\n    paths: [x]|"; wl_case "a paths filter added under pull_request"
clean_tree; caller_sed "s|contents: read|contents: write|"; wl_case "contents: write in place of contents: read"
clean_tree; caller_sed "s|^permissions: \{\}|permissions: write-all|"; wl_case "permissions: write-all in place of permissions: {}"

# The release rules run only after both offline rules passed.
clean_tree; pin_caller "$S1" v1.1; caller_sed "/^    uses:/s|\$| extra|"
run_check; expect "a whitelist-failing caller on the side branch commit" 1 "$CK $WL"
refute_msg "the release rules are skipped for a whitelist-failing caller" "is not on 603-Identity"

# The release rules.
clean_tree; pin_caller "$S1" v1.1
run_check; expect "the caller on the side-branch commit" 1 "$CK pins $S1, which is not on 603-Identity/devcontainers main's first-parent line"
clean_tree; pin_caller "$F1" v1.1
run_check; expect "the caller on the fork-only commit" 1 "$CK pins $F1, which is not on 603-Identity/devcontainers main's first-parent line"
clean_tree; pin_caller "$C2" v9.9
run_check; expect "the caller's tag does not exist" 1 "$CK is labeled v9.9, but 603-Identity/devcontainers has no tag v9.9"
clean_tree; pin_caller "$C2" v1.0
run_check; expect "the caller's tag peels to another commit" 1 "$CK: tag v1.0 points at $C1"

# The two caller warnings, each by the caller's path plus its own wording.
DIFFERS="$CK differs from the template pins"
BEHIND="$CK is behind"
clean_tree; pin_caller "$C1" v1.0
run_check; expect "the caller on the older release, FILES on the newest" 0 "$DIFFERS"
expect "the caller is behind the newest tag" 0 "$BEHIND"
clean_tree; pin_all "$C1" v1.0; set_syntax "$SYN_A"; pin_caller "$C2" v1.1
run_check; expect "FILES on the older release, the caller on the newest" 0 "$DIFFERS"
refute_msg "a caller on the newest tag is not behind" "$BEHIND"
expect "the self-pin staleness warning still fires for FILES" 0 "the self-pins name v1.0, but v1.1 is the newest release"
clean_tree
run_check; expect "caller and FILES on the newest release" 0
refute_msg "the clean case draws no caller-differs warning" "$DIFFERS"
refute_msg "the clean case draws no caller-behind warning" "$BEHIND"


run_check_args() { RC=0; ERR="$(cd "$TREE" && bash "$CHECK" extra 2>&1 > /dev/null)" || RC=$?; }
run_check_args; expect "an argument is a usage error" 2 "usage"

summary
