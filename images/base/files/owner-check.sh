#!/bin/sh
# Detects an accidental folder-name collision at every container start. The template names
# every per-repo volume after the checkout FOLDER (${localWorkspaceFolderBasename}), so two
# checkouts of different repos that share a folder name on one host share <folder>-home,
# -tmp, -node_modules and -venv: one trust domain, the first repo's gh token included
# (README host rule 3, IAC-D49 consumer obligation 4).
#
# The marker ~/.devc-owner, on the per-repo home volume, holds one line, <org>/<repo> in
# lowercase, written at the first start that has a valid origin. A later start whose origin
# names a different repo prints a loud banner and leaves the marker alone.
#
# It DETECTS; it does not prevent. By the time this runs the second container already has
# the first repo's home volume mounted. It is also warn-only: blocking would not protect
# the token, and would break a legitimate rename or transfer. A hostile .devcontainer/ can
# mount any volume and skip any start-up step, which stays out of scope (threat model
# boundary 5). See DEVC-D6 in docs/roadmap.md.
#
# The origin is read and parsed with the SAME anchored grammar as git-identity.sh, which
# also captures the repo segment. tests/smoke.sh runs one table of URLs through both scripts
# and asserts they agree on the org and on accept versus reject, so the regex copies cannot
# drift apart unnoticed for the tabled URLs. A URL the grammar
# rejects (no origin, not github.com, a lookalike, a multi-line value) yields NO owner. A
# trailing .git on the repo segment is dropped, so clone URLs that differ only by it name
# one repo.
#
# The origin URL can carry a token in its userinfo, so it is never printed: only the
# grammar-restricted org/repo appears in output. The marker's own content is written by
# code running in the volume and is untrusted: it is printed only after it matches the
# grammar, and never otherwise (a terminal escape sequence could ride in it).
#
# Like git-identity.sh and gpg-check.sh this always exits 0 and never fails the container's
# start. Deliberately `set -u` and NOT `set -e`. DEVC_OWNER_FILE and DEVC_OWNER_WORKSPACE
# exist for tests/smoke.sh; a repo's own remoteEnv, or a shell rc file in the home volume
# (the CLI's userEnvProbe sources them), could set them too, which gains it nothing: both
# already run arbitrary code in the container. Note DEVC_OWNER_FILE is what write_marker
# may `rm -rf` when it is a directory, so never point it at anything but a marker.
set -u
LC_ALL=C; export LC_ALL

MARKER=${DEVC_OWNER_FILE:-/home/app/.devc-owner}
WORKSPACE=${DEVC_OWNER_WORKSPACE:-/workspace}

ORG='[a-z0-9][a-z0-9-]*'                        # GitHub forbids a leading hyphen
REPO='[a-z0-9._-]*[a-z0-9_-][a-z0-9._-]*'       # one segment, never "." or ".."
OWNER_RE="^$ORG/$REPO\$"                        # a whole marker line, and a parsed owner

banner() { # banner <line>...: one loud box; every argument is a line that is safe to print
    echo '' >&2
    echo '  ############################################################' >&2
    echo '  # owner-check: THIS VOLUME BELONGS TO ANOTHER REPOSITORY    #' >&2
    echo '  ############################################################' >&2
    for l in "$@"; do printf '  # %s\n' "$l" >&2; done
    echo '  # The two repos share every per-repo volume, the gh token    #' >&2
    echo '  # included. See "Consuming from another org", host rule 3,  #' >&2
    echo '  # in the devcontainers README.                              #' >&2
    echo '  ############################################################' >&2
    echo '' >&2
}

