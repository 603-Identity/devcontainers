#!/bin/sh
# Asserts what a built image promises: pinned tool versions, the non-root user, the
# app-owned mount points the template's named volumes rely on, the cache and home
# layout (what is shared, what is per repo), the owner marker (owner-check.sh, near the end), and
# the git identity projection (git-identity.sh):
#   * no host config reaches the credential path: the only credential helper that
#     runs is gh's, checked by behaviour (GIT_TRACE on `git credential fill`);
#   * an org URL selects exactly one identity file, and only five allowlisted keys
#     are projected (no include, credential, url or gpg.* content);
#   * every failed selection (no origin, a non-github or lookalike origin, no or
#     several files claiming the org, an unreadable file, an empty directory) leaves
#     NO identity in place, with the expected reason printed;
#   * no token from the origin URL appears in any output.
# CI runs it against every image before anything is pushed; run it locally the same
# way:
#
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> sh /tests/smoke.sh <base|tofu|node>
#
# Expected versions are read from the Dockerfiles' own ARG lines by the CI step and
# passed in as environment variables. That keeps one source of truth: a version
# bumped in a Dockerfile but not built would fail here. The Python tools' versions come
# from images/base/tools/uv.lock the same way. One is hardcoded below, by design: the
# system Python's major.minor (the standard for consuming repos; apt moves the patch).
set -eu

flavor="${1:?usage: smoke.sh <base|tofu|node>}"
fail=0
check() { # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok   $1 = $3"
    else
        echo "FAIL $1: expected '$2', got '$3'"
        fail=1
    fi
}

check "uid" 1000 "$(id -u)"
check "user" app "$(id -un)"
check "gh" "$EXPECT_GH" "$(gh --version | awk 'NR==1{print $3}')"
check "yq" "v$EXPECT_YQ" "$(yq --version | awk '{print $NF}')"
check "uv" "$EXPECT_UV" "$(uv --version | awk '{print $2}')"
check "bc-detect-secrets" "$EXPECT_BC_DETECT_SECRETS" "$(detect-secrets --version)"
check "zizmor" "$EXPECT_ZIZMOR" "$(zizmor --version | awk '{print $2}')"
check "pre-commit" "$EXPECT_PRE_COMMIT" "$(pre-commit --version | awk '{print $2}')"
check "PATH has ~/.local/bin" 1 "$(printf '%s' ":$PATH:" | grep -c ':/home/app/.local/bin:')"
check "python3" 3.14 "$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
check "tools venv" /opt/devc/tools/bin/pre-commit "$(readlink /usr/local/bin/pre-commit)"
check "safe.directory" /workspace "$(git config --system --get-all safe.directory)"
check "setuid/setgid binaries" 0 "$(find / -xdev -perm /6000 -type f 2>/dev/null | wc -l)"
# The template mounts /home/app (per-repo), /home/app/.cache/tofu-plugins (shared) and
# the two dependency directories as volumes. Docker copies the image path's ownership into
# an empty volume, so each mount point must exist in the image and be app-owned, or it
# comes up root-owned and unwritable as uid 1000. ~/.cache is the shared mount's parent,
# seeded into the home volume, so it must be app-owned too.
for d in /home/app /home/app/.cache /home/app/.cache/tofu-plugins /workspace/.venv /workspace/node_modules; do
    check "owner $d" app "$(stat -c %U "$d")"
done
# Image-owned configuration must not live in the home directory: the home volume freezes
# the image's copy at first mount. git-identity.sh writes ~/.gitconfig at every start.
check "owner /home/app/.local" app "$(stat -c %U /home/app/.local)"
check "GIT_CONFIG_GLOBAL" /home/app/.gitconfig "${GIT_CONFIG_GLOBAL:-}"
check "no ~/.gitconfig in the image" "" "$(ls -A /home/app/.gitconfig /home/app/.gitconfig-identity 2>/dev/null || true)"

