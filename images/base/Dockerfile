# syntax=docker/dockerfile:1
#
# 603-Identity devcontainer BASE image: the tools every org repo needs, and nothing
# a specific toolchain needs. `tofu` and `node` build FROM this image; a repo's own
# .devcontainer/Dockerfile builds FROM one of the three and adds only its extras.
#
# Pinning rules, applied to every download below:
#   * the base image is pinned by DIGEST, not by tag;
#   * every binary is pinned by version AND sha256, and the sha256 was read from the
#     project's own published checksum file for that release, not computed from a
#     first download (trust-on-first-use);
#   * Python tools install only from a hash-locked file (pip --require-hashes).
# apt packages are the one deliberate exception (see the apt block).
#
# Ubuntu 24.04 tracks GitHub Actions' `ubuntu-latest` runner, so the container's
# system Python (3.12) and libc match CI. Re-pin deliberately when the runner moves.
FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3

LABEL org.opencontainers.image.source="https://github.com/603-Identity/devcontainers" \
      org.opencontainers.image.description="603-Identity devcontainer base: git, gh, jq, yq, pre-commit, bc-detect-secrets, non-root app user" \
      org.opencontainers.image.licenses="NOASSERTION"

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ubuntu:24.04 ships a built-in `ubuntu` user at uid/gid 1000. Remove it so `app` can
# take the conventional 1000:1000, which matches the Windows host's file ownership
# as Docker Desktop presents it on the /workspace bind mount.
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupdel ubuntu 2>/dev/null || true \
    && groupadd --gid 1000 app \
    && useradd --uid 1000 --gid app --create-home --shell /bin/bash app

# apt packages are NOT version-pinned (hadolint DL3008). Ubuntu's archive drops
# superseded versions, so an exact pin breaks the build within weeks. What pins this
# layer instead is the base image digest above plus the weekly scheduled rebuild in
# .github/workflows/build.yml, which is also how security updates arrive.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates curl git gnupg jq less openssh-client procps \
        python3 python3-venv unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# --- gh CLI, from the release tarball rather than the apt repo so the version is
# pinned and checksum-verified like every other binary here.
ARG GH_VERSION=2.101.0
ARG GH_SHA256=9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
        -o /tmp/gh.tar.gz \
    && echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64"

# --- yq (mikefarah v4, NOT the python `yq`, which has a different syntax). Required
# by way-of-working >= v0.13.0's /way-of-working:resume (bin/schema-complete.sh).
ARG YQ_VERSION=4.53.6
ARG YQ_SHA256=c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
        -o /tmp/yq \
    && echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c - \
    && install -m 0755 /tmp/yq /usr/local/bin/yq \
    && rm /tmp/yq

# --- Python tools (pre-commit, bc-detect-secrets) in their own venv, NOT the system
# site-packages. That avoids --break-system-packages, and it keeps a repo's own
# `python3 -m venv .venv` from inheriting them. Installed only from the hash lock.
# bc-detect-secrets is pinned to 1.5.47 because every org repo's .secrets.baseline
# and CI secret-scan job pins that version (see tools.in).
COPY tools.lock.txt /opt/603identity/tools.lock.txt
RUN python3 -m venv /opt/603identity/tools \
    && /opt/603identity/tools/bin/pip install --no-cache-dir --require-hashes \
        -r /opt/603identity/tools.lock.txt \
    && for b in pre-commit detect-secrets detect-secrets-hook; do \
        ln -s "/opt/603identity/tools/bin/$b" "/usr/local/bin/$b"; \
    done

# --- Start-up scripts, shipped in the image so repos do not each carry a copy.
# A repo's devcontainer.json runs them from postStartCommand; see README.md.
COPY --chmod=0755 files/git-identity.sh files/gpg-check.sh /usr/local/share/603identity/

# --- git config layout. The host's gitconfig is bind-mounted READ-ONLY at
# ~/.gitconfig-host. That mount cannot BE ~/.gitconfig, because every
# `git config --global` would then fail. So a writable ~/.gitconfig includes
# ~/.gitconfig-identity, which git-identity.sh points at the sidecar only when it is
# a regular file. The empty placeholder is the safe default until that runs.
RUN printf '[include]\n\tpath = /home/app/.gitconfig-identity\n' > /home/app/.gitconfig \
    && : > /home/app/.gitconfig-identity \
    && chown app:app /home/app/.gitconfig /home/app/.gitconfig-identity

# --- Mount points for named volumes, pre-created app-owned. Docker initialises an
# empty named volume from the image directory at its mount point, ownership
# included; a path missing from the image comes up root-owned and unwritable as
# uid 1000.
#   ~/.config/gh  per-repo GitHub credential (a fine-grained PAT, see README.md)
#   ~/.claude     per-repo Claude Code sessions and memory
#   ~/.cache      shared, integrity-checked download caches (tofu providers, npm)
RUN install -d -o app -g app -m 0755 /home/app/.config /home/app/.cache \
    && install -d -o app -g app -m 0700 /home/app/.config/gh /home/app/.claude \
    && install -o app -g app -m 0600 /dev/null /home/app/.config/gh/.keep \
    && install -o app -g app -m 0600 /dev/null /home/app/.claude/.keep

# System-level git settings, so they survive a rebuilt home directory and work from
# the first command in a fresh shell:
#   * GitHub HTTPS credentials come from gh, whose credential lives in the
#     per-repo volume above;
#   * /workspace is a bind mount owned by the host's uid, which git would
#     otherwise refuse as "dubious ownership".
RUN git config --system credential."https://github.com".helper "" \
    && git config --system --add credential."https://github.com".helper "!gh auth git-credential" \
    && git config --system --add safe.directory /workspace

# Hardening: strip every setuid/setgid bit (su, passwd, chsh, mount, ...). The app
# user has no password and no sudo, so these binaries serve no purpose here, and each
# is a classic privilege-escalation path. Belt-and-braces with the template's
# `--security-opt=no-new-privileges`, which neuters them at runtime anyway.
# tests/smoke.sh asserts that none remain.
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# GitHub's published ed25519 host key, set system-wide so the first ssh fetch has
# no trust-on-first-use prompt. Source: GitHub docs, "GitHub's SSH key fingerprints".
RUN echo 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
        > /etc/ssh/ssh_known_hosts

USER 1000:1000
WORKDIR /workspace
