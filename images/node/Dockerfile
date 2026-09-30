# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
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

# --- npm 12. Node 24.21.0 bundles npm 11.19.0; we move to npm 12, the standard the
# fleet is taking (#27). This is a major above what Node 24 bundles, so consuming
# repos' CI (`setup-node`, `node-version: 24`, npm 11 bundled) no longer matches the
# image until each takes npm 12 in CI (#27). The tarball is verified against the
# registry's published sha512 `integrity`, the same check `npm ci` applies to every
# package.
# Drop this block once the image's Node major bundles npm >= 12.2.0.
ARG NPM_VERSION=12.2.0
ARG NPM_INTEGRITY=sha512-ZsJjKpTnlmSXOLLXiU1xDCzC4Wlok4IwZmh/aw2KUuXytU7q6qMv/cUT7MoeSf95Slwuw/lRXYefGzGCspHPNQ==
RUN curl -fsSL "https://registry.npmjs.org/npm/-/npm-${NPM_VERSION}.tgz" -o /tmp/npm.tgz \
    && test "sha512-$(openssl dgst -sha512 -binary /tmp/npm.tgz | base64 -w0)" = "${NPM_INTEGRITY}" \
    && npm install -g --no-audit --no-fund /tmp/npm.tgz \
    && rm /tmp/npm.tgz \
    && test "$(npm --version)" = "${NPM_VERSION}"

# --- Two packages bundled inside npm 12.2.0 carry HIGH CVEs, and no npm release bundles
# fixed copies yet, so each is replaced in place with a fixed registry release, checked
# against that release's published sha512 `integrity` exactly as the npm tarball is.
#   brace-expansion 5.0.9 -> 5.0.12 (CVE-2026-102276, fixed in 5.0.10;
#     CVE-2026-102278, fixed in 5.0.11). The bundled minimatch requires ^5.0.5.
#   undici 6.28.0 -> 6.29.0 (CVE-2026-19534, fixed in 6.28.1). The bundled node-gyp
#     requires ^6.25.0; 6.29.0 is the newest 6.x.
# brace-expansion's one dependency (balanced-match ^4.0.2) is already bundled; undici has
# none. The replaced versions are asserted after the swap, and brace-expansion is loaded
# once so a missing dependency fails the build.
# Once npm bundles a package at or above its pin here, the build fails rather than let the
# swap downgrade it: remove that package's swap line and ARGs, and the whole block when
# neither remains.
ARG BRACE_EXPANSION_VERSION=5.0.12
ARG BRACE_EXPANSION_INTEGRITY=sha512-YovQ3rzhaLMIrDjNDMkNS01tea93qhEhG5xy8f6+R0l+dw3Ki+5sCoIoI942iuLZTHWogWktgwVDhU09iNEimQ==
ARG UNDICI_VERSION=6.29.0
ARG UNDICI_INTEGRITY=sha512-R+RODBqp6i2pPflGdq+xIOUkl+RNfGgHwoinecKu/JCuf2uO06cOKoDbI2P7Dn6KcswdKwrczbU6IYJ6K8X+wg==
RUN set -eu; \
    npm_modules=/usr/local/lib/node_modules/npm/node_modules; \
    swap() { \
        name="$1"; version="$2"; integrity="$3"; \
        bundled="$(node -p "require('${npm_modules}/${name}/package.json').version")"; \
        rc=0; \
        node -e "process.exit(require(process.argv[1]).gte(process.argv[2], process.argv[3]) ? 3 : 0)" \
            "${npm_modules}/semver" "${bundled}" "${version}" || rc=$?; \
        if [ "$rc" -eq 3 ]; then \
            echo "npm bundles ${name} ${bundled}, at or above ${version}: drop this swap" >&2; exit 1; \
        elif [ "$rc" -ne 0 ]; then \
            echo "could not compare ${name} ${bundled} with ${version}" >&2; exit 1; \
        fi; \
        curl -fsSL "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz" -o /tmp/pkg.tgz; \
        test "sha512-$(openssl dgst -sha512 -binary /tmp/pkg.tgz | base64 -w0)" = "${integrity}"; \
        rm -rf "${npm_modules:?}/${name}"; \
        mkdir "${npm_modules}/${name}"; \
        tar -xzf /tmp/pkg.tgz -C "${npm_modules}/${name}" --strip-components=1 --no-same-owner; \
        rm /tmp/pkg.tgz; \
        test "$(node -p "require('${npm_modules}/${name}/package.json').version")" = "${version}"; \
    }; \
    swap brace-expansion "${BRACE_EXPANSION_VERSION}" "${BRACE_EXPANSION_INTEGRITY}"; \
    swap undici "${UNDICI_VERSION}" "${UNDICI_INTEGRITY}"; \
    node -e "require('${npm_modules}/brace-expansion').expand('a{b,c}')"; \
    test "$(npm --version)" = "${NPM_VERSION}"

# npm's download cache lives in the per-repo home volume (~/.local/npm-cache), NOT in the
# shared ~/.cache. Only `npm ci` verifies tarballs against package-lock.json's sha512
# `integrity` field. `npx` and `npm exec` keep installed packages under <cache>/_npx and run
# them again without a check, and `npm install <pkg>` trusts cached metadata, so a cache
# shared between repos would let one repo's container plant code another runs.
# NPM_CONFIG_PREFIX puts `npm install -g` into the home volume (its bin is on PATH), since
# /usr/local is read-only at run time.
# PUPPETEER_CACHE_DIR: Puppeteer hard-codes ~/.cache/puppeteer and ignores XDG_CACHE_HOME, so
# its downloaded Chrome would land in the shared cache volume.
# The update notifier is off because it phones home on every npm invocation.
ENV NPM_CONFIG_CACHE=/home/app/.local/npm-cache \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_PREFIX=/home/app/.local \
    PUPPETEER_CACHE_DIR=/home/app/.local/puppeteer

USER 1000:1000
