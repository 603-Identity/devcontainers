#!/usr/bin/env bash
# Resolves the newest release for one ARG-pinned binary, per the line policy from #29:
# gh, yq, uv, tofu and tflint take the newest stable release; node tracks the current
# LTS line (nodejs.org flips a release's own `lts` field once its line enters LTS, so
# this needs no hardcoded major); npm takes the newest release whose `engines.node`
# is satisfied by the Dockerfile's CURRENT node pin. The checksum always comes from
# that release's own published file or the registry's `integrity` field -- never from
# hashing the download -- so the Dockerfiles' "no trust-on-first-use" rule holds here
# too. On a version bump it rewrites the Dockerfile's ARG lines, opens a
# bump/<tool>-<version> branch and PR (skipped if that PR is already open, or if the branch
# already exists on origin, e.g. after a human closed its PR unmerged), and leaves
# everything else -- the surrounding comments, consumer CI pins, .trivyignore.yaml --
# for the human review the PR goes through.
#
# betterleaks (#190) is the exception to "stable only", but only while its pin is itself a release
# candidate (X.Y.Z-rc.N): then it takes the highest-versioned release including prereleases (so
# it can reach 2.0.0 GA). Once the pin is on a GA release it takes stable releases only, like every
# other tool (#208). Either way it takes the checksum only after cosign verifies the release's
# sigstore bundle for its checksums.txt against the pinned signer identity.
#
# Every resolver sets CHECKSUM_URL, the URL its checksum was actually read from, next to
# RELEASE_URL; the bump PR body cites both (#85).
#
# Usage: bump-binaries.sh <gh|yq|uv|tofu|tflint|node|npm|betterleaks>
# Env:   REPO (owner/repo), GH_TOKEN (gh, authenticated for push+PR), APP_SLUG,
#        BOT_USER_ID (the bot's user id, for the commit's noreply email)
set -euo pipefail

tool="${1:?usage: bump-binaries.sh <gh|yq|uv|tofu|tflint|node|npm|betterleaks>}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
repo="${REPO:?REPO must be set, e.g. 603-Identity/devcontainers}"

NEW_VERSION=""
NEW_CHECKSUM=""
RELEASE_URL=""
CHECKSUM_URL=""

# sha256_line <url> <asset-filename> -> the sha256 field of a "sha256  filename" line.
# gh, tflint, tofu and uv all publish this exact format (verified against gh, tflint,
# tofu and uv's own checksum files; a format change elsewhere fails closed below).
#
# The file is read into a variable first, never piped into an awk that `exit`s on the first
# match: awk closing the pipe while curl is still writing makes curl fail with exit 23 under
# `pipefail`, and whether it does depends on the file's size and timing (first seen on a yq
# run, #102).
sha256_line() {
  local body
  body="$(curl -fsSL "$1")"
  awk -v f="$2" '$2 == f { print $1; exit }' <<< "$body"
}

# latest_release <owner/repo> -> tag_name and html_url from ONE API call, as
# "tag\turl". Two separate `gh api .../releases/latest` calls could race against a
# release published in between, pairing one release's tag with another's URL.
latest_release() {
  gh api "repos/$1/releases/latest" --jq '[.tag_name, .html_url] | @tsv'
}

resolve_gh() {
  local tag
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release cli/cli)"
  NEW_VERSION="${tag#v}"
  CHECKSUM_URL="https://github.com/cli/cli/releases/download/${tag}/gh_${NEW_VERSION}_checksums.txt"
  NEW_CHECKSUM="$(sha256_line "$CHECKSUM_URL" "gh_${NEW_VERSION}_linux_amd64.tar.gz")"
}

