#!/usr/bin/env bash
# Fetch the consumer's devcontainer files at ONE exact commit, through the API only (never a
# git checkout; spec section 1 step 5). Usage: fetch-consumer.sh <owner/repo> <sha> <dest-dir>
# Needs GH_TOKEN. Runs from the reusable workflows' checkout at the caller's pin, after the
# devc-verify build, so no consumer content exists on disk until here.
#
# Writes <dest>/.devcontainer/Dockerfile and <dest>/.devcontainer/devcontainer.json. If the
# commit holds ANY other devcontainer.json, an empty <dest>/_other/devcontainer.json marks
# that for `devc-verify files`, which rejects it; no attacker-chosen path ever reaches this
# filesystem. A truncated tree, a missing file or a non-regular file is an error, never
# "nothing found".
set -euo pipefail

repo="${1:?usage: fetch-consumer.sh <owner/repo> <sha> <dest-dir>}"
sha="${2:?usage: fetch-consumer.sh <owner/repo> <sha> <dest-dir>}"
dest="${3:?usage: fetch-consumer.sh <owner/repo> <sha> <dest-dir>}"

[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "::error::bad repo" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::bad sha" >&2; exit 2; }

tree="$(gh api "repos/${repo}/git/trees/${sha}?recursive=1")"
if [ "$(jq -r '.truncated' <<<"$tree")" != "false" ]; then
  echo "::error::the commit's file tree is truncated; refusing to guess" >&2
  exit 1
fi

for p in .devcontainer/Dockerfile .devcontainer/devcontainer.json; do
  if ! jq -e --arg p "$p" \
      'any(.tree[]; .path == $p and .type == "blob" and (.mode == "100644" or .mode == "100755"))' \
      <<<"$tree" >/dev/null; then
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
                  and .path != ".devcontainer/devcontainer.json")' <<<"$tree" >/dev/null; then
  echo "::error::a case-variant of a devcontainer file exists at ${sha}" >&2
  exit 1
fi

mkdir -p "${dest}/.devcontainer"
for p in .devcontainer/Dockerfile .devcontainer/devcontainer.json; do
  gh api -H 'Accept: application/vnd.github.raw+json' \
    "repos/${repo}/contents/${p}?ref=${sha}" > "${dest}/${p}"
done

if jq -e 'any(.tree[];
      .type != "tree" and (.path | test("(^|/)[.]?devcontainer[.]json$"; "i"))
      and .path != ".devcontainer/devcontainer.json")' <<<"$tree" >/dev/null; then
  mkdir -p "${dest}/_other"
  : > "${dest}/_other/devcontainer.json"
fi
