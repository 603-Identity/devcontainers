#!/usr/bin/env bash
# Lint for a consuming repo's workflows (spec section 4, "Consumer prerequisites"). Run it in
# the consuming repo, in the adoption PR and from the pilots:
#
#   check-consumer-workflows.sh [WORKFLOW_DIR]     default: .github/workflows
#
# Exit 0: clean. 1: at least one finding (each printed to stderr). 2: usage, or a missing tool.
# Needs bash, jq and yq (mikefarah, v4). Reads files only; it never touches the network.
#
# It runs when you tell it to: at adoption and from the pilots. Nothing re-runs it in the
# consuming repo's CI, so a later edit that breaks a rule is not caught until the next run.
#
# It fails when:
#   * a job other than the gate's `post` holds statuses, contents, pull-requests, checks or
#     actions: write (or has no `permissions:` block, so the repo's default token applies, or
#     `write-all`) in a workflow that a pull request, a PR comment, a PR review, a branch
#     creation or a push triggers (Dependabot's branch push runs its own bumped workflow
#     files), except a push limited to `tags:` alone or to literal branch names. A writer's PR workflow can mint the review status with such a token
#     (F9b), and upstream action code that Dependabot bumps must never share a runner with one;
#   * the gate is not exactly the file architect-review-gate.yml (only that file may define the
#     jobs resolve, decide and post, and only its `post` is exempt from the rule above);
#   * the gate's `resolve` or `post` job contains a `uses:`, a `container:` or `services:`
#     (same reason: they run on the bare runner with run: steps only), they run on anything but
#     a GitHub-hosted runner label, or `post` holds a scope other than statuses, contents,
#     pull-requests: write and issues: read;
#   * the gate's `.github/` rule is missing (a pin bump of `decide` edits only .github/, and
#     that rule is what makes it always need review);
#   * devcontainer-image.yml is not the caller the template ships: one job `verify`, no `name:`
#     and no `if:`, `pull_request` with no filter, `contents: read` only, a verify workflow
#     pinned `@<40-hex sha> # vX.Y`;
#   * secret-scan.yml is not the caller the template ships (#190): one job `secrets`, no `name:`
#     and no `if:`, `pull_request` with no filter, `contents: read` only, no `with:` or
#     `secrets:`, a secret-scan workflow pinned `@<40-hex sha> # vX.Y`. Its pin is independent
#     of the verify and decide pins.
# It also checks the gate's `decide` pin has that same shape, and warns when the two pins
# name different commits.
#
# When `.ai/project.yml` sits next to `.github/` (<dir>/../../.ai/project.yml) it also fails when
# (#214), for the gate's CONSUMER code_paths block:
#   * the block's `>>> CONSUMER: code_paths` region is missing from the post job;
#   * `code_paths` is not a list of strings;
#   * a line in the block, other than a blank or `#` comment line, is not a literal
#     `<glob>[|<glob>...]) touches=1 ;;` arm (the block is evaluated to read it, so nothing else
#     may reach that), or the arms together do not parse as `case` arms (`esac)` is one);
#   * a `code_paths` entry reads `touches=0` through the gate's `case`, one finding per entry. It
#     is a spot check: a dir `x/` is tried as a few paths under it, a glob as a few paths that
#     match it (`**/` also with zero directories). A block copied from another adopter fails here.
#     A leading `./` on an entry is dropped first (#245): the gate reads PR file paths from the
#     GitHub files API (`filename`, `previous_filename`), which never start with `./`, so a block
#     arm written `./tools/*` does not cover `tools/`.
# and warns when a block pattern matches no entry's sample, or when a glob entry (a bracket
# class, say) gets no sample that matches it, so that entry is not checked.
set -euo pipefail
export LC_ALL=C

dir="${1:-.github/workflows}"
VERIFY_WF='603-Identity/devcontainers/.github/workflows/verify-devcontainer-image.yml'
SCAN_WF='603-Identity/devcontainers/.github/workflows/secret-scan.yml'
DECIDE_WF='603-Identity/devcontainers/.github/workflows/devcontainer-bump-decision.yml'
# yq's line_comment returns "v1.0" or "# v1.0" depending on its version.
VERSION_COMMENT='^(#[[:space:]]*)?v[0-9]+\.[0-9]+$'