resolve_yq() {
  local tag order_url sums_url field sums
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release mikefarah/yq)"
  NEW_VERSION="${tag#v}"
  # The checksums file lists one hash per algorithm, in the order this sidecar file
  # names them (field 1 is the asset name) -- read the order instead of hardcoding a
  # column, so an upstream reshuffle fails closed on a missing SHA-256 line rather than
  # silently reading the wrong hash. The asset is the raw binary, not the tarball:
  # images/base/Dockerfile downloads yq_linux_amd64 and checks it against YQ_SHA256 (#164).
  order_url="https://github.com/mikefarah/yq/releases/download/${tag}/checksums_hashes_order"
  field="$(curl -fsSL "$order_url" | grep -n '^SHA-256$' | cut -d: -f1)"
  [ -n "$field" ] || { echo "::error::yq: SHA-256 not found in $order_url" >&2; exit 1; }
  field=$((field + 1))
  sums_url="https://github.com/mikefarah/yq/releases/download/${tag}/checksums"
  # Read into a variable first (see sha256_line): an early-exiting awk on a curl pipe races.
  sums="$(curl -fsSL "$sums_url")"
  NEW_CHECKSUM="$(awk -v f="yq_linux_amd64" -v col="$field" '$1 == f { print $col; exit }' <<< "$sums")"
  # Two files decide the hash: the column comes from the order file, the value from this one.
  CHECKSUM_URL="$sums_url (SHA-256 column per $order_url)"
}

resolve_uv() {
  IFS=$'\t' read -r NEW_VERSION RELEASE_URL <<< "$(latest_release astral-sh/uv)"
  CHECKSUM_URL="https://github.com/astral-sh/uv/releases/download/${NEW_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256"
  NEW_CHECKSUM="$(sha256_line "$CHECKSUM_URL" "uv-x86_64-unknown-linux-gnu.tar.gz")"
}

resolve_tofu() {
  local tag
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release opentofu/opentofu)"
  NEW_VERSION="${tag#v}"
  CHECKSUM_URL="https://github.com/opentofu/opentofu/releases/download/${tag}/tofu_${NEW_VERSION}_SHA256SUMS"
  NEW_CHECKSUM="$(sha256_line "$CHECKSUM_URL" "tofu_${NEW_VERSION}_linux_amd64.zip")"
}

resolve_tflint() {
  local tag
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release terraform-linters/tflint)"
  NEW_VERSION="${tag#v}"
  CHECKSUM_URL="https://github.com/terraform-linters/tflint/releases/download/${tag}/checksums.txt"
  NEW_CHECKSUM="$(sha256_line "$CHECKSUM_URL" "tflint_linux_amd64.zip")"
}

resolve_node() {
  local index major
  index="$(curl -fsSL https://nodejs.org/dist/index.json)"
  # The current LTS line: the highest major with ANY release nodejs.org marks with a
  # non-false `lts` codename (a line's releases carry `lts: false` until it enters
  # LTS). That resolves to the policy in #29 (24 today, 26 once it enters LTS) without
  # a hardcoded major, regardless of whether earlier same-line releases are retagged.
  major="$(printf '%s' "$index" | jq -r \
    '[.[] | select(.lts != false) | (.version | ltrimstr("v") | split(".")[0] | tonumber)] | max')"
  if [ -z "$major" ] || [ "$major" = "null" ]; then
    echo "::error::node: no LTS line found in dist/index.json" >&2
    exit 1
  fi
  NEW_VERSION="$(printf '%s' "$index" | jq -r --argjson maj "$major" \
    '[.[] | select(.lts != false) | .version | ltrimstr("v")
        | select(split(".")[0] | tonumber == $maj)]
     | sort_by(split(".") | map(tonumber)) | last')"
  CHECKSUM_URL="https://nodejs.org/dist/v${NEW_VERSION}/SHASUMS256.txt"
  NEW_CHECKSUM="$(sha256_line "$CHECKSUM_URL" "node-v${NEW_VERSION}-linux-x64.tar.xz")"
  RELEASE_URL="$(gh api "repos/nodejs/node/releases/tags/v${NEW_VERSION}" --jq '.html_url' 2>/dev/null \
    || echo "https://github.com/nodejs/node/blob/main/doc/changelogs/CHANGELOG_V${major}.md")"
}

