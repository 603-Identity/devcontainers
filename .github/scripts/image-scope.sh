#!/usr/bin/env bash
# Decides whether a change touches anything that affects an image or the template, and
# writes build=1 or build=0 to $GITHUB_OUTPUT. Two callers in build.yml: the PR test job
# (skip the slow build for a docs-only PR) and the publish gate (do not publish a new tag
# set, and so a Dependabot bump PR in every consumer, for a docs-only push to main).
#
# Env: EVENT_NAME (github.event_name), BASE_SHA (the commit to diff HEAD against: the PR
# base, or the push's `before`), RUNNER_TEMP, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.
# Run from a checkout of the commit under test, with `origin` pointing at the repo.
#
# The weekly schedule and manual dispatch always give build=1: they exist to rebuild
# unchanged sources (apt packages float, see images/base/Dockerfile). An event this
# script does not know also gives build=1, so a new trigger fails toward publishing.
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
# diff fails the job, and an empty list fails it too, so neither ever reads as "nothing
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
# A push that creates the branch has an all-zero `before`: there is no base to diff.
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
