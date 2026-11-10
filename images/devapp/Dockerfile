# syntax=docker/dockerfile:1.28@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
#
# Shared devcontainer DEV-APP flavour: the base or tofu image, plus a GitHub identity that
# is a per-repository dev App installation token and nothing else (DEVC-D9, recorded through #393; #418). This one
# Dockerfile builds BOTH published images, by BASE_IMAGE:
#
#   devcontainer-devapp       FROM devcontainer-base@<digest of the same run>
#   devcontainer-devapp-tofu  FROM devcontainer-tofu@<digest of the same run>
#
# Always build it through .github/scripts/build-and-test.sh (`bash .github/scripts/build-and-test.sh
# local`), which builds base, then the `claude-verify` stage (exported with --output type=local),
# then this image with `--build-context claude-export=<that directory>`. A bare `docker build`
# of this directory fails: claude-export is a named context, not a stage or an image.
#
# What this layer changes, and only in this flavour (base, tofu and node are untouched, and
# the legacy template keeps working on them):
#   * `gh` is a wrapper and git's credential helper is dev-token. Both read ONLY
#     /run/wow/dev-token, and refuse when it is absent or stale: they fail closed;
#   * gpg, gpg-agent, gpgconf, gpg-connect-agent and gpgsm are removed (gpgv stays), so no
#     private key and no agent can exist here; git-identity.sh projects signing off, via the
#     marker below;
#   * `claude` is installed from a binary verified against Anthropic's signature, with
#     root-owned managed settings that turn off its updater and pin its version;
#   * `plugin-install.sh` installs the repo's pinned Claude Code plugins at user scope, at the end
#     of every start, and fails the start loudly when it cannot (#503);
#   * the usual GNU coreutils replace Ubuntu 26.04's Rust ones on PATH.
#
# BASE_IMAGE is always passed by digest in CI; the default is for local builds only.
ARG BASE_IMAGE=devcontainer-base:local

# --- claude. One pin, and the only version authority for `claude`: CLAUDE_VERSION is the
# release, CLAUDE_SHA256 the linux-x64 checksum from that release's signed manifest.json
# (read it from there, never from a first download; claude-fetch.sh refuses a pin the
# manifest does not carry). Both ARGs are read by .github/scripts/build-and-test.sh for the
# smoke test. A bump is manual for now: change both, with a PR that says which release.
ARG CLAUDE_VERSION=2.1.316
ARG CLAUDE_SHA256=fd13c70000fec3f2116dfbcbb6121210b4a29328bf0e46210a59dd594a67d824

# --- Stage 1: fetch and verify claude. It runs as root on the base (which has curl, jq and
# gpg), and it is the whole of the build-time trust decision about the binary.
# hadolint ignore=DL3006
FROM ${BASE_IMAGE} AS claude-fetch
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# This stage runs as root and is never an image: only /out/claude leaves it.
# hadolint ignore=DL3002
USER 0
ARG CLAUDE_VERSION
ARG CLAUDE_SHA256
COPY --chmod=0644 files/claude-release.asc /tmp/claude-release.asc
COPY --chmod=0755 files/claude-fetch.sh /tmp/claude-fetch.sh
RUN /tmp/claude-fetch.sh "${CLAUDE_VERSION}" "${CLAUDE_SHA256}" /tmp/claude-release.asc /out

# --- Stage 2: the verified binary alone. build-and-test.sh builds this target FIRST,
# before anything is pushed, exports it with `--output type=local`, and hands the result
# to both devapp builds as the named context `claude-export`. A download or signature
# failure therefore stops the run before the registry sees a byte, and `claude` is fetched
# and verified once for both images, not once per image.
FROM scratch AS claude-verify
COPY --from=claude-fetch /out/claude /claude

# --- Stage 3: the image.
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

ARG CLAUDE_VERSION
ARG CLAUDE_SHA256
LABEL org.opencontainers.image.source="https://github.com/603-Identity/devcontainers" \
      org.opencontainers.image.description="Shared devcontainer, dev-App flavour: GitHub identity from a per-repository dev token only, no gpg, claude verified"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER 0

