# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# Shared devcontainer BASE image: the tools every consuming repo needs, and nothing
# a specific toolchain needs. `tofu` and `node` build FROM this image; a repo's own
# .devcontainer/Dockerfile builds FROM one of the three and adds only its extras.
#
# Pinning rules, applied to every download below:
#   * the base image is pinned by DIGEST, not by tag;
#   * every binary is pinned by version AND sha256, and the sha256 was read from the
#     project's own published checksum file for that release, not computed from a
#     first download (trust-on-first-use);
#   * Python tools install only from a hash-carrying lock (uv sync --locked);
#   * the `# syntax=` frontend on line 1 is pinned by digest too, so no floating image
#     is left in the build.
# apt packages are the one deliberate exception (see the apt block).
#
# Ubuntu 26.04. Its system Python 3.14 is the Python standard for consuming repos. The
# major tracks GitHub's `ubuntu-latest` runner. Re-pin it deliberately, together with
# tests/smoke.sh's Python check.
FROM ubuntu:26.04@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78

LABEL org.opencontainers.image.source="https://github.com/603-Identity/devcontainers" \
      org.opencontainers.image.description="Shared devcontainer base: git, gh, jq, yq, uv, pre-commit, bc-detect-secrets, zizmor, non-root app user" \
      org.opencontainers.image.licenses="NOASSERTION"

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Every binary downloaded below is linux amd64. Fail here, with a clear message, on any
# other architecture instead of letting each tool die at runtime with `exec format error`.
RUN [ "$(uname -m)" = x86_64 ] \
    || { echo "devc images are linux/amd64 only; this host reports $(uname -m)" >&2; exit 1; }

# Ubuntu's base image ships a built-in `ubuntu` user at uid/gid 1000. Remove it so `app` can
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
ARG GH_VERSION=2.102.0
ARG GH_SHA256=bb766f710eef8ede859c18578c72c327597cd4c8a85b06001b1f3843c6019386
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

# --- uv, the project manager for every Python repo. The sha256 is the release's own
# published `.sha256` asset (also verifiable with `gh attestation verify --repo
# astral-sh/uv`). uv provisions an older interpreter only for a repo whose
# `.python-version` asks for one; the image itself carries no alternate interpreter.
ARG UV_VERSION=0.12.21
ARG UV_SHA256=23f02075b652bb1df64178cfae41b5caf160822e720e2663568f3f5d63bc52c0
RUN curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
        -o /tmp/uv.tar.gz \
    && echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/uv.tar.gz -C /tmp \
    && install -m 0755 /tmp/uv-x86_64-unknown-linux-gnu/uv /tmp/uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/ \
    && rm -rf /tmp/uv.tar.gz /tmp/uv-x86_64-unknown-linux-gnu

# --- Python tools (pre-commit, bc-detect-secrets, zizmor) in their own venv, NOT the
# system site-packages. That avoids --break-system-packages, and it keeps a repo's own
# `python3 -m venv .venv` from inheriting them. Installed only from tools/uv.lock:
# `uv sync --locked` fails on any drift from pyproject.toml and verifies every hash.
# They land on the system interpreter; --no-cache keeps uv's cache out of the image and
# --no-build refuses source builds, whose build requirements are not in the lock.
# bc-detect-secrets is pinned in tools/pyproject.toml because every consuming repo's
# .secrets.baseline and CI secret-scan job pin that version.
COPY tools/pyproject.toml tools/uv.lock /opt/devc/tools-src/
RUN UV_PYTHON_DOWNLOADS=never UV_PROJECT_ENVIRONMENT=/opt/devc/tools \
        uv sync --locked --no-cache --no-build --python /usr/bin/python3 --project /opt/devc/tools-src \
    && for b in pre-commit detect-secrets detect-secrets-hook zizmor; do \
        ln -s "/opt/devc/tools/bin/$b" "/usr/local/bin/$b"; \
    done

# --- Start-up scripts, shipped in the image so repos do not each carry a copy.
# A repo's devcontainer.json runs them from postStartCommand; see README.md.
COPY --chmod=0755 files/git-identity.sh files/gpg-check.sh /usr/local/share/devc/

