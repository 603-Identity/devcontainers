# syntax=docker/dockerfile:1.28@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
#
# Shared devcontainer NODE image: base + Node.js 24 + npm 12. Node matches consuming
# repos' CI (`node-version: 24`); npm does not until they take npm 12 (#27).
#
# BASE_IMAGE is always passed by digest; see images/tofu/Dockerfile.
ARG BASE_IMAGE=devcontainer-base:local
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/603-Identity/devcontainers" \
      org.opencontainers.image.description="Shared devcontainer: base + Node.js 24 + npm 12"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER 0

# --- libatomic1. The official linux-x64 node binary is dynamically linked against
# libatomic.so.1 from Node 26 on (24.x loaded without it), and Ubuntu's minimal base
# does not ship it, so `node` dies at load with "error while loading shared libraries:
# libatomic.so.1" (#450, seen on the 24 -> 26 bump, #436). It belongs here rather than in
# base: only the node binary needs it, and base carries no node. Unpinned like base's apt
# layer (DL3008), for the same reason (see there): the base digest plus the weekly rebuild
# bound it.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --no-install-recommends -y libatomic1 \
    && rm -rf /var/lib/apt/lists/*

# --- Node.js, the official linux-x64 tarball. The sha256 is read from
# https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt.
# Residual risk: that file is fetched over TLS but its detached GPG signature
# (SHASUMS256.txt.asc) is not verified here. Doing that needs the Node release team's
# keyring pinned in this repo; tracked in docs/threat_model.md § "Known gaps".
ARG NODE_VERSION=26.13.0
ARG NODE_SHA256=d28a96af6c38596f6d9d97c0ee531c13d238d757742387d1928de822d959e997
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
        -o /tmp/node.tar.xz \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
        --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' \
    && rm /tmp/node.tar.xz \
    && node --version && npm --version

# --- npm 12. Node 24.22.2 bundles npm 11.19.1; we move to npm 12, the standard the
# fleet is taking (#27). This is a major above what Node 24 bundles, so consuming
# repos' CI (`setup-node`, `node-version: 24`, npm 11 bundled) no longer matches the
# image until each takes npm 12 in CI (#27). The tarball is verified against the
# registry's published sha512 `integrity`, the same check `npm ci` applies to every
# package.
# Drop this block once the image's Node major bundles npm >= 12.2.2 (the first npm 12
# whose bundled undici, 6.29.1, carries the CVE fixes the image used to swap in).
ARG NPM_VERSION=12.2.2
ARG NPM_INTEGRITY=sha512-KglgbZyacf7jH+FHuNRqVuCzQi8VhI2a7J87Ix43FsPTuZoGWmIXXGdZtBUOA79vwL+IJREqURVzupA7PsQTcA==
RUN curl -fsSL "https://registry.npmjs.org/npm/-/npm-${NPM_VERSION}.tgz" -o /tmp/npm.tgz \
    && test "sha512-$(openssl dgst -sha512 -binary /tmp/npm.tgz | base64 -w0)" = "${NPM_INTEGRITY}" \
    && npm install -g --no-audit --no-fund /tmp/npm.tgz \
    && rm /tmp/npm.tgz \
    && test "$(npm --version)" = "${NPM_VERSION}"

# npm's download cache lives in the per-repo home volume (~/.local/npm-cache), NOT in the
# shared tofu cache volume. Only `npm ci` verifies tarballs against package-lock.json's sha512
# `integrity` field. `npx` and `npm exec` keep installed packages under <cache>/_npx and run
# them again without a check, and `npm install <pkg>` trusts cached metadata, so a cache
# shared between repos would let one repo's container plant code another runs.
# NPM_CONFIG_PREFIX puts `npm install -g` into the home volume (its bin is on PATH), since
# /usr/local is read-only at run time.
# PUPPETEER_CACHE_DIR: Puppeteer hard-codes ~/.cache/puppeteer and ignores XDG_CACHE_HOME;
# this keeps its downloaded Chrome under ~/.local with the other caches.
# The update notifier is off because it phones home on every npm invocation.
ENV NPM_CONFIG_CACHE=/home/app/.local/npm-cache \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_PREFIX=/home/app/.local \
    PUPPETEER_CACHE_DIR=/home/app/.local/puppeteer

USER 1000:1000
