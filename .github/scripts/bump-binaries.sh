#!/usr/bin/env bash
# Resolves the newest release for one ARG-pinned binary, per the line policy from #29:
# gh, yq, uv, tofu and tflint take the newest stable release; node tracks the current
# LTS line (nodejs.org flips a release's own `lts` field once its line enters LTS, so
# this needs no hardcoded major); npm takes the newest release whose `engines.node`
# is satisfied by the Dockerfile's CURRENT node pin. The checksum always comes from
# that release's own published file or the registry's `integrity` field -- never from
# hashing the download -- so the Dockerfiles' "no trust-on-first-use" rule holds here
# too. On a version bump it rewrites the Dockerfile's ARG lines, opens a
# bump/<tool>-<version> branch and PR (skipped if that PR is already open), and leaves
# everything else -- the surrounding comments, consumer CI pins, .trivyignore.yaml --
# for the human review the PR goes through.
#
# Usage: bump-binaries.sh <gh|yq|uv|tofu|tflint|node|npm>
# Env:   REPO (owner/repo), GH_TOKEN (gh, authenticated for push+PR), APP_SLUG,
#        APP_ID (the commit's bot identity)
set -euo pipefail

tool="${1:?usage: bump-binaries.sh <gh|yq|uv|tofu|tflint|node|npm>}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
repo="${REPO:?REPO must be set, e.g. 603-Identity/devcontainers}"

NEW_VERSION=""
NEW_CHECKSUM=""
RELEASE_URL=""

# sha256_line <url> <asset-filename> -> the sha256 field of a "sha256  filename" line.
# gh, tflint, tofu and uv all publish this exact format (verified against gh, tflint,
# tofu and uv's own checksum files; a format change elsewhere fails closed below).
sha256_line() {
  curl -fsSL "$1" | awk -v f="$2" '$2 == f { print $1; exit }'
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
  NEW_CHECKSUM="$(sha256_line \
    "https://github.com/cli/cli/releases/download/${tag}/gh_${NEW_VERSION}_checksums.txt" \
    "gh_${NEW_VERSION}_linux_amd64.tar.gz")"
}

resolve_yq() {
  local tag order_url field
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release mikefarah/yq)"
  NEW_VERSION="${tag#v}"
  # The checksums file lists one hash per algorithm, in the order this sidecar file
  # names them (field 1 is the asset name) -- read the order instead of hardcoding a
  # column, so an upstream reshuffle fails closed on a missing SHA-256 line rather than
  # silently reading the wrong hash.
  order_url="https://github.com/mikefarah/yq/releases/download/${tag}/checksums_hashes_order"
  field="$(curl -fsSL "$order_url" | grep -n '^SHA-256$' | cut -d: -f1)"
  [ -n "$field" ] || { echo "::error::yq: SHA-256 not found in $order_url" >&2; exit 1; }
  field=$((field + 1))
  NEW_CHECKSUM="$(curl -fsSL "https://github.com/mikefarah/yq/releases/download/${tag}/checksums" \
    | awk -v f="yq_linux_amd64.tar.gz" -v col="$field" '$1 == f { print $col; exit }')"
}

resolve_uv() {
  IFS=$'\t' read -r NEW_VERSION RELEASE_URL <<< "$(latest_release astral-sh/uv)"
  NEW_CHECKSUM="$(sha256_line \
    "https://github.com/astral-sh/uv/releases/download/${NEW_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256" \
    "uv-x86_64-unknown-linux-gnu.tar.gz")"
}

resolve_tofu() {
  local tag
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release opentofu/opentofu)"
  NEW_VERSION="${tag#v}"
  NEW_CHECKSUM="$(sha256_line \
    "https://github.com/opentofu/opentofu/releases/download/${tag}/tofu_${NEW_VERSION}_SHA256SUMS" \
    "tofu_${NEW_VERSION}_linux_amd64.zip")"
}

resolve_tflint() {
  local tag
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release terraform-linters/tflint)"
  NEW_VERSION="${tag#v}"
  NEW_CHECKSUM="$(sha256_line \
    "https://github.com/terraform-linters/tflint/releases/download/${tag}/checksums.txt" \
    "tflint_linux_amd64.zip")"
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
  NEW_CHECKSUM="$(sha256_line \
    "https://nodejs.org/dist/v${NEW_VERSION}/SHASUMS256.txt" \
    "node-v${NEW_VERSION}-linux-x64.tar.xz")"
  RELEASE_URL="$(gh api "repos/nodejs/node/releases/tags/v${NEW_VERSION}" --jq '.html_url' 2>/dev/null \
    || echo "https://github.com/nodejs/node/blob/main/doc/changelogs/CHANGELOG_V${major}.md")"
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
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::$tool: resolved version is not a plain X.Y.Z: rejecting" >&2
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

# NEW_VERSION is validated X.Y.Z above; current_version is read from this repo's own
# Dockerfile, so a plain version-sort tells newer from older. Refuse a downgrade
# rather than opening a PR for one -- "latest" moving backwards (a yanked release, a
# tag deleted and reused) is a signal to fail closed on, not to propose as this
# week's bump.
if [ "$(printf '%s\n%s\n' "$NEW_VERSION" "$current_version" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" != "$NEW_VERSION" ]; then
  echo "::error::$tool: resolved $NEW_VERSION is older than the current pin $current_version -- refusing to open a downgrade PR" >&2
  exit 1
fi

branch="bump/${tool}-${NEW_VERSION}"
open_count="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq 'length')"
if [ "$open_count" != "0" ]; then
  echo "$tool: PR already open on $branch, nothing to do"
  exit 0
fi

gh auth setup-git

git -C "$root" config user.name "${APP_SLUG:?APP_SLUG must be set}[bot]"
git -C "$root" config user.email "${APP_ID:?APP_ID must be set}+${APP_SLUG}[bot]@users.noreply.github.com"
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

This still needs a human review before merge: read the release notes above (and the
diff since $current_version yourself -- this PR links the release, not a compare), and
-- for OpenTofu or Node -- open the matching CI-pin PRs in every consuming repo. The
ordinary gates (hadolint, Trivy, the smoke test, the template test, and
architect-review because \`images/\` is a code_path) run on this PR like any other.
EOF
)"
gh pr create --repo "$repo" --head "$branch" --base main \
  --title "build(images): bump $tool $current_version -> $NEW_VERSION" \
  --body "$body"
