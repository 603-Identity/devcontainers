#!/usr/bin/env bash
# Proves the TEMPLATE, not the image: brings up template/.devcontainer/ with the pinned
# @devcontainers/cli against the locally built devcontainer-tofu:local image, then asserts
# what the template promises from inside the running container. tests/smoke.sh proves what
# is IN an image; nothing else exercises the template's runArgs, its named-volume mounts,
# or the identity and gpg scripts running from postStartCommand.
#
# Asserted (each from inside the container, through `devcontainer exec`):
#   * uid 1000, an empty capability bounding set (--cap-drop=ALL), NoNewPrivs 1, and PID 1
#     is the init process ("init": true);
#   * the root filesystem is read-only: `/` is mounted ro, and a write to /usr/local fails
#     with EROFS (the devcontainer CLI's own setup had to succeed under --read-only first);
#   * the volume layout: <repo>-home at /home/app, devc-tofu-plugins nested at
#     ~/.cache/tofu-plugins, <repo>-tmp, <repo>-node_modules and <repo>-venv, and the host
#     identity directory read-only;
#   * the writable surfaces work: ~/.vscode-server, ~/.local, /tmp, /workspace/.venv;
#   * git-identity.sh wrote ~/.gitconfig on a fresh home volume and projected the fixture
#     identity, and the one credential helper that runs (checked by behaviour, as in
#     tests/smoke.sh) is gh's;
#   * tofu is the version the image pins, and pre-commit install ran in the workspace.
#
# Needs Docker, git, node and npm, and the image built first:
#
#   bash .github/scripts/build-and-test.sh local && bash tests/template-proof.sh
#
# The fixture lives in a temp directory, not in the checkout: a git-init'd directory inside
# this repo would be a nested repository. Its per-repo volumes carry a unique name and are
# removed on exit, with the image the CLI built for it. The shared devc-tofu-plugins volume
# is never removed (a developer's real containers mount it), but a local run DOES mount it
# and writes a scratch file there from an image built from this working tree: run it on a
# branch you trust.
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
home="$work/home"                   # stands in for the host's home (HOME)

fail=0
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   $1 = $3"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}
check_match() { # check_match <label> <extended-regex> <actual>
  if printf '%s' "$3" | grep -Eq -- "$2"; then echo "ok   $1"; else echo "FAIL $1: '$(printf '%s' "$3" | cut -c1-160)' does not match /$2/"; fail=1; fi
}

cleanup() {
  local ids c img
  ids="$(docker ps -aq --filter "volume=$name-home" 2>/dev/null || true)"
  for c in $ids; do
    img="$(docker inspect --format '{{.Config.Image}}' "$c" 2>/dev/null || true)"
    docker rm -f "$c" >/dev/null 2>&1 || true
    # the image the CLI built for this fixture (named after its unique folder), never a shared one
    case "$img" in "vsc-$name-"*) docker image rm -f "$img" >/dev/null 2>&1 || true ;; esac
  done
  # an image the CLI built before a failed `up` left no container behind
  docker image ls -q --filter "reference=vsc-$name-*" 2>/dev/null | xargs -r docker image rm -f >/dev/null 2>&1 || true
  for v in home tmp node_modules venv; do docker volume rm -f "$name-$v" >/dev/null 2>&1 || true; done
  rm -rf "$work" || true   # files the container (uid 1000) made on a Linux runner may resist
}
trap cleanup EXIT

# --- the pinned CLI, in a throwaway prefix (never a global install)
npm install --prefix "$work/cli" --no-audit --no-fund --loglevel=error "@devcontainers/cli@$CLI_VERSION"
dc() { # dc <args>: HOME is the fixture host home; USERPROFILE is unset so the path cannot double
  env -u USERPROFILE HOME="$(hostpath "$home")" \
    node "$(hostpath "$work/cli/node_modules/@devcontainers/cli/devcontainer.js")" "$@"
}
dx() { dc exec --workspace-folder "$(hostpath "$fixture")" "$@"; }   # dx <command...>
dxs() { dx sh -c "$1"; }                                            # dxs '<shell snippet>'

# --- the fixture: a git repo with an origin, the template copied in with FROM rewritten to the
# locally built image, and a host identity directory holding one throwaway identity
mkdir -p "$fixture/.devcontainer" "$home/.gitconfig.d"
cp -R "$root/template/.devcontainer/." "$fixture/.devcontainer/"
sed -i.bak -E 's#^FROM .*#FROM devcontainer-tofu:local#' "$fixture/.devcontainer/Dockerfile"
rm -f "$fixture/.devcontainer/Dockerfile.bak"
grep -qx 'FROM devcontainer-tofu:local' "$fixture/.devcontainer/Dockerfile" \
  || { echo "::error::could not rewrite the template's FROM line"; exit 1; }
