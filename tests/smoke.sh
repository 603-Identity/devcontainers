#!/bin/sh
# Asserts what a built image promises: pinned tool versions, the non-root user, and
# the app-owned mount points the template's named volumes rely on. CI runs it against
# every image before anything is pushed; run it locally the same way:
#
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> sh /tests/smoke.sh <base|tofu|node>
#
# Expected versions are read from the Dockerfiles' own ARG lines by the CI step and
# passed in as environment variables. That keeps one source of truth: a version
# bumped in a Dockerfile but not built would fail here.
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
check "bc-detect-secrets" 1.5.47 "$(detect-secrets --version)"
if command -v pre-commit >/dev/null; then
    echo "ok   pre-commit present"
else
    echo "FAIL pre-commit missing"
    fail=1
fi
check "safe.directory" /workspace "$(git config --system --get-all safe.directory)"
check "setuid/setgid binaries" 0 "$(find / -xdev -perm /6000 -type f 2>/dev/null | wc -l)"
for d in /home/app/.config/gh /home/app/.claude /home/app/.cache; do
    check "owner $d" app "$(stat -c %U "$d")"
done

case "$flavor" in
  base) ;;
  tofu)
    check "tofu" "v$EXPECT_TOFU" "$(tofu version | awk 'NR==1{print $2}')"
    check "tflint" "$EXPECT_TFLINT" "$(tflint --version | awk 'NR==1{print $3}')"
    check "TF_DATA_DIR" .terraform-devcontainer "${TF_DATA_DIR:-}"
    check "owner tofu cache" app "$(stat -c %U /home/app/.cache/tofu-plugins)"
    ;;
  node)
    check "node" "v$EXPECT_NODE" "$(node --version)"
    check "npm" "$EXPECT_NPM" "$(npm --version)"
    check "npm cache" /home/app/.cache/npm "$(npm config get cache)"
    ;;
  *) echo "FAIL unknown flavor $flavor"; fail=1 ;;
esac

exit "$fail"