# ver_key <X.Y.Z or X.Y.Z-rc.N> -> a fixed-width key that sorts as a version does, with every
# release candidate below its own GA release and rc.N below rc.N+1. `sort -V` cannot be used:
# it puts X.Y.Z-rc.1 above X.Y.Z.
ver_key() {
  local v="$1" core a b c rc=999999
  core="${v%%-*}"
  if [[ "$v" == *-rc.* ]]; then rc="${v##*-rc.}"; fi
  IFS=. read -r a b c <<< "$core"
  printf '%06d.%06d.%06d.%06d' "$((10#$a))" "$((10#$b))" "$((10#$c))" "$((10#$rc))"
}

# While Betterleaks is pinned to a release candidate, /releases/latest (which skips
# prereleases) is the wrong question: take the highest-versioned non-draft release instead,
# prereleases included, and never a tag that is not exactly vX.Y.Z or vX.Y.Z-rc.N. Once the pin
# is a GA release, consider only exactly-vX.Y.Z tags, so the job never proposes the next rc (#208).
# The pin is read from the Dockerfile here, ahead of the generic read further down.
# Its checksums.txt is taken ONLY after the release's sigstore bundle verifies with the pinned signer identity for that exact tag
# (the release workflow, run at that tag, via GitHub Actions OIDC); a failed or missing
# verification is an error, never a fallback to the unsigned file. Needs `cosign` on PATH.
BETTERLEAKS_ISSUER="https://token.actions.githubusercontent.com"
resolve_betterleaks() {
  local best="" best_key="" best_url="" tag url key dir identity pin tag_re
  pin="$(sed -n 's/^ARG BETTERLEAKS_VERSION=//p' "$root/images/base/Dockerfile")"
  [ -n "$pin" ] || { echo "::error::betterleaks: could not read BETTERLEAKS_VERSION from $root/images/base/Dockerfile" >&2; exit 1; }
  tag_re='^v[0-9]+\.[0-9]+\.[0-9]+$'
  if [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then
    tag_re='^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'
  fi
  while IFS=$'\t' read -r tag url; do
    [[ "$tag" =~ $tag_re ]] || continue
    key="$(ver_key "${tag#v}")"
    if [ -z "$best" ] || [[ "$key" > "$best_key" ]]; then best="$tag"; best_key="$key"; best_url="$url"; fi
  done < <(gh api "repos/betterleaks/betterleaks/releases" --paginate --jq '.[] | select(.draft | not) | [.tag_name, .html_url] | @tsv')
  [ -n "$best" ] || { echo "::error::betterleaks: no release matching ${tag_re} (pin $pin)" >&2; exit 1; }
  command -v cosign > /dev/null || { echo "::error::betterleaks: cosign is required to verify the release signature" >&2; exit 1; }

  NEW_VERSION="${best#v}"
  RELEASE_URL="$best_url"
  dir="$(mktemp -d)"
  CHECKSUM_URL="https://github.com/betterleaks/betterleaks/releases/download/${best}/checksums.txt"
  curl -fsSL "$CHECKSUM_URL" -o "$dir/checksums.txt"
  curl -fsSL "https://github.com/betterleaks/betterleaks/releases/download/${best}/checksums.txt.sigstore.json" -o "$dir/checksums.txt.sigstore.json"
  identity="https://github.com/betterleaks/betterleaks/.github/workflows/release.yml@refs/tags/${best}"
  if ! cosign verify-blob --bundle "$dir/checksums.txt.sigstore.json" \
      --certificate-identity "$identity" --certificate-oidc-issuer "$BETTERLEAKS_ISSUER" \
      "$dir/checksums.txt" >&2; then
    echo "::error::betterleaks: the signature on ${best}'s checksums.txt did not verify against ${identity}: refusing to take its checksum" >&2
    exit 1
  fi
  NEW_CHECKSUM="$(awk -v f="betterleaks_${NEW_VERSION}_linux_x64.tar.gz" '$2 == f { print $1; exit }' "$dir/checksums.txt")"
}

# satisfies <version> <engines.node range> -> exit 0 if version satisfies range.
# Implements only the operators npm's own engines field actually uses (`||`-joined
# clauses of `^x.y.z` / `>=x.y.z` / an exact `x.y.z`), so an unrecognised operator
# fails closed instead of silently guessing -- never fed anything but argv, so an
# untrusted range string is data, never code.
satisfies() {
  # Single-quoted on purpose below: this is JS source, handed to node as an argument,
  # not a string for bash to expand.
  # shellcheck disable=SC2016
  node --input-type=commonjs -e '
    const [version, range] = process.argv.slice(1);
    const toTuple = (s) => s.split(".").map(Number);
    const cmp = (a, b) => { for (let i = 0; i < 3; i++) { if (a[i] !== b[i]) return a[i] - b[i]; } return 0; };
    const v = toTuple(version);
    const clauses = range.split("||").map((s) => s.trim());
    for (const clause of clauses) {
      let ok = true;
      for (const term of clause.split(/\s+/).filter(Boolean)) {
        let m;
        if ((m = term.match(/^\^(\d+)\.(\d+)\.(\d+)$/))) {
          const base = [+m[1], +m[2], +m[3]];
          if (!(cmp(v, base) >= 0 && v[0] === base[0])) { ok = false; break; }
        } else if ((m = term.match(/^>=(\d+)\.(\d+)\.(\d+)$/))) {
          if (!(cmp(v, [+m[1], +m[2], +m[3]]) >= 0)) { ok = false; break; }
        } else if ((m = term.match(/^(\d+)\.(\d+)\.(\d+)$/))) {
          if (cmp(v, [+m[1], +m[2], +m[3]]) !== 0) { ok = false; break; }
        } else {
          console.error(`unsupported range term: ${term}`);
          process.exit(2);
        }
      }
      if (ok) { process.exit(0); }
    }
    process.exit(1);
  ' -- "$1" "$2"
}

resolve_npm() {
  local node_dockerfile current_node doc v range
  node_dockerfile="$root/images/node/Dockerfile"
  current_node="$(sed -n 's/^ARG NODE_VERSION=//p' "$node_dockerfile")"
  [ -n "$current_node" ] || { echo "::error::npm: could not read NODE_VERSION from $node_dockerfile" >&2; exit 1; }

  doc="$(curl -fsSL https://registry.npmjs.org/npm)"
  while IFS= read -r v; do
    range="$(printf '%s' "$doc" | jq -r --arg v "$v" '.versions[$v].engines.node // ""')"
    [ -n "$range" ] || continue
    rc=0
    satisfies "$current_node" "$range" || rc=$?
    if [ "$rc" -eq 2 ]; then
      # $range is registry-controlled; strip CR/LF before logging it so it cannot
      # inject a second workflow-command line into the Actions log.
      echo "::error::npm: unsupported engines.node range '$(printf '%s' "$range" | tr -d '\r\n')' for $v" >&2
      exit 1
    elif [ "$rc" -eq 0 ]; then
      NEW_VERSION="$v"
      NEW_CHECKSUM="$(printf '%s' "$doc" | jq -r --arg v "$v" '.versions[$v].dist.integrity // ""')"
      RELEASE_URL="https://www.npmjs.com/package/npm/v/${v}"
      CHECKSUM_URL="https://registry.npmjs.org/npm"
      return 0
    fi
  done <<< "$(printf '%s' "$doc" | jq -r '.versions | keys[]' | grep -vE -- '-' | sort -t. -k1,1nr -k2,2nr -k3,3nr)"

  echo "::error::npm: no release satisfies engines.node for the current pin ${current_node}" >&2
  exit 1
}

case "$tool" in
  gh)     dockerfile_dir=base; ver_arg=GH_VERSION;     sha_arg=GH_SHA256;     resolve_gh ;;
  yq)     dockerfile_dir=base; ver_arg=YQ_VERSION;     sha_arg=YQ_SHA256;     resolve_yq ;;
  uv)     dockerfile_dir=base; ver_arg=UV_VERSION;     sha_arg=UV_SHA256;     resolve_uv ;;
  tofu)   dockerfile_dir=tofu; ver_arg=TOFU_VERSION;   sha_arg=TOFU_SHA256;   resolve_tofu ;;
  tflint) dockerfile_dir=tofu; ver_arg=TFLINT_VERSION; sha_arg=TFLINT_SHA256; resolve_tflint ;;
  node)   dockerfile_dir=node; ver_arg=NODE_VERSION;   sha_arg=NODE_SHA256;   resolve_node ;;
  npm)    dockerfile_dir=node; ver_arg=NPM_VERSION;    sha_arg=NPM_INTEGRITY; resolve_npm ;;
  betterleaks) dockerfile_dir=base; ver_arg=BETTERLEAKS_VERSION; sha_arg=BETTERLEAKS_SHA256; resolve_betterleaks ;;
  *) echo "::error::unknown tool '$tool'" >&2; exit 1 ;;
