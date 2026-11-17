#!/usr/bin/env bash
# The release plan for .github/workflows/release.yml (#486): which tag a dispatch would make, every
# reason to refuse it, whether a consumer would notice the release, and the Release notes. It lives
# in a script so the tests can run it offline against a throwaway repository.
#
#   release-plan.sh mode    <dry_run>                      true -> dry, false -> real
#   release-plan.sh plan    <bump> <sha> <mode>            the tag, the refusals, the outputs
#   release-plan.sh notes   <prev> <tag> <sha> <out-file>  writes the Release notes to <out-file>
#   release-plan.sh summary <prev> <tag> <sha> <mode> <notes-file>   the step-summary text on stdout
#
# Run from a checkout with full history and tags. Exit 0: done. 1: a refusal, each reason one
# `::error::` line on stderr. 2: a usage error (an unknown subcommand, a missing, extra or malformed
# argument). Every value is validated with `[[ =~ ]]` or `case`, never a line-oriented grep, so a
# newline in a value cannot satisfy a pattern. A `vX.Y` tag is `^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`;
# any other `v*` tag is ignored when choosing the previous tag.
#
# `plan` appends prev=, tag=, consumer_changed= and template_changed= to the file GITHUB_OUTPUT names
# when that variable is set, and prints the same four lines on stdout.
set -euo pipefail
export LC_ALL=C

TAG_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
SHA_RE='^[0-9a-f]{40}$'

# What a consumer's pin reaches: the verifier, the template, the gate skeleton, the three reusable
# workflows, the tools/ scripts those workflows check out and run at the caller's pin, and the org
# secret-scan rules. images/base/Dockerfile is read separately (two ARG values only).
CONSUMER_PATHS=(
  tools/devc-verify/
  template/
  tools/gate-template.yml.in
  .github/workflows/verify-devcontainer-image.yml
  .github/workflows/devcontainer-bump-decision.yml
  .github/workflows/secret-scan.yml
  tools/decide-bump.sh
  tools/fetch-consumer.sh
  tools/secret-scan.sh
  tools/secret-scan-lint.sh
  images/base/files/secret-scan/org.toml
)
# The four files tools/check-self-pins.sh checks: the pin-bump PR edits their self-pins every release.
SELF_PIN_FILES=(
  tools/gate-template.yml.in
  template/.github/workflows/architect-review-gate.yml
  template/.github/workflows/devcontainer-image.yml
  template/.github/workflows/secret-scan.yml
)
SNAPSHOT=tools/devc-verify/templates/previous.devcontainer.json
TEMPLATE_JSON=template/.devcontainer/devcontainer.json
DOCKERFILE=images/base/Dockerfile
SELF_PIN_RE='(603-Identity/devcontainers/\.github/workflows/[A-Za-z0-9._-]+\.ya?ml)@[0-9a-f]{40} # v[0-9]+\.[0-9]+$'

usage_error() { echo "release-plan.sh: $*" >&2; exit 2; }
refuse() { echo "::error::$*" >&2; exit 1; }

git_() { git -c core.quotepath=off "$@"; }

need_args() { # subcommand expected-count actual-count
  [ "$3" -eq "$2" ] || usage_error "$1 takes exactly $2 argument(s), got $3."
}
valid_bump() { [[ "$1" == minor || "$1" == major ]]; }
valid_mode() { [[ "$1" == dry || "$1" == real ]]; }
valid_sha() { [[ "$1" =~ $SHA_RE ]]; }
valid_tag() { [[ "$1" =~ $TAG_RE ]]; }

# Reads tag names on stdin; prints the newest `vX.Y` one, ordered numerically by X then Y.
newest_tag() {
  local t
  while IFS= read -r t; do
    [[ "$t" =~ $TAG_RE ]] || continue
    printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$t"
  done | sort -k1,1n -k2,2n | tail -n 1 | cut -d' ' -f3
}

