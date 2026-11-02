#!/usr/bin/env bash
# Fetch the consumer's devcontainer files at ONE exact commit, through the API only (never a
# git checkout; spec section 1 step 5).
#
#   fetch-consumer.sh [--mode-only] <owner/repo> <sha> <dest-dir>
#
# Needs GH_TOKEN. Runs from the reusable workflows' checkout at the caller's pin, after the
# devc-verify build, so no consumer content exists on disk until here.
#
# The head (no option) writes <dest>/.devcontainer/Dockerfile and
# <dest>/.devcontainer/devcontainer.json. If the commit holds ANY other devcontainer.json, an
# empty <dest>/_other/devcontainer.json marks that for `devc-verify`, which rejects it; no
# attacker-chosen path ever reaches this filesystem. A truncated tree, a missing file or a
# non-regular file is an error, never "nothing found".
#
# It also writes every other file under .devcontainer/ (the files a dev-App Dockerfile's extras
# may COPY, #418): regular files only, at most 64, each at most 1 MiB, with every path segment
# matching [A-Za-z0-9._-]+ and none of them `.` or `..`. Anything else there (a symlink, a
# submodule, another name, a 65th file, or a case-variant .devcontainer/ directory) is not
# written; an empty <dest>/_irregular/.devcontainer marks it, which dev-App mode rejects and
# plain mode ignores.
#
# --mode-only is the lenient read of a PR base or a default-branch tip, which devc-verify reads
# as raw bytes for the mode markers and the base's FROM MAJOR.MINOR: it writes whichever of the
# two canonical files the commit has as a regular file, and nothing else, then the sentinel
# <dest>/_listed. A file it does not write is absent from the commit, because the tree listing
# succeeded and was not truncated; any API error is an error, and leaves no sentinel. A
# canonical path that is there but not a regular file (a symlink, a submodule) counts as absent
# on purpose: failing closed here would wedge the PR that repairs it, and a dev-App repo is
# still marked by its default branch's tip, whose files passed head verification to get there.
set -euo pipefail

mode_only=false
if [ "${1:-}" = --mode-only ]; then mode_only=true; shift; fi
usage="usage: fetch-consumer.sh [--mode-only] <owner/repo> <sha> <dest-dir>"
repo="${1:?$usage}"
sha="${2:?$usage}"
dest="${3:?$usage}"
[ "$#" -eq 3 ] || { echo "$usage" >&2; exit 2; }

[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "::error::bad repo" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::bad sha" >&2; exit 2; }

MAX_EXTRAS=64
MAX_SIZE=1048576
CANON='[".devcontainer/Dockerfile", ".devcontainer/devcontainer.json"]'
REGULAR='.type == "blob" and (.mode == "100644" or .mode == "100755")'

tree="$(gh api "repos/${repo}/git/trees/${sha}?recursive=1")"
if [ "$(jq -r '.truncated' <<<"$tree")" != "false" ]; then
  echo "::error::the commit's file tree is truncated; refusing to guess" >&2
  exit 1
fi
jq -e '.tree | type == "array"' <<<"$tree" > /dev/null \
  || { echo "::error::unexpected tree response shape" >&2; exit 1; }

raw() { # path -> dest/path
  mkdir -p "$(dirname "${dest}/$1")"
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/${repo}/contents/$1?ref=${sha}" > "${dest}/$1"
}

if [ "$mode_only" = true ]; then
  mkdir -p "$dest"
  # A command substitution, not a process substitution, so `set -e` sees jq fail.
  present="$(jq -r --argjson canon "$CANON" ".tree[] | select(.path as \$p | \$canon | index(\$p)) | select($REGULAR) | .path" <<<"$tree")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    raw "$p"
  done <<<"$present"
  : > "${dest}/_listed"
  exit 0
fi

for p in .devcontainer/Dockerfile .devcontainer/devcontainer.json; do
  if ! jq -e --arg p "$p" "any(.tree[]; .path == \$p and $REGULAR)" <<<"$tree" > /dev/null; then
    echo "::error::${p} is missing or not a regular file at ${sha}" >&2
    exit 1
  fi
done

# A path that differs from a canonical one only in case would collide with it on a
# case-insensitive checkout (Windows, macOS), where the last one written wins. The two
# fetches above are exact-case, so refuse the commit instead of verifying one file while
# a developer's machine builds another.
if jq -e 'any(.tree[]; (.path | ascii_downcase) as $l
                | ($l == ".devcontainer/dockerfile" or $l == ".devcontainer/devcontainer.json")
                  and .path != ".devcontainer/Dockerfile"
                  and .path != ".devcontainer/devcontainer.json")' <<<"$tree" > /dev/null; then
  echo "::error::a case-variant of a devcontainer file exists at ${sha}" >&2
  exit 1
fi

mkdir -p "${dest}/.devcontainer"
for p in .devcontainer/Dockerfile .devcontainer/devcontainer.json; do
  raw "$p"
done

if jq -e 'any(.tree[];
      .type != "tree" and (.path | test("(^|/)[.]?devcontainer[.]json$"; "i"))
      and .path != ".devcontainer/devcontainer.json")' <<<"$tree" > /dev/null; then
  mkdir -p "${dest}/_other"
  : > "${dest}/_other/devcontainer.json"
fi

# The extras. `fetch` lists what may be written; `irregular` is whether anything under a
# .devcontainer/ directory (in any letter case) was left out.
# shellcheck disable=SC2016  # jq variables, not shell ones
extras="$(jq -c --argjson canon "$CANON" --argjson max "$MAX_EXTRAS" --argjson size "$MAX_SIZE" '
  [.tree[] | select(.type != "tree") | select(.path | ascii_downcase | startswith(".devcontainer/"))
           | select(.path as $p | $canon | index($p) | not)] as $all
  | [$all[] | select(.path | startswith(".devcontainer/"))
            | select(.type == "blob" and (.mode == "100644" or .mode == "100755"))
            | select((.size | type) == "number" and .size <= $size)
            | select(.path | ltrimstr(".devcontainer/") | split("/")
                     | all(test("^[A-Za-z0-9._-]+$") and . != "." and . != ".."))
            | .path] as $ok
  | {fetch: $ok[:$max], irregular: (($ok | length) != ($all | length) or ($ok | length) > $max)}' <<<"$tree")"
fetch="$(jq -r '.fetch[]' <<<"$extras")"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  raw "$p"
done <<<"$fetch"
if [ "$(jq -r '.irregular' <<<"$extras")" = true ]; then
  mkdir -p "${dest}/_irregular"
  : > "${dest}/_irregular/.devcontainer"
fi
