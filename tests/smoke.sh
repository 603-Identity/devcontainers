#!/bin/sh
# Asserts what a built image promises: pinned tool versions, the non-root user, the
# app-owned mount points the template's named volumes rely on, the cache and home
# layout (what is shared, what is per repo), and the git identity projection (git-identity.sh):
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
# The template mounts /home/app (per-repo), /home/app/.cache (shared) and the two
# dependency directories as volumes. Docker copies the image path's ownership into an
# empty volume, so each mount point must exist in the image and be app-owned, or it comes
# up root-owned and unwritable as uid 1000.
for d in /home/app /home/app/.cache /home/app/.cache/tofu-plugins     /workspace/.venv /workspace/node_modules; do
    check "owner $d" app "$(stat -c %U "$d")"
done
# Image-owned configuration must not live in the home directory: the home volume freezes
# the image's copy at first mount. git-identity.sh writes ~/.gitconfig at every start.
check "no ~/.gitconfig in the image" "" "$(ls -A /home/app/.gitconfig /home/app/.gitconfig-identity 2>/dev/null || true)"

# Only lock-verified content may live in the shared volume (~/.cache): the tofu provider
# cache and npm's. Every other cache lives in the per-repo home volume (~/.local), so no
# XDG-aware tool may default into ~/.cache. XDG_CACHE_HOME moves them all at once.
check "XDG_CACHE_HOME" /home/app/.local/cache "${XDG_CACHE_HOME:-}"
check "UV_CACHE_DIR" /home/app/.local/uv-cache "${UV_CACHE_DIR:-}"
check "UV_LINK_MODE" copy "${UV_LINK_MODE:-}"
check "PRE_COMMIT_HOME" /home/app/.local/pre-commit "${PRE_COMMIT_HOME:-}"
# Unset, or an unverified cache entry could be used and written into a repo's lock file.
check "TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE" "" "${TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE:-}"
for v in XDG_CACHE_HOME PRE_COMMIT_HOME PIP_CACHE_DIR UV_CACHE_DIR; do
    val=$(printenv "$v" || true)
    case "$val" in
        /home/app/.cache|/home/app/.cache/*)
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
# So is a dangling symlink, and the link's target is not written through.
rm -f /home/app/.gitconfig; ln -s /nonexistent/gitconfig /home/app/.gitconfig
setorigin "$POS_URL"; run_fx "symlinked gitconfig"; expect_id "symlinked gitconfig"
check "home gitconfig: symlink replaced" "$stub|0" \
    "$(cat /home/app/.gitconfig 2>/dev/null || true)|$([ -L /home/app/.gitconfig ] && echo 1 || echo 0)"
# The identity is denied, yet the include is still in place.
setorigin ""; run_fx "no origin gitconfig"
check "home gitconfig: written on a denied identity" "$stub" "$(cat /home/app/.gitconfig 2>/dev/null || true)"

# The origin URL carried a token in these runs: neither it nor its user may be echoed.
if grep -qF -e secret -e x-token "$alllogs"; then
    echo "FAIL origin token leaked into git-identity output"; fail=1
else
    echo "ok   no origin token in git-identity output"
fi

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
    check "npm cache" /home/app/.cache/npm "$(npm config get cache)"
    check "npm global prefix" /home/app/.local "$(npm config get prefix)"
    ;;
  *) echo "FAIL unknown flavor $flavor"; fail=1 ;;
esac

exit "$fail"
