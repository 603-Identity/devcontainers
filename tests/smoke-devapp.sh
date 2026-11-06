#!/bin/sh
# Asserts what the dev-App flavour (images/devapp) promises on top of what tests/smoke.sh
# asserts for every image: a GitHub identity that is the dev token and nothing else, no way to
# sign, a verified `claude`, GNU coreutils. build-and-test.sh runs it once per /run/wow the host
# could present, each in a fresh container:
#
#   with       a valid dev-token, and decoys beside it (admin-token, token) that must never be read
#   without    no /run/wow at all
#   empty      /run/wow mounted, but empty
#   expired    a dev-token whose expires_at has passed
#   crlf       a dev-token with CRLF line endings
#   badtoken   a dev-token whose line 1 is not an installation token
#   stateless  a valid dev-token in GitHub's stateless format (ghs_APPID_JWT: dots, dashes,
#              520 characters after ghs_, a file over 512 bytes), served like `with` (#492)
#   oversize   a stateless-shaped dev-token in a file over the 2048-byte cap
#   badchar    a dev-token whose line 1 has a character outside [A-Za-z0-9._-]
#   short      a dev-token with 35 characters after ghs_, one fewer than the minimum
#
# `with` and `stateless` are the served modes. `stateless` runs only the credential and gh
# wrapper checks; the checks unrelated to the token run once, under `with`.
#
# Every other mode asserts the same thing: the layer FAILS CLOSED. dev-token answers
# `quit=1`, the gh wrapper refuses, and git cannot fill a credential. No mode may print the
# decoy token, or the dev token where it is not the one being served.
#
#   docker run --rm -v "$PWD/out/wow/with:/run/wow:ro" -v "$PWD/tests:/tests:ro" \
#     -e DEVC_FIXTURE_TOKEN=... -e DEVC_DECOY_TOKEN=... -e EXPECT_GH=... -e EXPECT_CLAUDE=... \
#     -e EXPECT_CLAUDE_SHA256=... <image> sh /tests/smoke-devapp.sh <devapp|devapp-tofu> with
#
# The tokens are generated per run by build-and-test.sh and mean nothing to GitHub. They are
# compared, never printed: `check` is given 1 or 0, not a token.
set -eu

usage="usage: smoke-devapp.sh <devapp|devapp-tofu> <with|without|empty|expired|crlf|badtoken|stateless|oversize|badchar|short>"
flavor="${1:?$usage}"
mode="${2:?$usage}"
: "${DEVC_FIXTURE_TOKEN:?} ${DEVC_DECOY_TOKEN:?} ${EXPECT_GH:?} ${EXPECT_CLAUDE:?} ${EXPECT_CLAUDE_SHA256:?}"
fail=0
check() { # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok   $1 = $3"
    else
        echo "FAIL $1: expected '$2', got '$3'"
        fail=1
    fi
}
yes_no() { if "$@"; then echo 1; else echo 0; fi; }   # yes_no <test...>: 1 when the test passes
# contains <text> <needle>: 1 when <text> holds the fixture-or-decoy needle. Never prints either.
contains() { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }

H=/usr/local/libexec/dev-token
GHBIN=/usr/local/libexec/gh-real
REQ='protocol=https\nhost=github.com\n\n'

# The fixture, as the mode describes it.
case "$flavor" in devapp|devapp-tofu) ;; *) echo "FAIL unknown flavor $flavor"; exit 1 ;; esac
case "$mode" in
    without) check "/run/wow is absent" 0 "$(yes_no test -e /run/wow)" ;;
    with|empty|expired|crlf|badtoken|stateless|oversize|badchar|short) check "/run/wow is mounted read-only" 1 \
        "$(yes_no sh -c 'grep -E "^[^ ]+ /run/wow " /proc/mounts | grep -qE "[ ,]ro[ ,]"')" ;;
    *) echo "FAIL unknown mode $mode"; exit 1 ;;
esac
case "$mode" in with|stateless) served=1 ;; *) served=0 ;; esac

