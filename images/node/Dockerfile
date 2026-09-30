# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# Shared devcontainer NODE image: base + Node.js 24 (npm included), matching
# consuming repos' CI, which runs `node-version: 24`.
#
# BASE_IMAGE is always passed by digest; see images/tofu/Dockerfile.
ARG BASE_IMAGE=devcontainer-base:local
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/603-Identity/devcontainers" \
      org.opencontainers.image.description="Shared devcontainer: base + Node.js 24"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER 0

# --- Node.js, the official linux-x64 tarball. The sha256 is read from
# https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt.
# Residual risk: that file is fetched over TLS but its detached GPG signature
# (SHASUMS256.txt.asc) is not verified here. Doing that needs the Node release team's
# keyring pinned in this repo; tracked in README.md § "Known gaps".
ARG NODE_VERSION=24.21.0
ARG NODE_SHA256=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
        -o /tmp/node.tar.xz \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
        --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' \
    && rm /tmp/node.tar.xz \
    && node --version && npm --version

# --- npm, upgraded within the SAME major that Node 24 bundles (11.x), so `npm ci`
# behaves as it does in CI's setup-node. Node 24.21.0 bundles npm 11.19.0, whose own
# dependencies carry fixed HIGH CVEs (tar, brace-expansion, ip-address); 11.20.0
# bundles the fixed versions. The tarball is verified against the registry's
# published sha512 `integrity`, the same check `npm ci` applies to every package.
# Drop this block once a Node 24 release bundles npm >= 11.20.0.
ARG NPM_VERSION=11.20.0
ARG NPM_INTEGRITY=sha512-dF3EDFwbYN+N5RUip+ZYDe0NeURK5BgqKOcvT1iNtUYhTMTl0FwWhBuXrS7KtXyduqyTMS5aaQaregnHDAxNgw==
RUN curl -fsSL "https://registry.npmjs.org/npm/-/npm-${NPM_VERSION}.tgz" -o /tmp/npm.tgz \
    && test "sha512-$(openssl dgst -sha512 -binary /tmp/npm.tgz | base64 -w0)" = "${NPM_INTEGRITY}" \
    && npm install -g --no-audit --no-fund /tmp/npm.tgz \
    && rm /tmp/npm.tgz \
    && test "$(npm --version)" = "${NPM_VERSION}"

# npm's download cache lives in ~/.cache/npm, not ~/.npm, and is per container: it is
# NOT in the shared volume. Only `npm ci` verifies tarballs against package-lock.json's
# sha512 `integrity` field. `npx`, `npm exec` and `npm install <pkg>` trust cached
# package metadata, so a cache shared between repos could feed one repo's install a
# forged entry planted by another.
# The update notifier is off because it phones home on every npm invocation.
ENV NPM_CONFIG_CACHE=/home/app/.cache/npm \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false
RUN install -d -o app -g app -m 0755 /home/app/.cache/npm

USER 1000:1000
