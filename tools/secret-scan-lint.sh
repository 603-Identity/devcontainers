#!/usr/bin/env bash
# Positive-schema lint for a repo's own betterleaks.toml (devcontainers#190, section 2).
#
#   secret-scan-lint.sh FILE
#
# Exit 0: clean. 1: at least one finding (each printed to stderr). 2: usage, or a missing tool.
# Needs bash, jq and yq (mikefarah, v4). Reads FILE only.
#
# The repo config is read from the PR's BASE commit, so it is reviewed code, but it must still
# only ADD to the org rule set, never weaken it. This is an allowlist of what a repo config may
# say; everything else fails, including keys this lint has never heard of:
#   * top level: only `title`, `extend` and `rules`;
#   * `[extend]`: exactly `path = "/usr/local/share/devc/secret-scan/org.toml"` and nothing
#     else (so no `useDefault`), and it is required, or the org rules would not apply;
#   * `[[rules]]`: each id starts with `repo-` (the org and default sets never use that prefix,
#     so no repo rule can override one), and each uses only id, description, regex, keywords,
#     path, confidence, secretGroup and tags. No `filter`, `skipReport`, `validate`, `analyze`,
#     `revoke`, allowlists or components.
# `prefilter`, `filter`, `disabledRules` and `useDefault` live only in the reviewed org config.
set -euo pipefail
export LC_ALL=C

# (the extend path is spelled inside the jq program: Git Bash rewrites a path-shaped --arg)
[ "$#" -eq 1 ] || { echo "usage: $0 FILE" >&2; exit 2; }
file="$1"
[ -f "$file" ] || { echo "$0: no such file: $file" >&2; exit 2; }
command -v jq > /dev/null || { echo "$0: jq not found" >&2; exit 2; }
command -v yq > /dev/null || { echo "$0: yq not found" >&2; exit 2; }

if ! json="$(yq -p toml -o json '.' "$file" 2> /dev/null)"; then
  echo "$file: not valid TOML" >&2
  exit 1
fi

findings="$(printf '%s' "$json" | jq -r '
  "/usr/local/share/devc/secret-scan/org.toml" as $ep |
  def allowed_top: ["title", "extend", "rules"];
  def allowed_rule: ["id", "description", "regex", "keywords", "path", "confidence", "secretGroup", "tags"];
  ( if type != "object" then ["config is not a table"] else
      ( keys - allowed_top | map("top-level key not allowed: " + .) )
    + ( if (.extend | type) != "object" then
          ["[extend] is required: path = \"" + $ep + "\""]
        else
          ( (.extend | keys) - ["path"] | map("[extend] key not allowed: " + .) )
        + ( if .extend.path != $ep then ["[extend] path must be exactly \"" + $ep + "\""] else [] end )
        end )
    + ( if has("rules") and ((.rules | type) != "array") then ["rules must be an array of tables"] else
        ( (.rules // []) | to_entries | map(
            .key as $i | .value as $r
            | if ($r | type) != "object" then ["rule #\($i) is not a table"] else
                ( if ($r.id | type) != "string" or (($r.id // "") | test("^repo-[a-z0-9][a-z0-9-]*$") | not)
                  then ["rule #\($i): id must match ^repo-[a-z0-9][a-z0-9-]*$"] else [] end )
              + ( ($r | keys) - allowed_rule | map("rule #\($i) (" + (($r.id // "?") | tostring) + "): key not allowed: " + .) )
              end
          ) | add // [] )
        end )
    end )
  | .[]')"

if [ -n "$findings" ]; then
  while IFS= read -r line; do
    printf '%s: %s
' "$file" "$line" >&2
  done <<< "$findings"
  exit 1
fi