esac

if [ -z "$NEW_VERSION" ] || [ -z "$NEW_CHECKSUM" ]; then
  echo "::error::$tool: could not resolve a new version or checksum" >&2
  exit 1
fi

# NEW_VERSION and NEW_CHECKSUM are upstream-controlled (a release tag, a checksum
# file's content, or the npm registry's integrity field) and end up in a sed/awk
# program, a git branch name, a commit message and a PR title/body. Reject anything
# that isn't the exact shape expected BEFORE any of that -- never a loose sanity check
# a crafted tag or checksum line could still slip through.
version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
[ "$tool" != betterleaks ] || version_re='^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'
if ! [[ "$NEW_VERSION" =~ $version_re ]]; then
  echo "::error::$tool: resolved version is not a plain X.Y.Z (or, for betterleaks, X.Y.Z-rc.N): rejecting" >&2
  exit 1
fi
if [ "$tool" = npm ]; then
  if ! [[ "$NEW_CHECKSUM" =~ ^sha512-[A-Za-z0-9+/]+=*$ ]]; then
    echo "::error::$tool: resolved integrity is not a well-formed sha512-... value: rejecting" >&2
    exit 1
  fi
elif ! [[ "$NEW_CHECKSUM" =~ ^[0-9a-f]{64}$ ]]; then
  echo "::error::$tool: resolved checksum is not a 64-char lowercase hex sha256: rejecting" >&2
  exit 1
