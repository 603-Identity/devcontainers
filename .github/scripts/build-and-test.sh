#!/usr/bin/env bash
# Builds base, then tofu and node FROM that exact base, then the dev-App flavour twice
# (devapp FROM base, devapp-tofu FROM tofu), and smoke-tests each image BEFORE it is pushed.
# Shared by both jobs in build.yml, so a PR tests exactly the code path main publishes with.
#
#   build-and-test.sh local        build and test only; tags are <name>:local
#   build-and-test.sh push <TAG>   also push; writes <name>_digest=sha256:... to
#                                  $GITHUB_OUTPUT for the attestation steps
#
# In push mode, tofu and node are built FROM "<registry>/devcontainer-base@<digest>",
# the digest pushed a moment earlier in this same run, never from a tag. That way a
# published tofu/node image always names the exact base it was built on. The devapp
# images are built the same way on the base and tofu digests of this run.
#
# The dev-App flavour's `claude` binary is fetched and signature-verified ONCE, right after
# base is built locally and before ANYTHING is pushed (the `claude-verify` stage of
# images/devapp/Dockerfile, exported with `--output type=local`). Both devapp builds then
# receive the verified file as the named build context `claude-export`; nothing relies on
# BuildKit reusing a cached layer. A download or signature failure pushes nothing. The
# devapp smoke test and Trivy run after base, tofu and node are pushed, which is the
# pattern tofu and node already have: each image is checked before ITS OWN push, not before
# every push.
set -euo pipefail

mode="${1:?usage: build-and-test.sh local | push <TAG>}"
tag="${2:-local}"
registry="${REGISTRY:-ghcr.io/603-identity}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
# Git Bash on a Windows host: docker.exe needs C:/... rather than /c/..., and
# MSYS_NO_PATHCONV=1 stops Git Bash rewriting the in-container /tests path. No-op in CI.
if command -v cygpath >/dev/null 2>&1; then root="$(cygpath -m "$root")"; export MSYS_NO_PATHCONV=1; fi

# Expected versions come from the Dockerfiles' own ARG lines and the tools venv's
# uv.lock, so tests/smoke.sh has no second copy of any version to drift.
arg() { sed -n "s/^ARG $2=//p" "$root/images/$1/Dockerfile"; }
lockver() { # lockver <package>: the version uv.lock resolved for it
  sed -n "/^name = \"$1\"\$/{n;s/^version = \"\(.*\)\"\$/\1/p;q;}" "$root/images/base/tools/uv.lock"
}
export EXPECT_GH EXPECT_YQ EXPECT_UV EXPECT_TOFU EXPECT_TFLINT EXPECT_NODE EXPECT_NPM
export EXPECT_PRE_COMMIT EXPECT_ZIZMOR EXPECT_BETTERLEAKS EXPECT_CLAUDE EXPECT_CLAUDE_SHA256
EXPECT_GH="$(arg base GH_VERSION)"
EXPECT_UV="$(arg base UV_VERSION)"
EXPECT_BETTERLEAKS="$(arg base BETTERLEAKS_VERSION)"
EXPECT_PRE_COMMIT="$(lockver pre-commit)"
EXPECT_ZIZMOR="$(lockver zizmor)"
EXPECT_CLAUDE="$(arg devapp CLAUDE_VERSION)"
EXPECT_CLAUDE_SHA256="$(arg devapp CLAUDE_SHA256)"
for v in EXPECT_UV EXPECT_BETTERLEAKS EXPECT_PRE_COMMIT EXPECT_ZIZMOR EXPECT_CLAUDE EXPECT_CLAUDE_SHA256; do
  [ -n "${!v}" ] || { echo "::error::could not read $v from a Dockerfile or images/base/tools/uv.lock"; exit 1; }
done
EXPECT_YQ="$(arg base YQ_VERSION)"
EXPECT_TOFU="$(arg tofu TOFU_VERSION)"
EXPECT_TFLINT="$(arg tofu TFLINT_VERSION)"
EXPECT_NODE="$(arg node NODE_VERSION)"
EXPECT_NPM="$(arg node NPM_VERSION)"

