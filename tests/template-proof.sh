#!/usr/bin/env bash
# Proves the TEMPLATE, not the image: brings up template/.devcontainer/ (the dev-App template,
# DEVC-D9) with the pinned @devcontainers/cli against the locally built devcontainer-devapp-tofu:local
# image, then asserts what the template promises from inside the running container.
# tests/smoke.sh and tests/smoke-devapp.sh prove what is IN an image; nothing else exercises the
# template's runArgs, its named-volume mounts, its token mount, or the owner and identity scripts
# running from postStartCommand.
#
# The host is faked: USERPROFILE points at a fixture home holding ~/.gitconfig.d and
# ~/.config/glunk-identity/tokens/proof-org/<folder>/dev-token (a generated ghs_ token and a
# future expiry), exactly the layout the host broker writes. HOME points somewhere else, because
# the template reads USERPROFILE only.
#
# Asserted (each from inside the container, through `devcontainer exec`):
#   * uid 1000, an empty capability bounding set (--cap-drop=ALL), NoNewPrivs 1, and PID 1
#     is the init process ("init": true);
#   * the root filesystem is read-only: `/` is mounted ro, and a write to /usr/local fails
#     with EROFS (the devcontainer CLI's own setup had to succeed under --read-only first);
#   * the volume layout: <repo>-home at /home/app, <repo>-tmp, <repo>-node_modules and
#     <repo>-venv, the host identity directory and the token directory both read-only, and NO
#     shared tofu-plugin volume and no ~/.aws;
#   * the token: /run/wow/dev-token is readable and not writable, `git credential fill` for
#     github.com returns exactly that token through dev-token (the one helper that runs), and
#     there is no gpg binary;
#   * the writable surfaces work: ~/.vscode-server, ~/.local, /tmp, /workspace/.venv;
#   * git-identity.sh wrote ~/.gitconfig on a fresh home volume and projected the fixture
#     identity, unsigned;
#   * owner-check.sh wrote the owner marker (~/.devc-owner) on a fresh home volume, and a
#     SECOND checkout with the same folder name but another origin, brought up for real so it
#     shares <folder>-home, gets the collision banner while the marker still names the first
#     repo (the mismatch the check exists for, not a simulation);
#   * tofu is the version the image pins, and pre-commit install ran in the workspace;
#   * a negative `up`: with no token directory on the host, either `up` fails (the CLI's --mount
#     refuses a missing source) or the container starts with an EMPTY /run/wow and every
#     credential path fails closed; which one depends on the daemon, and both are accepted;
#   * the appPort cases: a string and a list of loopback ports are published on 127.0.0.1 only.
#     Reachability through host.docker.internal is measured on the Windows host (the Linux runner
#     cannot show it) and recorded in the threat model.
#
# Needs Docker, git, node and npm, and the image built first:
#
#   bash .github/scripts/build-and-test.sh local && bash tests/template-proof.sh
#
# The fixtures live in a temp directory, not in the checkout: a git-init'd directory inside
# this repo would be a nested repository. Their per-repo volumes carry a unique name and are
# removed on exit, with the images the CLI built for them. Nothing shared is mounted.
set -euo pipefail

# The one pinned version of the devcontainer CLI. A bump is a reviewed edit to this line.
CLI_VERSION=0.87.0

root="$(cd "$(dirname "$0")/.." && pwd)"
hostpath() { echo "$1"; }
# Git Bash on a Windows host: git, node and docker.exe need C:/... rather than /c/..., and
# MSYS_NO_PATHCONV=1 stops Git Bash rewriting in-container paths. No-op in CI.
if command -v cygpath >/dev/null 2>&1; then
  hostpath() { cygpath -m "$1"; }
  export MSYS_NO_PATHCONV=1
fi
work="$(hostpath "$(mktemp -d)")"   # a path that bash and the native binaries both resolve
name="devc-proof-$$"                # the checkout folder name; every per-repo volume derives from it
fixture="$work/$name"
home="$work/home"                   # stands in for the host's home (USERPROFILE)
other_home="$work/other-home"       # HOME, which the template must not read
tokdir="$home/.config/glunk-identity/tokens/proof-org/$name"

fail=0
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   $1 = $3"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}
check_match() { # check_match <label> <extended-regex> <actual>
  if printf '%s' "$3" | grep -Eq -- "$2"; then echo "ok   $1"; else echo "FAIL $1: '$(printf '%s' "$3" | cut -c1-160)' does not match /$2/"; fail=1; fi
}