# --- the fail-closed modes (everything except `with` and `stateless`) -----------------------
if [ "$served" = 0 ]; then
    out=$(printf '%b' "$REQ" | "$H" get 2>/dev/null) && rc=0 || rc=$?
    check "dev-token get ($mode): exit" 0 "$rc"
    check "dev-token get ($mode): answers quit=1 only" "quit=1" "$out"
    err=$(printf '%b' "$REQ" | "$H" get 2>&1 >/dev/null || true)
    check "dev-token get ($mode): the reason is on stderr" 1 "$(yes_no test -n "$err")"
    # Each token-shape mode must be refused by the check it exists for, not by another one.
    case "$mode" in
        oversize) why="at most 2048 bytes" ;;
        badtoken|badchar|short) why="line 1 is not an installation token" ;;
        *) why= ;;
    esac
    [ -z "$why" ] || check "dev-token get ($mode): refused for: $why" 1 "$(contains "$err" "$why")"
    out=$("$H" token 2>/dev/null) && rc=0 || rc=$?
    check "dev-token token ($mode): refuses" 1 "$rc"
    check "dev-token token ($mode): prints nothing" "" "$out"
    seen="$out$err"

    out=$(gh --version 2>&1) && rc=0 || rc=$?
    seen="$seen$out"
    check "gh wrapper ($mode): refuses" 1 "$rc"
    check "gh wrapper ($mode): no gh output" 0 "$(contains "$out" "gh version")"
    check "gh-real still runs ($mode)" "$EXPECT_GH" "$($GHBIN --version | awk 'NR==1{print $3}')"

    rc=0
    out=$(printf 'protocol=https\nhost=github.com\npath=x/y\n\n' \
        | env -u GIT_ASKPASS -u SSH_ASKPASS timeout 10 git credential fill 2>&1) || rc=$?
    check "git credential fill ($mode): fails" 1 "$(yes_no test "$rc" -ne 0)"
    check "git credential fill ($mode): no password" 0 "$(contains "$out" password=)"

    seen="$seen$out"
    # nothing printed above may hold either token: the decoys sit in the directory, and the
    # fixture token sits in the `crlf` / `expired` file. (The `get` answer was checked to be
    # exactly quit=1 above.)
    check "no decoy token in any output ($mode)" 0 "$(contains "$seen" "$DEVC_DECOY_TOKEN")"
    check "no dev token in any output ($mode)" 0 "$(contains "$seen" "$DEVC_FIXTURE_TOKEN")"
    check "claude still runs ($mode)" "$EXPECT_CLAUDE" "$(claude --version | awk '{print $1}')"
    exit "$fail"
fi

# --- the served modes, `with` and `stateless` -------------------------------------------------
# dev-token as a git credential helper.
out=$(printf '%b' "$REQ" | "$H" get)
check "get: protocol" protocol=https "$(printf '%s\n' "$out" | sed -n 1p)"
check "get: host" host=github.com "$(printf '%s\n' "$out" | sed -n 2p)"
check "get: username" username=x-access-token "$(printf '%s\n' "$out" | sed -n 3p)"
check "get: the password is the dev token" 1 "$(yes_no test "$(printf '%s\n' "$out" | sed -n 4p)" = "password=$DEVC_FIXTURE_TOKEN")"
check "get: four lines" 4 "$(printf '%s\n' "$out" | wc -l)"
check "get: a path and a user in the request change nothing" 1 \
    "$(yes_no test "$out" = "$(printf 'protocol=https\nhost=github.com\npath=o/r\nusername=someone\n\n' | "$H" get)")"
check "get: no decoy in the output" 0 "$(contains "$out" "$DEVC_DECOY_TOKEN")"
check "token: the bare token" 1 "$(yes_no test "$("$H" token)" = "$DEVC_FIXTURE_TOKEN")"

