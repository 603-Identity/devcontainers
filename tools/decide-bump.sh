#!/usr/bin/env bash
# The body of devcontainer-bump-decision.yml (spec section 3). Decides, for ONE candidate
# SHA, whether it is a verified same-MAJOR Dockerfile bump. Writes `exempt=true|false`
# to $GITHUB_OUTPUT exactly once, at the very end.
#
# The boolean comes from `devc-verify decide`'s EXIT CODE only: 0 -> true, 3 -> false,
# anything else fails this script (and the job). An API error, a 403/429/5xx or a network
# failure also fails it under `set -e` before anything is written; none of them is ever
# turned into `false` (spec section 3, "Errors vs no").
#
# Env: REPO (the caller's repo), HEAD_SHA, CANDIDATE_PR, DEVC_VERIFY (built binary),
#      WORK_DIR (scratch dir), GH_TOKEN, GITHUB_OUTPUT.
set -euo pipefail

: "${REPO:?}" "${HEAD_SHA:?}" "${CANDIDATE_PR:?}" "${DEVC_VERIFY:?}" "${WORK_DIR:?}" "${GITHUB_OUTPUT:?}"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::head_sha is not a 40-hex SHA" >&2; exit 2; }
[[ "$CANDIDATE_PR" =~ ^[0-9]+$ ]] || { echo "::error::candidate_pr is not a number" >&2; exit 2; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exempt=false

# 1. The candidate PR must still be at head_sha.
pr="$(gh api "repos/${REPO}/pulls/${CANDIDATE_PR}")"
# A response that lacks the fields we rely on is an API fault, not a "no": fail the job.
jq -e '(.head.sha | type == "string") and (.base.sha | type == "string")' <<<"$pr" >/dev/null \
  || { echo "::error::unexpected pulls response shape" >&2; exit 1; }
cur_head="$(jq -r '.head.sha' <<<"$pr")"
base_sha="$(jq -r '.base.sha' <<<"$pr")"

if [ "$cur_head" = "$HEAD_SHA" ] && [[ "$base_sha" =~ ^[0-9a-f]{40}$ ]]; then
  # 2. Fixed SHAs on both sides: exactly .devcontainer/Dockerfile, +1/-1, modified.
  cmp="$(gh api "repos/${REPO}/compare/${base_sha}...${HEAD_SHA}")"
  jq -e '.files | type == "array"' <<<"$cmp" >/dev/null \
    || { echo "::error::unexpected compare response shape" >&2; exit 1; }
  if jq -e '(.files | length) == 1
            and .files[0].filename == ".devcontainer/Dockerfile"
            and .files[0].status == "modified"
            and .files[0].additions == 1 and .files[0].deletions == 1
            and (.files[0] | has("previous_filename") | not)
            and (.files[0].patch | type == "string")' <<<"$cmp" >/dev/null; then
    mkdir -p "$WORK_DIR"
    jq -r '.files[0].patch' <<<"$cmp" > "${WORK_DIR}/bump.patch"
    # 3. The files at head_sha, through the API.
    bash "${here}/fetch-consumer.sh" "$REPO" "$HEAD_SHA" "${WORK_DIR}/consumer"
    # 4. Verification and the bump predicate, decided by the tool's exit code.
    rc=0
    "$DEVC_VERIFY" decide --consumer-dir "${WORK_DIR}/consumer" --patch "${WORK_DIR}/bump.patch" || rc=$?
    case "$rc" in
      0) exempt=true ;;
      3) exempt=false ;;
      *) echo "::error::devc-verify failed with code ${rc}" >&2; exit 1 ;;
    esac
    # 5. The head must not have moved while we worked.
    again="$(gh api "repos/${REPO}/pulls/${CANDIDATE_PR}" --jq '.head.sha // ""')"
    [ "$again" = "$HEAD_SHA" ] || exempt=false
  fi
fi

echo "exempt=${exempt}" >> "$GITHUB_OUTPUT"