names=("$name" "$name-nt" "$name-pa" "$name-pb")   # every fixture folder name; each owns its volumes
cleanup() {
  local ids c img n v
  for n in "${names[@]}"; do
    ids="$(docker ps -aq --filter "volume=$n-home" 2>/dev/null || true)"
    for c in $ids; do
      img="$(docker inspect --format '{{.Config.Image}}' "$c" 2>/dev/null || true)"
      docker rm -f "$c" >/dev/null 2>&1 || true
      # the image the CLI built for this fixture (named after its unique folder), never a shared one
      case "$img" in "vsc-$n-"*) docker image rm -f "$img" >/dev/null 2>&1 || true ;; esac
    done
    # an image the CLI built before a failed `up` left no container behind
    docker image ls -q --filter "reference=vsc-$n-*" 2>/dev/null | xargs -r docker image rm -f >/dev/null 2>&1 || true
    for v in home tmp node_modules venv; do docker volume rm -f "$n-$v" >/dev/null 2>&1 || true; done
  done
  rm -rf "$work" || true   # files the container (uid 1000) made on a Linux runner may resist
}
trap cleanup EXIT

# --- the pinned CLI, in a throwaway prefix (never a global install)
npm install --prefix "$work/cli" --no-audit --no-fund --loglevel=error "@devcontainers/cli@$CLI_VERSION"
dc() { # dc <args>: USERPROFILE is the fixture host home; HOME is somewhere else on purpose
  env HOME="$(hostpath "$other_home")" USERPROFILE="$(hostpath "$home")" \
    node "$(hostpath "$work/cli/node_modules/@devcontainers/cli/devcontainer.js")" "$@"
}
dx() { dc exec --workspace-folder "$(hostpath "$fixture")" "$@"; }   # dx <command...>
dxs() { dx sh -c "$1"; }                                            # dxs '<shell snippet>'

# --- the fixture: a git repo with an origin, the template copied in with FROM rewritten to the
# locally built image and OWNER/REPO filled in, and a host home holding one throwaway identity and
# this repo's token directory
tmpl="$root/template/.devcontainer"
make_fixture() { # make_fixture <folder-name> [<extra sed expression for devcontainer.json>]
  local dir="$work/$1" extra="${2:-}"
  mkdir -p "$dir/.devcontainer"
  cp -R "$tmpl/." "$dir/.devcontainer/"
  sed -i.bak -E 's#^FROM .*#FROM devcontainer-devapp-tofu:local#' "$dir/.devcontainer/Dockerfile"
  rm -f "$dir/.devcontainer/Dockerfile.bak"
  grep -qx 'FROM devcontainer-devapp-tofu:local' "$dir/.devcontainer/Dockerfile" \
    || { echo "::error::could not rewrite the template's FROM line"; exit 1; }
  sed -i.bak -E "s#tokens/OWNER/REPO,#tokens/proof-org/$1,#${extra:+; $extra}" "$dir/.devcontainer/devcontainer.json"
  rm -f "$dir/.devcontainer/devcontainer.json.bak"
  grep -q "tokens/proof-org/$1," "$dir/.devcontainer/devcontainer.json" \
    || { echo "::error::could not fill in the template's token mount"; exit 1; }
  printf 'repos: []\n' > "$dir/.pre-commit-config.yaml"   # gives postCreateCommand a hook to install
  git -C "$dir" init -q
  # CI accommodation, not something the template does: on a Linux runner this fixture is created
  # by the runner's uid (1001) and the container's app user is 1000 (updateRemoteUserUID is
  # false), so the fixture must be writable by others for pre-commit install and the bind mount.
  # Harmless on Docker Desktop.
  chmod -R a+rwX "$dir"
  git -C "$dir" remote add origin "https://github.com/proof-org/$1"
}
mkdir -p "$other_home" "$home/.gitconfig.d" "$tokdir"
make_fixture "$name"
cat > "$home/.gitconfig.d/proof.gitconfig" <<'EOF'
[devcontainer]
	org = proof-org
[user]
	name = Template Proof
	email = template-proof@example.invalid
	signingkey = 0123456789ABCDEF
[commit]
	gpgsign = true
EOF
# the host broker's layout: line 1 the installation token, line 2 its expiry; readable by uid 1000
proof_token="ghs_$(head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 36)"
printf '%s\n%s\n' "$proof_token" "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" > "$tokdir/dev-token"
chmod -R a+rX "$home/.config" "$home/.gitconfig.d"

