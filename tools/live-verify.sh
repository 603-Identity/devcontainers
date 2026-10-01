#!/usr/bin/env bash
# Live check for verify-selftest.yml (spec section 5, "Live job"): take the newest published
# tag of each image whose build.yml run SUCCEEDED, and run the full `devc-verify attest`
# against its digest. Only attempt-1 runs count: a re-run build is permanently non-exempt
# by design (provenance signs /attempts/2), so it can never be the newest verifiable tag.
# Recovery if this job is red for lack of a fresh attempt-1 image: re-run it (a transient
# registry or API error), or dispatch build.yml on main.
# Tag lists are paginated (L5: unpaginated, the newest tag was missed) and sorted
# numerically, never lexically.
# Env: DEVC_VERIFY (built binary), GH_TOKEN. Needs curl, jq, gh.
set -euo pipefail

: "${DEVC_VERIFY:?}"
owner=603-identity
ok_runs="$(gh run list --repo 603-Identity/devcontainers --workflow build.yml \
  --status success --limit 400 --json number,attempt \
  --jq '.[] | select(.attempt == 1) | .number')"
[ -n "$ok_runs" ] || { echo "::error::no successful build.yml runs found" >&2; exit 1; }

for name in devcontainer-base devcontainer-tofu devcontainer-node; do
  token="$(curl -fsS --retry 3 --retry-delay 2 --retry-all-errors --max-time 30 "https://ghcr.io/token?scope=repository:${owner}/${name}:pull" | jq -r '.token')"
  tags=""
  url="https://ghcr.io/v2/${owner}/${name}/tags/list?n=200"
  while [ -n "$url" ]; do
    hdr="$(mktemp)"
    body="$(curl -fsS --retry 3 --retry-delay 2 --retry-all-errors --max-time 30 -D "$hdr" -H "Authorization: Bearer ${token}" "$url")"
    tags+="$(jq -r '.tags[]?' <<<"$body")"$'\n'
    next="$(grep -i '^link:' "$hdr" | sed -n 's/.*<\([^>]*\)>; *rel="next".*/\1/p' | tr -d '\r' || true)"
    rm -f "$hdr"
    if [ -n "$next" ]; then url="https://ghcr.io${next}"; else url=""; fi
  done

  pick=""
  while read -r tag; do
    minor="${tag#*.}"
    if grep -qx "$minor" <<<"$ok_runs"; then pick="$tag"; break; fi
  done < <(grep -E '^[0-9]+\.[0-9]+$' <<<"$tags" | sort -t. -k1,1nr -k2,2nr)
  [ -n "$pick" ] || { echo "::error::no verifiable tag found for ${name}" >&2; exit 1; }

  digest="$(curl -fsSI --retry 3 --retry-delay 2 --retry-all-errors --max-time 30 -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json' \
    "https://ghcr.io/v2/${owner}/${name}/manifests/${pick}" \
    | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }')"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "::error::no digest for ${name}:${pick}" >&2; exit 1; }

  echo "== ${name}:${pick}@${digest}"
  "$DEVC_VERIFY" attest --image "ghcr.io/${owner}/${name}:${pick}@${digest}"
done
