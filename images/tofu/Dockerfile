# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# Shared devcontainer TOFU image: base + OpenTofu + tflint.
#
# BASE_IMAGE is always passed by digest. CI passes the base digest it just built in
# the same run (.github/workflows/build.yml), so a tofu image is never built on a
# different base than the one published beside it. The default is for local builds
# only (`docker build -t devcontainer-base:local images/base` first).
ARG BASE_IMAGE=devcontainer-base:local
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/603-Identity/devcontainers" \
      org.opencontainers.image.description="Shared devcontainer: base + OpenTofu + tflint"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER 0

# --- OpenTofu. THE pin that matters most: it must equal `tofu_version` in every
# consuming repo's setup-opentofu step. Bump this and every repo's workflows TOGETHER,
# never this alone. A container that validates with a different tofu than CI reports a verdict CI
# does not share.
#
# 1.11.14 (from 1.11.6, 2026-09-28): 1.11.6 carries GHSA-q7j3-v8qv-22vq (HIGH,
# arbitrary file read during git operations via a crafted URL, fixed in 1.11.10).
# That is directly relevant wherever `tofu init` runs on PR-controlled module sources.
# Trivy counted 53 HIGH/CRITICAL findings in the 1.11.6 binary and 14 in 1.11.14. A
# patch bump within the same minor.
#
# 1.12.6 (from 1.11.14, 2026-09-30): the newest 1.12.x; 1.13.0 is out but is a further
# minor, not this move. Checksum from the release's own tofu_1.12.6_SHA256SUMS. Trivy:
# the same 14 HIGH findings as 1.11.14 (all allowlisted in .trivyignore.yaml), so this
# bump clears none of them. Consumers must move tofu_version in the same PR that takes
# this image's digest.
ARG TOFU_VERSION=1.12.6
ARG TOFU_SHA256=5dc43da4f750f33873dc25e94587128709e819e544b7be9016b255316153c3a8
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip" \
        -o /tmp/tofu.zip \
    && echo "${TOFU_SHA256}  /tmp/tofu.zip" | sha256sum -c - \
    && unzip -q /tmp/tofu.zip tofu -d /tmp/tofu \
    && install -m 0755 /tmp/tofu/tofu /usr/local/bin/tofu \
    && rm -rf /tmp/tofu.zip /tmp/tofu

# --- tflint, for pre-commit-terraform's terraform_tflint hook (language: script, so
# it needs the binary on PATH). No CI job runs tflint, so there is no CI pin to match.
ARG TFLINT_VERSION=0.64.0
ARG TFLINT_SHA256=cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537
RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
        -o /tmp/tflint.zip \
    && echo "${TFLINT_SHA256}  /tmp/tflint.zip" | sha256sum -c - \
    && unzip -q /tmp/tflint.zip tflint -d /tmp/tflint \
    && install -m 0755 /tmp/tflint/tflint /usr/local/bin/tflint \
    && rm -rf /tmp/tflint.zip /tmp/tflint

# TF_DATA_DIR is RELATIVE on purpose. It resolves per working directory, so every
# root module gets its own data directory, and none of them shares `.terraform/` with
# a Windows-host `tofu init` through the bind mount. (A host-side init leaves a backend
# record behind, and `-backend=false` REUSES that record rather than ignoring it.)
#
# TF_PLUGIN_CACHE_DIR points into ~/.cache/shared, which the template mounts as a
# volume SHARED by every repo on the host, in every org, so each provider version is
# downloaded and stored once per machine. Sharing a cache between repos is safe only
# because tofu verifies every cached provider against the repo's own
# .terraform.lock.hcl hashes when a command starts, so a tampered entry fails init. It
# is checked then, not at exec: see docs/threat_model.md, Known gaps.
ENV TF_DATA_DIR=.terraform-devcontainer \
    TF_PLUGIN_CACHE_DIR=/home/app/.cache/shared/tofu-plugins

USER 1000:1000