# Everything that is not https github.com is `quit=1`, and the token is nowhere in it.
quit_for() { # quit_for <label> <printf format of the request>
    got=$(printf '%b' "$2" | "$H" get 2>/dev/null) && rc=0 || rc=$?
    check "quit=1: $1" "0|quit=1" "$rc|$got"
}
quit_for "http" 'protocol=http\nhost=github.com\n\n'
quit_for "port 443" 'protocol=https\nhost=github.com:443\n\n'
quit_for "upper-case host" 'protocol=https\nhost=GitHub.com\n\n'
quit_for "trailing dot" 'protocol=https\nhost=github.com.\n\n'
quit_for "trailing space" 'protocol=https\nhost=github.com \n\n'
quit_for "gist.github.com" 'protocol=https\nhost=gist.github.com\n\n'
quit_for "api.github.com" 'protocol=https\nhost=api.github.com\n\n'
quit_for "lookalike suffix" 'protocol=https\nhost=github.com.evil.example\n\n'
quit_for "lookalike prefix" 'protocol=https\nhost=evilgithub.com\n\n'
quit_for "another host" 'protocol=https\nhost=gitlab.com\n\n'
quit_for "no host" 'protocol=https\n\n'
quit_for "empty host" 'protocol=https\nhost=\n\n'
quit_for "no protocol" 'host=github.com\n\n'
quit_for "ssh protocol" 'protocol=ssh\nhost=github.com\n\n'
quit_for "an empty request" '\n'
quit_for "a repeated host" 'protocol=https\nhost=github.com\nhost=evil.example\n\n'
quit_for "a repeated protocol" 'protocol=https\nprotocol=http\nhost=github.com\n\n'
quit_for "a request with the host in a url" 'url=https://github.com/o/r\n\n'
out=$(printf 'protocol=https\nhost=gitlab.com\n\n' | "$H" get 2>&1 || true)
check "quit=1: no token in any refusal" 0 "$(contains "$out" "$DEVC_FIXTURE_TOKEN")"

for a in store erase; do
    out=$(printf 'protocol=https\nhost=github.com\nusername=x\npassword=pw\n\n' | "$H" "$a" 2>&1) && rc=0 || rc=$?
    check "$a: exit and output" "0|" "$rc|$out"
done
rc=0; "$H" bogus >/dev/null 2>&1 || rc=$?
check "an unknown action exits 2" 2 "$rc"

# ...and through git itself, which is what the credential path really is: exactly one helper
# runs, it is dev-token, and a fill for another host fails without a prompt.
trace=$(mktemp)
out=$(printf 'protocol=https\nhost=github.com\npath=x/y\n\n' \
    | env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TRACE="$trace" timeout 10 git credential fill)
check "git credential fill: the password is the dev token" 1 \
    "$(yes_no test "$(printf '%s\n' "$out" | sed -n 's/^password=//p')" = "$DEVC_FIXTURE_TOKEN")"
check "git credential helpers run" 1 "$(grep -c 'run_command:' "$trace" || true)"
check "the credential helper is dev-token" 1 "$(grep -c 'run_command:.*/usr/local/libexec/dev-token get' "$trace" || true)"
rm -f "$trace"
rc=0
out=$(printf 'protocol=https\nhost=gitlab.com\npath=x/y\n\n' \
    | env -u GIT_ASKPASS -u SSH_ASKPASS timeout 10 git credential fill 2>&1) || rc=$?
check "git credential fill for another host: fails" 1 "$(yes_no test "$rc" -ne 0)"
check "git credential fill for another host: no password" 0 "$(contains "$out" password=)"
check "GIT_TERMINAL_PROMPT" 0 "${GIT_TERMINAL_PROMPT:-}"

# System git: the helper list is "" then dev-token (base's own gh helper is gone), and the listed
# ssh spellings of a github.com remote are https.
check "credential.helper list" "|/usr/local/libexec/dev-token|" \
    "$(git config --system --get-all credential.helper | tr '\n' '|')"
check "no gh credential helper left" "" "$(git config --system --get-all credential.https://github.com.helper || true)"
rt=$(mktemp -d)
git init -q "$rt"
for form in 'git@github.com:o/r.git' 'github.com:o/r.git' 'ssh://github.com/o/r.git' 'git@ssh.github.com:o/r.git' 'ssh://git@github.com/o/r.git' 'ssh://git@github.com:22/o/r.git' 'ssh://git@ssh.github.com:443/o/r.git'; do
    git -C "$rt" config remote.x.url "$form"
    check "insteadOf: $form" https://github.com/o/r.git "$(GIT_CONFIG_GLOBAL=/dev/null git -C "$rt" remote get-url x)"
done
git -C "$rt" config remote.x.url https://github.com/o/r.git
check "insteadOf: https is untouched" https://github.com/o/r.git "$(GIT_CONFIG_GLOBAL=/dev/null git -C "$rt" remote get-url x)"
rm -rf "$rt"