# --- origin -> owner (org/repo). Same grammar as git-identity.sh, with the repo captured.
# GIT_CONFIG_GLOBAL=/dev/null: this runs BEFORE git-identity.sh rewrites ~/.gitconfig, and that
# file lives on the shared home volume, so a planted `url.*.insteadOf` could otherwise change
# the URL seen here. This reads the true origin; git-identity.sh pins its read the same way.
url=$(GIT_CONFIG_GLOBAL=/dev/null git -C "$WORKSPACE" remote get-url origin 2>/dev/null) || url=
nl='
'
owner=
# shellcheck disable=SC1003
case "$url" in
    '') ;;
    *"$nl"*|*'\'*) ;;
    *)
        U="[a-z0-9._~%!\$&'()*+,;=:-]*@"          # RFC 3986 userinfo characters only
        TAIL="/($REPO)/?\$"
        owner=$(printf '%s\n' "$url" | tr '[:upper:]' '[:lower:]' |
                sed -nE -e "s#^https://($U)?github\\.com/($ORG)$TAIL#\\2/\\3#p" \
                  -e "s#^git@github\\.com:($ORG)$TAIL#\\1/\\2#p" \
                  -e "s#^ssh://git@github\\.com/($ORG)$TAIL#\\1/\\2#p")
        owner=${owner%.git}
        # one line, and a whole org/repo (a bare ".git" repo segment would leave nothing)
        case "$owner" in *"$nl"*) owner= ;; esac
        printf '%s\n' "$owner" | grep -Eq -- "$OWNER_RE" || owner=
        ;;
esac

if [ -z "$owner" ]; then
    echo "owner-check: skipped (origin is not a github.com org/repo URL); will retry at the next start" >&2
    exit 0
fi

# --- the marker. Anything but one grammar-clean line in a regular file is treated as
# a mismatch whose content is never echoed.
state=none                      # none | ok | other | junk
prev=
if [ -e "$MARKER" ] || [ -L "$MARKER" ]; then
    state=junk
    if [ -f "$MARKER" ] && [ ! -L "$MARKER" ] && [ -r "$MARKER" ]; then
        size=$(wc -c <"$MARKER" 2>/dev/null) || size=
        m=$(head -c 256 "$MARKER" 2>/dev/null) || m=
        # exactly the bytes this script writes: one line plus its newline, nothing hidden
        # (a NUL or a second line would make the lengths disagree)
        case "$m" in *"$nl"*) m= ;; esac
        if [ -n "$m" ] && [ "$size" = $((${#m} + 1)) ] \
            && printf '%s\n' "$m" | grep -Eq -- "$OWNER_RE"; then
            if [ "$m" = "$owner" ]; then state=ok; else state=other; prev=$m; fi
        fi
    fi
fi

write_marker() { # temp file + rename, so a planted symlink is replaced, not written through
    [ ! -d "$MARKER" ] || [ -L "$MARKER" ] || rm -rf -- "$MARKER"
    t=$(mktemp "$MARKER.XXXXXX" 2>/dev/null) || t=
    if [ -n "$t" ] && printf '%s\n' "$owner" >"$t" && mv -fT "$t" "$MARKER"; then return 0; fi
    [ -z "$t" ] || rm -f "$t"
    echo "owner-check: cannot write $MARKER" >&2
    return 1
}

case "$state" in
    none)
        write_marker && echo "owner-check: $owner (new marker)" >&2 ;;
    ok)
        echo "owner-check: ok ($owner)" >&2 ;;
    other)
        banner "This volume was first used by: $prev" \
               "The repo starting now is:      $owner" \
               "Usual cause: two checkouts share a folder name. Rename this" \
               "checkout's folder, then: docker volume rm <folder>-home" \
               "<folder>-tmp <folder>-node_modules <folder>-venv" \
               "Or, if this repo was renamed or transferred: rm ~/.devc-owner"
        ;;
    junk)
        banner "The owner marker $MARKER is unreadable, not a regular" \
               "file, or not an org/repo line, so this volume's owner is unknown." \
               "(Its content is not shown: code in the volume wrote it.)" \
               "It is being replaced with: $owner" \
               "If two checkouts share a folder name, rename this one's folder and" \
               "docker volume rm <folder>-home <folder>-tmp <folder>-node_modules <folder>-venv"
        write_marker
        ;;
esac
exit 0