in_repo() {
  git_ rev-parse --git-dir > /dev/null 2>&1 || refuse "not inside a git checkout."
}
is_commit() { git_ rev-parse --verify --quiet "$1^{commit}" > /dev/null 2>&1; }
tag_commit() { git_ rev-parse --verify --quiet "refs/tags/$1^{commit}" 2> /dev/null; }

# Does <path-or-dir> differ between two commits? Prints true or false.
differs() { # base head pathspec...
  local base="$1" head="$2" rc=0
  shift 2
  git_ diff --quiet --no-ext-diff --no-textconv --no-renames "$base" "$head" -- "$@" || rc=$?
  case "$rc" in
    0) echo false ;;
    1) echo true ;;
    *) refuse "could not compare $base and $head." ;;
  esac
}

# The ARG lines of images/base/Dockerfile for the scanner pin, at one commit ("" when absent).
scanner_args() { # commit
  git_ cat-file blob "$1:$DOCKERFILE" 2> /dev/null | sed -n -E '/^ARG BETTERLEAKS_(VERSION|SHA256)=/p' || true
}

# A self-pin file's change counts as the routine pin bump only when every changed line is a pin on
# both its removed and its added side and nothing else on the line moved. Returns 0 for "only pins".
only_pin_bumps() { # base head file
  local base="$1" head="$2" f="$3" line in_hunk=0 raw meta m1 m2 st
  local -a rem=() add=()
  # The file must be a regular file on both sides, modified in place (no mode change, no add/delete).
  raw="$(git_ diff --raw --no-ext-diff --no-textconv --no-renames "$base" "$head" -- "$f")"
  meta="${raw%%$'\t'*}"
  IFS=' ' read -r m1 m2 _ _ st <<< "$meta"
  [ "$m1" = :100644 ] && [ "$m2" = 100644 ] && [ "$st" = M ] || return 1
  # The line with its pin's SHA and tag removed; fails when the line holds no self-pin.
  pin_norm() {
    [[ "$1" =~ $SELF_PIN_RE ]] || return 1
    printf '%s' "${1%"${BASH_REMATCH[0]}"}${BASH_REMATCH[1]}@PIN"
  }
  # One -U0 hunk: as many lines removed as added, each pair a pin on both sides and equal everywhere else.
  flush_hunk() {
    local i a b
    [ "${#rem[@]}" -eq "${#add[@]}" ] || return 1
    for ((i = 0; i < ${#rem[@]}; i++)); do
      a="$(pin_norm "${rem[i]}")" || return 1
      b="$(pin_norm "${add[i]}")" || return 1
      [ "$a" = "$b" ] || return 1
    done
  }
  while IFS= read -r line; do
    if [[ "$line" == '@@ '* ]]; then
      if [ "$in_hunk" -eq 1 ]; then flush_hunk || return 1; fi
      in_hunk=1 rem=() add=()
      continue
    fi
    [ "$in_hunk" -eq 1 ] || continue
    case "$line" in
      -*) rem+=("${line:1}") ;;
      +*) add+=("${line:1}") ;;
      *) return 1 ;; # a "\ No newline" marker or anything unexpected: count it
    esac
  done < <(git_ diff -U0 --text --no-color --no-ext-diff --no-textconv --no-renames "$base" "$head" -- "$f")
  # A changed file with no hunk at all (a mode-only change, say) is not shown to be only pins.
  [ "$in_hunk" -eq 1 ] || return 1
  flush_hunk || return 1
  return 0
}

# The snapshot rotation is routine only when, at the head, it is a regular file byte-identical to the
# template at the previous tag. A deleted, symlinked or differently-written snapshot counts.
snapshot_is_rotation() { # base head
  local base="$1" head="$2" entry mode want have
  entry="$(git_ ls-tree "$head" -- "$SNAPSHOT")"
  [ -n "$entry" ] || return 1
  mode="${entry%% *}"
  [ "$mode" = 100644 ] || return 1
  have="$(git_ rev-parse --verify --quiet "$head:$SNAPSHOT")" || return 1
  want="$(git_ rev-parse --verify --quiet "$base:$TEMPLATE_JSON")" || return 1
  [ "$have" = "$want" ]
}

