#!/bin/sh
# devapp-check.sh: runs from postStartCommand BEFORE git-identity.sh in a dev-App
# container, and always exits 0 (a failed postStartCommand buries its own message). It
# removes what a dev-App container must not carry, and says so loudly when something is
# wrong that it cannot fix.
#
#   * a leftover ~/.config/gh/hosts.yml and ~/.git-credentials. They are credentials from a
#     time before this container (a PAT login in a home volume that outlived its image, or a
#     tool that wrote one). The wrapper ignores hosts.yml, but git would use .git-credentials
#     only through a `store` helper that this image does not configure; neither should be
#     left to be found by something else. rm -rf, because either could be a directory. If
#     ~/.config or ~/.config/gh is a symlink, rm would follow it out of the volume, so the
#     file is left alone and a warning says so.
#   * a forwarded agent. SSH_AUTH_SOCK, a VS Code ssh-agent or gpg-agent socket: a dev-App
#     container signs and authenticates with the dev token alone, so an agent being there
#     means the container was opened by a route that is not the launcher.
#   * a `claude` that is not /usr/local/bin/claude, found first on PATH. The one in /usr/local/bin
#     was verified against Anthropic's signature at build time; ~/.local/bin leads PATH and a
#     `claude` installed there (the stock updater does this) is not that binary.
#
# Deliberately `set -u` and NOT `set -e`, like git-identity.sh.
set -u

HOME_DIR=${HOME:-/home/app}

banner() { # banner <title> <detail...>
    title=$1; shift
    echo '' >&2
    echo '  ############################################################' >&2
    printf '  # devapp-check: %s\n' "$title" >&2
    for d in "$@"; do printf '  # %s\n' "$d" >&2; done
    echo '  ############################################################' >&2
    echo '' >&2
}

if [ -L "$HOME_DIR/.config" ] || [ -L "$HOME_DIR/.config/gh" ]; then
    echo "devapp-check: ~/.config or ~/.config/gh is a symlink; leaving hosts.yml alone" >&2
else
    rm -rf -- "$HOME_DIR/.config/gh/hosts.yml"
fi
rm -rf -- "$HOME_DIR/.git-credentials"

agent=
[ -z "${SSH_AUTH_SOCK:-}" ] || agent="SSH_AUTH_SOCK is set"
for s in "$HOME_DIR"/.gnupg/S.gpg-agent* /tmp/vscode-ssh-auth-*.sock /tmp/ssh-*/agent.*; do
    [ -S "$s" ] && agent="an agent socket exists ($s)"
done
if [ -n "$agent" ]; then
    banner "AN AGENT IS FORWARDED INTO THIS CONTAINER" "$agent" \
        "A dev-App container uses the dev token only. Close it and reopen it" \
        "through the launcher."
fi

found=$(command -v claude 2>/dev/null || true)
if [ "$found" != /usr/local/bin/claude ]; then
    banner "claude IS NOT THE VERIFIED ONE" "first on PATH: ${found:-none}" \
        "The verified binary is /usr/local/bin/claude. Remove the other one."
fi

exit 0
