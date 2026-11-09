#!/bin/sh
# plugin-install.sh: runs LAST in postStartCommand of a dev-App container, from the workspace
# root. It installs the repo's pinned Claude Code plugins at USER scope (#503): a plugin is
# pinned when .claude/settings.json enables it (`enabledPlugins`: true, as P@M) and declares
# its marketplace M in `extraKnownMarketplaces` as a github source with both `repo` and `ref`.
# It reads that file with jq and never writes it.
#
# It is the ONE deliberate exception to the "start-up scripts exit 0" rule of devapp-check.sh,
# gpg-check.sh, owner-check.sh and DEVC-D6: it exits 1 when a pinned plugin cannot be installed
# or verified, so `up` fails loudly instead of a session starting silently without the plugin
# (DEVC-D10). Why it can: it runs at the END of postStartCommand, after the forwarded-credential
# cleanup, owner-check, devapp-check and git-identity, so a failure skips none of them. In
# postCreateCommand a failure would skip all of postStart, and the CLI never retries a failed
# postCreate.
#
# Why `--scope user` on every call that takes it: measured on claude 2.1.319, `marketplace
# remove M` with no --scope emptied both keys in the tracked project settings file (the likely
# cause of #503's "rewrote the tracked file"). It never falls back to an unscoped call.
# Why every `claude` call runs from a fresh empty directory under /tmp and never from the
# workspace: no project settings.json (env, hooks, apiKeyHelper) can then reach a claude
# process that runs without a person or a folder-trust prompt. Why a fixed PATH, TMPDIR and
# no CLAUDE_CONFIG_DIR: ~/.local/bin (home volume) leads the normal PATH, and neither the
# repo nor a Dockerfile extra may move the scratch space or the user scope.
#
# If .claude/settings.json changes while it runs (hash compared before and after) it fails and
# keeps a snapshot of the bytes it read; it never restores the workspace file.
#
# Exit codes: 0 everything pinned is installed at its pinned ref, or nothing is pinned;
# 1 a pinned plugin is not installed or verified, the settings file was refused or changed, or
# a tool call failed; 2 usage error.
#
# Recovery: run `sh /usr/local/share/devc/plugin-install.sh` by hand in the container, from the
# workspace root, then start a fresh `claude` session.
#
# Deliberately `set -u` and NOT `set -e`, like devapp-check.sh: every status is checked.
set -u

PATH=/usr/local/bin:/usr/bin:/bin; export PATH
TMPDIR=/tmp; export TMPDIR
unset CLAUDE_CONFIG_DIR
CLAUDE=/usr/local/bin/claude

RECOVERY='Run, from the workspace root: sh /usr/local/share/devc/plugin-install.sh   (then start a fresh claude session)'

banner() { # banner <title> <detail...>: every line of every detail is framed
    title=$1; shift
    {
        echo ''
        echo '  ############################################################'
        printf '  # plugin-install: %s\n' "$title"
        for d in "$@"; do
            printf '%s\n' "$d" | while IFS= read -r l; do printf '  # %s\n' "$l"; done
        done
        echo '  ############################################################'
        echo ''
    } >&2
}