# The gh wrapper: the dev token authenticates, and nothing the environment or the home
# volume holds can stand in for it.
check "gh is the wrapper" "/usr/local/bin/gh|root:root 755" "$(command -v gh)|$(stat -c '%U:%G %a' /usr/local/bin/gh)"
check "gh-real" "root:root 755" "$(stat -c '%U:%G %a' "$GHBIN")"
check "dev-token" "root:root 755" "$(stat -c '%U:%G %a' "$H")"
check "gh --version through the wrapper" "$EXPECT_GH" "$(gh --version | awk 'NR==1{print $3}')"
check "gh auth token is the dev token" 1 "$(yes_no test "$(gh auth token)" = "$DEVC_FIXTURE_TOKEN")"
check "GH_TOKEN in the environment is replaced" 1 \
    "$(yes_no test "$(GH_TOKEN=$DEVC_DECOY_TOKEN gh auth token)" = "$DEVC_FIXTURE_TOKEN")"
check "GITHUB_TOKEN and GH_ENTERPRISE_TOKEN are not used" 1 \
    "$(yes_no test "$(GITHUB_TOKEN=$DEVC_DECOY_TOKEN GH_ENTERPRISE_TOKEN=$DEVC_DECOY_TOKEN gh auth token)" = "$DEVC_FIXTURE_TOKEN")"
mkdir -p /home/app/.config/gh
printf 'github.com:\n    oauth_token: %s\n    user: decoy\n' "$DEVC_DECOY_TOKEN" >/home/app/.config/gh/hosts.yml
check "a hosts.yml in the home volume is not the credential" 1 "$(yes_no test "$(gh auth token)" = "$DEVC_FIXTURE_TOKEN")"
check "the decoys are not read: no decoy in gh's output" 0 "$(contains "$(gh auth token 2>&1)" "$DEVC_DECOY_TOKEN")"

# Everything below does not depend on the token's shape: it runs once, under `with`.
[ "$mode" = with ] || exit "$fail"

# devapp-check.sh: removes the leftovers, warns, and always exits 0.
CHECK=/usr/local/share/devc/devapp-check.sh
run_check() { # run_check [VAR=value ...]: $clog holds stdout+stderr
    clog=$(mktemp)
    rc=0
    env "$@" sh "$CHECK" >"$clog" 2>&1 || rc=$?
    check "devapp-check exit" 0 "$rc"
}
printf 'github.com:\n    oauth_token: %s\n' "$DEVC_DECOY_TOKEN" >/home/app/.config/gh/hosts.yml
printf 'https://x:%s@github.com\n' "$DEVC_DECOY_TOKEN" >/home/app/.git-credentials
run_check A=1
check "devapp-check removes hosts.yml" 0 "$(yes_no test -e /home/app/.config/gh/hosts.yml)"
check "devapp-check removes .git-credentials" 0 "$(yes_no test -e /home/app/.git-credentials)"
check "devapp-check is quiet when nothing is wrong" "" "$(cat "$clog")"
mkdir -p /home/app/.config/gh/hosts.yml/sub
run_check A=1
check "devapp-check removes a directory named hosts.yml" 0 "$(yes_no test -e /home/app/.config/gh/hosts.yml)"
# A symlinked ~/.config/gh is not followed out of the volume.
elsewhere=$(mktemp -d)
printf 'kept\n' >"$elsewhere/hosts.yml"
rm -rf /home/app/.config/gh
ln -s "$elsewhere" /home/app/.config/gh
run_check A=1
check "devapp-check does not follow a symlinked ~/.config/gh" kept "$(cat "$elsewhere/hosts.yml")"
check "devapp-check says so" 1 "$(yes_no grep -q 'is a symlink' "$clog")"
rm -f /home/app/.config/gh; rm -rf "$elsewhere"
run_check SSH_AUTH_SOCK=/tmp/not-a-socket
check "devapp-check: an agent banner" 1 "$(yes_no grep -q 'AN AGENT IS FORWARDED' "$clog")"
mkdir -p /home/app/.local/bin
printf '#!/bin/sh\nexit 0\n' >/home/app/.local/bin/claude
chmod 755 /home/app/.local/bin/claude
run_check A=1
check "devapp-check: a claude that is not the verified one" 1 "$(yes_no grep -q 'claude IS NOT THE VERIFIED ONE' "$clog")"
rm -f /home/app/.local/bin/claude
rm -f "$clog"

# Signing is off. The host identity file below asks for the opposite on every count.
fx=$(mktemp -d); repo=$(mktemp -d)
cat >"$fx/a.gitconfig" <<EOF
[devcontainer]
    org = fixture-org