fi

dockerfile="$root/images/${dockerfile_dir}/Dockerfile"
current_version="$(sed -n "s/^ARG ${ver_arg}=//p" "$dockerfile")"
[ -n "$current_version" ] || { echo "::error::could not read $ver_arg from $dockerfile" >&2; exit 1; }

if [ "$NEW_VERSION" = "$current_version" ]; then
  echo "$tool: up to date at $current_version"
  exit 0
fi

# NEW_VERSION is validated above; current_version is read from this repo's own
# Dockerfile, so ver_key tells newer from older. Refuse a downgrade
# rather than opening a PR for one -- "latest" moving backwards (a yanked release, a
# tag deleted and reused) is a signal to fail closed on, not to propose as this
# week's bump.
if [[ "$(ver_key "$NEW_VERSION")" < "$(ver_key "$current_version")" ]]; then
  echo "::error::$tool: resolved $NEW_VERSION is older than the current pin $current_version -- refusing to open a downgrade PR" >&2
  exit 1
fi

branch="bump/${tool}-${NEW_VERSION}"
open_count="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq 'length')"
if [ "$open_count" != "0" ]; then
  echo "$tool: PR already open on $branch, nothing to do"
  exit 0
fi

# A human who closes a bump PR unmerged and leaves its branch has declined that version. Cutting
# a fresh branch would be rejected as non-fast-forward against it on every weekly run (#86), so
# skip with a warning, and never force-push or delete the branch. `gh auth setup-git` only wires a
# credential helper (the checkout does not persist one), so ls-remote also works on a private repo.
gh auth setup-git

