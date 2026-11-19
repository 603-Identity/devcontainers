#!/usr/bin/env bash
# Checks that this repo's zizmor container pins follow the zizmor the base image ships (#423).
# The image installs zizmor from images/base/tools/uv.lock; CI's `zizmor (workflow security)` job
# (.github/workflows/lint.yml) and the matching entry of gates.green (.ai/project.yml) each run a
# `ghcr.io/zizmorcore/zizmor:<version>@sha256:<digest>` container. Dependabot's uv updater moves
# only the lock, so without this check the pins lag and the container validates with a different
# zizmor than CI does.
#
#   check-zizmor-pin.sh [root]   root defaults to the current directory
#
# Exit 0: clean. 1: at least one finding (each printed to stderr, prefixed `check-zizmor-pin:`).
# 2: usage error (more than one argument).
#
# It fails when:
#   * images/base/tools/uv.lock under root is missing or has no zizmor entry;
#   * .github/workflows/lint.yml or .ai/project.yml under root is missing, or does not hold exactly
#     one `ghcr.io/zizmorcore/zizmor` reference;
#   * that reference is not `ghcr.io/zizmorcore/zizmor:<version>@sha256:<64 lowercase hex>`;
#   * its version differs from the uv.lock version;
#   * the two references are not identical (so the digests cannot drift apart either).
#
# It compares tags and references only, and makes no network call and runs no docker. Docker pulls
# by the digest and ignores the tag, so that the tag names the image the digest points to is not
# checked here: the registry read the PR records, and the owner's own read before merging, are
# what establish it (README.md "Toolchain versions must match CI").
set -euo pipefail
export LC_ALL=C

if [ "$#" -gt 1 ]; then
  echo "usage: check-zizmor-pin.sh [root]" >&2
  exit 2
fi
root="${1:-.}"

rc=0
finding() { echo "check-zizmor-pin: $*" >&2; rc=1; }

lock="images/base/tools/uv.lock"
lint=".github/workflows/lint.yml"
proj=".ai/project.yml"

# The version uv.lock resolved for zizmor: the `version = "..."` line directly after the
# `name = "zizmor"` line, the rule build-and-test.sh's lockver uses.
lockver=""
if [ ! -f "$root/$lock" ] || [ ! -r "$root/$lock" ]; then
  finding "$lock is missing: cannot read the zizmor version the image ships"
else
  lockver="$(sed -n '/^name = "zizmor"$/{n;s/^version = "\(.*\)"$/\1/p;q;}' "$root/$lock")"
  [ -n "$lockver" ] || finding "$lock has no zizmor entry: cannot read the zizmor version the image ships"
fi

refs=() # the reference found in each of the two files ("" when none usable)
for f in "$lint" "$proj"; do
  ref=""
  if [ ! -f "$root/$f" ] || [ ! -r "$root/$f" ]; then
    finding "$f is missing: it must pin the zizmor container"
  else
    found="$(grep -o 'ghcr\.io/zizmorcore/zizmor[^[:space:]"]*' "$root/$f" || true)"
    n=0
    [ -z "$found" ] || n="$(printf '%s\n' "$found" | wc -l)"
    if [ "$n" -eq 0 ]; then
      finding "$f has no ghcr.io/zizmorcore/zizmor reference: pin the zizmor container as ghcr.io/zizmorcore/zizmor:<version>@sha256:<digest>"
    elif [ "$n" -gt 1 ]; then
      finding "$f has $n ghcr.io/zizmorcore/zizmor references: it must hold exactly one"
    elif [[ "$found" =~ ^ghcr\.io/zizmorcore/zizmor:([0-9]+(\.[0-9]+)*)@sha256:[0-9a-f]{64}$ ]]; then
      ref="$found"
      if [ -n "$lockver" ] && [ "${BASH_REMATCH[1]}" != "$lockver" ]; then
        finding "$f pins zizmor ${BASH_REMATCH[1]} but $lock has $lockver: move both container pins (this file and the other of $lint and $proj) to $lockver by digest, in the same PR as the lock"
      fi
    else
      finding "$f has a zizmor reference that is not ghcr.io/zizmorcore/zizmor:<version>@sha256:<64 lowercase hex>: $found"
    fi
  fi
  refs+=("$ref")
done

if [ -n "${refs[0]}" ] && [ -n "${refs[1]}" ] && [ "${refs[0]}" != "${refs[1]}" ]; then
  finding "the zizmor references in $lint and $proj differ: they must be identical, tag and digest"
fi

exit "$rc"
