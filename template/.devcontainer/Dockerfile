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

# Mount points for the per-repo dependency volumes in devcontainer.json, pre-created
# app-owned so each volume comes up writable as uid 1000 (Docker copies the image
# path's ownership into an empty named volume). Delete the lines you do not mount.
USER 0
RUN install -d -o app -g app /workspace/node_modules /workspace/.venv
USER 1000:1000

# Repo-specific extras go here, following the same rules as the shared images:
# version plus sha256 from the upstream checksum file, never trust-on-first-use.
