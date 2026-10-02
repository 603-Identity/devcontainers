#!/bin/sh
# Asserts that commit signing will actually work, at container start rather
# than at commit time. This repo sets commit.gpgsign=true, so an unsigned-
# capable container fails on the FIRST commit, after the work is done --
# which is how Sprint 04 lost a commit to an unreachable pinentry prompt.
#
# Signing here is provided entirely by VS Code's GPG agent forwarding
# (VS Code Dev Containers), which creates a real unix socket at
# ~/.gnupg/S.gpg-agent over the server's stdio channel before postStart runs,
# and connects it to the host's RESTRICTED agent endpoint -- `GETINFO
# restricted` returns OK through it, so the host will sign but will not
# export the private key. No mount, no relay and no host env var are involved.
#
# A DIFFERENT failure, which this script cannot see (it runs once, at start): mid-session
# `gpg: signing failed: Timeout` means the HOST passphrase cache expired and a pinentry
# prompt is waiting on the host. README.md "Host signing policy" is the fix; nothing in the
# image can warm or extend that cache.
#
# This replaced a socat relay (see git history: .devcontainer/gpg-forward.sh,
# adapted from glunk-works/loop-orchestrator PR #81). Do not re-add that
# without measuring first: it bind-mounted GPG_HOST_DIR and relayed the
# agent's port to host.docker.internal, and on this host it never carried a
# single signature. Gpg4win binds the agent to the Windows host's 127.0.0.1
# and Docker Desktop's gateway does not reach host loopback, so every
# connection timed out. It also forwarded the FULL agent socket, i.e. it was
# strictly less restricted than what VS Code already provides. Verify with
# `timeout 5 socat -u TCP:host.docker.internal:<port> /dev/null` before
# believing otherwise.
set -eu

AGENT_SOCK="${GNUPGHOME:-/home/app/.gnupg}/S.gpg-agent"

if [ -S "$AGENT_SOCK" ] \
    && gpg-connect-agent --no-autostart 'getinfo version' /bye >/dev/null 2>&1; then
    exit 0
fi

# Deliberately loud, and deliberately exit 0: a failed postStartCommand is
# reported as a container-start error, which buries the actual message.
echo '' >&2
echo '  ############################################################' >&2
echo '  # gpg-check: NO GPG AGENT -- COMMIT SIGNING WILL FAIL       #' >&2
echo '  ############################################################' >&2
echo '  # This repo sets commit.gpgsign=true, so "git commit" will  #' >&2
echo '  # fail until an agent answers at:                           #' >&2
echo "  #   $AGENT_SOCK" >&2
echo '  #                                                           #' >&2
echo '  # Signing is provided by VS Code agent forwarding, so       #' >&2
echo '  # this is expected in a session with no VS Code attached    #' >&2
echo '  # ("devcontainer up", a bare "docker exec", CI). Commit     #' >&2
echo '  # from a VS Code terminal, or sign on the host.             #' >&2
echo '  #                                                           #' >&2
echo '  # Later "gpg: signing failed: Timeout" = the HOST cache     #' >&2
echo '  # expired; see README.md "Host signing policy".             #' >&2
echo '  ############################################################' >&2
echo '' >&2
exit 0