[user]
    name = Fixture User
    email = a@fixture.example
    signingkey = ABCDEF0123456789
[commit]
    gpgsign = true
[tag]
    gpgsign = true
EOF
git init -q "$repo"
git -C "$repo" config remote.origin.url https://github.com/fixture-org/r
env GIT_IDENTITY_DIR="$fx" GIT_IDENTITY_WORKSPACE="$repo" sh /usr/local/share/devc/git-identity.sh >/dev/null 2>&1
OUT=/home/app/.gitconfig-identity
check "identity: email still projected" a@fixture.example "$(git config -f "$OUT" --get user.email)"
check "identity: commit.gpgsign is false" false "$(git config -f "$OUT" --get commit.gpgsign)"
check "identity: tag.gpgsign is false" false "$(git config -f "$OUT" --get tag.gpgsign)"
check "identity: no signing key" "" "$(git config -f "$OUT" --get user.signingkey || true)"
check "identity: in effect for git" "false|false|" \
    "$(git config --includes --global --get commit.gpgsign)|$(git config --includes --global --get tag.gpgsign)|$(git config --includes --global --get user.signingkey || true)"
rm -rf "$fx" "$repo" "$OUT"

# No gpg, and nothing that asserts one.
for p in gpg gpg-agent gpgconf gpg-connect-agent gpgsm; do
    check "$p is gone" "" "$(command -v "$p" || true)"
done
check "gpgv stays" 1 "$(yes_no sh -c 'command -v gpgv >/dev/null')"
check "gpg-check.sh is gone from this image" 0 "$(yes_no test -e /usr/local/share/devc/gpg-check.sh)"
check "the unsigned marker" "root:root 644" "$(stat -c '%U:%G %a' /usr/local/share/devc/unsigned)"
for f in git-identity.sh owner-check.sh; do
    check "$f stays" 1 "$(yes_no test -x "/usr/local/share/devc/$f")"
done

# claude: the verified binary, root-owned, and the settings that pin it.
check "claude path" /usr/local/bin/claude "$(command -v claude)"
check "claude owner and mode" "root:root 755" "$(stat -c '%U:%G %a' /usr/local/bin/claude)"
check "claude sha256" "$EXPECT_CLAUDE_SHA256" "$(sha256sum /usr/local/bin/claude | awk '{print $1}')"
check "claude version" "$EXPECT_CLAUDE" "$(timeout 60 claude --version | awk '{print $1}')"
MS=/etc/claude-code/managed-settings.json
check "managed settings dir" "root:root 755" "$(stat -c '%U:%G %a' /etc/claude-code)"
check "managed settings file" "root:root 444" "$(stat -c '%U:%G %a' "$MS")"
check "managed settings: updater off" "1|1" "$(jq -r '"\(.env.DISABLE_UPDATES)|\(.env.DISABLE_AUTOUPDATER)"' "$MS")"
check "managed settings: minimum and maximum version" "$EXPECT_CLAUDE|$EXPECT_CLAUDE" \
    "$(jq -r '"\(.requiredMinimumVersion)|\(.requiredMaximumVersion)"' "$MS")"
check "managed settings: nothing else" "env,requiredMaximumVersion,requiredMinimumVersion" \
    "$(jq -r 'keys | join(",")' "$MS")"
check "DISABLE_UPDATES" 1 "${DISABLE_UPDATES:-}"
check "DISABLE_AUTOUPDATER" 1 "${DISABLE_AUTOUPDATER:-}"

# GNU coreutils: the links, the tools that differ, and the package.
check "timeout is GNU's" /usr/bin/gnutimeout "$(readlink /usr/local/bin/timeout)"
check "timeout --version" "timeout (GNU coreutils)" "$(timeout --version | sed -n '1s/ [0-9.]*$//p')"
check "date is GNU's" /usr/bin/gnudate "$(readlink /usr/local/bin/date)"
check "date --version" "date (GNU coreutils)" "$(date --version | sed -n '1s/ [0-9.]*$//p')"
check "date width" "00002" "$(date -u -d @86400 +%5d)"
check "gnu-coreutils is installed" "install ok installed" "$(dpkg -s gnu-coreutils | sed -n 's/^Status: //p')"
check "no setuid/setgid binaries" 0 "$(find / -xdev -perm /6000 -type f 2>/dev/null | wc -l)"

exit "$fail"
