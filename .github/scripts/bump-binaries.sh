#!/usr/bin/env bash
# Resolves the newest release for each ARG-pinned binary, per the line policy from #29:
# gh, yq, uv, tofu and tflint take the newest stable release; node tracks the current
# LTS line (nodejs.org flips a release's own `lts` field once its line enters LTS, so
# this needs no hardcoded major); npm takes the newest release whose `engines.node`
# is satisfied by the Dockerfile's CURRENT node pin. The checksum always comes from
# that release's own published file or the registry's `integrity` field -- never from
# hashing the download -- so the Dockerfiles' "no trust-on-first-use" rule holds here
# too (tofu's and betterleaks's only after a cosign check, see below).
#
# One run is one grouped PR (#715). The tools run in a fixed order, gh, yq, uv, tofu, tflint, node,
# npm, betterleaks, python, on one working tree; each leg that finds a newer version rewrites its
# Dockerfile's ARG lines and commits them as its own commit on one branch, bump/weekly-<YYYYMMDD> (the
# run's UTC date). The run then pushes that branch once and opens one PR whose body records each
# moved tool, and leaves everything else -- the surrounding comments, consumer CI pins,
# .trivyignore.yaml -- for the human review the PR goes through. node runs before npm, and npm reads
# the node pin from the working tree, so when node moved the pin in this run, npm resolves against the
# new pin. A leg that fails (a word from a fixed vocabulary names its step) leaves its Dockerfile as the
# last commit had it and does not stop the others; the PR body names it, and the run exits 1 after the
# PR is opened. A run in which nothing moved cuts no branch and opens nothing.
#
# A bump/<tool>-<version> branch on origin (python: bump/python-<version>-<build>) declines that
# version, whatever the state of any PR on it, e.g. after a human closed a PR unmerged or pushed such a
# branch to say no: the leg is skipped with a warning, and every declined tool is listed in the job
# summary and the PR body. The branch is never deleted. A new weekly PR closes the older open weekly PRs
# this App opened (they are superseded; their branches stay). Today's weekly branch already on origin
# fails a run that has something to propose, and pushes nothing.
#
# python is the exception to the rule: it takes the newest build of the image's pinned
# major.minor, a new build tag alone counting as a bump (all three of its ARGs are rewritten).
#
# betterleaks (#190) is the exception to "stable only", but only while its pin is itself a release
# candidate (X.Y.Z-rc.N): then it takes the highest-versioned release among any GA release and the
# release candidates of the pin's own X.Y.Z (so it can reach 2.0.0 GA, and never follows a later
# line's rcs past it, #304). Once the pin is on a GA release it takes stable releases only, like every
# other tool (#208). Either way it takes the checksum only after cosign verifies the release's
# sigstore bundle for its checksums.txt against the pinned signer identity.
#
# tofu (#717) takes its checksum only after cosign verifies the keyless signature on the release's
# tofu_X.Y.Z_SHA256SUMS (its .sig and .pem) against the pinned signer identity and the release tag's
# commit, and reads the sha256 only from the copy that verified. A failed or missing verification is an
# error, never a fallback. The verification runs on every tofu run, an "up to date" one included.
#
# python (#561) stays on the pinned major.minor of images/base/Dockerfile (DEVC-D11): it lists the
# five most recent astral-sh/python-build-standalone releases in ONE call (the default page size
# returns HTTP 504), skips drafts, prereleases and any tag that is not exactly eight digits, tries the
# rest newest tag first, and takes the first whose own SHA256SUMS lists exactly one
# cpython-X.Y.N+TAG-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz for the pinned X.Y. A new
# build tag with the same CPython patch counts as a bump, so it rewrites all three ARGs
# (PYTHON_VERSION, PYTHON_BUILD, PYTHON_SHA256) and its decline branch is bump/python-<version>-<build>. A
# candidate whose SHA256SUMS cannot be read is skipped with a warning and the next one is tried; once
# one has failed, no candidate at or below the pin's build is fetched, and a run left with no usable
# candidate fails with a count of the unreadable ones. A move to another minor stays a hand re-pin
# (tests/smoke.sh hardcodes the major.minor).
#
# npm also looks for the node image's bundled-package swap block: a `RUN` that defines a shell
# function `swap() {` and calls it once per package, as a line whose first field is exactly `swap`
# and whose second is the package name (`swap undici "${UNDICI_VERSION}" ...`). The block fails the
# build by design once npm bundles that package at or above the swap pin, so when the Dockerfile has
# call lines the PR body names the packages and the removal a human pushes if the build goes red. It
# only reads the call lines' names (each must match ^[a-z0-9][a-z0-9._-]*$, or the npm leg changes
# nothing); it reads no npm tarball, parses no pins and compares no versions. A definition
# must be written `swap() {`, and a call chained after `&&` is not detected.
#
# Every resolver sets CHECKSUM_URL, the URL its checksum was actually read from, next to
# RELEASE_URL; the bump PR body cites both (#85).
#
# Usage: bump-binaries.sh [<gh|yq|uv|tofu|tflint|node|npm|betterleaks|python>...]
#        With no argument it runs all nine tools; with names it runs only those, always in the fixed order.
# Env:   REPO (owner/repo), GH_TOKEN (gh, authenticated for push+PR, and to close and comment on the
#        superseded PRs), APP_SLUG, BOT_USER_ID (the bot's user id, for the commit's noreply email),
#        COSIGN_OUTCOME and COSIGN_BIN (betterleaks and tofu: the cosign install step's outcome, which must
#        be `success`, and the absolute path of the pinned cosign binary, the only way cosign is run)
# Exit:  1, with nothing pushed or opened: an unknown tool name, a run date that is not eight digits, a
#        failed `gh pr list` or one returning 500 or more records, an ls-remote failure on the weekly
#        branch check, today's weekly branch already on origin, an open weekly PR not older than today's, a
#        failed push. 1 after the fact: a failed `gh pr create` (nothing is closed), any failed close (after
#        every close was attempted), any failed leg (after the PR, if any leg moved, is opened and the
#        closes are done). 0 otherwise, a run where nothing moved and nothing failed included.
set -euo pipefail