# --- up
echo "::group::devcontainer up"
dc up --workspace-folder "$(hostpath "$fixture")" --log-level info 2>&1 | tee "$work/up-a.log"
echo "::endgroup::"

# --- privileges and init
check "uid" 1000 "$(dx id -u)"
check "CapEff (zero for any non-root process)" 0000000000000000 "$(dxs "awk '/^CapEff/{print \$2}' /proc/self/status")"
# CapEff is zero for ANY non-root process; the bounding set is what --cap-drop=ALL empties.
check "CapBnd (--cap-drop=ALL)" 0000000000000000 "$(dxs "awk '/^CapBnd/{print \$2}' /proc/self/status")"
check "NoNewPrivs" 1 "$(dxs "awk '/^NoNewPrivs/{print \$2}' /proc/self/status")"
cid="$(docker ps -q --filter "volume=$name-home")"
[ -n "$cid" ] || { echo "FAIL no running container for the fixture"; exit 1; }
check "HostConfig.Init" true "$(docker inspect --format '{{.HostConfig.Init}}' "$cid")"
check_match "PID 1 is the init process" "^/sbin/docker-init" "$(dxs "tr '\\0' ' ' < /proc/1/cmdline")"

# --- read-only root
check "HostConfig.ReadonlyRootfs" true "$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$cid")"
check_match "/ is mounted ro" '(^|,)ro(,|$)' "$(dxs 'findmnt -no OPTIONS /')"
erofs="$(dxs 'touch /usr/local/x 2>&1; true')"
check_match "a write to the image fails with EROFS" 'Read-only file system' "$erofs"

# --- volume layout: every expected mount, by target, with the volume it is backed by
mounts="$(docker inspect --format '{{range .Mounts}}{{.Type}} {{.Name}} {{.Destination}} {{.RW}}{{println}}{{end}}' "$cid")"
check "the container has exactly seven mounts (workspace, home, tmp, node_modules, venv, gitconfig.d, wow)" 7 "$(printf '%s\n' "$mounts" | grep -c .)"
if printf '%s\n' "$mounts" | grep -Eq 'tofu-plugins|\.aws'; then echo "FAIL the container mounts a shared tofu cache or ~/.aws"; fail=1
else echo "ok   no shared tofu cache and no ~/.aws mount"; fi
for want in \
    "volume $name-home /home/app true" \
    "volume $name-tmp /tmp true" \
    "volume $name-node_modules /workspace/node_modules true" \
    "volume $name-venv /workspace/.venv true" \
    "bind  /home/app/.gitconfig.d false" \
    "bind  /run/wow false"; do
  if printf '%s\n' "$mounts" | grep -Fxq -- "$want"; then echo "ok   mount: $want"
  else echo "FAIL mount missing: $want"; fail=1; fi
done
for t in /home/app /tmp /workspace/node_modules /workspace/.venv /home/app/.gitconfig.d /run/wow; do
  check "findmnt lists $t" "$t" "$(dxs "findmnt -no TARGET $t")"
done

# --- writable surfaces (the mounts and tmpfs) still work under the read-only root
for d in /home/app/.vscode-server /home/app/.local /tmp /workspace/.venv /var/tmp; do
  check "writable $d" ok "$(dxs "mkdir -p $d && touch $d/.proof && rm -f $d/.proof && echo ok" 2>&1 | tail -n 1)"
done
check "home volume owned by app" app "$(dxs 'stat -c %U /home/app')"

# --- git identity, written by postStartCommand on a fresh home volume
check "the home gitconfig is written on a fresh volume" 1 \
  "$(dxs 'grep -c "path = /home/app/.gitconfig-identity" /home/app/.gitconfig')"
check "git user.email from the fixture identity" template-proof@example.invalid "$(dx git config user.email)"
check "git user.name from the fixture identity" "Template Proof" "$(dx git config user.name)"
# The credential helper, by behaviour and not by one key name (as tests/smoke-devapp.sh does):
# exactly one helper process runs, it is dev-token, and the answer is the fixture token. The probe
# is a script in the fixture (the workspace bind mount) so it needs no shell quoting.
cat > "$fixture/.proof-cred.sh" <<'EOF'
trace=/tmp/cred-trace
rm -f "$trace"
out=$(printf 'protocol=https\nhost=github.com\npath=x/y\n\n' \
  | env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=0 GIT_TRACE="$trace" \
      timeout 10 git credential fill 2>/dev/null || true)