ref() { # ref <flavor> -> the tag this run builds
  if [ "$mode" = push ]; then echo "$registry/devcontainer-$1:$tag"; else echo "devcontainer-$1:local"; fi
}

# The commit the images are built from, for the org.opencontainers.image.revision label
# (README: "Comparing two tags"). CI has GITHUB_SHA; a local run asks git.
revision="${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)}"

# Fixtures for the dev-App smoke test: what the host's broker would mount at /run/wow. The
# dev-token is generated here, shaped like an installation token and unrelated to any real
# one, and so are the decoys: files a dev-App container must never read (the elevated
# `admin-token`, a stray `token`). The smoke test asserts that the decoy values never appear
# in anything the identity layer prints. Directories are 0755 and files 0644: the container's
# uid 1000 must read what a CI runner's user wrote.
export DEVC_FIXTURE_TOKEN DEVC_DECOY_TOKEN
rand_token() { printf 'ghs_%s' "$(head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 36)"; }
# rand_alnum <n>: n random alphanumerics. The output is cut in the shell, not by a `head` at the
# end of the pipe, so no stage takes a SIGPIPE that pipefail would turn into a failure.
rand_alnum() {
  local s
  s="$(head -c $(($1 + 64)) /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9')"
  printf '%s' "${s:0:$1}"
}
# rand_stateless_token <n>: shaped like GitHub's stateless installation token (ghs_APPID_JWT:
# dots and dashes, ~520 characters), with n characters after `ghs_`. The `.`, `-` and `_` sit at
# fixed places so every fixture has them.
rand_stateless_token() {
  local head
  head="1234567_$(rand_alnum 30).$(rand_alnum 30)-$(rand_alnum 30)."
  printf 'ghs_%s%s' "$head" "$(rand_alnum $(($1 - ${#head})))"
}
# The /run/wow modes, in run order. smoke-devapp.sh documents each one.
WOW_MODES=(with without empty expired crlf badtoken stateless oversize badchar short)
make_wow_fixtures() {
  local w="$root/out/wow" m exp tok
  DEVC_FIXTURE_TOKEN="$(rand_token)"
  DEVC_DECOY_TOKEN="$(rand_token)"
  exp="$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)"
  rm -rf "$w"
  for m in "${WOW_MODES[@]}"; do
    [ "$m" = without ] && continue
    mkdir -p "$w/$m"
    chmod 0755 "$w/$m"
    [ "$m" = empty ] && continue
    printf '%s\n' "$DEVC_DECOY_TOKEN" > "$w/$m/admin-token"
    printf '%s\n' "$DEVC_DECOY_TOKEN" > "$w/$m/token"
  done
  printf '%s\n%s\n' "$DEVC_FIXTURE_TOKEN" "$exp" > "$w/with/dev-token"
  printf '%s\n%s\n' "$DEVC_FIXTURE_TOKEN" "2020-01-01T00:00:00Z" > "$w/expired/dev-token"
  printf '%s\r\n%s\r\n' "$DEVC_FIXTURE_TOKEN" "$exp" > "$w/crlf/dev-token"
  printf 'gho_%s\n%s\n' "${DEVC_FIXTURE_TOKEN#ghs_}" "$exp" > "$w/badtoken/dev-token"
  # #492: the stateless format is served. Over the cap, a character outside the class, or fewer
  # than 36 characters after `ghs_`, it is refused.
  printf '%s\n%s\n' "$(rand_stateless_token 520)" "$exp" > "$w/stateless/dev-token"
  printf '%s\n%s\n' "$(rand_stateless_token 2100)" "$exp" > "$w/oversize/dev-token"
  printf '%s/%s\n%s\n' "${DEVC_FIXTURE_TOKEN:0:20}" "${DEVC_FIXTURE_TOKEN:21}" "$exp" > "$w/badchar/dev-token"
  printf 'ghs_%s\n%s\n' "$(rand_alnum 35)" "$exp" > "$w/short/dev-token"
  chmod 0644 "$w"/*/*
  # The fixtures must keep testing what they are for. A stateless token that shrank under 256
  # characters or a file under 513 bytes would pass against the old check too.
  tok="$(head -n 1 "$w/stateless/dev-token")"
  if [ "${#tok}" -le 259 ] || [ "$(wc -c < "$w/stateless/dev-token")" -le 512 ] \
     || [[ "$tok" != *.* || "$tok" != *-* ]] \
     || [ "$(wc -c < "$w/oversize/dev-token")" -le 2048 ] \
     || [ "$(head -n 1 "$w/short/dev-token" | wc -c)" -ne 40 ]; then
    echo "make_wow_fixtures: a token fixture is not the shape it tests" >&2
    exit 1
  fi
}

smoke() { # smoke <flavor>
  docker run --rm \
    -e EXPECT_GH -e EXPECT_YQ -e EXPECT_UV -e EXPECT_PRE_COMMIT \
    -e EXPECT_ZIZMOR -e EXPECT_BETTERLEAKS -e EXPECT_TOFU -e EXPECT_TFLINT -e EXPECT_NODE -e EXPECT_NPM \
    -v "$root/tests:/tests:ro" "$(ref "$1")" sh /tests/smoke.sh "$1"
  case "$1" in devapp|devapp-tofu) smoke_devapp "$1" ;; esac
}

# The dev-App identity layer, once per /run/wow the host could present: a valid token (with
# decoys beside it), none at all, an empty directory, an expired token, CRLF line endings, a
# token of the wrong kind, a valid token in the stateless format, a file over the size cap, a
# token with a bad character and one too short (WOW_MODES). Each is a fresh container: the
# layer must hold on every one.
smoke_devapp() { # smoke_devapp <flavor>
  local m mounts net tok
  make_wow_fixtures
  for m in "${WOW_MODES[@]}"; do
    mounts=()
    [ "$m" = without ] || mounts=(-v "$root/out/wow/$m:/run/wow:ro")
    # `with` runs without a network (#503): its plugin-install.sh checks must fail fast, not reach
    # GitHub. None of its other assertions needs the network.
    net=()
    [ "$m" != with ] || net=(--network none)
    # In the #492 modes the dev token is the file's own line 1, so "served" and "never printed"
    # are checked against the token that is actually there.
    tok="$DEVC_FIXTURE_TOKEN"
    case "$m" in stateless|oversize|badchar|short) tok="$(head -n 1 "$root/out/wow/$m/dev-token")" ;; esac
    echo "devapp smoke ($1, /run/wow: $m)"
    DEVC_FIXTURE_TOKEN="$tok" docker run --rm \
      -e EXPECT_GH -e EXPECT_TOFU -e EXPECT_TFLINT -e EXPECT_CLAUDE -e EXPECT_CLAUDE_SHA256 \
      -e DEVC_FIXTURE_TOKEN -e DEVC_DECOY_TOKEN \
      "${net[@]}" "${mounts[@]}" -v "$root/tests:/tests:ro" "$(ref "$1")" sh /tests/smoke-devapp.sh "$1" "$m"
  done
}

# Trivy runs from its own image, pinned by digest, rather than through trivy-action:
# that is one fewer third-party Action holding this job's token. It reads the
# image to scan through the Docker socket.
TRIVY="aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969"
trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v devc-trivy-cache:/root/.cache/trivy \
    -v "$root:/src" "$TRIVY" "$@"
}

scan() { # scan <flavor>
  # THE GATE. It fails the build on any HIGH/CRITICAL vulnerability that HAS a fix, and
  # on any secret baked into the image. Unfixed findings do not block, because nothing
  # could be done about them today. They still reach code scanning (the SARIF report
  # below) and resurface here on the weekly rebuild once a fix ships. The only other
  # way past this gate is a reviewed entry in .trivyignore.yaml, and each entry
  # carries an expiry.
  trivy image --quiet --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed \
    --ignorefile /src/.trivyignore.yaml --exit-code 1 "$(ref "$1")"
  if [ "$mode" = push ]; then
    mkdir -p "$root/out"
    # SBOM (attested beside the provenance) and a FULL report, including unfixed and
    # ignored findings, for GitHub code scanning.
    trivy image --quiet --scanners vuln --format cyclonedx --output "/src/out/$1.cdx.json" "$(ref "$1")"
    trivy image --quiet --scanners vuln,secret --severity HIGH,CRITICAL --format sarif \
      --output "/src/out/$1.sarif" "$(ref "$1")"
  fi
}

push_and_digest() { # push_and_digest <flavor> -> prints sha256:...
  docker push --quiet "$(ref "$1")" >/dev/null
  docker inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$(ref "$1")" \
    | sed -n "s|^$registry/devcontainer-$1@||p" | head -n1
}

echo "::group::base"
docker build --pull -t "$(ref base)" "$root/images/base"

# claude, fetched and verified now: before the smoke test, the scan and every push. The
# exported file is the only thing the devapp builds take from this step.
claude_export="$root/out/claude-export"
rm -rf "$claude_export"
mkdir -p "$claude_export"
docker build --target claude-verify --build-arg "BASE_IMAGE=$(ref base)"   --output "type=local,dest=$claude_export" "$root/images/devapp"
[ -s "$claude_export/claude" ] || { echo "::error::claude-verify exported no claude binary"; exit 1; }

smoke base
scan base
echo "::endgroup::"

base_from="$(ref base)"
if [ "$mode" = push ]; then
  base_digest="$(push_and_digest base)"
  [ -n "$base_digest" ] || { echo "::error::no digest for base after push"; exit 1; }
  echo "base_digest=$base_digest" >> "$GITHUB_OUTPUT"
  base_from="$registry/devcontainer-base@$base_digest"
fi

# image_dir <flavor>: the directory an image is built from. devapp and devapp-tofu share one.
image_dir() { case "$1" in devapp|devapp-tofu) echo "$root/images/devapp" ;; *) echo "$root/images/$1" ;; esac; }

# build_flavor <flavor> <base image>: build, smoke-test, scan and (in push mode) push one image,
# leaving its digest in $flavor_ref and, in push mode, in $GITHUB_OUTPUT as <flavor>_digest
# (devapp-tofu -> devapp_tofu_digest). The devapp flavours also get the verified claude binary
# and the commit they are built from.
flavor_ref=
build_flavor() {
  local flavor="$1" from="$2" extra=()
  case "$flavor" in
    devapp|devapp-tofu)
      extra=(--build-arg "REVISION=$revision" --build-context "claude-export=$claude_export") ;;
  esac
  echo "::group::$flavor"
  docker build -t "$(ref "$flavor")" --build-arg "BASE_IMAGE=$from" "${extra[@]}" "$(image_dir "$flavor")"
  case "$flavor" in
    devapp|devapp-tofu)
      got="$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$(ref "$flavor")")"
      [ "$got" = "$revision" ] || { echo "::error::$flavor carries revision '$got', not '$revision'"; exit 1; } ;;
  esac
  smoke "$flavor"
  scan "$flavor"
  flavor_ref="$(ref "$flavor")"
  if [ "$mode" = push ]; then
    local d
    d="$(push_and_digest "$flavor")"
    [ -n "$d" ] || { echo "::error::no digest for $flavor after push"; exit 1; }
    echo "${flavor//-/_}_digest=$d" >> "$GITHUB_OUTPUT"
    flavor_ref="$registry/devcontainer-$flavor@$d"
  fi
  echo "::endgroup::"
}

build_flavor tofu "$base_from"
tofu_from="$flavor_ref"
build_flavor node "$base_from"
build_flavor devapp "$base_from"
build_flavor devapp-tofu "$tofu_from"