# Only the tofu provider cache is directed into the shared volume (~/.cache/tofu-plugins).
# Every other cache lives in the per-repo home volume (~/.local); XDG_CACHE_HOME moves the
# XDG-aware tools there all at once.
check "XDG_CACHE_HOME" /home/app/.local/cache "${XDG_CACHE_HOME:-}"
check "UV_CACHE_DIR" /home/app/.local/uv-cache "${UV_CACHE_DIR:-}"
check "UV_LINK_MODE" copy "${UV_LINK_MODE:-}"
check "PRE_COMMIT_HOME" /home/app/.local/pre-commit "${PRE_COMMIT_HOME:-}"
# Unset, or an unverified cache entry could be used and written into a repo's lock file.
check "TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE" "" "${TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE:-}"
for v in XDG_CACHE_HOME PRE_COMMIT_HOME PIP_CACHE_DIR UV_CACHE_DIR NPM_CONFIG_CACHE PUPPETEER_CACHE_DIR; do
    val=$(printenv "$v" || true)
    case "$val" in
        /home/app/.cache/tofu-plugins|/home/app/.cache/tofu-plugins/*)
            echo "FAIL $v=$val is inside the shared cache volume"; fail=1 ;;
        *) echo "ok   $v not in the shared cache volume (${val:-unset})" ;;
    esac
done

# --- git identity (see the header). The script and its output file are fixed paths;
# only the identity directory and the workspace are overridable, for these tests.
SCRIPT=/usr/local/share/devc/git-identity.sh
OUT=/home/app/.gitconfig-identity
# Token-bearing, so a leak of the origin URL on ANY denial path shows up in $alllogs.
POS_URL=https://x-token:secret@github.com/fixture-org/r
alllogs=$(mktemp)

# The effective credential helpers, by behaviour, not by one key name: exactly one
# helper process may run, and it is gh's. "Every helper is gh" alone would pass when
# no helper runs. GIT_TRACE appends, so each probe gets a fresh absolute path. With no
# gh token the fill fails in ~100 ms, hence `|| true`; stdout is dropped in case a
# token is ever present.
cred_probe() { # cred_probe <label>
    trace=$(mktemp)
    printf 'protocol=https\nhost=github.com\npath=x/y\n\n' \
        | env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=0 GIT_TRACE="$trace" \
            timeout 10 git credential fill >/dev/null 2>&1 || true
    check "credential helpers run ($1)" 1 "$(grep -c 'run_command:' "$trace" || true)"
    check "credential helper is gh's ($1)" 1 \
        "$(grep -c "run_command: '/usr/local/bin/gh auth git-credential get'\$" "$trace" || true)"
    rm -f "$trace"
}

run_id() { # run_id <label> [VAR=value ...]: runs the script; $log holds stdout+stderr
    label=$1; shift
    log=$(mktemp)
    rc=0
    env "$@" sh "$SCRIPT" >"$log" 2>&1 || rc=$?
    check "git-identity exit ($label)" 0 "$rc"
    cat "$log" >>"$alllogs"
}
run_fx() { run_id "$1" GIT_IDENTITY_DIR="$fx" GIT_IDENTITY_WORKSPACE="$repo"; }

expect_id() { # expect_id <label>: an identity is live and holds only the allowlist
    check "identity email ($1)" a@fixture.example "$(git config --includes --global user.email || true)"
    if grep -qF -- 'git-identity: fixture-org -> a.gitconfig (' "$log"; then
        echo "ok   success line ($1)"
    else
        echo "FAIL success line ($1): $(cat "$log")"; fail=1
    fi
    check "projected keys ($1)" "" \
        "$(git config -f "$OUT" --name-only --list \
            | grep -vxE 'user\.(name|email|signingkey)|commit\.gpgsign|tag\.gpgsign' || true)"
}
expect_none() { # expect_none <label> <reason>: no identity, and the reason was printed
    if [ ! -e "$OUT" ] && [ ! -L "$OUT" ]; then
        echo "ok   no identity ($1)"
    else
        echo "FAIL no identity ($1): $OUT exists"; fail=1
    fi
    if grep -qF -- "$2" "$log"; then
        echo "ok   reason '$2' ($1)"
    else
        echo "FAIL reason ($1): expected '$2' in: $(cat "$log")"; fail=1
    fi
}
setorigin() { # setorigin <url>; empty removes the origin
    if [ -n "$1" ]; then
        git -C "$repo" config remote.origin.url "$1"
    else
        git -C "$repo" config --unset-all remote.origin.url || true
    fi
}
denied() { # denied <label> <url> <reason>: a live identity first, so absence proves removal
    setorigin "$POS_URL"; run_fx "live before $1"; expect_id "live before $1"
    setorigin "$2"; run_fx "$1"; expect_none "$1" "$3"
}
restore_a() {
    rm -f "$fx/a.gitconfig"
    cp "$keep/a.pristine" "$fx/a.gitconfig"
}

cred_probe "before the script"
# The system helper names gh by absolute path, so an accidental `gh` in ~/.local/bin (which
# leads PATH) cannot shadow it.
check "system credential helper is absolute gh" "!/usr/local/bin/gh auth git-credential" \
    "$(git config --system --get-all credential.https://github.com.helper | tail -n 1)"

fx=$(mktemp -d); outside=$(mktemp -d); repo=$(mktemp -d); keep=$(mktemp -d)
cat >"$outside/extra.cfg" <<EOF
[user]
    email = included@evil.example
[credential]
    helper = !echo included
EOF
# The [include] comes AFTER user.email: git expands includes in place and the last
# value wins, so only this order catches a regression to --includes.
cat >"$keep/a.pristine" <<EOF
[devcontainer]
    org = Fixture-Org
[user]
    name = Fixture User
    email = a@fixture.example
    signingkey = ABCDEF0123456789
[commit]
    gpgsign = true
[gpg]
    program = C:/x/gpg.exe
[include]
    path = $outside/extra.cfg
[credential]
    helper = !C:/x/gh.exe auth git-credential
[credential "https://github.com"]
    helper = !C:/x/gh.exe auth git-credential
[credential "https://github.com/"]
    helper = !C:/x/gh.exe auth git-credential
[Credential "HTTPS://GitHub.com"]
    helper = !C:/x/gh.exe auth git-credential
[url "https://evil.example/"]
    insteadOf = https://github.com/
[core]
    sshCommand = C:/x/ssh.exe
    fsmonitor = C:/x/fsmon.exe
[alias]
    x = !echo hostile
EOF
printf '[devcontainer]\n    org = other\n' >"$keep/b.pristine"
cp "$keep/a.pristine" "$fx/a.gitconfig"
cp "$keep/b.pristine" "$fx/b.gitconfig"
git init -q "$repo"

# Positive: three origin forms, all resolving to a's direct email.
for url in \
    'https://x-token:secret@github.com/fixture-org/r.git' \
    'git@GitHub.com:Fixture-Org/r.git' \
    'ssh://git@github.com/fixture-org/r'; do
    setorigin "$url"; run_fx "positive"; expect_id "positive"; cred_probe "after positive"
done

# The default directory: /home/app/.gitconfig.d exists (the Dockerfile creates it) and
# is empty here. Only the workspace is overridden, since /workspace is not a repo in
# this container. The live identity from the positive run must be cleared.
setorigin "$POS_URL"; run_fx "live before default dir"; expect_id "live before default dir"
run_id "default dir" GIT_IDENTITY_WORKSPACE="$repo"
expect_none "default dir" "directory empty"
check "owner /home/app/.gitconfig.d" app "$(stat -c %U /home/app/.gitconfig.d)"

# Negative origins.
denied "gitlab" 'https://x-token:secret@gitlab.example/o/r.git' 'origin is not a github.com org URL'
denied "userinfo lookalike" 'https://evil.example/p@github.com/fixture-org/r' 'origin is not a github.com org URL'
denied "fragment lookalike" 'https://evil.example#@github.com/fixture-org/r' 'origin is not a github.com org URL'
denied "query lookalike" 'https://evil.example?@github.com/fixture-org/r' 'origin is not a github.com org URL'
denied "dot segments" 'https://github.com/fixture-org/r/../../octocat/x' 'origin is not a github.com org URL'
denied "host suffix" 'https://github.com.evil.example/fixture-org/r' 'origin is not a github.com org URL'
denied "userinfo host" 'https://github.com@evil.example/fixture-org/r' 'origin is not a github.com org URL'
denied "http" 'http://github.com/fixture-org/r' 'origin is not a github.com org URL'
denied "port" 'https://github.com:443/fixture-org/r' 'origin is not a github.com org URL'
denied "leading hyphen" 'https://github.com/-x/r' 'origin is not a github.com org URL'
denied "scp user" 'evil@github.com:fixture-org/r' 'origin is not a github.com org URL'
# One value with an embedded newline (not --add, of which get-url reads only the
# first), then a literal backslash-n (two characters), which catches an echo feed:
# a.gitconfig still claims fixture-org, so a regression shows as the success line.
denied "newline" "$(printf 'https://evil.example/x\nhttps://github.com/fixture-org/r')" 'origin is not a github.com org URL'
denied "backslash-n" 'https://evil.example/x\nhttps://github.com/fixture-org/r' 'origin is not a github.com org URL'
denied "no origin" '' 'no origin'

# Ambiguity, then malformed input, each isolated behind a positive run.
denied "unclaimed org" https://x-token:secret@github.com/nobody/r 'no file claims nobody'
setorigin "$POS_URL"; run_fx "live before several"; expect_id "live before several"
git config -f "$fx/b.gitconfig" --add devcontainer.org fixture-org
run_fx "several"; expect_none "several" 'several files claim fixture-org'
rm -f "$fx/b.gitconfig"; cp "$keep/b.pristine" "$fx/b.gitconfig"

# Restore is rm + a fresh copy from outside the fixture dir: as uid 1000, cp or > onto
# a mode-000 file fails, and onto a dangling symlink cp refuses to write through it.
setorigin "$POS_URL"; run_fx "live before unparseable"; expect_id "live before unparseable"
printf '[devcontainer\n garbage\n' >"$fx/a.gitconfig"
run_fx "unparseable"; expect_none "unparseable" 'unreadable a.gitconfig'
restore_a; setorigin "$POS_URL"; run_fx "live before mode 000"; expect_id "live before mode 000"
chmod 000 "$fx/a.gitconfig"
run_fx "mode 000"; expect_none "mode 000" 'unreadable a.gitconfig'
restore_a; setorigin "$POS_URL"; run_fx "live before dangling"; expect_id "live before dangling"
rm -f "$fx/a.gitconfig"; ln -s /nonexistent "$fx/a.gitconfig"
run_fx "dangling symlink"; expect_none "dangling symlink" 'unreadable a.gitconfig'
restore_a; setorigin "$POS_URL"; run_fx "live after restore"; expect_id "live after restore"

# An invalid boolean is skipped, not projected: `commit.gpgsign = maybe` would make
# every commit in the container fail.
git config -f "$fx/a.gitconfig" commit.gpgsign maybe
setorigin "$POS_URL"; run_fx "bad boolean"; expect_id "bad boolean"
check "commit.gpgsign skipped" "" "$(git config -f "$OUT" --get commit.gpgsign || true)"
cred_probe "after the identity runs"

# ~/.gitconfig is written by the script at every start, and only ever holds the include.
stub=$(printf '[include]\n\tpath = %s' "$OUT")
check "home gitconfig: written by the script" "$stub" "$(cat /home/app/.gitconfig 2>/dev/null || true)"
# A stale or hand-edited copy (the home volume outlives image rebuilds) is rewritten.
printf '[user]\n\tname = stale\n' >/home/app/.gitconfig
setorigin "$POS_URL"; run_fx "stale gitconfig"; expect_id "stale gitconfig"
check "home gitconfig: stale copy rewritten" "$stub" "$(cat /home/app/.gitconfig 2>/dev/null || true)"
# So is a symlink, and the link's target is not written through.
printf '# untouched\n' >"$fx/link-target"
rm -f /home/app/.gitconfig; ln -s "$fx/link-target" /home/app/.gitconfig
setorigin "$POS_URL"; run_fx "symlinked gitconfig"; expect_id "symlinked gitconfig"
check "home gitconfig: symlink replaced" "$stub|0" \
    "$(cat /home/app/.gitconfig 2>/dev/null || true)|$([ -L /home/app/.gitconfig ] && echo 1 || echo 0)"
check "home gitconfig: symlink target untouched" '# untouched' "$(cat "$fx/link-target")"
# A directory there is removed and replaced.
setorigin "$POS_URL"
rm -f /home/app/.gitconfig; mkdir -p /home/app/.gitconfig/sub
run_fx "directory gitconfig"; expect_id "directory gitconfig"
check "home gitconfig: directory replaced" "$stub" "$(cat /home/app/.gitconfig 2>/dev/null || true)"
# git's XDG config file is removed at every start. GIT_CONFIG_GLOBAL already makes plain git
# ignore it, but pre-commit strips GIT_* variables from the environment of the git it runs,
# and that git reads it.
mkdir -p /home/app/.config/git; printf '[user]\n\tname = planted\n' >/home/app/.config/git/config
setorigin "$POS_URL"; run_fx "planted xdg git config"; expect_id "planted xdg git config"
check "XDG git config removed" 0 "$([ -e /home/app/.config/git/config ] && echo 1 || echo 0)"
# A symlinked ~/.config/git is not followed: its target's file survives.
rm -rf /home/app/.config/git; mkdir -p "$fx/dot-git"; printf '[user]\n\tname = dotfile\n' >"$fx/dot-git/config"
ln -s "$fx/dot-git" /home/app/.config/git
setorigin "$POS_URL"; run_fx "symlinked xdg dir"; expect_id "symlinked xdg dir"
check "symlinked XDG git dir not followed" 1 "$([ -e "$fx/dot-git/config" ] && echo 1 || echo 0)"
rm -f /home/app/.config/git
# The origin is read with git's global config off: ~/.gitconfig-identity is the previous
# start's copy on the home volume, and ~/.gitconfig includes it, so a url.*.insteadOf planted
# there must not steer the org (#118). Success is still fixture-org -> a.gitconfig, never
# `other` (b.gitconfig).
setorigin "https://github.com/fixture-org/r"; run_fx "live before planted insteadOf"; expect_id "live before planted insteadOf"
printf '[url "https://github.com/other/r"]\n\tinsteadOf = https://github.com/fixture-org/r\n' >>"$OUT"
check "planted insteadOf steers git's view of the origin" https://github.com/other/r \
    "$(git -C "$repo" remote get-url origin)"
run_fx "planted insteadOf in identity"; expect_id "planted insteadOf in identity"
# The identity is denied, yet the include is still in place: start from no file, so only
# a write on the denied path can produce it.
rm -f /home/app/.gitconfig
setorigin ""; run_fx "no origin gitconfig"
check "home gitconfig: written on a denied identity" "$stub" "$(cat /home/app/.gitconfig 2>/dev/null || true)"

# The origin URL carried a token in these runs: neither it nor its user may be echoed.
if grep -qF -e secret -e x-token "$alllogs"; then
    echo "FAIL origin token leaked into git-identity output"; fail=1
else
    echo "ok   no origin token in git-identity output"
fi

# --- owner check (owner-check.sh): the folder-name collision marker. Same origin grammar as
# git-identity.sh, which the agreement table below pins. Output goes to its own log, so a
# token from the origin URL leaking on ANY path shows up in $ologs.
OSCRIPT=/usr/local/share/devc/owner-check.sh
ofile=$(mktemp -u)              # the marker; an absent path until a run writes it
ologs=$(mktemp)
run_oc() { # run_oc <label>: runs the script; $olog holds stdout+stderr
    olog=$(mktemp)
    rc=0
    env DEVC_OWNER_FILE="$ofile" DEVC_OWNER_WORKSPACE="$repo" sh "$OSCRIPT" >"$olog" 2>&1 </dev/null || rc=$?
    check "owner-check exit ($1)" 0 "$rc"
    cat "$olog" >>"$ologs"
}
oc_says() { # oc_says <label> <text>: the run's output holds <text>
    if grep -qF -- "$2" "$olog"; then echo "ok   owner-check says '$2' ($1)"
    else echo "FAIL owner-check ($1): expected '$2' in: $(cat "$olog")"; fail=1; fi
}
oc_silent_on() { # oc_silent_on <label> <text>: the run's output does not hold <text>
    if grep -qF -- "$2" "$olog"; then echo "FAIL owner-check ($1): '$2' appeared in: $(cat "$olog")"; fail=1
    else echo "ok   owner-check does not print '$2' ($1)"; fi
}
BANNER='THIS VOLUME BELONGS TO ANOTHER REPOSITORY'

# match: the first start writes the lowercased owner, the next prints ok
rm -rf "$ofile"
setorigin https://x-token:secret@github.com/Fixture-Org/R
run_oc "first start"
check "owner marker written, lowercase" fixture-org/r "$(cat "$ofile" 2>/dev/null || true)"
oc_says "first start" "fixture-org/r (new marker)"
run_oc "same repo again"
oc_says "same repo again" "owner-check: ok (fixture-org/r)"
oc_silent_on "same repo again" "$BANNER"
# a clone URL that differs only by .git or the scheme names the same repo
setorigin git@github.com:fixture-org/r.git
run_oc "same repo, ssh .git URL"
oc_says "same repo, ssh .git URL" "owner-check: ok (fixture-org/r)"

# mismatch: a banner naming both repos, exit 0, the marker left alone
setorigin https://x-token:secret@github.com/fixture-org/other
run_oc "mismatch"
oc_says "mismatch" "$BANNER"
oc_says "mismatch" "first used by: fixture-org/r"
oc_says "mismatch" "starting now is:      fixture-org/other"
check "owner marker unchanged on a mismatch" fixture-org/r "$(cat "$ofile")"

# no owner: nothing is written, one line says so, and a previous marker is left alone
setorigin ""; run_oc "no origin"
oc_says "no origin" "owner-check: skipped"
check "owner marker unchanged with no origin" fixture-org/r "$(cat "$ofile")"
rm -f "$ofile"
for u in https://evil.example/p@github.com/fixture-org/r https://github.com.evil.example/fixture-org/r; do
    setorigin "$u"; run_oc "rejected origin $u"
    oc_says "rejected origin $u" "owner-check: skipped"
    check "no owner marker for rejected origin $u" 0 "$([ -e "$ofile" ] && echo 1 || echo 0)"
done
# a multi-line origin value is storable and never accepted
git -C "$repo" config --unset-all remote.origin.url || true
git -C "$repo" config remote.origin.url "$(printf 'https://github.com/fixture-org/r\nhttps://github.com/x/y')"
run_oc "multi-line origin"
oc_says "multi-line origin" "owner-check: skipped"
check "no owner marker for a multi-line origin" 0 "$([ -e "$ofile" ] && echo 1 || echo 0)"

# a marker that is not one clean org/repo line: treated as a mismatch, NEVER echoed, and
# replaced, so the banner fires once and not at every start
setorigin https://github.com/fixture-org/r
esc=$(printf '\033')
for kind in escape multiline nul dir symlink oversize; do
    rm -rf "$ofile"
    case "$kind" in
        escape)    printf 'fixture-org/%s]0;pwned\007\n' "$esc" >"$ofile" ;;
        multiline) printf 'fixture-org/r\nanother/line\n' >"$ofile" ;;
        nul)       printf 'fixture-org/r\000junk\n' >"$ofile" ;;
        dir)       mkdir -p "$ofile/sub" ;;
        symlink)   printf '# untouched\n' >"$fx/owner-target"; ln -s "$fx/owner-target" "$ofile" ;;
        oversize)  head -c 3000 /dev/zero | tr '\0' 'a' >"$ofile" ;;
    esac
    run_oc "junk marker ($kind)"
    oc_says "junk marker ($kind)" "$BANNER"
    oc_silent_on "junk marker ($kind)" "$esc"
    oc_silent_on "junk marker ($kind)" pwned
    oc_silent_on "junk marker ($kind)" another/line
    check "junk marker ($kind) replaced by the owner" "fixture-org/r|0" \
        "$(cat "$ofile" 2>/dev/null || true)|$([ -L "$ofile" ] && echo 1 || echo 0)"
    run_oc "after junk marker ($kind)"
    oc_says "after junk marker ($kind)" "owner-check: ok (fixture-org/r)"
done
check "symlinked owner marker: target not written through" '# untouched' "$(cat "$fx/owner-target")"
# a symlink is never READ through either: its target holds a valid, DIFFERENT owner, which
# must not be taken as the marker (a mismatch banner, not a silent ok or a new marker)
rm -rf "$ofile"; printf 'other-org/other\n' >"$fx/owner-target2"; ln -s "$fx/owner-target2" "$ofile"
run_oc "symlink to a valid owner"
oc_says "symlink to a valid owner" "$BANNER"
oc_silent_on "symlink to a valid owner" "other-org/other"
check "symlink to a valid owner replaced by the owner" "fixture-org/r|0" \
    "$(cat "$ofile" 2>/dev/null || true)|$([ -L "$ofile" ] && echo 1 || echo 0)"
check "symlink to a valid owner: target untouched" other-org/other "$(cat "$fx/owner-target2")"

# a url.*.insteadOf planted in the home volume's global config (git reads it from
# GIT_CONFIG_GLOBAL, and this script runs before git-identity.sh rewrites it) must not change
# the origin seen here
rm -f "$ofile"
setorigin https://github.com/fixture-org/r
printf '[url "https://github.com/spoof-org/spoof"]\n\tinsteadOf = https://github.com/fixture-org/r\n' >/home/app/.gitconfig
run_oc "planted insteadOf"
oc_says "planted insteadOf" "fixture-org/r (new marker)"
rm -f /home/app/.gitconfig "$ofile"

# the origin's token and user never reach output
if grep -qF -e secret -e x-token "$ologs"; then
    echo "FAIL origin token leaked into owner-check output"; fail=1
else
    echo "ok   no origin token in owner-check output"
fi

# the grammar lives in two scripts: one table of URLs through both, and they must agree on
# the org and on accept versus reject. A drift in either copy fails here. (One deliberate,
# fail-safe difference is not in the table: owner-check.sh drops a trailing .git from the
# repo segment, so an origin whose repo is exactly ".git" gets no owner there.)
gx=$(mktemp -d)
printf '[devcontainer]\n    org = fixture-org\n    org = other-org\n' >"$gx/all.gitconfig"
while IFS='|' read -r url want; do
    [ -n "$url" ] || continue
    setorigin "$url"
    rm -rf "$ofile"; run_oc "agreement $url"
    got_oc=$(sed -n 's/^owner-check: \(.*\) (new marker)$/\1/p' "$olog")
    glog=$(mktemp)
    env GIT_IDENTITY_DIR="$gx" GIT_IDENTITY_WORKSPACE="$repo" sh "$SCRIPT" >"$glog" 2>&1 </dev/null || true
    got_gi=$(sed -n 's/^git-identity: \([^ ]*\) -> .*/\1/p' "$glog")
    check "grammar: owner-check owner for $url" "$want" "$got_oc"
    check "grammar: git-identity org for $url" "${want%%/*}" "$got_gi"