# --- GNU coreutils. Ubuntu 26.04 ships uutils (Rust) coreutils as /usr/bin/<name>, and
# its `date` and `timeout` differ from the GNU tools the scripts here and the repos'
# hooks are written against. gnu-coreutils installs the GNU build as /usr/bin/gnu<name>;
# /usr/local/bin leads PATH ahead of /usr/bin but behind ~/.local/bin, so a link per name
# there is what makes `date` mean GNU date. The wrappers' own PATH reads /usr/local/bin
# first too. tests/smoke-devapp.sh asserts `timeout`, the `date` width and the package.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --no-install-recommends -y gnu-coreutils \
    && rm -rf /var/lib/apt/lists/* \
    && dpkg -L gnu-coreutils | while read -r g; do \
        case "$g" in /usr/bin/gnu?*) n="${g#/usr/bin/gnu}"; \
            if [ ! -e "/usr/local/bin/$n" ]; then ln -s "$g" "/usr/local/bin/$n" || exit 1; fi ;; esac; \
    done

# --- The identity layer.
# gh moves out of PATH's reach; the wrapper takes its place. dev-token is the credential
# helper and the wrapper's token reader. All of them are root-owned and not writable by app.
RUN install -d -m 0755 /usr/local/libexec \
    && mv /usr/local/bin/gh /usr/local/libexec/gh-real
COPY --chmod=0755 files/dev-token /usr/local/libexec/dev-token
COPY --chmod=0755 files/gh /usr/local/bin/gh
COPY --chmod=0755 files/devapp-check.sh /usr/local/share/devc/devapp-check.sh
COPY --chmod=0755 files/plugin-install.sh /usr/local/share/devc/plugin-install.sh

# System git: the helper list is reset, then dev-token is the only helper, for every host (it
# answers `quit=1` to all but https github.com, which stops git trying anything else). base's
# own gh helper is unset first. The ssh spellings of a github.com remote listed below are
# rewritten to https, so a clone made over ssh still goes through dev-token. The list is exact:
# a spelling not on it (a different case of the host, say) still goes over ssh, with whatever
# key or agent is present (docs/threat_model.md, Known gaps).
RUN git config --system --unset-all credential."https://github.com".helper \
    && git config --system credential.helper "" \
    && git config --system --add credential.helper /usr/local/libexec/dev-token \
    && for p in 'git@github.com:' 'github.com:' 'ssh://git@github.com/' 'ssh://github.com/' 'ssh://git@github.com:22/' 'ssh://git@ssh.github.com:443/' 'git@ssh.github.com:'; do \
        git config --system --add url."https://github.com/".insteadOf "$p"; \
    done

# --- Signing is off in this flavour. No private key and no agent exist here: the signing
# programs go (gpgv, which only verifies, stays), and so does gpg-check.sh, which asserts a
# working agent. It is deleted from THIS layer only: the v1.5 pilots' postStartCommand still
# calls it from base, so base keeps it. The marker tells git-identity.sh to project
# commit.gpgsign=false and tag.gpgsign=false and never user.signingkey. A repo-local
# commit.gpgsign=true then makes commits fail, which fails closed (README, "Git identity").
RUN rm -f /usr/bin/gpg /usr/bin/gpg-agent /usr/bin/gpgconf /usr/bin/gpg-connect-agent /usr/bin/gpgsm \
        /usr/local/share/devc/gpg-check.sh \
    && : >/usr/local/share/devc/unsigned \
    && chmod 0644 /usr/local/share/devc/unsigned

# --- claude, from the build context the pre-push stage exported. The checksum is checked
# again here against the same pin, so the file in the image is the file that was verified.
# Root-owned, mode 0755, in /usr/local/bin: app cannot replace it.
# claude-export is a build context, not a stage (--build-context claude-export=<dir>).
# hadolint ignore=DL3022
COPY --from=claude-export --chmod=0755 /claude /usr/local/bin/claude
RUN echo "${CLAUDE_SHA256}  /usr/local/bin/claude" | sha256sum -c - \
    && [ ! -e /etc/claude-code ] \
    && install -d -m 0755 /etc/claude-code \
    && jq -n --arg v "${CLAUDE_VERSION}" \
        '{env: {DISABLE_UPDATES: "1", DISABLE_AUTOUPDATER: "1"}, requiredMinimumVersion: $v, requiredMaximumVersion: $v}' \
        >/etc/claude-code/managed-settings.json \
    && chmod 0444 /etc/claude-code/managed-settings.json

# Stripping setuid/setgid was done in base; this layer installed packages, so do it again.
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# git never prompts for a credential, and neither updater runs. The managed settings carry
# the two DISABLE_* variables for claude's own process; the image ENV is the same for every
# other process.
ENV GIT_TERMINAL_PROMPT=0 \
    DISABLE_UPDATES=1 \
    DISABLE_AUTOUPDATER=1

# CI passes the commit it built; a local build carries the local HEAD (or "unknown"). `docker inspect` on two tags shows
# which commits they came from (README: "Comparing two tags"). Declared last, so a new commit
# invalidates no layer above it.
ARG REVISION=unknown
LABEL org.opencontainers.image.revision="${REVISION}"

USER 1000:1000