consumer_changed() { # base head -> prints true|false
  local base="$1" head="$2" f p skip
  while IFS= read -r -d '' f; do
    if [ "$f" = "$SNAPSHOT" ]; then
      snapshot_is_rotation "$base" "$head" && continue
      echo true
      return
    fi
    skip=0
    for p in "${SELF_PIN_FILES[@]}"; do
      if [ "$f" = "$p" ] && only_pin_bumps "$base" "$head" "$f"; then skip=1; fi
    done
    [ "$skip" -eq 1 ] && continue
    echo true
    return
  done < <(git_ diff --name-only -z --no-ext-diff --no-textconv --no-renames "$base" "$head" -- "${CONSUMER_PATHS[@]}")
  if [ "$(scanner_args "$base")" != "$(scanner_args "$head")" ]; then
    echo true
    return
  fi
  echo false
}

cmd_mode() {
  need_args mode 1 "$#"
  case "$1" in
    true) echo dry ;;
    false) echo real ;;
    *) usage_error "dry_run must be exactly true or false." ;;
  esac
}

cmd_plan() {
  need_args plan 3 "$#"
  local bump="$1" sha="$2" mode="$3" prev x y next t newest_all consumer template
  valid_bump "$bump" || usage_error "bump must be exactly minor or major."
  valid_sha "$sha" || usage_error "the SHA must be 40 lowercase hex characters."
  valid_mode "$mode" || usage_error "mode must be exactly dry or real."
  in_repo
  is_commit "$sha" || refuse "$sha is not a commit in this checkout."

  prev="$(git_ tag --merged "$sha" | newest_tag)"
  [ -n "$prev" ] || refuse "no vX.Y tag is reachable from $sha: nothing to count from."
  [[ "$prev" =~ $TAG_RE ]]
  x="${BASH_REMATCH[1]}" y="${BASH_REMATCH[2]}"
  [ "${#x}" -le 9 ] && [ "${#y}" -le 9 ] || refuse "$prev has a component too long to count from."
  if [ "$bump" = minor ]; then next="v$x.$((y + 1))"; else next="v$((x + 1)).0"; fi

  # The SHA is already released: any v* tag, lightweight or annotated (peeled), whatever its shape.
  while IFS= read -r t; do
    if [ "$(tag_commit "$t")" = "$sha" ]; then
      refuse "$sha is already the target of the tag $t; a commit is released once."
    fi
  done < <(git_ tag --list 'v*')

  if git_ rev-parse --verify --quiet "refs/tags/$next" > /dev/null 2>&1; then
    refuse "the tag $next already exists."
  fi
  newest_all="$(git_ tag --list | newest_tag)"
  if [ -n "$newest_all" ]; then
    # next is not an existing tag, so next > newest_all holds exactly when it sorts last.
    t="$(printf '%s\n%s\n' "$newest_all" "$next" | newest_tag)"
    [ "$t" = "$next" ] || refuse "$next is not newer than $newest_all, the newest vX.Y tag in the repository (it is not reachable from $sha)."
  fi

  consumer="$(consumer_changed "refs/tags/$prev" "$sha")"
  if [ "$consumer" = false ]; then
    if [ "$mode" = real ]; then
      refuse "nothing a consumer pins has changed since $prev (only routine pin-bump edits, if anything): there is nothing to release."
    fi
    echo "::warning::nothing a consumer pins has changed since $prev; a real run would refuse."
  fi
  template="$(differs "refs/tags/$prev" "$sha" template/.devcontainer/)"

  local out="prev=$prev
tag=$next
consumer_changed=$consumer
template_changed=$template"
  printf '%s\n' "$out"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s\n' "$out" >> "$GITHUB_OUTPUT"; fi
}