printf 'repos: []\n' > "$fixture/.pre-commit-config.yaml"   # gives postCreateCommand a hook to install
git -C "$fixture" init -q
# CI accommodation, not something the template does: on a Linux runner this fixture is created
# by the runner's uid (1001) and the container's app user is 1000 (updateRemoteUserUID is
# false), so the fixture must be writable by others for pre-commit install and the bind mount.
# Harmless on Docker Desktop.
chmod -R a+rwX "$fixture"
git -C "$fixture" remote add origin "https://github.com/proof-org/$name"
cat > "$home/.gitconfig.d/proof.gitconfig" <<'EOF'
[devcontainer]
	org = proof-org
[user]
	name = Template Proof
	email = template-proof@example.invalid
EOF

# --- up
echo "::group::devcontainer up"
dc up --workspace-folder "$(hostpath "$fixture")" --log-level info
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
for want in \
    "volume $name-home /home/app true" \
    "volume $name-tmp /tmp true" \
    "volume devc-tofu-plugins /home/app/.cache/tofu-plugins true" \
    "volume $name-node_modules /workspace/node_modules true" \
    "volume $name-venv /workspace/.venv true" \
    "bind  /home/app/.gitconfig.d false"; do
  if printf '%s\n' "$mounts" | grep -Fxq -- "$want"; then echo "ok   mount: $want"
  else echo "FAIL mount missing: $want"; fail=1; fi
done
for t in /home/app /tmp /home/app/.cache/tofu-plugins /workspace/node_modules /workspace/.venv /home/app/.gitconfig.d; do
  check "findmnt lists $t" "$t" "$(dxs "findmnt -no TARGET $t")"
done

# --- writable surfaces (the mounts and tmpfs) still work under the read-only root
for d in /home/app/.vscode-server /home/app/.local /tmp /workspace/.venv /var/tmp /home/app/.cache/tofu-plugins; do
  check "writable $d" ok "$(dxs "mkdir -p $d && touch $d/.proof && rm -f $d/.proof && echo ok" 2>&1 | tail -n 1)"
done
check "home volume owned by app" app "$(dxs 'stat -c %U /home/app')"

# --- git identity, written by postStartCommand on a fresh home volume
check "the home gitconfig is written on a fresh volume" 1 \
  "$(dxs 'grep -c "path = /home/app/.gitconfig-identity" /home/app/.gitconfig')"
check "git user.email from the fixture identity" template-proof@example.invalid "$(dx git config user.email)"
check "git user.name from the fixture identity" "Template Proof" "$(dx git config user.name)"
# The credential helper, by behaviour and not by one key name (as tests/smoke.sh does): exactly
# one helper process runs, and it is gh's. With no gh token the fill fails fast, hence `|| true`.
# The probe is a script in the fixture (the workspace bind mount) so it needs no shell quoting.
cat > "$fixture/.proof-cred.sh" <<'EOF'
trace=/tmp/cred-trace
rm -f "$trace"
printf 'protocol=https\nhost=github.com\npath=x/y\n\n' \
  | env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=0 GIT_TRACE="$trace" \
      timeout 10 git credential fill >/dev/null 2>&1 || true
echo "$(grep -c 'run_command:' "$trace" || true) $(grep -c "run_command: '/usr/local/bin/gh auth git-credential get'\$" "$trace" || true)"
EOF
check "credential helpers run, and the one that runs is gh's" "1 1" "$(dx sh /workspace/.proof-cred.sh)"

# --- the toolchain and the postCreateCommand
expect_tofu="$(sed -n 's/^ARG TOFU_VERSION=//p' "$root/images/tofu/Dockerfile")"
[ -n "$expect_tofu" ] || { echo "::error::could not read TOFU_VERSION from images/tofu/Dockerfile"; exit 1; }
check "tofu version" "OpenTofu v$expect_tofu" "$(dxs "tofu version | head -n 1")"
check "pre-commit install ran in the fixture" 1 "$([ -x "$fixture/.git/hooks/pre-commit" ] && echo 1 || echo 0)"

if [ "$fail" -ne 0 ]; then echo "template proof: FAILED"; exit 1; fi
echo "template proof: all checks passed"
