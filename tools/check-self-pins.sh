#!/usr/bin/env bash
# Checks this repo's own pins of its reusable workflows (#125): the `decide` pin in the gate
# skeleton and the rendered gates, and the verify and secret-scan pins in the template's callers.
# Dependabot never bumps these here (they point at this repo's own releases), so a release can
# leave the template shipping a stale or inconsistent verifier to new adopters, who copy
# template/ from `main`.
#
#   check-self-pins.sh            run from the repo root (CI's `gate scripts and rendered template`)
#
# Exit 0: clean. 1: at least one finding (each printed to stderr). 2: usage or a bad
# CHECK_SELF_PINS_UPSTREAM. 3: no finding from the offline rules, but the release could not be
# read (no git or no network): never read it as ok.
#
# It fails when:
#   * a file below lacks its pin, or the pins do not all name the same `@<40-hex sha> # vX.Y`;
#   * the pinned SHA is not on the first-parent line of 603-Identity/devcontainers `main`;
#   * the `# vX.Y` comment names a tag that does not exist or does not peel to the pinned SHA;
#   * template/.devcontainer/Dockerfile's `# syntax=` line is not one of the values the
#     verifier AT THE PINNED RELEASE accepts (its CurrentSyntax or PreviousSyntax). That is what
#     an adopter's `verify / verify` runs, so a template whose syntax line is newer than its
#     pinned verifier fails every adoption PR (#422 shipped exactly that, fixed by the v1.5 bump).
# It only WARNS when a newer `v*` tag exists than the one pinned: a commit cannot pin its own
# release, so right after a tag is cut every branch pins the previous one until the bump PR lands
# (README.md, "Cutting a release"). Failing there would turn every open PR red at once.
#
# The release is read from one scratch clone of `main` (`--bare --single-branch --filter=tree:0`,
# not shallow), with git hardened as tools/check-consumer-workflows.sh does it; a SHA is never
# fetched by name. CHECK_SELF_PINS_UPSTREAM replaces the clone URL for the tests and must be a
# local path.
set -euo pipefail
export LC_ALL=C

UPSTREAM_URL="https://github.com/603-Identity/devcontainers.git"
FILES=(
  tools/gate-template.yml.in
  .github/workflows/architect-review-gate.yml
  template/.github/workflows/architect-review-gate.yml
  template/.github/workflows/devcontainer-image.yml
  template/.github/workflows/secret-scan.yml
)
TEMPLATE_DOCKERFILE=template/.devcontainer/Dockerfile
SYNTAX_GO=tools/devc-verify/internal/dockerfile/dockerfile.go

[ "$#" -eq 0 ] || { echo "usage: check-self-pins.sh   (no arguments; run from the repo root)" >&2; exit 2; }

findings=0
finding() { findings=$((findings + 1)); echo "check-self-pins: $*" >&2; }
warn() { echo "::warning::check-self-pins: $*" >&2; }

# --- offline: every file pins the same release ------------------------------------------------
pin_re='603-Identity/devcontainers/\.github/workflows/[A-Za-z0-9._-]+\.ya?ml@([0-9a-f]{40}) # (v[0-9]+\.[0-9]+)$'
sha="" tag=""
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then finding "$f is missing."; continue; fi
  lines="$(grep -oE "$pin_re" "$f" || true)"
  if [ -z "$lines" ]; then
    finding "$f has no '603-Identity/devcontainers/.github/workflows/<file>@<40-hex sha> # vX.Y' pin."
    continue
  fi
  while IFS= read -r l; do
    [[ "$l" =~ $pin_re ]]
    s="${BASH_REMATCH[1]}" t="${BASH_REMATCH[2]}"
    if [ -z "$sha" ]; then
      sha="$s" tag="$t"
    elif [ "$s" != "$sha" ] || [ "$t" != "$tag" ]; then
      finding "$f pins $s # $t, but ${FILES[0]} pins $sha # $tag: bump every self-pin together."
    fi
  done <<< "$lines"
done
# The same-shaped pin can be followed by trailing text the regex above does not match; a
# workflow line naming this repo's workflows in any other form is a finding too.
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  if grep -nE '603-Identity/devcontainers/\.github/workflows/' "$f" | grep -vE "$pin_re" | grep -q .; then
    finding "$f has a reference to this repo's workflows that is not '@<40-hex sha> # vX.Y' at the end of the line."
  fi
done

syntax_line="$(head -n 1 "$TEMPLATE_DOCKERFILE" 2> /dev/null || true)"
if [[ "$syntax_line" != "# syntax="* ]]; then
  finding "$TEMPLATE_DOCKERFILE line 1 is not a '# syntax=' line."
fi

if [ "$findings" -gt 0 ] || [ -z "$sha" ]; then
  echo "check-self-pins: $findings finding(s)." >&2
  exit 1
