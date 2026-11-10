# syntax=docker/dockerfile:1.28@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
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
# consuming repo's setup-opentofu step. A consumer moves `tofu_version` in the same PR
# that takes this image's digest, so the two never differ for long. A container that
# validates with a different tofu than CI reports a verdict CI does not share.
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
#
# 1.13.0 (from 1.12.6, 2026-10-01): the newest release (2026-09-30). Checksum from the
# release's own tofu_1.13.0_SHA256SUMS. Trivy: 3 of the 14 HIGH findings remain
# (CVE-2026-56864, CVE-2026-56865, CVE-2026-84445), so this clears 11 exceptions.
# Compatibility notes: base64gzip output is equivalent but not byte-identical, and WinRM
# provisioners are removed; no consuming repo uses either (checked 2026-10-01).
#
# 1.13.2 (from 1.13.1, 2026-11-02): the newest release (2026-10-21), a patch bump. Trivy:
# 5 HIGH findings, all allowlisted in .trivyignore.yaml (CVE-2026-56864, CVE-2026-56865,
# CVE-2026-84445, plus CVE-2026-78669 and CVE-2026-116587, published since 1.13.0).
#
# 1.13.9 (from 1.13.2, 2026-11-09, #505): the newest release (2026-11-05), a patch bump.
# Checksum from the release's own tofu_1.13.9_SHA256SUMS. 1.13.3 to 1.13.7 were never
# published; 1.13.8 fixes the `-v` alias regression and a panic on invalid
# state-encryption config, 1.13.9 fixes local-backend state persistence after a crashed
# first apply. Nothing breaking. go.mod is unchanged since 1.13.2, so Trivy reports the
# same findings (see .trivyignore.yaml).
#
# The checksum file itself was verified for 1.13.9 (2026-11-09, #511), by hand, with
# cosign v3.1.3 against the release's keyless signature (the .sig and .pem beside
# tofu_1.13.9_SHA256SUMS), checked against the Rekor transparency log; 1.13.2 (2026-11-02)
# and 1.13.0 (2026-10-02, #58) were verified the same way:
#   signer identity: https://github.com/opentofu/opentofu/.github/workflows/release.yml@refs/heads/v1.13
#   OIDC issuer:     https://token.actions.githubusercontent.com
#   source commit:   c83e7e50daff10ac704cb0811e9ffd0ad2523759 (the v1.13.9 tag)
# The image does not check this, and bump-binaries.sh does not either: it rewrites the
# two ARGs below and leaves this comment alone. A pin at any other version is
# unverified until someone repeats the check and updates this record (see
# docs/threat_model.md, Known gaps). To repeat it, download tofu_<v>_SHA256SUMS and its
# .sig and .pem from the v<v> release and run this on those files (cosign needs network
# access to Sigstore, Rekor and its TUF root: the certificate expired minutes after
# signing):
#   sha=$(gh api repos/opentofu/opentofu/commits/v<v> --jq .sha) &&
#   printf '%s' "$sha" | grep -qxE '[0-9a-f]{40}' &&
#   cosign verify-blob --certificate tofu_<v>_SHA256SUMS.pem --signature tofu_<v>_SHA256SUMS.sig \
#     --certificate-identity "https://github.com/opentofu/opentofu/.github/workflows/release.yml@refs/heads/v<major>.<minor>" \
#     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
#     --certificate-github-workflow-repository opentofu/opentofu \
#     --certificate-github-workflow-sha "$sha" tofu_<v>_SHA256SUMS &&
#   grep -qxF "<TOFU_SHA256>  tofu_<v>_linux_amd64.zip" tofu_<v>_SHA256SUMS && echo verified
# The identity names a branch, not a tag, so it accepts any release run from that
# branch; --certificate-github-workflow-sha is what binds the signature to v<v>'s
# commit. cosign treats an empty value as "not set" and skips that check, which is why
# the sha is resolved and shape-checked first rather than substituted inline. The final
# grep is what ties the verified file to the pin: a valid signature on one copy of
# SHA256SUMS says nothing about a sha taken from another. Record the resolved sha as the
# source commit above.
ARG TOFU_VERSION=1.13.9
ARG TOFU_SHA256=bc44eb6b06446ba83bd4072114891987f590f66cca712737a7f1147c50c539ce
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip" \
        -o /tmp/tofu.zip \
    && echo "${TOFU_SHA256}  /tmp/tofu.zip" | sha256sum -c - \
    && unzip -q /tmp/tofu.zip tofu -d /tmp/tofu \
    && install -m 0755 /tmp/tofu/tofu /usr/local/bin/tofu \
    && rm -rf /tmp/tofu.zip /tmp/tofu

# --- tflint, for pre-commit-terraform's terraform_tflint hook (language: script, so
# it needs the binary on PATH). No CI job runs tflint, so there is no CI pin to match.
ARG TFLINT_VERSION=0.66.0
ARG TFLINT_SHA256=22be11cadc25cd02401e94c0ccc91aa63467debb8485c2a755d98f4c0a9d1e2e
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
# TF_PLUGIN_CACHE_DIR is ~/.cache/tofu-plugins, which the legacy template mounts as the one
# volume SHARED by every repo on the host, in every org, so each provider version is
# downloaded and stored once per machine. Sharing a cache between repos is safe only
# because tofu verifies every cached provider against the repo's own
# .terraform.lock.hcl hashes when a command starts, so a tampered entry fails init. It
# is checked then, not at exec: see docs/threat_model.md, Known gaps.
#
# TFLINT_PLUGIN_DIR is per repo, in the home volume: tflint plugins are not re-verified
# against a lock on use, so they never go near the shared cache.
ENV TF_DATA_DIR=.terraform-devcontainer \
    TF_PLUGIN_CACHE_DIR=/home/app/.cache/tofu-plugins \
    TFLINT_PLUGIN_DIR=/home/app/.local/tflint-plugins

USER 1000:1000
