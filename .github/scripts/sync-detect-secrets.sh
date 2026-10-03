#!/usr/bin/env bash
# Keeps the image's bc-detect-secrets on the version 603-Identity/checkov-ledger-action's
# latest release uses. The version is never chosen here: Checkov pins bc-detect-secrets
# EXACTLY, so whatever Checkov version the action is built and tested against decides it,
# and every 603 repo's .secrets.baseline and CI secret-scan pin follow the same release.
# A different version on the image's PATH rewrites a repo's baseline to one its CI rejects.
#
# Two reads of the same release must agree, or nothing is proposed:
#   * the `version` field of the release's own .secrets.baseline, and
#   * the bc-detect-secrets==X that PyPI's metadata for the release's
#     examples/checkov-ledger.json `checkov_version` requires.
# On a mismatch with images/base/tools/uv.lock it rewrites the pyproject.toml pin,
# re-locks with uv (hashes from PyPI, `uv lock` installs no package), and opens a
# bump/bc-detect-secrets-<version> PR (skipped if that PR is already open). Consumer
# repos' baselines and CI pins are left to the human review the PR goes through.
#
# Usage: sync-detect-secrets.sh
# Env:   REPO (owner/repo), GH_TOKEN (gh, authenticated for push+PR), APP_SLUG, APP_ID
#        (the commit's bot identity), uv on PATH.
#        DRY_RUN=1 resolves and compares only: no git, no uv, no PR, no write token
#        needed. Exits 0 in sync, 3 behind, 1 on any error (the check step and the tests).
#        ACTION_REPO, PYPI_URL and DEVC_ROOT override the defaults (the offline tests).
set -euo pipefail

root="${DEVC_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
action_repo="${ACTION_REPO:-603-Identity/checkov-ledger-action}"
pypi="${PYPI_URL:-https://pypi.org/pypi}"
pyproject="$root/images/base/tools/pyproject.toml"
lock="$root/images/base/tools/uv.lock"
semver='^[0-9]+\.[0-9]+\.[0-9]+$'

die() { echo "::error::bc-detect-secrets: $*" >&2; exit 1; }

# The action releases as signed, annotated vX.Y.Z tags with a CHANGELOG.md entry, not
# GitHub Releases, so "latest" is the highest plain vX.Y.Z tag. Tag and commit come from
# one listing, and every later read pins ?ref= to that commit, so a tag moved or pushed
# mid-run cannot pair one release's name with another's files.
tags="$(gh api --paginate "repos/$action_repo/tags" --jq '.[] | [.name, .commit.sha] | @tsv')" \
  || die "could not list the tags of $action_repo"
IFS=$'\t' read -r tag sha <<< "$(printf '%s\n' "$tags" | grep -E $'^v[0-9]+\\.[0-9]+\\.[0-9]+\t[0-9a-f]{40}$' \
  | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')"
# Only lines of exactly that shape survive the grep, so tag and sha reach the URLs below,
# a PR body and the log already validated; re-check in case the listing had none.
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && "$sha" =~ ^[0-9a-f]{40}$ ]] || die "$action_repo has no vX.Y.Z tag"
release_url="https://github.com/$action_repo/blob/$tag/CHANGELOG.md"

raw() { # raw <path> -> that file's content at the tag's commit
  gh api "repos/$action_repo/contents/$1?ref=$sha" -H "Accept: application/vnd.github.raw"
}
baseline_version="$(raw .secrets.baseline | jq -r '.version // ""')" \
  || die "could not read .secrets.baseline at $action_repo@$tag"
checkov_version="$(raw examples/checkov-ledger.json | jq -r '.checkov_version // ""')" \
  || die "could not read examples/checkov-ledger.json at $action_repo@$tag"
[[ "$baseline_version" =~ $semver ]] || die "$action_repo@$tag .secrets.baseline version is not a plain X.Y.Z: rejecting"
[[ "$checkov_version" =~ $semver ]] || die "$action_repo@$tag checkov_version is not a plain X.Y.Z: rejecting"

# Exactly one `bc-detect-secrets==X.Y.Z` requirement, environment markers ignored. A
# range, or none at all, means Checkov stopped pinning it exactly and the rule this
# script rests on no longer holds: fail closed and let a human look.
checkov_pin="$(curl -fsSL "$pypi/checkov/$checkov_version/json" \
  | jq -r '[.info.requires_dist[]? | select(test("^bc-detect-secrets\\s*==")) | capture("==\\s*(?<v>[^ ;,]+)").v] | if length == 1 then .[0] else "" end')" \
  || die "could not read PyPI metadata for checkov $checkov_version"
[[ "$checkov_pin" =~ $semver ]] || die "checkov $checkov_version does not pin bc-detect-secrets to one exact X.Y.Z"
[ "$checkov_pin" = "$baseline_version" ] \
  || die "$action_repo@$tag disagrees with itself: its .secrets.baseline is $baseline_version but checkov $checkov_version pins $checkov_pin"
