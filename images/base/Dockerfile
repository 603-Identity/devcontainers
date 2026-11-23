# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
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
# Ubuntu 26.04. The Ubuntu major tracks GitHub's `ubuntu-latest` runner. The Python
# standard for consuming repos is the pinned interpreter installed below (its version is
# the PYTHON_VERSION ARG), not Ubuntu's apt Python 3.14, which stays only for apt's own
# tools and the tools venv. The weekly bump re-pins the interpreter within its minor; a change of
# minor is a deliberate hand re-pin, together with tests/smoke.sh's major.minor checks and DEVC-D11.
FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

LABEL org.opencontainers.image.source="https://github.com/603-Identity/devcontainers" \
      org.opencontainers.image.description="Shared devcontainer base: git, gh, jq, yq, uv, pre-commit, betterleaks, zizmor, non-root app user" \
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
# `apt-get upgrade` is what makes that true for the packages the base image itself ships
# (apt, libc, ...): `install` alone never touches them, and the digest only moves when
# Canonical republishes the image. #494: apt 3.2.0 (CVE-2026-109518) sat in the pinned
# image while the archive already had the fix.
# /usr/bin/pebble is removed (#625): the ubuntu:26.04 image is a rockcraft build whose pebble
# service manager (not an apt package) carries CVE-2026-97054, and nothing in these images starts it.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y \
        ca-certificates curl git gnupg jq less openssh-client procps \
        python3 python3-venv unzip xz-utils \
    && rm -f /usr/bin/pebble && rm -rf /var/lib/pebble \
    && rm -rf /var/lib/apt/lists/*

# --- gh CLI, from the release tarball rather than the apt repo so the version is
# pinned and checksum-verified like every other binary here.
ARG GH_VERSION=2.105.0
ARG GH_SHA256=79e7ab5db738c48777b696e374f8b428f0647debfb424f44d2f426370407fe2f
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
        -o /tmp/gh.tar.gz \
    && echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64"

# --- yq (mikefarah v4, NOT the python `yq`, which has a different syntax). Required
# by way-of-working >= v0.13.0's /way-of-working:resume (bin/schema-complete.sh).
ARG YQ_VERSION=4.54.3
ARG YQ_SHA256=129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
        -o /tmp/yq \
    && echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c - \
    && install -m 0755 /tmp/yq /usr/local/bin/yq \
    && rm /tmp/yq

# --- Betterleaks, the org secret scanner (#190). ARG-pinned like every binary here. These two
# ARGs are also the single version authority for CI: .github/workflows/secret-scan.yml reads
# them at the caller's pinned commit, so the scanner a PR is checked with and the one in the
# container are the same release. The sha256 is the linux_x64 tarball's entry in the release's
# checksums.txt, which `bump-binaries.sh betterleaks` verifies against its sigstore bundle
# (signer: betterleaks/betterleaks release.yml at refs/tags/v<version>, issuer
# https://token.actions.githubusercontent.com) before taking it.
# /usr/local/bin/betterleaks is an absolute path on purpose: ~/.local/bin leads PATH.
ARG BETTERLEAKS_VERSION=2.0.0-rc.8
ARG BETTERLEAKS_SHA256=323a6476ffe06a52fc6bc1c293eb98e3f17d2bfb0110f08feedd38ea3b00e38f
RUN curl -fsSL "https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/betterleaks_${BETTERLEAKS_VERSION}_linux_x64.tar.gz" \
        -o /tmp/betterleaks.tar.gz \
    && echo "${BETTERLEAKS_SHA256}  /tmp/betterleaks.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/betterleaks.tar.gz -C /tmp betterleaks \
    && install -m 0755 /tmp/betterleaks /usr/local/bin/betterleaks \
    && rm -f /tmp/betterleaks.tar.gz /tmp/betterleaks

# The org rule set. A repo's own betterleaks.toml may only `extend` this exact path (the
# lint in tools/secret-scan-lint.sh enforces it); CI installs the same file at the same path.
# The directory is created first: --chmod on a COPY also sets the mode of the parent
# directories it creates, and 0644 would make /usr/local/share/devc untraversable for `app`.
RUN install -d -m 0755 /usr/local/share/devc /usr/local/share/devc/secret-scan
COPY --chmod=0644 files/secret-scan/org.toml /usr/local/share/devc/secret-scan/org.toml

# --- uv, the project manager for every Python repo. The sha256 is the release's own
# published `.sha256` asset (also verifiable with `gh attestation verify --repo
# astral-sh/uv`). The image carries two interpreters (the pinned 3.15 below and Ubuntu's
# 3.14); uv downloads one only when neither satisfies the request (another minor, or an
# exact patch other than the pinned one). uv prefers interpreters it manages, so one
# already installed in the home volume is used ahead of the image's.
ARG UV_VERSION=0.13.9
ARG UV_SHA256=a7fbaff2b9a271d85c1bdb540941090fd1ce011797b4abeb48e4dcd39c2471d5
RUN curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
        -o /tmp/uv.tar.gz \
    && echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/uv.tar.gz -C /tmp \
    && install -m 0755 /tmp/uv-x86_64-unknown-linux-gnu/uv /tmp/uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/ \
    && rm -rf /tmp/uv.tar.gz /tmp/uv-x86_64-unknown-linux-gnu

# --- The Python standard for consuming repos: a pinned CPython from astral-sh/python-build-standalone,
# pinned by version AND sha256 like every binary here. The sha256 is the asset's line in the release's own
# published SHA256SUMS, not computed from a first download. Ubuntu 26.04 and `ubuntu-latest` stay on
# 3.14, so this cannot come from apt. The weekly apt rebuild does not touch it; bump-binaries.sh re-pins all three ARGs
# within this major.minor, and a minor change is a hand re-pin (DEVC-D11).
# The `+` between version and build tag is `%2B` in the URL.
# `tar --no-same-owner` keeps the files root-owned (as root, tar would keep the archive's uid, which could
# be 1000, the app user). pip is deleted to keep today's surface (Ubuntu's Python has no pip module);
# `python3 -m venv` still gives each venv its own pip from the stdlib's ensurepip wheel. The
# EXTERNALLY-MANAGED file (PEP 668) makes installers that honour it refuse to write into this interpreter.
# /usr/local/bin precedes /usr/bin on PATH, so a bare `python3`/`python` (and an `env python3` shebang)
# resolves to this one, unless an entry in ~/.local/bin, which leads PATH, shadows it. apt's scripts keep
# their absolute /usr/bin/python3 shebangs and stay on 3.14.
ARG PYTHON_VERSION=3.15.2
ARG PYTHON_BUILD=20261110
ARG PYTHON_SHA256=ad23d1b73fac26440b0306ae06911031344c49a90ec19716c8362e7fa40cae43
RUN curl -fsSL "https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_BUILD}/cpython-${PYTHON_VERSION}%2B${PYTHON_BUILD}-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz" \
        -o /tmp/python.tar.gz \
    && echo "${PYTHON_SHA256}  /tmp/python.tar.gz" | sha256sum -c - \
    && install -d -m 0755 /opt/devc \
    && tar --no-same-owner -xzf /tmp/python.tar.gz -C /opt/devc \
    && rm -f /tmp/python.tar.gz \
    && py_minor="${PYTHON_VERSION%.*}" \
    && rm -rf "/opt/devc/python/lib/python${py_minor}/site-packages/pip" \
        "/opt/devc/python/lib/python${py_minor}"/site-packages/pip-*.dist-info \
    && rm -f /opt/devc/python/bin/pip* \
    && chmod -R go-w /opt/devc/python \
    && printf '[externally-managed]\nError=This interpreter is part of the devcontainer image. Create a virtual environment (python3 -m venv, or uv venv) and install there.\n' \
        > "/opt/devc/python/lib/python${py_minor}/EXTERNALLY-MANAGED" \
    && for n in python3 "python${py_minor}" python; do \
        ln -s "/opt/devc/python/bin/python${py_minor}" "/usr/local/bin/$n"; \
    done

# --- Python tools (pre-commit, zizmor) in their own venv, NOT the
# system site-packages. That avoids --break-system-packages, and it keeps a repo's own
# `python3 -m venv .venv` from inheriting them. Installed only from tools/uv.lock:
# `uv sync --locked` fails on any drift from pyproject.toml and verifies every hash.
# They land on Ubuntu's 3.14 at its apt path (/usr/bin/python3), not the pinned 3.15 above:
# pre-commit depends on PyYAML, whose current release (6.0.3, the one uv.lock resolves)
# publishes no CPython 3.15 wheel, and this step refuses source builds. The tools venv moves
# to 3.15 when the lock can resolve a 3.15 wheel for every package. One consequence:
# pre-commit's own Python hooks default to the interpreter pre-commit runs on, so they run on
# 3.14 unless a repo sets `default_language_version`.
# --no-cache keeps uv's cache out of the image and --no-build refuses source builds, whose
# build requirements are not in the lock.
COPY tools/pyproject.toml tools/uv.lock /opt/devc/tools-src/
RUN UV_PYTHON_DOWNLOADS=never UV_PROJECT_ENVIRONMENT=/opt/devc/tools \
        uv sync --locked --no-cache --no-build --python /usr/bin/python3 --project /opt/devc/tools-src \
    && for b in pre-commit zizmor; do \
        ln -s "/opt/devc/tools/bin/$b" "/usr/local/bin/$b"; \
    done

# --- Start-up scripts, shipped in the image so repos do not each carry a copy.
# A repo's devcontainer.json runs them from postStartCommand; see README.md.
# The dev-App flavour (images/devapp) deletes gpg-check.sh from ITS layer only: the v1.5
# pilots' postStartCommand still calls it from this image, so base keeps shipping it.
COPY --chmod=0755 files/owner-check.sh files/git-identity.sh files/gpg-check.sh /usr/local/share/devc/

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
# uid 1000. The legacy template mounts these (the dev-App template mounts the home
# volume but no tofu-plugins volume; see each devcontainer.json):
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
#     per-repo volume above. (The dev-App flavour, images/devapp, replaces this helper
#     with dev-token and unsets this entry; base and the legacy template keep it.) The helper is an absolute path because ~/.local/bin
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
