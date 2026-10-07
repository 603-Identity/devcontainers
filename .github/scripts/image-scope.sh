#!/usr/bin/env bash
# Decides whether a change touches anything that affects an image or the template, and
# writes build=1 or build=0 to $GITHUB_OUTPUT. Two callers in build.yml: the PR test job
# (skip the slow build for a docs-only PR) and the publish gate (do not publish a new tag
# set, and so a Dependabot bump PR in every consumer, for a docs-only push to main).
#
# Env: EVENT_NAME (github.event_name), BASE_SHA (the commit to diff HEAD against: the PR
# base, or for a push the last successful publish, see last-publish-sha.sh), RUNNER_TEMP,
# GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.
# Run from a checkout of the commit under test, with `origin` pointing at the repo.
#
# The weekly schedule and manual dispatch always give build=1: they exist to rebuild
# unchanged sources (apt packages float, see images/base/Dockerfile). An event this
# script does not know also gives build=1 (it falls back to building, not skipping). Whether
# anything publishes is gated separately by build.yml's event allowlist, so a new trigger
# publishes nothing.
#
# Only what decides an image's or the template's behaviour counts: images/, template/,
# tests/, the build scripts, build.yml, and the two root files that shape images. A new
# path that shapes an image must be added to the `case` below (and to code_paths).
#
# The diff is base..HEAD, so a base that moved since a PR branch was cut only adds files
# (more runs, never fewer). `--no-renames` lists a renamed file's old path too, so moving
# a file out of scope cannot skip the build. `-z` makes the names NUL-delimited: without
# it git C-quotes a path with non-ASCII bytes, a control character such as a tab or
# newline, `"` or `\`, which then matches no pattern below. The list goes through a file
# because a shell variable cannot hold a NUL. `set -e` is load-bearing: a failed fetch or
# diff fails the job, and an empty list fails it too unless the base has HEAD's tree (then
# nothing changed since it, and the build is skipped), so a failure never reads as "nothing
# changed".
set -euo pipefail

emit() { echo "build=$1" >> "$GITHUB_OUTPUT"; }

case "${EVENT_NAME:?EVENT_NAME is required}" in
  pull_request|push) ;;
  *)
    emit 1
    echo "Event $EVENT_NAME always builds." >> "$GITHUB_STEP_SUMMARY"
    exit 0
    ;;
esac

: "${BASE_SHA:?BASE_SHA is required}"
# An all-zero base means there is none to diff: no last successful publish was found
# (last-publish-sha.sh gives it for every failure), or a push created the branch.
case "$BASE_SHA" in
  *[!0]*) ;;
  *)
    emit 1
    echo "No base commit to diff against: building." >> "$GITHUB_STEP_SUMMARY"
    exit 0
    ;;
esac

git fetch --no-tags --depth=1 origin "$BASE_SHA"
files="${RUNNER_TEMP:?RUNNER_TEMP is required}/changed-files.nul"
git diff -z --name-only --no-renames "$BASE_SHA" HEAD > "$files"
# The same tree as the base (a revert of everything since the last publish, or the base is HEAD)
# lists nothing legitimately, and nothing has changed since an image was published from it.
if [ ! -s "$files" ] && [ "$(git rev-parse "$BASE_SHA^{tree}")" = "$(git rev-parse 'HEAD^{tree}')" ]; then
  emit 0
  echo "HEAD has the same tree as the base: build skipped." >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
if [ ! -s "$files" ]; then
  echo "::error::git diff listed no changed files. Failing closed rather than skipping the build."
  exit 1
fi
build=0
while IFS= read -r -d '' f; do
  case "$f" in
    images/*|template/*|tests/*|.github/scripts/*|.github/workflows/build.yml) build=1 ;;
    .trivyignore.yaml|.gitattributes) build=1 ;;
  esac
done < "$files"
emit "$build"
if [ "$build" != 1 ]; then
  echo "No image, template, test or build file changed: build skipped." >> "$GITHUB_STEP_SUMMARY"
fi