fi

# --- the release itself ----------------------------------------------------------------------
upstream="$UPSTREAM_URL"
if [ -n "${CHECK_SELF_PINS_UPSTREAM:-}" ]; then
  upstream="$CHECK_SELF_PINS_UPSTREAM"
  case "$upstream" in
    /* | file:///*) ;;
    *) echo "check-self-pins: CHECK_SELF_PINS_UPSTREAM must be an absolute local path or a file:/// URL." >&2; exit 2 ;;
  esac
  warn "CHECK_SELF_PINS_UPSTREAM is set: the release is read from $upstream, not $UPSTREAM_URL."
fi

TIMEOUT_CMD=()
! command -v timeout > /dev/null || TIMEOUT_CMD=(timeout 120)
up_git() {
  ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
    -u GIT_DIR -u GIT_WORK_TREE -u GIT_ASKPASS -u SSH_ASKPASS \
    GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 git -c credential.helper= "$@"
}
cannot_check() {
  echo "check-self-pins: could not read the pinned release: ${1//$'\n'/; }" >&2
  echo "check-self-pins: no offline findings, but the release was not checked (exit 3, never ok)." >&2
  exit 3
}

command -v git > /dev/null || cannot_check "git is not installed."
scratch="$(mktemp -d)" || cannot_check "mktemp -d failed."
trap 'rm -rf "$scratch"' EXIT
up="$scratch/up.git"
err="$(up_git clone -q --bare --single-branch --branch main --filter=tree:0 --no-tags -- "$upstream" "$up" 2>&1)" \
  || cannot_check "$err"
err="$(up_git -C "$up" rev-list --first-parent main 2>&1 > "$scratch/first-parent")" || cannot_check "$err"
tags="$(up_git -C "$up" ls-remote --tags origin 2>&1)" || cannot_check "$tags"

if ! grep -Fxq "$sha" "$scratch/first-parent"; then
  finding "the pinned $sha is not on 603-Identity/devcontainers main's first-parent line."
fi
# An annotated tag lists its commit on the `^{}` line, a lightweight one on its own.
peel() {
  printf '%s\n' "$tags" | awk -v t="refs/tags/$1" \
    '$2 == (t "^{}") { print $1; f = 1 } $2 == t { p = $1 } END { if (!f && p != "") print p }'
}
peeled="$(peel "$tag")"
if [ -z "$peeled" ]; then
  finding "the pins are labeled $tag, but 603-Identity/devcontainers has no tag $tag."
elif [ "$peeled" != "$sha" ]; then
  finding "tag $tag points at $peeled, not the pinned $sha."
fi

# The verifier at the pinned commit: the two Go string constants, where PreviousSyntax may be
# `= CurrentSyntax`. The blob is fetched lazily from the filtered clone.
if go_src="$(up_git -C "$up" show "$sha:$SYNTAX_GO" 2>&1)"; then
  current="$(printf '%s\n' "$go_src" | sed -n 's/^const CurrentSyntax = "\(.*\)"$/\1/p')"
  previous="$(printf '%s\n' "$go_src" | sed -n 's/^const PreviousSyntax = "\(.*\)"$/\1/p')"
  printf '%s\n' "$go_src" | grep -qx 'const PreviousSyntax = CurrentSyntax' && previous="$current"
  if [ -z "$current" ] || [ -z "$previous" ]; then
    finding "could not read CurrentSyntax and PreviousSyntax from $SYNTAX_GO at $sha; update this script if their form changed."
  elif [ "$syntax_line" != "# syntax=$current" ] && [ "$syntax_line" != "# syntax=$previous" ]; then
    finding "$TEMPLATE_DOCKERFILE line 1 ('$syntax_line') is not accepted by the verifier at the pinned $tag ($sha), which allows only '$current'$([ "$previous" = "$current" ] || echo " and '$previous'"). Cut a release with the new syntax first, then bump the pins and the template together."
  fi
else
  # The SHA passed the first-parent check above, so a failure here is the network, not the pin.
  grep -Fxq "$sha" "$scratch/first-parent" && cannot_check "$go_src"
fi

# Staleness only warns (see the header).
newest="$(printf '%s\n' "$tags" | awk '{ print $2 }' | sed -n 's|^refs/tags/\(v[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' | sort -V | tail -n 1)"
if [ -n "$newest" ] && [ "$newest" != "$tag" ] && [ "$(printf '%s\n%s\n' "$tag" "$newest" | sort -V | tail -n 1)" = "$newest" ]; then
  warn "the self-pins name $tag, but $newest is the newest release: bump all of them to $newest (README.md, \"Cutting a release\")."
fi

if [ "$findings" -gt 0 ]; then
  echo "check-self-pins: $findings finding(s)." >&2
  exit 1
fi
echo "check-self-pins: ok ($tag, $sha)."