echo "$(grep -c 'run_command:' "$trace" || true) $(grep -c 'run_command:.*/usr/local/libexec/dev-token get' "$trace" || true)"
printf '%s\n' "$out" | sed -n 's/^password=//p'
EOF
cred="$(dx sh /workspace/.proof-cred.sh)"
check "credential helpers run, and the one that runs is dev-token" "1 1" "$(printf '%s\n' "$cred" | head -n 1)"
# the fixture token is random, but it is shaped like a real one: compare by hash, print nothing
sha() { printf '%s' "$1" | sha256sum | cut -c1-12; }
check "git credential fill returns the token from /run/wow (sha256 prefix)" "$(sha "$proof_token")" "$(sha "$(printf '%s\n' "$cred" | sed -n 2p)")"
check "the token file is readable at /run/wow/dev-token (sha256 prefix)" "$(sha "$proof_token")" "$(sha "$(dxs 'head -n 1 /run/wow/dev-token')")"
check_match "/run/wow is not writable" 'Read-only file system' "$(dxs 'touch /run/wow/x 2>&1; true')"
# the exec answers (the neighbouring checks), and gpg is simply absent
check "there is no gpg binary" none "$(dxs 'command -v gpg >/dev/null 2>&1 && echo found || echo none')"
# the fixture identity file asks for signing with a key; the unsigned marker must override both
check "commit.gpgsign is projected off despite the identity file" false "$(dx git config --type=bool --get commit.gpgsign)"
check "no signing key is projected despite the identity file" none "$(dxs 'git config --get user.signingkey || echo none')"

# --- owner check: the marker, written by postStartCommand on a fresh home volume
BANNER='THIS VOLUME BELONGS TO ANOTHER REPOSITORY'
check "owner marker on a fresh home volume" "proof-org/$name" "$(dxs 'cat /home/app/.devc-owner')"
# the positive line first: it proves `up`'s log carries postStartCommand output, so the absence
# check below can fail
check_match "up's log shows the owner marker written" "owner-check: proof-org/$name \(new marker\)" "$(cat "$work/up-a.log")"
if grep -qF -- "$BANNER" "$work/up-a.log"; then echo "FAIL a first checkout printed the collision banner"; fail=1
else echo "ok   no collision banner for the first checkout"; fi

# --- a REAL folder-name collision: a second checkout of ANOTHER repo in a different directory
# but with the same folder name, so the template derives the same <name>-home volume. The
# banner must appear and the marker must still name the first repo.
fixture_b="$work/b/$name"
mkdir -p "$fixture_b/.devcontainer"
cp -R "$fixture/.devcontainer/." "$fixture_b/.devcontainer/"   # already carries the rewritten FROM
git -C "$fixture_b" init -q
chmod -R a+rwX "$fixture_b"
git -C "$fixture_b" remote add origin "https://github.com/proof-org/other-$name"
echo "::group::devcontainer up (colliding checkout)"
dc up --workspace-folder "$(hostpath "$fixture_b")" --log-level info 2>&1 | tee "$work/up-b.log"
echo "::endgroup::"
dxb() { dc exec --workspace-folder "$(hostpath "$fixture_b")" "$@"; }
cid_b="$(docker ps -q --filter "volume=$name-home" | { grep -vx "$cid" || true; } | head -n 1)"
[ -n "$cid_b" ] || { echo "FAIL no running container for the second checkout"; exit 1; }
mounts_b="$(docker inspect --format '{{range .Mounts}}{{.Name}} {{.Destination}}{{println}}{{end}}' "$cid_b")"
if printf '%s\n' "$mounts_b" | grep -Fxq -- "$name-home /home/app"; then echo "ok   the second checkout shares $name-home"
else echo "FAIL the second checkout does not share $name-home: $mounts_b"; fail=1; fi
# the banner must come from the second container's OWN postStartCommand, as shown in up's log
# (the positive line for the first checkout above proves the log carries that output)
if grep -qF -- "$BANNER" "$work/up-b.log"; then
  echo "ok   the collision banner appeared in the second checkout's up log"
else
  echo "FAIL the collision banner is missing from the second checkout's up log"; fail=1
fi
check "owner marker still names the first repo" "proof-org/$name" "$(dxb sh -c 'cat /home/app/.devc-owner')"

