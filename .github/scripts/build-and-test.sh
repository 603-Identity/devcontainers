#!/usr/bin/env bash
# Builds base, then tofu and node FROM that exact base, and smoke-tests each image
# BEFORE anything is pushed. Shared by both jobs in build.yml, so a PR tests exactly
# the code path main publishes with.
#
#   build-and-test.sh local        build and test only; tags are <name>:local
#   build-and-test.sh push <TAG>   also push; writes <name>_digest=sha256:... to
#                                  $GITHUB_OUTPUT for the attestation steps
#
# In push mode, tofu and node are built FROM "<registry>/devcontainer-base@<digest>",
# the digest pushed a moment earlier in this same run, never from a tag. That way a
# published tofu/node image always names the exact base it was built on.
set -euo pipefail

mode="${1:?usage: build-and-test.sh local | push <TAG>}"
tag="${2:-local}"
registry="${REGISTRY:-ghcr.io/603-identity}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
# Git Bash on a Windows host: docker.exe needs C:/... rather than /c/..., and
# MSYS_NO_PATHCONV=1 stops Git Bash rewriting the in-container /tests path. No-op in CI.
if command -v cygpath >/dev/null 2>&1; then root="$(cygpath -m "$root")"; export MSYS_NO_PATHCONV=1; fi

# Expected versions come from the Dockerfiles' own ARG lines, so tests/smoke.sh has
# no second copy of any version to drift.
arg() { sed -n "s/^ARG $2=//p" "$root/images/$1/Dockerfile"; }
export EXPECT_GH EXPECT_YQ EXPECT_TOFU EXPECT_TFLINT EXPECT_NODE EXPECT_NPM
EXPECT_GH="$(arg base GH_VERSION)"
EXPECT_YQ="$(arg base YQ_VERSION)"
EXPECT_TOFU="$(arg tofu TOFU_VERSION)"
EXPECT_TFLINT="$(arg tofu TFLINT_VERSION)"
EXPECT_NODE="$(arg node NODE_VERSION)"
EXPECT_NPM="$(arg node NPM_VERSION)"

ref() { # ref <flavor> -> the tag this run builds
  if [ "$mode" = push ]; then echo "$registry/devcontainer-$1:$tag"; else echo "devcontainer-$1:local"; fi
}

smoke() { # smoke <flavor>
  docker run --rm \
    -e EXPECT_GH -e EXPECT_YQ -e EXPECT_TOFU -e EXPECT_TFLINT -e EXPECT_NODE -e EXPECT_NPM \
    -v "$root/tests:/tests:ro" "$(ref "$1")" sh /tests/smoke.sh "$1"
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

for flavor in tofu node; do
  echo "::group::$flavor"
  docker build -t "$(ref "$flavor")" --build-arg "BASE_IMAGE=$base_from" "$root/images/$flavor"
  smoke "$flavor"
  scan "$flavor"
  if [ "$mode" = push ]; then
    d="$(push_and_digest "$flavor")"
    [ -n "$d" ] || { echo "::error::no digest for $flavor after push"; exit 1; }
    echo "${flavor}_digest=$d" >> "$GITHUB_OUTPUT"
  fi
  echo "::endgroup::"
done
