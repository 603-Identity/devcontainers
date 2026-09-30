# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# This repo's devcontainer: one published shared image, pinned by tag AND digest,
# plus this repo's own extras (if any) below. Dependabot's docker ecosystem bumps the
# FROM line; add this directory to the repo's .github/dependabot.yml:
#
#   - package-ecosystem: docker
#     directory: /.devcontainer
#     schedule: { interval: weekly }
#
# Choose ONE image: devcontainer-base, devcontainer-tofu or devcontainer-node. Take the
# tag@digest from the latest "Build images" run summary in 603-Identity/devcontainers,
# and verify it before first use AND for every new digest (each Dependabot bump), not
# only the first:
#   gh attestation verify oci://ghcr.io/603-identity/devcontainer-tofu@sha256:<digest> \
#     --repo 603-Identity/devcontainers \
#     --signer-workflow 603-Identity/devcontainers/.github/workflows/build.yml \
#     --source-ref refs/heads/main --deny-self-hosted-runners
FROM ghcr.io/603-identity/devcontainer-tofu:TAG@sha256:DIGEST

# The mount points for the home, dependency and cache volumes in devcontainer.json are
# pre-created app-owned in the shared images, so there is nothing to add here for them.
# The container's root filesystem is read-only at run time (devcontainer.json runArgs):
# install anything extra in this Dockerfile, not in a running container. Install it outside
# /home/app: the home volume copies the image's /home/app once, at first mount, so an
# install there never reaches an existing volume, and a root install that writes there
# (npm's cache, ~/.local) leaves it root-owned and breaks the app user. As root, send
# caches elsewhere, for example (this one assumes the devcontainer-node image):
#   USER 0
#   RUN npm install -g --prefix /usr/local --cache /tmp/npm-cache <pkg>@<ver> \
#       && rm -rf /tmp/npm-cache
#   USER 1000:1000
USER 1000:1000

# Repo-specific extras go here, following the same rules as the shared images:
# version plus sha256 from the upstream checksum file, never trust-on-first-use.
