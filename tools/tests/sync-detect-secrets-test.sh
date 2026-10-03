#!/usr/bin/env bash
# Tests for .github/scripts/sync-detect-secrets.sh against the fake `gh`, a PyPI served
# from file://, a fake `uv`, and a scratch git repo with a bare origin. Offline.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# The host's git config (autocrlf, commit signing, identity) stays out of every git call here.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

SCRIPT="$ROOT_DIR/.github/scripts/sync-detect-secrets.sh"
A=0000000000000000000000000000000000000a12   # v0.1.2's commit
B=0000000000000000000000000000000000000b10   # v0.1.10's commit

setup() { # setup <image's locked version> -> a scratch repo, fixtures for v0.1.2 = 1.5.52
  new_scenario
  REPO_ROOT="$SCRATCH/repo"
  mkdir -p "$REPO_ROOT/images/base/tools" "$SCRATCH/pypi/checkov/3.3.22" "$SCRATCH/bin"
  cat > "$REPO_ROOT/images/base/tools/pyproject.toml" <<EOF
# (v0.1.1: checkov 3.3.8 -> $1). Every 603 repo's baseline and CI secret-scan job
[project]
dependencies = [
    "bc-detect-secrets==$1",
    "pre-commit",
]
EOF
  printf '[[package]]\nname = "bc-detect-secrets"\nversion = "%s"\n' "$1" > "$REPO_ROOT/images/base/tools/uv.lock"
  printf '[{"name":"v0.1.2","commit":{"sha":"%s"}},{"name":"v0.1.1","commit":{"sha":"%s"}}]' "$A" "$B" > "$FAKE_FIX/tags.json"
  printf '{"version":"1.5.52","results":{}}' > "$FAKE_FIX/contents__.secrets.baseline.json"
  printf '{"checkov_version":"3.3.22"}' > "$FAKE_FIX/contents__examples__checkov-ledger.json.json"
  pypi_json 3.3.22 '["bc-detect-secrets==1.5.52", "bc-python-hcl2==0.4.3"]'
  # Fake uv: re-locks bc-detect-secrets to whatever the pyproject pin now says;
  # FAKE_UV_EXTRA=1 also touches a file a real re-lock must never change.
  cat > "$SCRATCH/bin/uv" <<'U'
#!/usr/bin/env bash
echo "uv $*" >> "$FAKE_LOG"
d="$(dirname "$0")/../repo/images/base/tools"
v="$(sed -n 's/^    "bc-detect-secrets==\(.*\)",$/\1/p' "$d/pyproject.toml")"
printf '[[package]]\nname = "bc-detect-secrets"\nversion = "%s"\n' "$v" > "$d/uv.lock"
[ "${FAKE_UV_EXTRA:-0}" = 1 ] && echo x > "$d/stray"
exit 0
U
  chmod +x "$SCRATCH/bin/uv"
  PYPI="$SCRATCH/pypi"
  if command -v cygpath >/dev/null 2>&1; then PYPI="$(cygpath -m "$PYPI")"; fi
  unset FAKE_PR_OPEN FAKE_UV_EXTRA
}
pypi_json() { # pypi_json <checkov version> <requires_dist JSON array>
  mkdir -p "$SCRATCH/pypi/checkov/$1"
  printf '{"info":{"requires_dist":%s}}' "$2" > "$SCRATCH/pypi/checkov/$1/json"
}
git_init() { # the scratch repo as a clone-like checkout of a bare origin, on main
  git init -q -b main --bare "$SCRATCH/origin.git"
  git -C "$REPO_ROOT" init -q -b main
  git -C "$REPO_ROOT" add -A
  git -C "$REPO_ROOT" -c user.name=t -c user.email=t@t commit -q -m init
  git -C "$REPO_ROOT" remote add origin "$SCRATCH/origin.git"
  git -C "$REPO_ROOT" push -q origin main
}
run_sync() { # [VAR=value ...] -> RC; dry run unless DRY_RUN=0 is passed
  RC=0
  env PATH="$SCRATCH/bin:$PATH" DEVC_ROOT="$REPO_ROOT" PYPI_URL="file:///${PYPI#/}" \
    ACTION_REPO=603-Identity/checkov-ledger-action REPO=603-Identity/devcontainers \
    APP_SLUG=sync-bot APP_ID=1 GH_TOKEN=t DRY_RUN=1 \
    "$@" bash "$SCRIPT" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr" || RC=$?
}
out_has() { if grep -qF -- "$2" "$SCRATCH/stdout" "$SCRATCH/stderr"; then pass; else fail "$1" "output lacks: $2"; fi; }
locked() { sed -n '3s/^version = "\(.*\)"$/\1/p' "$REPO_ROOT/images/base/tools/uv.lock"; }

suite "sync-detect-secrets.sh"

setup 1.5.52; run_sync
assert_rc "in sync" 0 "$RC"; out_has "in sync says so" "in sync with 603-Identity/checkov-ledger-action@v0.1.2 at 1.5.52"
end_scenario