if [ $# -ne 0 ]; then
    echo 'usage: plugin-install.sh (no arguments)' >&2
    exit 2
fi

ws=$(pwd -P) || exit 1
[ "$ws" != / ] || { banner 'REFUSED' 'The workspace root cannot be /.'; exit 1; }
f="$ws/.claude/settings.json"
tab=$(printf '\t')

# 2. The file.
if [ ! -e "$f" ] && [ ! -L "$f" ] && [ ! -L "$ws/.claude" ]; then
    echo 'plugin-install: nothing pinned' >&2
    exit 0
fi
settings_ok() { # not a symlink (nor its directory), a regular file, at most 64 KiB
    [ ! -L "$ws/.claude" ] && [ ! -L "$f" ] && [ -f "$f" ] || return 1
    [ "$(wc -c < "$f")" -le 65536 ] 2>/dev/null
}
if ! settings_ok; then
    banner 'REFUSED .claude/settings.json' \
        'It (or .claude) is a symlink, is not a regular file, or is over 64 KiB.' \
        'Nothing was installed.'
    exit 1
fi

# 3. Scratch and snapshot, in this order. The snapshot is outside the scratch directory so it
# can outlive the cleanup.
tmp='' snap='' sha=''
cleanup_early() { rm -rf -- "$tmp"; rm -f -- "$snap"; }
tmp=$(mktemp -d) && [ -n "$tmp" ] || { banner 'COULD NOT CREATE A SCRATCH DIRECTORY'; exit 1; }
snap=$(mktemp "$TMPDIR/plugin-install-settings.XXXXXX") && [ -n "$snap" ] \
    || { cleanup_early; banner 'COULD NOT CREATE A SNAPSHOT FILE'; exit 1; }
rt=$(cd -- "$tmp" 2>/dev/null && pwd -P)
rs=$(cd -- "$(dirname -- "$snap")" 2>/dev/null && pwd -P)
for d in "$rt" "$rs"; do
    case $d in
        '') cleanup_early; banner 'COULD NOT RESOLVE THE SCRATCH PATHS'; exit 1 ;;
        "$ws" | "$ws"/*) cleanup_early; banner 'THE SCRATCH SPACE IS INSIDE THE WORKSPACE' 'Refusing to run claude near the repo.'; exit 1 ;;
    esac
done
if ! cp -- "$f" "$snap" || ! settings_ok || [ "$(wc -c < "$snap")" -gt 65536 ]; then
    cleanup_early
    banner 'REFUSED .claude/settings.json' 'It changed while it was being read, or could not be copied.'
    exit 1
fi
sha=$(sha256sum < "$snap") && [ -n "$sha" ] || { cleanup_early; banner 'COULD NOT HASH THE SETTINGS FILE'; exit 1; }

# shellcheck disable=SC2329 # called from on_exit, which the EXIT trap runs
integrity() { # 0 if the workspace file is still the bytes in $sha
    if [ ! -L "$ws/.claude" ] && [ ! -L "$f" ] && [ -f "$f" ]; then
        now=$(sha256sum < "$f") && [ "$now" = "$sha" ] && return 0
    fi
    banner 'SETTINGS FILE CHANGED' \
        '.claude/settings.json changed while plugin-install ran. If you edited it or switched branch during start-up, that is expected; otherwise the CLI rewrote it.' \
        "The original bytes are in $snap. Nothing was restored."
    return 1
}
# shellcheck disable=SC2329 # run by the EXIT trap below
on_exit() {
    rc=$?
    keep=0
    if [ -n "$sha" ]; then integrity || { rc=1; keep=1; }; fi
    rm -rf -- "$tmp"
    [ "$keep" -eq 1 ] || rm -f -- "$snap"
    exit "$rc"
}
trap on_exit EXIT
trap 'exit 129' HUP INT TERM

# 4. Parse and validate inside jq, once, from the snapshot.
# shellcheck disable=SC2016 # a jq program: nothing in it is meant for the shell
JQ_PROG='
def clean: test("[[:cntrl:]]") | not;
def nm: type == "string" and clean and test("\\A[A-Za-z0-9][A-Za-z0-9._-]{0,99}\\z");
def rp: type == "string" and clean and test("\\A[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}\\z")
        and ((split("/")[1]) as $x | $x != "." and $x != "..");
def rf: type == "string" and clean and test("\\A[A-Za-z0-9][A-Za-z0-9._/-]{0,199}\\z") and (contains("..") | not);
(if (.enabledPlugins | type) == "object" then .enabledPlugins else {} end) as $ep
| (if (.extraKnownMarketplaces | type) == "object" then .extraKnownMarketplaces else {} end) as $km
| ($ep | to_entries | to_entries[]) as $e
| select($e.value.value == true)
| ($e.key + 1) as $n
| $e.value.key as $k
| ($k | split("@")) as $p
| if (($p | length) != 2) or (($p[0] | nm) | not) or (($p[1] | nm) | not) then
    ["INVALID", $n, "plugin id"]
  else
    $km[$p[1]] as $d
    | if ($d | type) != "object" then
        ["WARN", "warning: \($k) is enabled but not pinned (marketplace not declared); not installed here"]
      elif ($d.source | type) != "object" or $d.source.source != "github" then
        ["WARN", "warning: \($k) is enabled but not pinned (source is not github); not installed here"]
      elif $d.source.ref == null then
        ["WARN", "warning: \($k) is enabled but not pinned (no ref); not installed here"]
      elif ($d.source.repo | rp | not) then ["INVALID", $n, "repo"]
      elif ($d.source.ref | rf | not) then ["INVALID", $n, "ref"]
      else ["PIN", $k, $p[1], $d.source.repo, $d.source.ref] end
  end
| @tsv'
if ! jq -r "$JQ_PROG" "$snap" > "$tmp/parsed" 2>/dev/null; then
    banner 'CANNOT READ .claude/settings.json' 'It is not valid JSON, or not the expected shape.' "$RECOVERY"
    exit 1
fi

fails=
: > "$tmp/pins"
while IFS="$tab" read -r kind a b c d; do
    case $kind in
        PIN) printf '%s\t%s\t%s\t%s\n' "$a" "$b" "$c" "$d" >> "$tmp/pins" ;;
        WARN) echo "plugin-install: $a" >&2 ;;
        INVALID) echo "plugin-install: <invalid entry $a: $b>" >&2
                 fails="$fails<invalid entry $a: $b>: refused, not installed
" ;;
    esac
done < "$tmp/parsed"

if [ ! -s "$tmp/pins" ] && [ -z "$fails" ]; then
    echo 'plugin-install: nothing pinned' >&2
    exit 0
fi

if [ ! -s "$tmp/pins" ]; then
    banner 'INVALID PINNED ENTRIES' "$fails" 'No claude command was run.'
    exit 1
fi

# Helpers for the claude calls (spec D5/D6).
inlist() { printf '%s\n' "$2" | grep -Fxq -- "$1"; }
cl() { # cl <seconds> <claude args...>: from the scratch directory, fixed env, no stdin
    secs=$1; shift
    env -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_CONFIG_SYSTEM \
        -u GIT_CONFIG_NOSYSTEM -u GIT_DIR -u GIT_WORK_TREE -u GIT_EXEC_PATH -u GIT_ASKPASS \
        -u GIT_SSH_COMMAND -u LD_PRELOAD -u LD_LIBRARY_PATH -u LD_AUDIT -u BASH_ENV -u ENV \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$TMPDIR" \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        timeout "$secs" "$CLAUDE" "$@" < /dev/null > "$tmp/out" 2> "$tmp/err"
}
sane() { tr -cd '[:print:]' | cut -c1-200; }
why() { # why <rc>: a sanitised reason from the last call's JSON message, stderr or status
    w=$(tail -n 1 "$tmp/out" 2>/dev/null | jq -r '.message // empty' 2>/dev/null | sane)
    [ -n "$w" ] || w=$(sane < "$tmp/err")
    if [ -z "$w" ]; then
        if [ "$1" -eq 124 ]; then w='timed out'; else w="exit status $1"; fi
    fi
    printf '%s' "$w"
}
outcome() { tail -n 1 "$tmp/out" 2>/dev/null | jq -r '.outcome // empty' 2>/dev/null; }
read_lists() { # read both lists into $tmp/ml.json and $tmp/pl.json; 0 on success
    cl 30 plugin marketplace list --json; rc=$?
    if [ "$rc" -ne 0 ]; then listerr=$(why "$rc"); return 1; fi
    cp -- "$tmp/out" "$tmp/ml.json"
    cl 30 plugin list --json; rc=$?
    if [ "$rc" -ne 0 ]; then listerr=$(why "$rc"); return 1; fi
    cp -- "$tmp/out" "$tmp/pl.json"
    jq -e type "$tmp/ml.json" "$tmp/pl.json" > /dev/null 2>&1 || { listerr='unparseable output'; return 1; }
}
mkt_ok() { # mkt_ok <M> <repo> <ref>
    jq -e --arg m "$1" --arg r "$2" --arg f "$3" \
        'any(.[]; .name == $m and .repo == $r and .ref == $f)' "$tmp/ml.json" > /dev/null 2>&1
}
mkt_listed() { jq -e --arg m "$1" 'any(.[]; .name == $m)' "$tmp/ml.json" > /dev/null 2>&1; }
plug_ok() { # plug_ok <P@M>
    jq -e --arg i "$1" 'any(.[]; .id == $i and .scope == "user" and .enabled == true)' "$tmp/pl.json" > /dev/null 2>&1
}
pins_ok() { # 0 if every pin is installed at its ref (the fast-path conditions)
    while IFS="$tab" read -r id m repo ref; do
        mkt_ok "$m" "$repo" "$ref" && plug_ok "$id" || return 1
    done < "$tmp/pins"
}

# 6. Every claude call runs from the empty scratch directory.
# TMPDIR is the persistent <repo>-tmp volume: a planted repo or project settings there would sit
# above every scratch directory, so refuse to run (the git ceiling in cl() is the second guard).
if [ -e "$TMPDIR/.git" ] || [ -L "$TMPDIR/.git" ] || [ -e "$TMPDIR/.claude" ] || [ -L "$TMPDIR/.claude" ]; then
    banner 'REFUSED: A .git OR .claude EXISTS DIRECTLY UNDER THE TEMP DIRECTORY' \
        "Remove $TMPDIR/.git and $TMPDIR/.claude (or wipe the <repo>-tmp volume), then run:" "$RECOVERY"
    exit 1
fi
cd -- "$tmp" || exit 1
if ! read_lists; then
    banner 'COULD NOT READ THE INSTALLED PLUGINS' "could not read the installed plugins ($listerr)" "$RECOVERY"
    exit 1
fi

# 6a. User-scope extras that this tree does not pin: reported, never removed (spec D10).
cut -f2 "$tmp/pins" | sort -u > "$tmp/pinM"
cut -f1 "$tmp/pins" | sort -u > "$tmp/pinP"
extras=$(jq -r --rawfile pp "$tmp/pinP" '
    def nm: type == "string" and test("\\A[A-Za-z0-9][A-Za-z0-9._@-]{0,200}\\z");
    ($pp | split("\n")) as $p
    | .[] | select(.scope == "user" and .enabled == true and ((.id // "") as $i | $p | index($i) | not))
    | "plugin \(.id | if nm then . else "<unnamed entry>" end) is installed at user scope but not pinned by .claude/settings.json"' \
    "$tmp/pl.json" 2>/dev/null)
extras_m=$(jq -r --rawfile pm "$tmp/pinM" '
    def nm: type == "string" and test("\\A[A-Za-z0-9][A-Za-z0-9._-]{0,99}\\z");
    ($pm | split("\n")) as $m
    | .[] | select((.name // "") as $n | $m | index($n) | not)
    | (if ((.repo // "") | type == "string" and test("\\A[A-Za-z0-9._/-]{1,300}\\z")) and ((.ref // "") | type == "string" and test("\\A[A-Za-z0-9._/-]{0,200}\\z"))
       then " (\(.repo // "?")#\(.ref // ""))" else "" end) as $src
    | "marketplace \(.name | if nm then . else "<unnamed entry>" end)\($src) is installed at user scope but not pinned by .claude/settings.json"' \
    "$tmp/ml.json" 2>/dev/null)
all_extras=$extras
[ -z "$extras_m" ] || all_extras="${all_extras:+$all_extras
}$extras_m"
if [ -n "$all_extras" ]; then
    banner 'WARNING: USER-SCOPE INSTALLS THIS TREE DOES NOT PIN' "$all_extras" \
        'Nothing was removed. To remove one:' \
        '  claude plugin uninstall <P@M> --scope user' \
        '  claude plugin marketplace remove <M> --scope user'
fi

# 6b. Fast path: the pinned conditions alone decide it, and it needs no network.
if pins_ok; then
    [ -z "$fails" ] && exit 0
    # Every valid pin is installed; only an invalid entry fails. No network work.
    banner 'AN ENTRY IN .claude/settings.json IS INVALID' "$fails" 'Fix the entry in .claude/settings.json; nothing else was changed.'
    exit 1
fi

# 7. Marketplaces.
repointed=
failedm=
seen=
while IFS="$tab" read -r id m repo ref; do
    inlist "$m" "$seen" && continue
    seen="$seen$m
"
    if mkt_ok "$m" "$repo" "$ref"; then
        continue
    elif mkt_listed "$m"; then
        cl 300 plugin marketplace remove --scope user --json -- "$m"; rc=$?
        if [ "$rc" -ne 0 ] || [ "$(outcome)" != ok ]; then
            fails="$fails$m: could not re-point the marketplace ($(why "$rc"))
"
            failedm="$failedm$m
"
            continue
        fi
        repointed="$repointed$m
"
    fi
    cl 300 plugin marketplace add --scope user --json -- "$repo#$ref"; rc=$?
    if [ "$rc" -ne 0 ] || [ "$(outcome)" != ok ]; then
        fails="$fails$m: could not add the marketplace at $repo#$ref ($(why "$rc"))
"
        failedm="$failedm$m
"
    fi
done < "$tmp/pins"

# 8. Plugins.
failedp=
while IFS="$tab" read -r id m repo ref; do
    if inlist "$m" "$failedm"; then
        fails="$fails$id: not installed (its marketplace failed)
"
        failedp="$failedp$id
"
        continue
    fi
    cl 300 plugin install --scope user --json -- "$id"; rc=$?
    if [ "$rc" -ne 0 ] || [ "$(outcome)" != ok ]; then
        fails="$fails$id: install failed ($(why "$rc"))
"
        failedp="$failedp$id
"
        continue
    fi
    upd=0
    inlist "$m" "$repointed" && upd=1
    if tail -n 1 "$tmp/out" | jq -e '(.installedVersion // empty) as $i | (.availableVersion // empty) as $a | $i != $a' > /dev/null 2>&1; then
        upd=1
    fi
    if [ "$upd" -eq 1 ]; then
        cl 300 plugin update --scope user -- "$id"; rc=$?
        if [ "$rc" -ne 0 ]; then
            fails="$fails$id: update failed ($(why "$rc"))
"
            failedp="$failedp$id
"
        fi
    fi
done < "$tmp/pins"

# 9. Verify, with the same conditions as the fast path.
if read_lists; then
    while IFS="$tab" read -r id m repo ref; do
        inlist "$id" "$failedp" && continue
        if ! mkt_ok "$m" "$repo" "$ref" || ! plug_ok "$id"; then
            fails="$fails$id: not installed at user scope at $repo#$ref after the install
"
        fi
    done < "$tmp/pins"
else
    fails="${fails}could not read the installed plugins to verify ($listerr)
"
fi

# 10. Report.
if [ -n "$fails" ]; then
    banner 'A PINNED PLUGIN IS NOT INSTALLED' "$fails" "$RECOVERY"
    exit 1
fi
names=$(cut -f1 "$tmp/pins" | tr '\n' ' ')
refs=$(awk -F"$tab" '{ printf "%s#%s ", $3, $4 }' "$tmp/pins")
echo "plugin-install: installed ${names}at ${refs}" >&2
exit 0
