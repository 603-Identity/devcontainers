#!/bin/sh
# Builds the container's git identity (~/.gitconfig-identity) from the host's identity
# files, at every container start. It first (re)writes ~/.gitconfig, whose only content
# is an `include` of that file, so nothing else here touches git's global config.
# ~/.gitconfig is written HERE and not shipped in the image because /home/app is a
# per-repo volume: the image's copy would be frozen at first mount, and a stale or
# hand-edited one could never be corrected by a rebuild.
#
# The template mounts the host's ~/.gitconfig.d/ read-only at ~/.gitconfig.d/. It
# holds one git-config file per GitHub account, named <anything>.gitconfig, each
# listing the orgs it serves:
#
#   [devcontainer]
#       org = 603-identity
#
# This script reads /workspace's origin, takes the org from a github.com URL, finds
# the ONE file that claims that org, and PROJECTS five keys from it (user.name,
# user.email, user.signingkey, commit.gpgsign, tag.gpgsign). It never includes or
# links the host file: those files also carry `[credential]` sections whose helper is
# a host path (gh.exe), and a global helper beats the image's system `gh auth
# git-credential`, which broke every HTTPS fetch and push. gpg.* is left out for the
# same reason (host paths and commands), so SSH signing is out of scope. Includes are
# never followed. Host edits take effect at the next container start.
#
# Failing closed: any problem (no origin, a foreign or lookalike origin, no file or
# several files claiming the org, an unreadable file) removes ~/.gitconfig-identity,
# prints a loud banner, and exits 0. "No file" means "no identity"; git ignores an
# include whose path is missing. Like gpg-check.sh, this never fails the container's
# start. Removing, not emptying, is what survives a failed mktemp.
# Fail-safe case: if the current ~/.gitconfig-identity is already broken (a planted
# symlink to a directory, or a real directory), every git call fails through
# ~/.gitconfig's include, even the writes below. That start removes it and gets no
# identity; the next start recovers.
#
# Identity follows remote.origin.url's FIRST value (the fetch URL). A repo with
# several origin URLs, or a pushurl / pushInsteadOf, can push elsewhere under that
# identity. That is an identity, not a credential. GIT_IDENTITY_DIR and
# GIT_IDENTITY_WORKSPACE exist for tests/smoke.sh; a repo's own remoteEnv could set
# them too, which gains it nothing, since it already controls its own mounts.
#
# The origin URL can carry a token in its userinfo, so it is never printed: only the
# org (which the grammar below restricts to [a-z0-9-]) appears in output.
#
# Deliberately `set -u` and NOT `set -e`: `git config --get` exits 1 for an unset key
# and 128 for a malformed file, and either would abort before the final move. Every
# write goes through w(), which is only ever called in the main shell (in $(...), a
# pipeline or ( ... ), its `exit 1` would leave only the subshell).
set -u

OUT=/home/app/.gitconfig-identity
GITCONFIG=/home/app/.gitconfig
IDENTITY_DIR=${GIT_IDENTITY_DIR:-/home/app/.gitconfig.d}
WORKSPACE=${GIT_IDENTITY_WORKSPACE:-/workspace}

# The include stub, before anything else, so it is in place even when the identity below
# is denied. Rewritten, not merged, at every start; temp file + rename, so a planted
# symlink at the destination is replaced rather than written through. Failure is not
# fatal (git then has no global config, which only means no identity).
# A directory there would make every git call fail and defeat the rename; remove it, as
# finish() does for $OUT.
[ ! -d "$GITCONFIG" ] || [ -L "$GITCONFIG" ] || rm -rf -- "$GITCONFIG"
# git's XDG global file is also removed. GIT_CONFIG_GLOBAL (base image ENV) makes git ignore
# it, but pre-commit strips GIT_* variables from the environment of the git it runs, and
# that git reads it: a file planted there by a process in the home volume would survive
# rebuilds and apply to every hook clone. This bounds the persistence; it cannot stop a
# file planted and used within one session.
# rm follows a symlinked PARENT, so a dotfiles tool that links ~/.config or ~/.config/git into
# a checkout must not have that checkout's file deleted: leave the file alone then.
if [ ! -L /home/app/.config ] && [ ! -L /home/app/.config/git ]; then
    rm -rf -- /home/app/.config/git/config
fi
stub=$(mktemp "$GITCONFIG.XXXXXX") || stub=
if [ -n "$stub" ]; then
    if printf '[include]\n\tpath = %s\n' "$OUT" >"$stub" && mv -fT "$stub" "$GITCONFIG"; then :
    else rm -f "$stub"; echo "git-identity: cannot write $GITCONFIG" >&2; fi
else
    echo "git-identity: cannot write $GITCONFIG" >&2
fi

tmp= ; ok=0                        # initialised BEFORE the traps (set -u)
finish() {
    trap '' HUP INT TERM           # no re-entry while finishing
    if [ "${ok:-0}" = 1 ] && [ -n "${tmp:-}" ] && mv -fT "$tmp" "$OUT"; then :
    else
        [ -n "${tmp:-}" ] && rm -f "$tmp"
        rm -rf -- "$OUT"           # fail closed: no file = no identity (removes a link, not its target)
    fi
    exit 0                         # explicit; dash otherwise keeps the prior status
}
trap finish EXIT
trap 'exit 1' HUP INT TERM         # dash skips the EXIT trap on signals without this
tmp=$(mktemp "$OUT.XXXXXX") || tmp=