# --- the toolchain and the postCreateCommand
expect_tofu="$(sed -n 's/^ARG TOFU_VERSION=//p' "$root/images/tofu/Dockerfile")"
[ -n "$expect_tofu" ] || { echo "::error::could not read TOFU_VERSION from images/tofu/Dockerfile"; exit 1; }
check "tofu version" "OpenTofu v$expect_tofu" "$(dxs "tofu version | head -n 1")"
check "pre-commit install ran in the fixture" 1 "$([ -x "$fixture/.git/hooks/pre-commit" ] && echo 1 || echo 0)"

# --- a negative `up`: no token directory on the host. Depending on the daemon, Docker either
# refuses a bind mount whose source does not exist (Docker Desktop on Windows: "bind source path
# does not exist"), or creates it empty and root-owned (some Linux and WSL daemons). The template
# must be safe under both, so the assertion is the outcome that matters: either `up` fails, or the
# container starts with an EMPTY /run/wow and every credential path fails closed (dev-token
# answers quit=1, git has no password, the gh wrapper refuses). It never falls back to a PAT.
name_nt="$name-nt"
make_fixture "$name_nt"
if dc up --workspace-folder "$(hostpath "$work/$name_nt")" --log-level info >"$work/up-nt.log" 2>&1; then
  echo "note up started with no token directory (the daemon created the bind source); checking it fails closed"
  dxn() { dc exec --workspace-folder "$(hostpath "$work/$name_nt")" "$@"; }
  check "tokenless: /run/wow is empty" 0 "$(dxn sh -c 'ls -A /run/wow | wc -l')"
  check "tokenless: dev-token answers quit=1 only" "quit=1"     "$(dxn sh -c "printf 'protocol=https
host=github.com

' | /usr/local/libexec/dev-token get 2>/dev/null || true")"
  check "tokenless: git credential fill returns no password" 0     "$(dxn sh -c "printf 'protocol=https
host=github.com
path=x/y

' | env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=0 timeout 10 git credential fill 2>/dev/null | grep -c '^password=' || true")"
  check "tokenless: the gh wrapper refuses" 1 "$(dxn sh -c 'gh --version >/dev/null 2>&1 && echo 0 || echo 1')"
else
  echo "ok   up fails with no token directory on the host"
  check_match "the failure names the missing bind source" "bind source path does not exist.*tokens/proof-org/$name_nt" "$(cat "$work/up-nt.log")"
fi

# --- the appPort cases: the one per-repo surface that publishes a port. Each is published on
# 127.0.0.1 only, never on 0.0.0.0 or ::.
p1=$((20000 + $$ % 10000)); p2=$((p1 + 1)); p3=$((p1 + 2))   # pa still holds p1 while pb runs
appport_case() { # appport_case <folder-name> <appPort JSON value> <expected "docker port" lines, sorted>
  local n="$1" value="$2" want="$3" dir cidp got
  mkdir -p "$home/.config/glunk-identity/tokens/proof-org/$n"
  cp "$tokdir/dev-token" "$home/.config/glunk-identity/tokens/proof-org/$n/dev-token"
  chmod -R a+rX "$home/.config/glunk-identity/tokens/proof-org/$n"
  make_fixture "$n" "s#\"init\": true,#\"init\": true, \"appPort\": $value,#"
  dir="$work/$n"
  dc up --workspace-folder "$(hostpath "$dir")" --log-level info >"$work/up-$n.log" 2>&1 \
    || { echo "FAIL up with appPort $value"; sed 's/^/    /' "$work/up-$n.log" | tail -n 20; fail=1; return; }
  cidp="$(docker ps -q --filter "volume=$n-home")"
  got="$(docker port "$cidp" | sort)"
  check "appPort $value publishes loopback only" "$want" "$got"
  if printf '%s\n' "$got" | grep -Eq '0\.0\.0\.0|\[::\]'; then echo "FAIL appPort $value is published on a wildcard address"; fail=1; fi
}
appport_case "$name-pa" "\"127.0.0.1:$p1:8080\"" "8080/tcp -> 127.0.0.1:$p1"
appport_case "$name-pb" "[\"127.0.0.1:$p2:8080\", \"127.0.0.1:$p3:9090\"]" "$(printf '8080/tcp -> 127.0.0.1:%s\n9090/tcp -> 127.0.0.1:%s' "$p2" "$p3" | sort)"

if [ "$fail" -ne 0 ]; then echo "template proof: FAILED"; exit 1; fi
echo "template proof: all checks passed"