setup 1.5.51; run_sync
assert_rc "behind" 3 "$RC"; out_has "behind names the move" "1.5.51 -> 1.5.52 (checkov 3.3.22"
assert_log_has "reads at the tag's commit, not the tag name" "contents/.secrets.baseline?ref=$A"
assert_eq "dry run leaves the lock" 1.5.51 "$(locked)"
end_scenario

setup 1.5.51
printf '[{"name":"v0.1.9","commit":{"sha":"%s"}},{"name":"v0.1.10","commit":{"sha":"%s"}},{"name":"v0.2.0-rc1","commit":{"sha":"%s"}},{"name":"latest","commit":{"sha":"%s"}}]' \
  "$A" "$B" "$A" "$A" > "$FAKE_FIX/tags.json"
run_sync
assert_rc "highest tag" 3 "$RC"; out_has "v0.1.10 beats v0.1.9; rc and non-semver tags ignored" "checkov-ledger-action@v0.1.10"
assert_log_has "reads v0.1.10's commit" "?ref=$B"
end_scenario

setup 1.5.51; printf '[{"name":"latest","commit":{"sha":"%s"}}]' "$A" > "$FAKE_FIX/tags.json"; run_sync
assert_rc "no vX.Y.Z tag" 1 "$RC"; out_has "no tag says so" "has no vX.Y.Z tag"
end_scenario

setup 1.5.51; status_of tags 500; run_sync
assert_rc "tag listing fails" 1 "$RC"
end_scenario

setup 1.5.51; printf '{"version":"1.5.47"}' > "$FAKE_FIX/contents__.secrets.baseline.json"; run_sync
assert_rc "action disagrees with itself" 1 "$RC"; out_has "disagreement named" "its .secrets.baseline is 1.5.47 but checkov 3.3.22 pins 1.5.52"
end_scenario

setup 1.5.51; printf '{"version":"1.5.52\\n::warning::x"}' > "$FAKE_FIX/contents__.secrets.baseline.json"; run_sync
assert_rc "malformed baseline version" 1 "$RC"; out_has "malformed rejected" "is not a plain X.Y.Z"
end_scenario

setup 1.5.51; drop contents__examples__checkov-ledger.json; run_sync
assert_rc "no example ledger" 1 "$RC"
end_scenario

setup 1.5.51; pypi_json 3.3.22 '["bc-detect-secrets>=1.5.47"]'; run_sync
assert_rc "checkov stops pinning exactly" 1 "$RC"; out_has "range rejected" "does not pin bc-detect-secrets to one exact X.Y.Z"
end_scenario

setup 1.5.51; pypi_json 3.3.22 '["bc-detect-secrets==1.5.52 ; python_version >= \"3.9\"", "pyyaml"]'; run_sync
assert_rc "environment marker tolerated" 3 "$RC"; out_has "marker stripped" "1.5.51 -> 1.5.52"
end_scenario

setup 1.5.53; run_sync
assert_rc "downgrade refused" 1 "$RC"; out_has "downgrade named" "refusing to open a downgrade PR"
end_scenario

setup 1.5.51; git_init; run_sync DRY_RUN=0
assert_rc "write path" 0 "$RC"
assert_eq "on the bump branch" bump/bc-detect-secrets-1.5.52 "$(git -C "$REPO_ROOT" branch --show-current)"
assert_eq "lock moved" 1.5.52 "$(locked)"
assert_eq "pin moved" 1 "$(grep -c '^    "bc-detect-secrets==1.5.52",$' "$REPO_ROOT/images/base/tools/pyproject.toml")"
assert_eq "comment names the release" 1 "$(grep -c '^# (v0.1.2: checkov 3.3.22 -> 1.5.52)\. Every' "$REPO_ROOT/images/base/tools/pyproject.toml")"
assert_eq "branch pushed" 1 "$(git -C "$SCRATCH/origin.git" branch --list bump/bc-detect-secrets-1.5.52 | wc -l | tr -d ' ')"
assert_eq "commit as the app" "sync-bot[bot]" "$(git -C "$REPO_ROOT" log -1 --format=%an)"
assert_log_has "PR opened" "gh pr create --repo 603-Identity/devcontainers --head bump/bc-detect-secrets-1.5.52 --base main"
end_scenario

setup 1.5.51; git_init; FAKE_PR_OPEN=1; export FAKE_PR_OPEN; run_sync DRY_RUN=0
assert_rc "PR already open" 0 "$RC"; assert_eq "nothing committed" main "$(git -C "$REPO_ROOT" branch --show-current)"
assert_log_lacks "no second PR" "gh pr create"
end_scenario

setup 1.5.51; git_init; FAKE_UV_EXTRA=1; export FAKE_UV_EXTRA; run_sync DRY_RUN=0
assert_rc "re-lock moved something else" 1 "$RC"; out_has "stray change named" "unexpected changes after the re-lock"
assert_log_lacks "no PR on a dirty re-lock" "gh pr create"
end_scenario

echo "sync-detect-secrets: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