new="$checkov_pin"

current="$(sed -n '/^name = "bc-detect-secrets"$/{n;s/^version = "\(.*\)"$/\1/p;q;}' "$lock")"
[[ "$current" =~ $semver ]] || die "could not read bc-detect-secrets from $lock"

if [ "$new" = "$current" ]; then
  echo "bc-detect-secrets: in sync with $action_repo@$tag at $current"
  exit 0
fi
# A "latest" release going backwards (a yanked release, a deleted and reused tag) is a
# signal to fail closed on, as bump-binaries.sh does; a deliberate rollback is a manual PR.
if [ "$(printf '%s\n%s\n' "$new" "$current" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" != "$new" ]; then
  die "$action_repo@$tag uses $new, older than the image's $current -- refusing to open a downgrade PR"
fi

echo "bc-detect-secrets: $current -> $new (checkov $checkov_version, $action_repo@$tag)"
[ "${DRY_RUN:-0}" = 1 ] && exit 3

repo="${REPO:?REPO must be set, e.g. 603-Identity/devcontainers}"
branch="bump/bc-detect-secrets-${new}"
open_count="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq 'length')"
if [ "$open_count" != "0" ]; then
  echo "bc-detect-secrets: PR already open on $branch, nothing to do"
  exit 0
fi

gh auth setup-git
git -C "$root" config user.name "${APP_SLUG:?APP_SLUG must be set}[bot]"
git -C "$root" config user.email "${APP_ID:?APP_ID must be set}+${APP_SLUG}[bot]@users.noreply.github.com"
git -C "$root" switch -c "$branch"

# The version is validated above, but it travels through ENVIRON rather than an
# interpolated awk program or -v (which would run escape processing on it).
SYNC_VER="$new" awk '
  /^    "bc-detect-secrets==[^"]*",$/ { print "    \"bc-detect-secrets==" ENVIRON["SYNC_VER"] "\","; n++; next }
  { print }
  END { exit n == 1 ? 0 : 1 }
' "$pyproject" > "$pyproject.new" || die "expected exactly one bc-detect-secrets pin line in $pyproject"
mv "$pyproject.new" "$pyproject"
# The comment naming the release the pin follows moves with it.
SYNC_TAG="$tag" SYNC_CK="$checkov_version" SYNC_VER="$new" awk '
  /^# \(v[0-9.]+: checkov [0-9.]+ -> [0-9.]+\)/ { sub(/^# \(v[0-9.]+: checkov [0-9.]+ -> [0-9.]+\)/, "# (" ENVIRON["SYNC_TAG"] ": checkov " ENVIRON["SYNC_CK"] " -> " ENVIRON["SYNC_VER"] ")") }
  { print }
' "$pyproject" > "$pyproject.new" && mv "$pyproject.new" "$pyproject"

uv lock --project "$root/images/base/tools" --upgrade-package bc-detect-secrets
locked="$(sed -n '/^name = "bc-detect-secrets"$/{n;s/^version = "\(.*\)"$/\1/p;q;}' "$lock")"
[ "$locked" = "$new" ] || die "uv lock resolved $locked, expected $new"
# Nothing but the pin and the lock may change: a re-lock that moved anything else is a
# separate decision, not part of this sync.
changed="$(git -C "$root" status --porcelain | sed 's/^...//' | sort | tr '\n' ' ')"
[ "$changed" = "images/base/tools/pyproject.toml images/base/tools/uv.lock " ] \
  || die "unexpected changes after the re-lock: $changed"

git -C "$root" add "$pyproject" "$lock"
git -C "$root" commit -m "build(base): bc-detect-secrets $current -> $new (follows checkov-ledger-action $tag)"
git -C "$root" push -u origin "$branch"

body="$(cat <<EOF
Opened by \`sync-detect-secrets.sh\` (\`bump-binaries.yml\`): bc-detect-secrets $current -> $new.

[$action_repo $tag]($release_url) uses Checkov $checkov_version, which pins
bc-detect-secrets==$new exactly, and its own \`.secrets.baseline\` is version $new. The image
follows it so \`detect-secrets\` on the container's PATH writes the baseline version CI expects.

Hashes in \`uv.lock\` come from PyPI via \`uv lock\`; nothing else in the lock moved.

Before merge: every 603 repo that opens in this image regenerates its \`.secrets.baseline\`
with $new and moves its CI secret-scan pin (and its ledger's \`checkov_version\` to
$checkov_version) to match, or its baseline is rewritten in the container to a version its
CI rejects. The ordinary gates (the smoke test asserts the locked version, Trivy, and
architect-review because \`images/\` is a code_path) run on this PR like any other.
EOF
)"
gh pr create --repo "$repo" --head "$branch" --base main \
  --title "build(base): bc-detect-secrets $current -> $new" \
  --body "$body"