ALL_TOOLS=(gh yq uv tofu tflint node npm betterleaks python)
requested=("$@")
root="$(cd "$(dirname "$0")/../.." && pwd)"
repo="${REPO:?REPO must be set, e.g. 603-Identity/devcontainers}"

NEW_VERSION=""
NEW_CHECKSUM=""
RELEASE_URL=""
CHECKSUM_URL=""
SIGNATURE_NOTE=""   # betterleaks and tofu: the PR body's line saying the checksum file's signature was verified
NEW_BUILD=""   # python only: the python-build-standalone release tag
PIN_BUILD=""   # python only: the Dockerfile's current PYTHON_BUILD
dockerfile_dir="" ver_arg="" sha_arg="" build_arg=""   # set by dispatch, one leg at a time
STEP_FILE=""   # a leg's file for the step word of the step it is in

# step <word>: record which step of the leg is running, from a fixed vocabulary written in this script
# (resolve, cosign, version shape, pin read, checksum shape, downgrade, decline check, swap names,
# rewrite, commit). A failed leg is reported by this word, never by upstream text.
step() { [ -z "$STEP_FILE" ] || printf '%s' "$1" > "$STEP_FILE"; }

# need_cosign <tool>: cosign runs only by the absolute path in COSIGN_BIN, never by a PATH lookup, and
# only when the workflow's install step succeeded.
need_cosign() {
  step cosign
  if [ "${COSIGN_OUTCOME:-}" != success ] || [[ "${COSIGN_BIN:-}" != /* ]] || [ ! -f "${COSIGN_BIN:-}" ] || [ ! -x "${COSIGN_BIN:-}" ]; then
    echo "::error::$1: cosign is required to verify the release signature (COSIGN_OUTCOME must be success and COSIGN_BIN an executable file)" >&2
    exit 1
  fi
}

# sha256_line <url> <asset-filename> -> the sha256 field of a "sha256  filename" line.
# gh, tflint, tofu and uv all publish this exact format (verified against gh, tflint,
# tofu and uv's own checksum files; a format change elsewhere fails closed below). tofu no longer
# calls this: it reads its sha256 from the SHA256SUMS copy cosign verified (#717).
#
# The file is read into a variable first, never piped into an awk that `exit`s on the first
# match: awk closing the pipe while curl is still writing makes curl fail with exit 23 under
# `pipefail`, and whether it does depends on the file's size and timing (first seen on a yq
# run, #102). Every caller runs this inside `$( )`, where `set -e` does not reach, so a failed
# curl must `return 1` here: without it a transfer that dies after the wanted line arrived
# would be accepted.
sha256_line() {
  local body
  body="$(curl -fsSL "$1")" || return 1
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
  local tag order_url sums_url field sums order lines n_sha
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release mikefarah/yq)"
  NEW_VERSION="${tag#v}"
  # The checksums file lists one hash per algorithm, in the order this sidecar file
  # names them (field 1 is the asset name) -- read the order instead of hardcoding a
  # column, so an upstream reshuffle fails closed on a missing SHA-256 line rather than
  # silently reading the wrong hash. The asset is the raw binary, not the tarball:
  # images/base/Dockerfile downloads yq_linux_amd64 and checks it against YQ_SHA256 (#164).
  order_url="https://github.com/mikefarah/yq/releases/download/${tag}/checksums_hashes_order"
  # Read into a variable first, and tolerate grep's no-match exit: under pipefail a missing
  # SHA-256 line would otherwise kill the script before the message below (#325). A curl
  # failure still exits here: keep this a plain assignment with no `|| true`, so a failed
  # download is not reported as a missing SHA-256 line (pinned in tools/tests/bump-asset-names-test.sh, #378).
  order="$(curl -fsSL "$order_url")"
  lines="$(grep -n '^SHA-256$' <<< "$order" | cut -d: -f1 || true)"
  [ -n "$lines" ] || { echo "::error::yq: SHA-256 not found in $order_url" >&2; exit 1; }
  # Exactly one SHA-256 line, or fail closed rather than guess a column (#379).
  n_sha="$(wc -l <<< "$lines")"
  n_sha="${n_sha//[[:space:]]/}"
  [ "$n_sha" -eq 1 ] || { echo "::error::yq: SHA-256 listed ${n_sha} times in $order_url, expected exactly one" >&2; exit 1; }
  field=$((lines + 1))
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

# tofu (#717): the SHA256SUMS file is taken ONLY after cosign verifies its keyless signature (the
# .sig and .pem beside it) against the signer identity of the release workflow on the tag's
# vMAJOR.MINOR branch, the GitHub Actions issuer, the repository, and the tag's own commit. The tag
# and the commit are shape-checked before any URL or cosign flag is built from them (cosign treats an
# empty --certificate-github-workflow-sha as unset). A failed or missing verification is an error,
# never a fallback to the unsigned file, and the sha256 is read from the verified copy, never from a
# second fetch. Runs cosign only by the path in COSIGN_BIN (see need_cosign). The errors name no upstream
# value but the shape-checked version.
resolve_tofu() {
  local tag ver sha dir base identity branch
  IFS=$'\t' read -r tag RELEASE_URL <<< "$(latest_release opentofu/opentofu)"
  step "version shape"
  [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "::error::tofu: the latest release tag is not exactly vX.Y.Z: rejecting" >&2; exit 1; }
  ver="${tag#v}"
  branch="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  need_cosign tofu
  sha="$(gh api "repos/opentofu/opentofu/commits/${tag}" --jq .sha)" || { echo "::error::tofu: could not resolve the release tag's commit" >&2; exit 1; }
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::tofu: the release tag's commit is not a 40-char lowercase hex sha: rejecting" >&2; exit 1; }

  NEW_VERSION="$ver"
  step resolve
  dir="$(mktemp -d)"
  base="https://github.com/opentofu/opentofu/releases/download/${tag}/tofu_${ver}_SHA256SUMS"
  CHECKSUM_URL="$base"
  curl -fsSL "$base" -o "$dir/SHA256SUMS"
  curl -fsSL "${base}.sig" -o "$dir/SHA256SUMS.sig"
  curl -fsSL "${base}.pem" -o "$dir/SHA256SUMS.pem"
  identity="https://github.com/opentofu/opentofu/.github/workflows/release.yml@refs/heads/${branch}"
  step cosign
  if ! "$COSIGN_BIN" verify-blob --certificate "$dir/SHA256SUMS.pem" --signature "$dir/SHA256SUMS.sig" \
      --certificate-identity "$identity" --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
      --certificate-github-workflow-repository opentofu/opentofu \
      --certificate-github-workflow-sha "$sha" \
      "$dir/SHA256SUMS" >&2; then
    echo "::error::tofu: the signature on v${ver}'s SHA256SUMS did not verify: refusing to take its checksum" >&2
    exit 1
  fi
  SIGNATURE_NOTE="The checksum file's cosign signature was verified at resolution time against the signer identity \`${identity}\` and the tag's commit \`${sha}\`."
  NEW_CHECKSUM="$(awk -v f="tofu_${ver}_linux_amd64.zip" '$2 == f { print $1; exit }' "$dir/SHA256SUMS")"
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
# counting only GA releases and rcs of the pin's own X.Y.Z (a newer line's rc would keep the pin
# on the rc track and never land on GA, #304), and never a tag that is not exactly vX.Y.Z or
# vX.Y.Z-rc.N. Once the pin is a GA release, consider only exactly-vX.Y.Z tags, so the job never
# proposes the next rc (#208).
# The pin is read from the Dockerfile here, ahead of the generic read further down.
# Its checksums.txt is taken ONLY after the release's sigstore bundle verifies with the pinned signer identity for that exact tag
# (the release workflow, run at that tag, via GitHub Actions OIDC); a failed or missing
# verification is an error, never a fallback to the unsigned file. Runs cosign only by the path in
# COSIGN_BIN (see need_cosign).
BETTERLEAKS_ISSUER="https://token.actions.githubusercontent.com"
resolve_betterleaks() {
  local best="" best_key="" best_url="" tag url key dir identity pin pin_core="" tag_re
  step "pin read"
  pin="$(sed -n 's/^ARG BETTERLEAKS_VERSION=//p' "$root/images/base/Dockerfile")"
  [ -n "$pin" ] || { echo "::error::betterleaks: could not read BETTERLEAKS_VERSION from $root/images/base/Dockerfile" >&2; exit 1; }
  step resolve
  tag_re='^v[0-9]+\.[0-9]+\.[0-9]+$'
  if [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then
    tag_re='^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'
    pin_core="${pin%%-*}"
  fi
  while IFS=$'\t' read -r tag url; do
    [[ "$tag" =~ $tag_re ]] || continue
    # In rc mode an rc counts only on the pin's own X.Y.Z; GA releases always count.
    if [[ -n "$pin_core" && "$tag" == *-rc.* && "${tag#v}" != "$pin_core"-rc.* ]]; then continue; fi
    key="$(ver_key "${tag#v}")"
    if [ -z "$best" ] || [[ "$key" > "$best_key" ]]; then best="$tag"; best_key="$key"; best_url="$url"; fi
  done < <(gh api "repos/betterleaks/betterleaks/releases" --paginate --jq '.[] | select(.draft | not) | [.tag_name, .html_url] | @tsv')
  if [ -z "$best" ]; then
    if [ -n "$pin_core" ]; then
      # rc mode: tag_re alone also matches the rc tags of a later line that were skipped above.
      echo "::error::betterleaks: no release matching ${tag_re} (pin $pin): only GA releases or ${pin_core}-rc.N count" >&2
    else
      echo "::error::betterleaks: no release matching ${tag_re} (pin $pin)" >&2
    fi
    exit 1
  fi
  need_cosign betterleaks

  step resolve
  NEW_VERSION="${best#v}"
  RELEASE_URL="$best_url"
  dir="$(mktemp -d)"
  CHECKSUM_URL="https://github.com/betterleaks/betterleaks/releases/download/${best}/checksums.txt"
  curl -fsSL "$CHECKSUM_URL" -o "$dir/checksums.txt"
  curl -fsSL "https://github.com/betterleaks/betterleaks/releases/download/${best}/checksums.txt.sigstore.json" -o "$dir/checksums.txt.sigstore.json"
  identity="https://github.com/betterleaks/betterleaks/.github/workflows/release.yml@refs/tags/${best}"
  step cosign
  if ! "$COSIGN_BIN" verify-blob --bundle "$dir/checksums.txt.sigstore.json" \
      --certificate-identity "$identity" --certificate-oidc-issuer "$BETTERLEAKS_ISSUER" \
      "$dir/checksums.txt" >&2; then
    echo "::error::betterleaks: the signature on ${best}'s checksums.txt did not verify against ${identity}: refusing to take its checksum" >&2
    exit 1
  fi
  SIGNATURE_NOTE="The checksum file's cosign signature was verified at resolution time against the signer identity \`${identity}\`."
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
  step "pin read"
  node_dockerfile="$root/images/node/Dockerfile"
  current_node="$(sed -n 's/^ARG NODE_VERSION=//p' "$node_dockerfile")"
  [ -n "$current_node" ] || { echo "::error::npm: could not read NODE_VERSION from $node_dockerfile" >&2; exit 1; }
  step resolve

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

# python-build-standalone (#561). The pin (PYTHON_VERSION, PYTHON_BUILD) is read from the Dockerfile
# and checked before any network call; every value taken from upstream is checked by shape again
# before anything is written. Errors and warnings name only repo-side values (the pinned minor, a
# count), never an upstream tag or a SHA256SUMS line, so upstream text cannot reach the Actions log.
PBS_REPO="astral-sh/python-build-standalone"
resolve_python() {
  local df="$root/images/base/Dockerfile" pin_ver minor listing tag url cands sums_url sums matches n failed=0
  step "pin read"
  pin_ver="$(sed -n 's/^ARG PYTHON_VERSION=//p' "$df")"
  PIN_BUILD="$(sed -n 's/^ARG PYTHON_BUILD=//p' "$df")"
  [[ "$pin_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "::error::python: PYTHON_VERSION in $df is missing or not a plain X.Y.Z" >&2; exit 1; }
  [[ "$PIN_BUILD" =~ ^[0-9]{8}$ ]] \
    || { echo "::error::python: PYTHON_BUILD in $df is missing or not exactly eight digits" >&2; exit 1; }
  minor="${pin_ver%.*}"
  step resolve

  listing="$(gh api "repos/$PBS_REPO/releases?per_page=5" \
    --jq '.[] | select((.draft | not) and (.prerelease | not)) | [.tag_name, .html_url] | @tsv')"
  # Keep only exactly-eight-digit tags, newest first by tag (the API's order is not relied on).
  cands=""
  while IFS=$'\t' read -r tag url; do
    [[ "$tag" =~ ^[0-9]{8}$ ]] || continue
    cands+="${tag}"$'\t'"${url}"$'\n'
  done <<< "$listing"
  cands="$(printf '%s' "$cands" | sort -r)"

  while IFS=$'\t' read -r tag url; do
    [ -n "$tag" ] || continue
    # After a failed fetch never reach for the pin's own release or an older one (string compare
    # of equal-length digit tags): that could only end on a downgrade or the up-to-date message.
    if [ "$failed" -gt 0 ] && ! [[ "$tag" > "$PIN_BUILD" ]]; then break; fi
    sums_url="https://github.com/$PBS_REPO/releases/download/${tag}/SHA256SUMS"
    # Read into a variable first (see sha256_line). A failed transfer skips this candidate with a
    # warning and tries the next, so one unreadable release does not fail the whole leg.
    sums="$(curl -fsSL "$sums_url")" || {
      echo "::warning::python: could not read the SHA256SUMS of a candidate release for $minor, trying the next"
      failed=$((failed + 1))
      continue
    }
    # A literal comparison, not a regex: fixed prefix, digits-only patch, fixed suffix. The
    # values travel through ENVIRON. Prints "<sha256> <X.Y.N>" per matching line.
    matches="$(PBS_PFX="cpython-${minor}." PBS_SFX="+${tag}-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz" awk '
      BEGIN { pfx = ENVIRON["PBS_PFX"]; sfx = ENVIRON["PBS_SFX"]; lp = length(pfx); ls = length(sfx) }
      NF == 2 && length($2) > lp + ls && substr($2, 1, lp) == pfx && substr($2, length($2) - ls + 1) == sfx {
        patch = substr($2, lp + 1, length($2) - lp - ls)
        if (patch ~ /^[0-9]+$/) print $1, substr(pfx, 9) patch
      }' <<< "$sums")"
    n="$(printf '%s' "$matches" | awk 'END { print NR }')"
    if [ "$n" -gt 1 ]; then
      echo "::error::python: SHA256SUMS of a candidate release lists $n assets for $minor, expected one" >&2
      exit 1
    fi
    if [ "$n" -eq 1 ]; then
      read -r NEW_CHECKSUM NEW_VERSION <<< "$matches"
      NEW_BUILD="$tag"
      RELEASE_URL="$url"
      CHECKSUM_URL="$sums_url"
      return 0
    fi
  done <<< "$cands"

  if [ "$failed" -gt 0 ]; then
    echo "::error::python: could not read the SHA256SUMS of $failed candidate release(s) for $minor, and no readable release above the pin carries the asset" >&2
    exit 1
  fi
  echo "::error::python: none of the listed releases carries a $minor install_only_stripped linux x86_64 asset" >&2
  exit 1
}

# dispatch <tool>: sets the tool's Dockerfile and ARG names, then runs its resolver. The case
# lines keep one shape (two spaces, the tool, `)`, then `dockerfile_dir=`): bump-asset-names-test.sh
# reads the tool list from them.
dispatch() {
case "$1" in
  gh)     dockerfile_dir=base; ver_arg=GH_VERSION;     sha_arg=GH_SHA256;     resolve_gh ;;
  yq)     dockerfile_dir=base; ver_arg=YQ_VERSION;     sha_arg=YQ_SHA256;     resolve_yq ;;
  uv)     dockerfile_dir=base; ver_arg=UV_VERSION;     sha_arg=UV_SHA256;     resolve_uv ;;
  tofu)   dockerfile_dir=tofu; ver_arg=TOFU_VERSION;   sha_arg=TOFU_SHA256;   resolve_tofu ;;
  tflint) dockerfile_dir=tofu; ver_arg=TFLINT_VERSION; sha_arg=TFLINT_SHA256; resolve_tflint ;;
  node)   dockerfile_dir=node; ver_arg=NODE_VERSION;   sha_arg=NODE_SHA256;   resolve_node ;;
  npm)    dockerfile_dir=node; ver_arg=NPM_VERSION;    sha_arg=NPM_INTEGRITY; resolve_npm ;;
  betterleaks) dockerfile_dir=base; ver_arg=BETTERLEAKS_VERSION; sha_arg=BETTERLEAKS_SHA256; resolve_betterleaks ;;
  python) dockerfile_dir=base; ver_arg=PYTHON_VERSION; sha_arg=PYTHON_SHA256; build_arg=PYTHON_BUILD; resolve_python ;;
  *) echo "::error::unknown tool '$1'" >&2; exit 1 ;;
esac
}

# The values are validated before they are written, but the rewrite uses no sed/awk program built
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

# leg <tool>: one tool's whole bump, run in a subshell by the loop below (never in a tested context,
# so errexit and pipefail hold). It ends as moved (its Dockerfile rewritten and committed on the
# weekly branch), up to date, declined or failed; a leg that ends 0 has written its outcome word to
# $work/<tool>.status last. Records for the PR body go to $work/<tool>.<field>. A failure leaves the
# step word of the last `step` call in $work/<tool>.step.
leg() {
  local tool="$1" dockerfile current_version current_label new_label branch version_re rc remote_refs
  local swap_names line first second
  STEP_FILE="$work/$tool.step"
  step resolve
  dispatch "$tool"
  step resolve
  if [ -z "$NEW_VERSION" ] || [ -z "$NEW_CHECKSUM" ]; then
    echo "::error::$tool: could not resolve a new version or checksum" >&2
    exit 1
  fi

  # NEW_VERSION and NEW_CHECKSUM (and, for python, NEW_BUILD) are upstream-controlled (a release tag, a checksum
  # file's content, or the npm registry's integrity field) and end up in a sed/awk
  # program, a git branch name, a commit message and a PR title/body. Reject anything
  # that isn't the exact shape expected BEFORE any of that -- never a loose sanity check
  # a crafted tag or checksum line could still slip through.
  step "version shape"
  version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
  [ "$tool" != betterleaks ] || version_re='^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'
  if ! [[ "$NEW_VERSION" =~ $version_re ]]; then
    echo "::error::$tool: resolved version is not a plain X.Y.Z (or, for betterleaks, X.Y.Z-rc.N): rejecting" >&2
    exit 1
  fi
  step "checksum shape"
  if [ "$tool" = npm ]; then
    if ! [[ "$NEW_CHECKSUM" =~ ^sha512-[A-Za-z0-9+/]+=*$ ]]; then
      echo "::error::$tool: resolved integrity is not a well-formed sha512-... value: rejecting" >&2
      exit 1
    fi
  elif ! [[ "$NEW_CHECKSUM" =~ ^[0-9a-f]{64}$ ]]; then
    echo "::error::$tool: resolved checksum is not a 64-char lowercase hex sha256: rejecting" >&2
    exit 1
  fi

  step "pin read"
  dockerfile="$root/images/${dockerfile_dir}/Dockerfile"
  current_version="$(sed -n "s/^ARG ${ver_arg}=//p" "$dockerfile")"
  [ -n "$current_version" ] || { echo "::error::could not read $ver_arg from $dockerfile" >&2; exit 1; }

  # python is pinned by version AND build tag: the label carries both (X.Y.N+TAG) wherever a
  # message, branch, commit or PR title names the move, so a build-only bump never reads as
  # 3.15.2 -> 3.15.2. Every other tool's label is its plain version.
  current_label="$current_version"
  new_label="$NEW_VERSION"
  branch="bump/${tool}-${NEW_VERSION}"
  if [ "$tool" = python ]; then
    # Defence in depth: the listing filter and the asset match already guarantee these.
    step "version shape"
    if ! [[ "$NEW_BUILD" =~ ^[0-9]{8}$ ]] || [ "${NEW_VERSION%.*}" != "${current_version%.*}" ]; then
      echo "::error::python: resolved build tag or minor fails its shape check: rejecting" >&2
      exit 1
    fi
    current_label="${current_version}+${PIN_BUILD}"
    new_label="${NEW_VERSION}+${NEW_BUILD}"
    branch="bump/python-${NEW_VERSION}-${NEW_BUILD}"
  fi

  if [ "$new_label" = "$current_label" ]; then
    echo "$tool: up to date at $current_label"
    echo uptodate > "$work/$tool.status"
    return 0
  fi

  # NEW_VERSION is validated above; current_version is read from this repo's own
  # Dockerfile, so ver_key tells newer from older. Refuse a downgrade
  # rather than opening a PR for one -- "latest" moving backwards (a yanked release, a
  # tag deleted and reused) is a signal to fail closed on, not to propose as this
  # week's bump.
  # python also refuses a lower build tag (equal-length digit strings compare as strings, so no
  # leading-zero octal reading).
  step downgrade
  if [[ "$(ver_key "$NEW_VERSION")" < "$(ver_key "$current_version")" ]] \
    || { [ "$tool" = python ] && [[ "$NEW_BUILD" < "$PIN_BUILD" ]]; }; then
    echo "::error::$tool: resolved $new_label is older than the current pin $current_label -- refusing to propose a downgrade" >&2
    exit 1
  fi

  # A human who closes a bump PR unmerged and leaves its branch has declined that version, and so
  # has anyone who pushes a bump/<tool>-<version> branch to say so. The branch alone declines it,
  # whatever the state of any PR on it: this leg is skipped with a warning. ls-remote's pattern
  # matches the END of a ref name (x/refs/heads/bump/... would match), so read its output and compare
  # the ref exactly. Any ls-remote failure (network, auth) fails the leg, never a reason to proceed or skip.
  step "decline check"
  rc=0
  remote_refs="$(git -C "$root" ls-remote origin "refs/heads/$branch")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "::error::$tool: could not check origin for $branch (git ls-remote exit $rc)" >&2
    exit 1
  fi
  if printf '%s\n' "$remote_refs" | BUMP_REF="refs/heads/$branch" awk '$2 == ENVIRON["BUMP_REF"] { found = 1 } END { exit !found }'; then
    echo "::warning::$tool: $branch already exists on origin, skipping this version; delete the branch to propose it again"
    printf '%s' "$branch" > "$work/$tool.decline"
    echo declined > "$work/$tool.status"
    return 0
  fi

  # npm only: the node image's bundled-package swap calls (see the header). A refused name makes the
  # npm leg change nothing. The names are validated before they reach the PR body, and the refusal
  # never echoes one.
  if [ "$tool" = npm ]; then
    step "swap names"
    swap_names=""
    while IFS= read -r line || [ -n "$line" ]; do
      read -r first second _ <<< "$line" || true
      [ "$first" = swap ] || continue
      if ! [[ "$second" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        echo "::error::npm: a swap call in images/node/Dockerfile has no valid package name (lower-case letters, digits, '.', '_' and '-' only): the npm leg changes nothing" >&2
        exit 1
      fi
      swap_names="${swap_names:+$swap_names, }$second"
    done < "$dockerfile"
    if [ -n "$swap_names" ]; then
      printf '%s' "The node image carries a bundled-package swap block (swapped: ${swap_names}). It fails the build by design once npm bundles a swapped package at or above its swap pin. If this PR is red with that message, before review remove that package's \`swap\` line and both its ARGs from \`images/node/Dockerfile\` (the whole block when no swap remains) and the package's mention in the npm row of the \`docs/threat_model.md\` inputs table." > "$work/$tool.swap"
    fi
  fi

  # The loop restores the Dockerfile from this copy when the leg fails after the rewrite.
  cp "$dockerfile" "$work/$tool.snap"
  printf '%s' "$dockerfile" > "$work/$tool.df"
  step rewrite
  set_arg "$dockerfile" "$ver_arg" "$NEW_VERSION"
  set_arg "$dockerfile" "$sha_arg" "$NEW_CHECKSUM"
  [ "$tool" != python ] || set_arg "$dockerfile" "$build_arg" "$NEW_BUILD"

  # The record files are written before the commit, so no write can fail after it; the status word is last.
  printf '%s' "$current_label" > "$work/$tool.old"
  printf '%s' "$new_label" > "$work/$tool.new"
  printf '%s' "$RELEASE_URL" > "$work/$tool.rel"
  printf '%s' "$CHECKSUM_URL" > "$work/$tool.sum"
  printf '%s' "$SIGNATURE_NOTE" > "$work/$tool.sig"
  if [ "$tool" = python ]; then
    printf '%s' "PYTHON_VERSION=${NEW_VERSION} PYTHON_BUILD=${NEW_BUILD} PYTHON_SHA256=${NEW_CHECKSUM}" > "$work/$tool.args"
  fi
  # The weekly branch is cut here, from the checkout as it stands, just before the run's first commit.
  step commit
  git -C "$root" config user.name "${APP_SLUG}[bot]"
  git -C "$root" config user.email "${BOT_USER_ID}+${APP_SLUG}[bot]@users.noreply.github.com"
  if [ ! -e "$work/branch-cut" ]; then
    git -C "$root" switch -c "$weekly_branch"
    : > "$work/branch-cut"
  fi
  git -C "$root" add "$dockerfile"
  git -C "$root" commit -m "build(images): bump $tool $current_label -> $new_label"

  echo moved > "$work/$tool.status"
}

# --- the run -------------------------------------------------------------------------------------
# Every check below runs before any network or git call.
selected() { # selected <tool>: the tool is in the run
  local t
  [ "${#requested[@]}" -gt 0 ] || return 0
  for t in "${requested[@]}"; do [ "$t" != "$1" ] || return 0; done
  return 1
}
for t in "${requested[@]}"; do
  known=0
  for k in "${ALL_TOOLS[@]}"; do [ "$k" != "$t" ] || known=1; done
  [ "$known" -eq 1 ] || { echo "::error::unknown tool '$t'" >&2; exit 1; }
done
run_date="$(date -u +%Y%m%d)"
[[ "$run_date" =~ ^[0-9]{8}$ ]] || { echo "::error::the run date is not exactly eight digits" >&2; exit 1; }
: "${APP_SLUG:?APP_SLUG must be set}" "${BOT_USER_ID:?BOT_USER_ID must be set}"
weekly_branch="bump/weekly-${run_date}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export TMPDIR="$work"

# `gh auth setup-git` only wires a credential helper (the checkout does not persist one), so
# ls-remote also works on a private repo. It runs once, before the run's first ls-remote.
gh auth setup-git

moved=() declined=() failed=() failed_steps=() decline_branches=()
for tool in "${ALL_TOOLS[@]}"; do
  selected "$tool" || continue
  echo "::group::$tool"
  # Never in a tested context (if, while, ||, && or !): bash switches errexit off there.
  set +e
  ( set -euo pipefail; leg "$tool" )
  rc=$?
  set -e
  echo "::endgroup::"
  status="$(cat "$work/$tool.status" 2> /dev/null || true)"
  if [ "$rc" -ne 0 ] || [ -z "$status" ]; then
    word="$(cat "$work/$tool.step" 2> /dev/null || true)"
    case "$word" in
      resolve | cosign | "version shape" | "pin read" | "checksum shape" | downgrade | "decline check" | "swap names" | rewrite | commit) ;;
      *) word=resolve ;;
    esac
    # Leave the tree and the index as the last commit had them.
    if [ -f "$work/$tool.snap" ]; then
      cp "$work/$tool.snap" "$(cat "$work/$tool.df")"
      if [ "$word" = commit ]; then git -C "$root" reset -q -- "$(cat "$work/$tool.df")" || true; fi
    fi
    echo "::error::$tool: failed at step: $word" >&2
    failed+=("$tool"); failed_steps+=("$word")
    continue
  fi
  case "$status" in
    moved) moved+=("$tool") ;;
    declined) declined+=("$tool"); decline_branches+=("$(cat "$work/$tool.decline")") ;;
  esac
done

# Every declined tool, with its branch, goes to the job summary on every run.
if [ "${#declined[@]}" -gt 0 ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Declined versions"
    for i in "${!declined[@]}"; do echo "- ${declined[$i]}: \`${decline_branches[$i]}\` exists on origin"; done
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "${#moved[@]}" -gt 0 ]; then
  # Today's weekly branch on origin (exact-ref compare, see the decline check): a second run on the
  # same day that has something to propose fails and pushes nothing. Never force-pushed or deleted.
  rc=0
  remote_refs="$(git -C "$root" ls-remote origin "refs/heads/$weekly_branch")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "::error::could not check origin for $weekly_branch (git ls-remote exit $rc)" >&2
    exit 1
  fi
  if printf '%s\n' "$remote_refs" | BUMP_REF="refs/heads/$weekly_branch" awk '$2 == ENVIRON["BUMP_REF"] { found = 1 } END { exit !found }'; then
    echo "::error::$weekly_branch already exists on origin: nothing is pushed or opened (a second run today?)" >&2
    exit 1
  fi

  # The older open weekly PRs this App opened are superseded by this one (closed after it is created,
  # below). The listing holds the write token's decision, so a record is used only when ALL of these
  # hold: the author is exactly app/$APP_SLUG and a bot, the PR is not from a fork, its number is a
  # plain positive integer and its head is exactly bump/weekly- and eight digits. Anything else is
  # ignored and never printed. A used record whose date is not lower than today's stops the run
  # before any push. Branches are never deleted.
  superseded=() superseded_heads=()
  pr_listing="$(gh pr list --repo "$repo" --state open --limit 500 \
    --json number,headRefName,author,isCrossRepository \
    --jq '.[] | [(.number | tostring), .headRefName, (.author.login // "-"), ((.author.is_bot // false) | tostring), (.isCrossRepository | tostring)] | @tsv')" \
    || { echo "::error::could not list the open pull requests" >&2; exit 1; }
  if [ "$(printf '%s' "$pr_listing" | awk 'END { print NR }')" -ge 500 ]; then
    echo "::error::the open pull request listing may be truncated" >&2
    exit 1
  fi
  while IFS=$'\t' read -r pr_num pr_head pr_login pr_bot pr_cross; do
    [ -n "$pr_num" ] && [ -n "$pr_head" ] && [ -n "$pr_login" ] && [ -n "$pr_bot" ] && [ -n "$pr_cross" ] || continue
    [[ "$pr_num" =~ ^[1-9][0-9]*$ ]] || continue
    [ "$pr_login" = "app/${APP_SLUG}" ] && [ "$pr_bot" = true ] && [ "$pr_cross" = false ] || continue
    [[ "$pr_head" =~ ^bump/weekly-([0-9]{8})$ ]] || continue
    if ! [[ "${BASH_REMATCH[1]}" < "$run_date" ]]; then
      echo "::error::the open weekly PR #${pr_num} is not older than this run (${run_date}): nothing is pushed or opened" >&2
      exit 1
    fi
    superseded+=("$pr_num"); superseded_heads+=("$pr_head")
  done <<< "$pr_listing"

  body="Opened by \`bump-binaries.yml\` (#29): one grouped bump for the run of ${run_date}.

Each checksum below was taken from that release's own published checksum file (or, for
npm, the registry's \`integrity\` field) -- never from hashing the download."
  for tool in "${moved[@]}"; do
    body+="

### $tool $(cat "$work/$tool.old") -> $(cat "$work/$tool.new")

Release notes: $(cat "$work/$tool.rel")
Checksum source: $(cat "$work/$tool.sum")"
    [ ! -s "$work/$tool.sig" ] || body+="

$(cat "$work/$tool.sig")"
    [ ! -f "$work/$tool.swap" ] || body+="

$(cat "$work/$tool.swap")"
    if [ "$tool" = python ]; then
      body+="

New ARG values: $(cat "$work/$tool.args")

DEVC-D11 cites consumers running actions/setup-python at the image's version, so a patch bump may call for consumer pin PRs (tracked on #556)."
    fi
  done
  if [ "${#declined[@]}" -gt 0 ]; then
    body+="

### Declined versions

A \`bump/<tool>-<version>\` branch on origin declines that version; delete the branch to propose it again."
    for i in "${!declined[@]}"; do body+="
- ${declined[$i]}: \`${decline_branches[$i]}\`"; done
  fi
  if [ "${#failed[@]}" -gt 0 ]; then
    body+="

### Failed tools

These tools were not bumped in this PR; the step that failed is named."
    for i in "${!failed[@]}"; do body+="
- ${failed[$i]}: ${failed_steps[$i]}"; done
  fi
  if [ "${#superseded[@]}" -gt 0 ]; then
    body+="

### Older weekly PRs closed by this one"
    for i in "${!superseded[@]}"; do body+="
- #${superseded[$i]} (\`${superseded_heads[$i]}\`)"; done
  fi
  body+="

This still needs a human review before merge: read each release's notes above (and the
diff since each tool's old label yourself -- this PR links the releases, not compares). For
Node, also open the matching CI-pin PRs in every consuming repo; for OpenTofu each
consumer moves its tofu_version in the PR that takes the new image digest. To drop a tool,
revert its commit. The ordinary gates (hadolint, Trivy, the smoke test, the template test, and
architect-review because \`images/\` is a code_path) run on this PR like any other."

  git -C "$root" push -u origin "$weekly_branch"
  new_pr="$(gh pr create --repo "$repo" --head "$weekly_branch" --base main \
    --title "build(images): bump pinned binaries (weekly ${run_date})" \
    --body "$body")"
  # gh prints the new PR's URL; name it in the comments only when it has exactly that shape.
  new_ref="$weekly_branch"
  if [[ "$new_pr" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$ ]]; then new_ref="$new_pr"; fi

  # Close the older PRs the new one supersedes, once the new PR exists (a failed `gh pr create`
  # above exits first, so nothing is closed). Every close is attempted; the branches stay, so a
  # closed PR can be reopened.
  close_failed=0
  for pr_num in "${superseded[@]}"; do
    gh pr close "$pr_num" --repo "$repo" --comment "Superseded by ${new_ref}." \
      || { echo "::error::could not close superseded PR #${pr_num}" >&2; close_failed=1; }
  done
  [ "$close_failed" -eq 0 ] || exit 1
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo "::error::failed: ${failed[*]}" >&2
  exit 1
fi