w() { git config -f "$tmp" "$@" || exit 1; }

deny() { # deny <reason> [detail]
    echo '' >&2
    echo '  ############################################################' >&2
    echo '  # git-identity: NO GIT IDENTITY -- COMMITS WILL HAVE NONE   #' >&2
    echo '  ############################################################' >&2
    printf '  # reason: %s\n' "$1" >&2
    [ -z "${2:-}" ] || printf '  # %s\n' "$2" >&2
    echo '  # Commits in this container will have no user.name,         #' >&2
    echo '  # user.email or signing key until this is fixed. See        #' >&2
    echo '  # "Git identity" in the devcontainers README.               #' >&2
    echo '  ############################################################' >&2
    echo '' >&2
    exit 0
}

[ -n "$tmp" ] || deny "cannot create a temp file next to $OUT"

# --- origin -> org
# GIT_CONFIG_GLOBAL=/dev/null: ~/.gitconfig-identity is still the PREVIOUS start's copy on the
# per-repo home volume (replaced only at the end), and the stub above includes it, so a
# `url.*.insteadOf` planted there would change the URL parsed here and steer the identity to
# another org. Same as owner-check.sh (#118). /etc/gitconfig and the repo's own config still apply.
if url=$(GIT_CONFIG_GLOBAL=/dev/null git -C "$WORKSPACE" remote get-url origin 2>/dev/null); then :; else
    deny "no origin"
fi
nl='
'
# A multi-line value is storable, and a backslash could become a newline in an
# escape-expanding feed; the grammar below can never accept either. The quoted
# backslash is deliberate: dash does not match `*\\*`.
# shellcheck disable=SC1003
case "$url" in *"$nl"*|*'\'*) deny "origin is not a github.com org URL" ;; esac

# Whole-URL anchored EREs, NOT case globs: `https://*@github.com/*` accepts
# https://evil.example/p@github.com/org/r. The userinfo set excludes / ? # \ @, and the
# path is exactly ORG/REPO[/], so a dot segment cannot make ORG differ from the org git
# fetches. Feed with printf, never echo: dash's echo expands a literal \n.
ORG='[a-z0-9][a-z0-9-]*'                        # GitHub forbids a leading hyphen
REPO='[a-z0-9._-]*[a-z0-9_-][a-z0-9._-]*'       # one segment, never "." or ".."
U="[a-z0-9._~%!\$&'()*+,;=:-]*@"                 # RFC 3986 userinfo characters only
TAIL="/($REPO)/?\$"
org=$(printf '%s\n' "$url" | LC_ALL=C tr '[:upper:]' '[:lower:]' |
      LC_ALL=C sed -nE -e "s#^https://($U)?github\\.com/($ORG)$TAIL#\\2#p" \
        -e "s#^git@github\\.com:($ORG)$TAIL#\\1#p" \
        -e "s#^ssh://git@github\\.com/($ORG)$TAIL#\\1#p")
[ -n "$org" ] || deny "origin is not a github.com org URL"

# --- org -> the one file that claims it
match= ; names= ; n=0 ; seen=0
for f in "$IDENTITY_DIR"/*.gitconfig; do
    [ -e "$f" ] || [ -L "$f" ] || continue   # unexpanded glob; -L keeps a dangling link
    seen=1
    b=${f##*/}
    if [ -f "$f" ] && [ -r "$f" ]; then :; else deny "unreadable $b"; fi
    # Capture BEFORE grepping: in a pipeline dash (no pipefail) loses git's 128.
    if out=$(git config -f "$f" --get-all devcontainer.org 2>/dev/null); then rc=0; else rc=$?; fi
    case $rc in
        0) ;;
        1) continue ;;                       # the file sets no devcontainer.org
        *) deny "unreadable $b" ;;           # e.g. 128, a parse error
    esac
    if printf '%s\n' "$out" | LC_ALL=C tr '[:upper:]' '[:lower:]' | grep -qxF -e "$org"; then
        n=$((n + 1)); match=$f; names="$names $b"
    fi
done
[ "$seen" = 1 ] || deny "directory empty"
[ "$n" -ge 1 ] || deny "no file claims $org"
[ "$n" -le 1 ] || deny "several files claim $org" "files:$names"

# --- project the allowlist. Never --includes.
for k in user.name user.email user.signingkey; do
    if v=$(git config -f "$match" --get "$k" 2>/dev/null); then w "$k" "$v"; fi
done
for k in commit.gpgsign tag.gpgsign; do
    # An invalid boolean (exit 128) skips the key: `commit.gpgsign = maybe` would
    # make every commit in the container fail.
    if v=$(git config -f "$match" --type=bool --get "$k" 2>/dev/null); then w "$k" "$v"; fi
done

email=$(git config -f "$tmp" --get user.email 2>/dev/null) || email='no user.email set'
printf 'git-identity: %s -> %s (%s)\n' "$org" "${match##*/}" "$email" >&2
ok=1
