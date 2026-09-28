#!/bin/sh
# Resolves the host's git identity/signing config into the container's global
# git config, without letting a read-only bind mount become ~/.gitconfig.
#
# devcontainer.json mounts %USERPROFILE%\.gitconfig-work read-only at
# ~/.gitconfig-host; the Dockerfile gives ~/.gitconfig an `include` pointing at
# ~/.gitconfig-identity. This script points ~/.gitconfig-identity at the
# sidecar, but ONLY when the sidecar is a regular file -- if
# .gitconfig-work is missing on the host, Docker Desktop materialises the bind
# source as an empty directory, and git aborts hard ("fatal: bad config line")
# on an include whose path is a directory. Degrading to an empty file instead
# costs the identity but keeps every other git command working -- the same
# posture gpg-check.sh takes for a missing agent: report loudly, break nothing
# else, and never fail the container's start over it.
#
# A symlink rather than a copy, so edits to the host's config take effect
# without a container restart.
set -eu

HOST_CONFIG="/home/app/.gitconfig-host"
IDENTITY="/home/app/.gitconfig-identity"

if [ -f "$HOST_CONFIG" ]; then
    ln -sfn "$HOST_CONFIG" "$IDENTITY"
    echo "git-identity: including $HOST_CONFIG ($(git config --get user.email 2>/dev/null || echo 'no user.email set'))" >&2
else
    # Replace any stale symlink from a previous start with an empty regular
    # file, so the include stays a no-op instead of resolving to a directory.
    rm -f "$IDENTITY"
    : > "$IDENTITY"
    echo "git-identity: $HOST_CONFIG is not a regular file (%USERPROFILE%\\.gitconfig-work missing on host?), skipping -- commits will have no identity or signing key" >&2
fi