# ls-remote's pattern matches the END of a ref name (x/refs/heads/bump/... would match), so read
# its output and compare the ref exactly. Any ls-remote failure (network, auth) is an error, not
# a reason to proceed or to skip.
rc=0
remote_refs="$(git -C "$root" ls-remote origin "refs/heads/$branch")" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "::error::$tool: could not check origin for $branch (git ls-remote exit $rc)" >&2
  exit 1
fi
if printf '%s\n' "$remote_refs" | BUMP_REF="refs/heads/$branch" awk '$2 == ENVIRON["BUMP_REF"] { found = 1 } END { exit !found }'; then
  # A branch with no PR at all is an orphan (the push worked, `gh pr create` failed), not a
  # human's decline: fail loudly, as the rejected push used to, rather than hide the version.
  any_count="$(gh pr list --repo "$repo" --head "$branch" --state all --json number --jq 'length')"
  if [ "$any_count" = "0" ]; then
    echo "::error::$tool: $branch exists on origin but has no PR (a failed run's leftover?): open its PR by hand, or delete the branch" >&2
    exit 1
  fi
  echo "::warning::$tool: $branch already exists on origin and its PR is not open (closed unmerged?), skipping; delete the branch to propose this version again"
  exit 0
fi

git -C "$root" config user.name "${APP_SLUG:?APP_SLUG must be set}[bot]"
git -C "$root" config user.email "${BOT_USER_ID:?BOT_USER_ID must be set}+${APP_SLUG}[bot]@users.noreply.github.com"
git -C "$root" switch -c "$branch"

# The two values are validated above, but rewrite without a sed/awk program built
# from interpolated strings anyway. The value travels through ENVIRON, not -v: awk's
# -v assignment runs C-style backslash-escape processing on its value (so a
# validated, backslash-free value could still, through -v, turn a literal `\n` into a
# real newline and inject a second Dockerfile line) -- ENVIRON takes it verbatim,
# with no escape processing at all.
set_arg() { # set_arg <file> <ARG name> <value>
  BUMP_ARG_VAL="$3" awk -v name="$2" '
    $0 ~ ("^ARG " name "=") { print "ARG " name "=" ENVIRON["BUMP_ARG_VAL"]; next }
    { print }
  ' "$1" > "$1.new" && mv "$1.new" "$1"
}
set_arg "$dockerfile" "$ver_arg" "$NEW_VERSION"
set_arg "$dockerfile" "$sha_arg" "$NEW_CHECKSUM"

git -C "$root" add "$dockerfile"
git -C "$root" commit -m "build(images): bump $tool $current_version -> $NEW_VERSION"
git -C "$root" push -u origin "$branch"

body="$(cat <<EOF
Opened by \`bump-binaries.yml\` (#29): $tool $current_version -> $NEW_VERSION.

The checksum above was taken from that release's own published checksum file (or, for
npm, the registry's \`integrity\` field) -- never from hashing the download.

Release notes: $RELEASE_URL
Checksum source: $CHECKSUM_URL

This still needs a human review before merge: read the release notes above (and the
diff since $current_version yourself -- this PR links the release, not a compare). For
Node, also open the matching CI-pin PRs in every consuming repo; for OpenTofu each
consumer moves its tofu_version in the PR that takes the new image digest. The
ordinary gates (hadolint, Trivy, the smoke test, the template test, and
architect-review because \`images/\` is a code_path) run on this PR like any other.
EOF
)"
gh pr create --repo "$repo" --head "$branch" --base main \
  --title "build(images): bump $tool $current_version -> $NEW_VERSION" \
  --body "$body"