for tool in jq yq; do
  command -v "$tool" > /dev/null || { echo "check-consumer-workflows: $tool is required" >&2; exit 2; }
done
yq --version 2> /dev/null | grep -q 'mikefarah' \
  || { echo "check-consumer-workflows: yq must be mikefarah/yq (v4)" >&2; exit 2; }
[ -d "$dir" ] || { echo "usage: check-consumer-workflows.sh [WORKFLOW_DIR] ($dir is not a directory)" >&2; exit 2; }

findings=0
finding() { findings=$((findings + 1)); echo "check-consumer-workflows: $*" >&2; }
warn() { echo "check-consumer-workflows: warning: $*" >&2; }
j() { jq -r "$@" | tr -d '\r'; }   # jq.exe writes CRLF on Windows

GATE_NAME=architect-review-gate.yml
# A workflow file is a mapping whose jobs: is a mapping of mappings.
SHAPE_JQ='type == "object" and ((.jobs // {}) | type == "object" and all(.[]; type == "object"))'
PR_EVENTS='["pull_request","pull_request_target","pull_request_review","pull_request_review_comment","issue_comment"]'

# The events whose runs can execute a Dependabot branch's own workflow files, one per line:
# the PR events above; `create` (Dependabot creating its branch); and `push`, unless its filter
# provably keeps branch pushes out: `tags:` alone, or a non-empty `branches:` list of literal
# names (no glob character, so nothing can match dependabot/...). A `branches-ignore:` never
# counts: Dependabot's branch name is configurable (`pull-request-branch-name.separator`),
# so no ignore pattern can be trusted to cover it. `workflow_run` and
# `merge_group` are not listed: they run files from the default branch or after approval.
# shellcheck disable=SC2016
TRIGGERS_JQ='(.on // {}) as $on
  | (if ($on | type) == "string" then [$on] elif ($on | type) == "array" then $on else ($on | keys) end) as $ev
  | def literal_branches: (type == "array") and (length > 0) and all(.[]; (type == "string") and (test("[*?\\[!+]") | not));
    def keeps_branches_out: ($on | type) == "object" and (($on.push // {}) | type == "object")
      and (($on.push // {}) as $p
           | if ($p | has("branches")) then ($p.branches | literal_branches)
             elif ($p | has("branches-ignore")) then false
             else ($p | has("tags")) end);
  ([$ev[] | select(. as $e | $pr | index($e))]
     + [$ev[] | select(. == "create")]
     + [if ($ev | index("push")) != null and (keeps_branches_out | not) then "push" else empty end])
  | .[]'

# job<TAB>reason, one line per job that holds a watched write permission or has no explicit block.
# shellcheck disable=SC2016  # jq variables, not shell ones
PERM_JQ='
  def watched: ["statuses","contents","pull-requests","checks","actions"];
  (.permissions // null) as $wf
  | (.jobs // {}) | to_entries[]
  | .key as $id
  | (if (.value | has("permissions")) then .value.permissions else $wf end) as $p
  | (if $p == null then "has no permissions: block, so the repo default token applies"
     elif ($p | type) == "string" then (if $p == "write-all" then "has write-all" else empty end)
     elif ($p | type) == "object" then
       ([$p | to_entries[] | select(.value == "write" and (.key as $k | watched | index($k))) | .key]
        | if length > 0 then "holds " + join(", ") + ": write" else empty end)
     else "has an unreadable permissions: value" end) as $why
  | "\($id)\t\($why)"'

# The events a workflow runs on, one per line, whether `on:` is a string, a list or a map.
EVENTS_JQ='(.on // {}) | if type == "string" then [.] elif type == "array" then . else keys end | .[]'

# `uses:` of one job and of its steps, one per line.
# shellcheck disable=SC2016
USES_JQ='(.jobs[$j] // {}) | [.uses?, (.steps[]? | .uses?)] | map(select(. != null)) | .[]'

# One job's `container:` or `services:` image is third-party code too, and Dependabot's docker
# ecosystem bumps it. `post` and `resolve` must have neither.
# shellcheck disable=SC2016
IMAGES_JQ='(.jobs[$j] // {}) | [has("container"), has("services")] | any'

# True when the job runs on a GitHub-hosted runner label. A persistent self-hosted runner can
# keep code from an earlier job (a Dependabot-bumped action) alive next to the status token.
# shellcheck disable=SC2016
HOSTED_JQ='(.jobs[$j]["runs-on"] // null) | (type == "string") and test("^(ubuntu|windows|macos)-(latest|[0-9]+([.][0-9]+)*)(-arm)?$")'

# True when the gate's `post` job holds exactly the scopes spec section 0 gives it.
POST_PERMS_JQ='(.jobs.post.permissions // null)
  | (type == "object")
    and ([keys[] | select(IN("statuses", "contents", "pull-requests", "issues") | not)] | length == 0)
    and ((.issues // "read") == "read")'

shopt -s nullglob dotglob nocaseglob
files=("$dir"/*.yml "$dir"/*.yaml)
[ "${#files[@]}" -gt 0 ] || { echo "check-consumer-workflows: no workflow files in $dir" >&2; exit 1; }

gate="$dir/$GATE_NAME"
gate_json=""
for f in "${files[@]}"; do
  if ! json="$(yq -o=json '.' "$f" 2> /dev/null)"; then
    finding "$f: not parseable YAML"
    continue
  fi
  if [ "$(printf '%s' "$json" | j "$SHAPE_JQ")" != "true" ]; then
    finding "$f: not a workflow (the top level and jobs: must be mappings)"
    continue
  fi

  # The gate is the file named architect-review-gate.yml, never any file that merely has jobs
  # of the same names: the `post` exemption below must not be one a decoy can claim.
  shaped="$(printf '%s' "$json" | j '(.jobs // {}) | (has("resolve") and has("decide") and has("post"))')"
  is_gate=false
  if [ "$f" = "$gate" ]; then
    is_gate=true
    gate_json="$json"
    [ "$shaped" = "true" ] || finding "$f: must define the gate's three jobs (resolve, decide, post)."
  elif [ "$shaped" = "true" ]; then
    finding "$f: defines the gate's job names (resolve, decide, post) but is not $GATE_NAME. Only that file may."
  fi

  # Rule 1: write permissions on a workflow that a PR, or a Dependabot branch push, triggers.
  # The gate's `post` is the one exception.
  if [ -n "$(printf '%s' "$json" | j --argjson pr "$PR_EVENTS" "$TRIGGERS_JQ")" ]; then
    while IFS=$'\t' read -r id why; do
      [ -n "$id" ] || continue
      if [ "$is_gate" = true ] && [ "$id" = "post" ]; then continue; fi
      finding "$f: job '$id' $why on a workflow that a pull request or a branch push triggers. Only the gate's post job may hold a write token there."
    done < <(printf '%s' "$json" | j "$PERM_JQ")
  fi
done

# Rules 2 and 3: the gate.
if [ ! -f "$gate" ]; then
  finding "$gate is missing. Copy template/.github/workflows/$GATE_NAME."
elif [ -n "$gate_json" ]; then
  for job in resolve post; do
    while IFS= read -r u; do
      [ -n "$u" ] || continue
      finding "$gate: job '$job' contains 'uses: $u'. resolve and post have run: steps only."
    done < <(printf '%s' "$gate_json" | j --arg j "$job" "$USES_JQ")
    [ "$(printf '%s' "$gate_json" | j --arg j "$job" "$IMAGES_JQ")" = "false" ] \
      || finding "$gate: job '$job' has container: or services:. resolve and post run on the bare runner."
    [ "$(printf '%s' "$gate_json" | j --arg j "$job" "$HOSTED_JQ")" = "true" ] \
      || finding "$gate: job '$job' must run on a GitHub-hosted runner (runs-on: ubuntu-latest), not a self-hosted one."
  done
  [ "$(printf '%s' "$gate_json" | j "$POST_PERMS_JQ")" = "true" ] \
    || finding "$gate: job 'post' may hold only statuses, contents and pull-requests: write, plus issues: read."
  # The line anywhere in post's script, not in the fixed region of it: this catches an honest
  # edit that dropped the rule, not a writer who plants a decoy copy (writers are trusted, F9b).
  if ! printf '%s' "$gate_json" | j '.jobs.post.steps[]? | .run? // empty' | grep -qE '^[[:space:]]*\.github/\*\) touches=1 ;;$'; then
    finding "$gate: the post job's .github/ rule is missing (a changed file under .github/ must always be in review scope)."
  fi
  decide_uses="$(printf '%s' "$gate_json" | j '.jobs.decide.uses // ""')"
  decide_comment="$(yq '.jobs.decide.uses | line_comment' "$gate" 2> /dev/null | tr -d '\r' || true)"
  decide_sha=""
  if [[ "$decide_uses" == "$DECIDE_WF@"* ]] && [[ "${decide_uses#"$DECIDE_WF"@}" =~ ^[0-9a-f]{40}$ ]]; then decide_sha="${decide_uses#"$DECIDE_WF"@}"; fi
  if [ -z "$decide_sha" ] || ! [[ "$decide_comment" =~ $VERSION_COMMENT ]]; then
    decide_sha=""
    finding "$gate: the decide pin must be '$DECIDE_WF@<40-hex sha> # vX.Y'."
  fi

  # Rule 2b (#214): the CONSUMER `code_paths` block must cover the repo's own `.ai/project.yml`
  # code_paths. A block copied from another adopter fails silently in the unsafe direction: a
  # missing glob reads as "No code_paths touched -- no review required", never as a red check.
  # Runs only when `.ai/project.yml` sits next to `.github/` (dir/../../.ai/project.yml).
  root="$(CDPATH="" cd -- "$dir/../.." 2> /dev/null && pwd -P)" || root=""
  project="$root/.ai/project.yml"
  if [ -n "$root" ] && [ -f "$project" ]; then
    region="$(printf '%s' "$gate_json" | j '.jobs.post.steps[]? | .run? // empty' \
      | awk '/# <<< CONSUMER: code_paths/ { on = 0 } on { print } /# >>> CONSUMER: code_paths/ { on = 1; seen = 1 } END { if (!seen) exit 3 }')" \
      || region="__missing__"
    if [ "$region" = "__missing__" ]; then
      finding "$gate: the post job's '>>> CONSUMER: code_paths' region is missing, so $project's code_paths cannot be checked against it."
    elif ! cp_json="$(yq -o=json '.code_paths' "$project" 2> /dev/null)" \
        || [ "$(printf '%s' "$cp_json" | j 'type == "array" and all(.[]; type == "string")')" != "true" ]; then
      finding "$project: code_paths must be a list of strings."
    else
      arms="" arm_ok=true
      while IFS= read -r line; do
        case "$line" in *[![:space:]]*) ;; *) continue ;; esac   # blank
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # Only literal case arms. The block is evaluated below, so nothing else may reach eval.
        # [[:blank:]], not [[:space:]]: a \v or \f would turn `touches=1` into a command name.
        if [[ "$line" =~ ^[[:blank:]]*[]A-Za-z0-9_./*?[-]+(\|[]A-Za-z0-9_./*?[-]+)*\)[[:blank:]]+touches=1[[:blank:]]+\;\;[[:blank:]]*$ ]]; then
          arms+="$line"$'\n'
        else
          finding "$gate: the CONSUMER code_paths block holds a line that is not '<glob>|<glob>) touches=1 ;;': $line"
          arm_ok=false
        fi
      done <<< "$region"
      if [ "$arm_ok" = true ]; then
        # The gate's own two `case` statements, the fixed `.github/` rule first.
        # A reserved word as a pattern (`esac)`) passes the arm shape but is a syntax error here.
        if ! eval "gate_touches() { local touches=0; case \"\$1\" in .github/*) touches=1 ;; esac; case \"\$1\" in
$arms
        esac; echo \"\$touches\"; }" 2> /dev/null; then
          finding "$gate: the CONSUMER code_paths block does not parse as case arms."
          arm_ok=false
        fi
      fi
      if [ "$arm_ok" = true ]; then
        samples=()
        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          # The gate's `case` sees PR file paths from the GitHub files API (`tools/a`), never
          # `./tools/a`, so sample the entry without a leading `./` (#245). A block arm written
          # `./tools/*` then reads touches=0, as the real gate would. A bare `./` (or `.`) is left
          # as it was, so it is still sampled as `./a` and is not checked correctly.
          path="$entry"
          while [[ "$path" == ./* ]]; do path="${path#./}"; done
          [ -n "$path" ] || path="$entry"
          # Several samples per entry, so one lucky shape (`images/a)` for `images/`) cannot pass.
          cands=(); match="$path"
          # `**/` also covers zero directories, so a base without it too; a glob in a dir entry
          # (`modules/*/`) is filled in the same way.
          if [[ "$path" == */ ]] || [ -d "$root/$path" ]; then
            base="${path%/}/"; match="${base}*"
            bases=("${base//[*?]/a}" "${base//\*/Z9_-.}" "${base//\*\*\//}")
            bases[1]="${bases[1]//\?/Z}"; bases[2]="${bases[2]//[*?]/a}"
            for b in "${bases[@]}"; do cands+=("${b}a" "${b}A" "${b}.a" "${b}a/b" "${b}Z9_-."); done
          else
            cands=("${path//[*?]/a}" "${path//\*/Z9_-.}" "${path//\*\*\//}")
            cands[1]="${cands[1]//\?/Z}"; cands[2]="${cands[2]//[*?]/a}"
          fi
          checked=0
          hint=""
          [[ "$path" == *[/*?\[]* ]] || hint=" (A directory entry needs a trailing slash, or to exist next to .github/.)"
          zero="${match//\*\*\//}"
          for sample in "${cands[@]}"; do
            # A sample built from a glob must itself match it, or it proves nothing.
            # (`**/` matching zero directories is how gitignore reads it, not bash, so try both.)
            # shellcheck disable=SC2053  # the glob match is the point
            if [[ "$match" == *[*?\[]* ]] && ! [[ "$sample" == $match || "$sample" == $zero ]]; then continue; fi
            checked=1
            samples+=("$sample")
            if [ "$(gate_touches "$sample")" != 1 ]; then
              finding "$gate: the CONSUMER block does not cover code_paths entry '$entry' in $project ($sample reads touches=0). A PR touching only it would post 'no review required'. Derive the block from this repo's own code_paths, never from another adopter's gate.${hint}"
              break   # one finding per entry
            fi
          done
          [ "$checked" = 1 ] || warn "cannot build a sample path for the code_paths entry '$entry', so it is not checked."
        done < <(printf '%s' "$cp_json" | j '.[]')
        # The reverse is a warning: a pattern that none of the entries' samples matches.
        while IFS= read -r line; do
          [[ "$line" =~ ^[[:space:]]*#|^[[:space:]]*$ ]] && continue
          pats="${line%%)*}"; pats="${pats#"${pats%%[![:space:]]*}"}"
          IFS='|' read -ra plist <<< "$pats"
          for p in "${plist[@]}"; do
            [ "$p" = '.github/*' ] && continue
            hit=false
            # shellcheck disable=SC2053  # the glob match is the point
            for s in ${samples[@]+"${samples[@]}"}; do [[ "$s" == $p ]] && { hit=true; break; }; done
            [ "$hit" = true ] || warn "$gate: the CONSUMER pattern '$p' matches none of the code_paths entries in $project."
          done
        done <<< "$region"
      fi
    fi
  fi
fi


# Rule 4: the caller.
caller="$dir/devcontainer-image.yml"
if [ ! -f "$caller" ]; then
  finding "$caller is missing. Copy template/.github/workflows/devcontainer-image.yml."
elif ! cjson="$(yq -o=json '.' "$caller" 2> /dev/null)" || [ "$(printf '%s' "$cjson" | j "$SHAPE_JQ")" != "true" ]; then
  :   # the loop above already reported it as not parseable, or not a workflow
else
  c() { printf '%s' "$cjson" | j "$@"; }
  [ "$(c '(.jobs // {}) | keys | join(",")')" = "verify" ] \
    || finding "$caller: the only job must be 'verify' (found: $(c '(.jobs // {}) | keys | join(",")'))."
  [ "$(c '[.jobs.verify | has("name"), has("if")] | any')" = "false" ] \
    || finding "$caller: job 'verify' must have no name: and no if:, so the check is always 'verify / verify'."
  [ "$(c "[$EVENTS_JQ] | join(\",\")")" = "pull_request" ] \
    || finding "$caller: the only trigger must be pull_request."
  [ "$(c '(.on | if type == "object" then (.pull_request // {}) else {} end) | (type == "object") and (keys | length == 0)')" = "true" ] \
    || finding "$caller: pull_request must have no paths:, paths-ignore:, branches: or branches-ignore: filter (a filtered required check never reports)."
  [ "$(c '.jobs.verify.permissions | . == {"contents":"read"}')" = "true" ] \
    || finding "$caller: job 'verify' must have exactly 'permissions: { contents: read }'."
  [ "$(c '.jobs.verify | has("with") or has("secrets")')" = "false" ] \
    || finding "$caller: job 'verify' takes no with: or secrets:."
  verify_uses="$(c '.jobs.verify.uses // ""')"
  verify_comment="$(yq '.jobs.verify.uses | line_comment' "$caller" 2> /dev/null | tr -d '\r' || true)"
  verify_sha=""
  if [[ "$verify_uses" == "$VERIFY_WF@"* ]] && [[ "${verify_uses#"$VERIFY_WF"@}" =~ ^[0-9a-f]{40}$ ]]; then verify_sha="${verify_uses#"$VERIFY_WF"@}"; fi
  if [ -z "$verify_sha" ] || ! [[ "$verify_comment" =~ $VERSION_COMMENT ]]; then
    finding "$caller: the verify pin must be '$VERIFY_WF@<40-hex sha> # vX.Y'."
  elif [ -n "${decide_sha:-}" ] && [ "$decide_sha" != "$verify_sha" ]; then
    warn "the verify pin ($verify_sha) and the decide pin ($decide_sha) name different commits. Bump them together."
  fi
fi

# Rule 5: the secret-scan caller (#190). Same shape as the verify caller, job `secrets`; its pin
# is independent of the verify/decide pins (a scanner bump should not need an image re-verify).
scan_caller="$dir/secret-scan.yml"
if [ ! -f "$scan_caller" ]; then
  finding "$scan_caller is missing. Copy template/.github/workflows/secret-scan.yml."
elif ! sjson="$(yq -o=json '.' "$scan_caller" 2> /dev/null)" || [ "$(printf '%s' "$sjson" | j "$SHAPE_JQ")" != "true" ]; then
  :   # the loop above already reported it as not parseable, or not a workflow
else
  s() { printf '%s' "$sjson" | j "$@"; }
  [ "$(s '(.jobs // {}) | keys | join(",")')" = "secrets" ]     || finding "$scan_caller: the only job must be 'secrets' (found: $(s '(.jobs // {}) | keys | join(",")'))."
  [ "$(s '[.jobs.secrets | has("name"), has("if")] | any')" = "false" ]     || finding "$scan_caller: job 'secrets' must have no name: and no if:, so the check is always 'secrets / scan'."
  [ "$(s "[$EVENTS_JQ] | join(\",\")")" = "pull_request" ]     || finding "$scan_caller: the only trigger must be pull_request."
  [ "$(s '(.on | if type == "object" then (.pull_request // {}) else {} end) | (type == "object") and (keys | length == 0)')" = "true" ]     || finding "$scan_caller: pull_request must have no paths:, paths-ignore:, branches: or branches-ignore: filter (a filtered required check never reports)."
  [ "$(s '.jobs.secrets.permissions | . == {"contents":"read"}')" = "true" ]     || finding "$scan_caller: job 'secrets' must have exactly 'permissions: { contents: read }'."
  [ "$(s '.jobs.secrets | has("with") or has("secrets")')" = "false" ]     || finding "$scan_caller: job 'secrets' takes no with: or secrets:."
  scan_uses="$(s '.jobs.secrets.uses // ""')"
  scan_comment="$(yq '.jobs.secrets.uses | line_comment' "$scan_caller" 2> /dev/null | tr -d '\r' || true)"
  if ! { [[ "$scan_uses" == "$SCAN_WF@"* ]] && [[ "${scan_uses#"$SCAN_WF"@}" =~ ^[0-9a-f]{40}$ ]] && [[ "$scan_comment" =~ $VERSION_COMMENT ]]; }; then
    finding "$scan_caller: the secrets pin must be '$SCAN_WF@<40-hex sha> # vX.Y'."
  fi
fi

if [ "$findings" -gt 0 ]; then
  echo "check-consumer-workflows: $findings finding(s)." >&2
  exit 1
fi
echo "check-consumer-workflows: ok."