# --- git config layout. ~/.gitconfig (an include of ~/.gitconfig-identity) is NOT in the
# image: /home/app is a per-repo volume, which freezes whatever the image holds there at
# first mount. git-identity.sh writes ~/.gitconfig at every start, and GENERATES
# ~/.gitconfig-identity beside it: it projects five identity keys from the host file that
# claims the origin's org (the host's ~/.gitconfig.d is mounted read-only), and never
# includes the host file itself. An absent identity file means "no identity"; git ignores
# an include whose path is missing. System git settings stay in /etc/gitconfig below.

# --- Mount point for the host's identity directory (~/.gitconfig.d, read-only), created
# in the RUN below. It gives the bind mount a stable, app-owned target; once mounted, the
# host's ownership shows instead. It is not what makes an unmounted run safe:
# git-identity.sh treats a missing directory like an empty one.

# --- Mount points for named volumes, pre-created app-owned. Docker initialises an
# empty named volume from the image directory at its mount point, ownership
# included; a path missing from the image comes up root-owned and unwritable as
# uid 1000. The template mounts (see its devcontainer.json):
#   ~/ (/home/app)     per-repo home volume. It holds every user-scoped file: the gh
#                      credential, Claude sessions, the editor server and extensions, uv's
#                      interpreters and cache, the pre-commit and tflint caches. The
#                      image's own /home/app is copied in at first mount and never again,
#                      so image-owned configuration must not live there.
#   ~/.cache/tofu-plugins
#                      the ONE volume shared by every repo on the host, in every org. It
#                      holds only tofu's provider cache, which `tofu init` checks against
#                      the consuming repo's .terraform.lock.hcl. It is mounted at this one
#                      directory, not over ~/.cache, so the rest of ~/.cache (and anything
#                      that hard-codes it) is ordinary per-repo home-volume space.
#                      It is created here, in base, so it exists whichever flavor first
#                      initialises the volume: tofu does not create a missing plugin
#                      cache directory.
#   ~/.local           created here so it is app-owned: it is the parent of every cache
#                      directory below. A derived image must not install into /home/app
#                      (the volume would never see it), least of all as root.
#   /workspace/.venv and /workspace/node_modules
#                      per-repo dependency volumes. /workspace itself is the host bind
#                      mount, so these directories live in the image only as mount points.
RUN install -d -o app -g app -m 0755 /home/app/.gitconfig.d /home/app/.local \
        /home/app/.cache /home/app/.cache/tofu-plugins /workspace/.venv /workspace/node_modules

# System-level git settings, so they survive a rebuilt home directory and work from
# the first command in a fresh shell:
#   * GitHub HTTPS credentials come from gh, whose credential lives in the
#     per-repo volume above. The helper is an absolute path because ~/.local/bin
#     (writable by app) leads PATH, so a bare `gh` could be shadowed by accident, e.g. a
#     `uv tool install` entry point named gh. This is hygiene, not a boundary against
#     code running as app (see docs/threat_model.md, boundary 8);
#   * /workspace is a bind mount owned by the host's uid, which git would
#     otherwise refuse as "dubious ownership".
RUN git config --system credential."https://github.com".helper "" \
    && git config --system --add credential."https://github.com".helper "!/usr/local/bin/gh auth git-credential" \
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

# Devcontainer shells are not login shells, so ~/.local/bin (where `uv tool install`
# puts executables) goes on PATH here, not in a profile script.
ENV PATH=/home/app/.local/bin:$PATH

# Every cache except tofu's shared one lives under ~/.local in the per-repo home volume,
# not in the read-only image and never beside the shared ~/.cache/tofu-plugins.
# XDG_CACHE_HOME moves every XDG-aware tool (pip included) there in one line. uv's cache and the project
# environment (/workspace/.venv) are separate mounts, and hardlinks between mounts fail
# with EXDEV, so uv copies instead.
# GIT_CONFIG_GLOBAL pins git's global file to ~/.gitconfig (which git-identity.sh rewrites
# at every start), so a file planted in the persistent home volume at
# ~/.config/git/config is ignored.
ENV GIT_CONFIG_GLOBAL=/home/app/.gitconfig \
    XDG_CACHE_HOME=/home/app/.local/cache \
    UV_CACHE_DIR=/home/app/.local/uv-cache \
    UV_LINK_MODE=copy \
    PRE_COMMIT_HOME=/home/app/.local/pre-commit

USER 1000:1000
WORKDIR /workspace