done <<'TABLE'
https://github.com/fixture-org/r|fixture-org/r
https://github.com/Fixture-Org/Repo|fixture-org/repo
https://x-token:secret@github.com/fixture-org/r.git|fixture-org/r
https://user@github.com/other-org/a.b_c-d/|other-org/a.b_c-d
git@github.com:fixture-org/r.git|fixture-org/r
ssh://git@github.com/fixture-org/r|fixture-org/r
https://evil.example/p@github.com/fixture-org/r|
https://github.com.evil.example/fixture-org/r|
https://github.com/fixture-org/r/extra|
https://github.com/fixture-org/..|
https://github.com/fixture-org/.|
https://github.com/-fixture/r|
http://github.com/fixture-org/r|
git@github.com:fixture-org|
git@evil.example:fixture-org/r|
TABLE
rm -rf "$ofile"
setorigin "$POS_URL"

case "$flavor" in
  base) ;;
  tofu)
    check "tofu" "v$EXPECT_TOFU" "$(tofu version | awk 'NR==1{print $2}')"
    check "tflint" "$EXPECT_TFLINT" "$(tflint --version | awk 'NR==1{print $3}')"
    check "TF_DATA_DIR" .terraform-devcontainer "${TF_DATA_DIR:-}"
    check "TF_PLUGIN_CACHE_DIR" /home/app/.cache/tofu-plugins "${TF_PLUGIN_CACHE_DIR:-}"
    check "TFLINT_PLUGIN_DIR" /home/app/.local/tflint-plugins "${TFLINT_PLUGIN_DIR:-}"
    ;;
  node)
    check "node" "v$EXPECT_NODE" "$(node --version)"
    check "npm" "$EXPECT_NPM" "$(npm --version)"
    check "npm cache" /home/app/.local/npm-cache "$(npm config get cache)"
    check "npm global prefix" /home/app/.local "$(npm config get prefix)"
    check "PUPPETEER_CACHE_DIR" /home/app/.local/puppeteer "${PUPPETEER_CACHE_DIR:-}"
    ;;
  *) echo "FAIL unknown flavor $flavor"; fail=1 ;;
esac

exit "$fail"