cmd_notes() {
  need_args notes 4 "$#"
  local prev="$1" tag="$2" sha="$3" out="$4" entry mode tmp template
  valid_tag "$prev" || usage_error "the previous tag is not a vX.Y tag."
  valid_tag "$tag" || usage_error "the new tag is not a vX.Y tag."
  valid_sha "$sha" || usage_error "the SHA must be 40 lowercase hex characters."
  [ -n "$out" ] || usage_error "the output path is empty."
  in_repo
  is_commit "$sha" || refuse "$sha is not a commit in this checkout."
  tag_commit "$prev" > /dev/null || refuse "the previous tag $prev does not exist."
  git_ merge-base --is-ancestor "refs/tags/$prev" "$sha" || refuse "the previous tag $prev is not an ancestor of $sha."

  NOTES_TMP="$(mktemp)"
  tmp="$NOTES_TMP"
  trap 'rm -f "$NOTES_TMP"' EXIT
  entry="$(git_ ls-tree "$sha" -- "docs/releases/$tag.md")"
  if [ -n "$entry" ]; then
    mode="${entry%% *}"
    [ "$mode" = 100644 ] || refuse "docs/releases/$tag.md is not a regular file at $sha (mode $mode)."
    git_ cat-file blob "$sha:docs/releases/$tag.md" > "$tmp" || refuse "could not read docs/releases/$tag.md at $sha."
  else
    template="$(differs "refs/tags/$prev" "$sha" template/.devcontainer/)"
    {
      printf '## Changes since %s\n\n' "$prev"
      git_ log --first-parent --format='- %s' "refs/tags/$prev..$sha"
      printf '\n'
      if [ "$template" = true ]; then
        printf '%s\n\n' "The dev-App template changed in this release. A dev-App consumer accepts this release's template and the previous release's, no older: a consumer two releases behind fails \`verify / verify\` until it catches up."
      fi
      printf '%s\n' "Next step: open the pin-bump PR (README, \"Cutting a release\"): bump every self-pin to $tag and rotate the template snapshot."
    } > "$tmp"
  fi
  cat "$tmp" > "$out" || refuse "could not write $out."
}

cmd_summary() {
  need_args summary 5 "$#"
  local prev="$1" tag="$2" sha="$3" mode="$4" notes="$5" longest fence
  valid_tag "$prev" || usage_error "the previous tag is not a vX.Y tag."
  valid_tag "$tag" || usage_error "the new tag is not a vX.Y tag."
  valid_sha "$sha" || usage_error "the SHA must be 40 lowercase hex characters."
  valid_mode "$mode" || usage_error "mode must be exactly dry or real."
  [ -n "$notes" ] || usage_error "the notes path is empty."
  [ -f "$notes" ] || refuse "the notes file is missing."
  cat -- "$notes" > /dev/null 2>&1 || refuse "the notes file is unreadable."
  longest="$(tr -c '`' '\n' < "$notes" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
  # One backtick longer than the longest run in the notes, and at least three.
  if [ "$longest" -ge 3 ]; then longest=$((longest + 1)); else longest=3; fi
  fence="$(printf '%*s' "$longest" '' | tr ' ' '`')"
  printf '## Release plan\n\n'
  printf -- '- previous tag: %s\n- new tag: %s\n- commit: %s\n- mode: %s\n\n' "$prev" "$tag" "$sha" "$mode"
  printf '### Release notes, exactly as they will be published\n\n'
  printf '%s\n' "$fence"
  cat -- "$notes"
  # The closing fence must start a line.
  if [ -s "$notes" ] && [ "$(tail -c 1 -- "$notes" | od -An -c | tr -d ' ')" != '\n' ]; then printf '\n'; fi
  printf '%s\n' "$fence"
}

[ "$#" -ge 1 ] || usage_error "usage: release-plan.sh mode|plan|notes|summary ARGS..."
sub="$1"
shift
case "$sub" in
  mode) cmd_mode "$@" ;;
  plan) cmd_plan "$@" ;;
  notes) cmd_notes "$@" ;;
  summary) cmd_summary "$@" ;;
  *) usage_error "unknown subcommand." ;;
esac
