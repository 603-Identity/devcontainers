#!/usr/bin/env bash
# Tests for the grouped run of .github/scripts/bump-binaries.sh (#715): one branch bump/weekly-<date>,
# one commit per moved tool in a fixed order, one PR whose body records every moved, declined and failed
# tool, and the older open weekly PRs the App opened closed after it. The script runs in a scratch git
# repository (a real `git`, wrapped to log calls and to inject a failed commit, push or ls-remote) with a
# bare repository as `origin`; fake `gh`, `curl`, `cosign`, `node` and `date` stand in for the network and
# the clock. Offline; needs bash, awk, jq, yq and git.
# shellcheck disable=SC2016  # fixture text and workflow expressions hold literal $ and backtick characters
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/bump-binaries.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/bump-binaries.yml"
REAL_GIT="$(command -v git)"
suite "bump-binaries (grouped weekly run)"

DATE=20261125
WEEKLY="bump/weekly-$DATE"
SHA_OLD=$(printf 'b%.0s' $(seq 1 64))
SHA_NEW=$(printf 'a%.0s' $(seq 1 64))
INT_OLD="sha512-$(printf 'B%.0s' $(seq 1 86))=="
INT_NEW="sha512-$(printf 'A%.0s' $(seq 1 86))=="
COMMIT=0123456789abcdef0123456789abcdef01234567
ORDER=(gh yq uv tofu tflint node npm betterleaks python)

# setup: a repository holding the script and the three Dockerfiles at their old pins, pushed to a bare
# origin as `main`, and the fakes. Every upstream has a newer version; each case overrides what it needs.
setup() {
  SCRATCH="$(mktemp -d)"
  R="$SCRATCH/root"
  O="$SCRATCH/origin.git"
  mkdir -p "$R/.github/scripts" "$R/images/base" "$R/images/tofu" "$R/images/node" "$SCRATCH/bin" "$SCRATCH/cosign-bin"
  cp "$SCRIPT" "$R/.github/scripts/"
  cat > "$R/images/base/Dockerfile" <<EOF
ARG GH_VERSION=1.0.0
ARG GH_SHA256=$SHA_OLD
ARG YQ_VERSION=4.0.0
ARG YQ_SHA256=$SHA_OLD
ARG UV_VERSION=0.1.0
ARG UV_SHA256=$SHA_OLD
ARG BETTERLEAKS_VERSION=1.0.0
ARG BETTERLEAKS_SHA256=$SHA_OLD
ARG PYTHON_VERSION=3.15.2
ARG PYTHON_BUILD=20261110
ARG PYTHON_SHA256=$SHA_OLD
EOF
  cat > "$R/images/tofu/Dockerfile" <<EOF
ARG TOFU_VERSION=1.0.0
ARG TOFU_SHA256=$SHA_OLD
ARG TFLINT_VERSION=0.1.0
ARG TFLINT_SHA256=$SHA_OLD
EOF
  cat > "$R/images/node/Dockerfile" <<EOF
ARG NODE_VERSION=20.0.0
ARG NODE_SHA256=$SHA_OLD
ARG NPM_VERSION=10.0.0
ARG NPM_INTEGRITY=$INT_OLD
EOF
  "$REAL_GIT" init -q -b main "$R"
  "$REAL_GIT" init -q --bare "$O"
  "$REAL_GIT" -C "$R" config user.name test
  "$REAL_GIT" -C "$R" config user.email test@example.test
  "$REAL_GIT" -C "$R" add -A
  "$REAL_GIT" -C "$R" commit -q -m init
  "$REAL_GIT" -C "$R" remote add origin "$O"
  "$REAL_GIT" -C "$R" push -q origin main
  : > "$SCRATCH/calls.log"
  : > "$SCRATCH/prlist.tsv"
  export FAKE_LOG="$SCRATCH/calls.log" FAKE_BODY="$SCRATCH/body.txt" FAKE_TITLE="$SCRATCH/title.txt" FAKE_PRLIST="$SCRATCH/prlist.tsv"
  export FAKE_REAL_GIT="$REAL_GIT" FAKE_DATE="$DATE" FAKE_COMMIT="$COMMIT"
  export FAKE_SHA_NEW="$SHA_NEW" FAKE_INT_NEW="$INT_NEW"
  unset FAKE_CURL_FAIL FAKE_GH_FAIL FAKE_COMMIT_RC FAKE_COMMIT_FAIL FAKE_PUSH_FAIL FAKE_LSREMOTE_FAIL FAKE_PRLIST_FAIL \
    FAKE_PRLIST_COUNT FAKE_CREATE_FAIL FAKE_CLOSE_FAIL FAKE_COSIGN_FAIL FAKE_TAG_GH FAKE_TAG_TOFU FAKE_COSIGN_OUTCOME \
    FAKE_COSIGN_BIN FAKE_SUMMARY FAKE_ALL_FAIL FAKE_CHECKSUM_GH FAKE_BAD_NODE_LATEST
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
[ -z "${FAKE_ALL_FAIL:-}" ] || [ "$1" != api ] || exit 1
case "$1 $2" in
  "api repos/cli/cli/releases/latest") printf '%s\thttps://example.test/gh\n' "${FAKE_TAG_GH:-v1.1.0}" ;;
  "api repos/mikefarah/yq/releases/latest") printf 'v4.1.0\thttps://example.test/yq\n' ;;
  "api repos/astral-sh/uv/releases/latest") printf '0.2.0\thttps://example.test/uv\n' ;;
  "api repos/opentofu/opentofu/releases/latest") printf '%s\thttps://example.test/tofu\n' "${FAKE_TAG_TOFU:-v1.1.0}" ;;
  "api repos/opentofu/opentofu/commits/"*) [ -z "${FAKE_COMMIT_RC:-}" ] || exit "$FAKE_COMMIT_RC"; printf '%s\n' "$FAKE_COMMIT" ;;
  "api repos/terraform-linters/tflint/releases/latest") printf 'v0.2.0\thttps://example.test/tflint\n' ;;
  "api repos/nodejs/node/releases/tags/"*) echo https://example.test/node ;;
  "api repos/betterleaks/betterleaks/releases") printf 'v1.1.0\thttps://example.test/betterleaks\n' ;;
  "api repos/astral-sh/python-build-standalone/releases?per_page=5") printf '20261117\thttps://example.test/python\n' ;;
  "auth setup-git") ;;
  "pr list")
    [ -z "${FAKE_PRLIST_FAIL:-}" ] || exit 1
    if [ -n "${FAKE_PRLIST_COUNT:-}" ]; then
      awk -v n="$FAKE_PRLIST_COUNT" 'BEGIN { for (i = 1; i <= n; i++) printf "%d\tfeature/x\tsomeone\tfalse\ttrue\n", i }'
    else cat "$FAKE_PRLIST"; fi ;;
  "pr create")
    [ -z "${FAKE_CREATE_FAIL:-}" ] || exit 1
    while [ $# -gt 0 ]; do
      case "$1" in --body) printf '%s' "$2" > "$FAKE_BODY" ;; --title) printf '%s' "$2" > "$FAKE_TITLE" ;; esac
      shift
    done
    echo https://github.com/o/r/pull/99 ;;
  "pr close") case " ${FAKE_CLOSE_FAIL:-} " in *" $3 "*) exit 1 ;; esac ;;
  *) echo "unexpected gh $*" >&2; exit 9 ;;
esac
G
  cat > "$SCRATCH/bin/git" <<'G'
#!/usr/bin/env bash
echo "git $*" >> "$FAKE_LOG"
case "$*" in
  *" commit "*) [ -z "${FAKE_COMMIT_FAIL:-}" ] || case "$*" in *"bump $FAKE_COMMIT_FAIL "*) exit 1 ;; esac ;;
  *" push "*) [ -z "${FAKE_PUSH_FAIL:-}" ] || exit 1 ;;
  *ls-remote*) [ -z "${FAKE_LSREMOTE_FAIL:-}" ] || case "$*" in *"$FAKE_LSREMOTE_FAIL"*) exit 128 ;; esac ;;
esac
exec "$FAKE_REAL_GIT" "$@"
G
  cat > "$SCRATCH/bin/curl" <<'C'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
echo "curl $url" >> "$FAKE_LOG"
[ -z "${FAKE_ALL_FAIL:-}" ] || exit 22
for f in ${FAKE_CURL_FAIL:-}; do case "$url" in *"$f"*) exit 22 ;; esac; done
emit() { if [ -n "$out" ]; then printf '%s' "$1" > "$out"; else printf '%s' "$1"; fi; }
case "$url" in
  *cli/cli*checksums.txt) v="${url##*/gh_}"; v="${v%_checksums.txt}"; emit "${FAKE_CHECKSUM_GH:-$FAKE_SHA_NEW}  gh_${v}_linux_amd64.tar.gz
" ;;
  *checksums_hashes_order) emit $'MD5\nSHA-1\nSHA-256\n' ;;
  */mikefarah/yq/*/checksums) emit "yq_linux_amd64 md5 sha1 $FAKE_SHA_NEW
" ;;
  *astral-sh/uv/*.sha256) emit "$FAKE_SHA_NEW  uv-x86_64-unknown-linux-gnu.tar.gz
" ;;
  *terraform-linters/tflint/*checksums.txt) emit "$FAKE_SHA_NEW  tflint_linux_amd64.zip
" ;;
  *opentofu/opentofu/*_SHA256SUMS) emit "$FAKE_SHA_NEW  tofu_1.1.0_linux_amd64.zip
" ;;
  *opentofu/opentofu/*_SHA256SUMS.sig) emit sig ;;
  *opentofu/opentofu/*_SHA256SUMS.pem) emit pem ;;
  *nodejs.org/dist/index.json) emit '[{"version":"v20.1.0","lts":"Fake"}]' ;;
  *nodejs.org/dist/*SHASUMS256.txt) emit "$FAKE_SHA_NEW  node-v20.1.0-linux-x64.tar.xz
" ;;
  *registry.npmjs.org/npm) emit "{\"versions\":{\"11.0.0\":{\"engines\":{\"node\":\">=20.1.0\"},\"dist\":{\"integrity\":\"$FAKE_INT_NEW\"}},\"10.9.0\":{\"engines\":{\"node\":\">=20.0.0\"},\"dist\":{\"integrity\":\"$FAKE_INT_NEW\"}}}}" ;;
  *betterleaks/*checksums.txt.sigstore.json) emit '{}' ;;
  *betterleaks/*checksums.txt) emit "$FAKE_SHA_NEW  betterleaks_1.1.0_linux_x64.tar.gz
" ;;
  *python-build-standalone/*SHA256SUMS) emit "$FAKE_SHA_NEW  cpython-3.15.3+20261117-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz
" ;;
  *) echo "unexpected curl $url" >&2; exit 9 ;;
esac
C
  # Both the pinned binary (COSIGN_BIN) and a decoy on PATH log their calls; the decoy must never run.
  cat > "$SCRATCH/cosign-bin/cosign" <<'S'
#!/usr/bin/env bash
echo "cosign $*" >> "$FAKE_LOG"
case "$*" in
  *--certificate\ *) [ "${FAKE_COSIGN_FAIL:-}" != tofu ] || exit 1 ;;
  *--bundle*) [ "${FAKE_COSIGN_FAIL:-}" != betterleaks ] || exit 1 ;;
esac
exit 0
S
  cat > "$SCRATCH/bin/cosign" <<'S'
#!/usr/bin/env bash
echo "cosign-on-path $*" >> "$FAKE_LOG"
exit 0
S
  # satisfies(): the fake answers `>=X` ranges, the only kind the fake registry serves.
  cat > "$SCRATCH/bin/node" <<'N'
#!/usr/bin/env bash
v="${*: -2:1}"; r="${*: -1}"; r="${r#>=}"
[ "$(printf '%s\n%s\n' "$r" "$v" | sort -V | head -n 1)" = "$r" ]
N
  cat > "$SCRATCH/bin/date" <<'D'
#!/usr/bin/env bash
echo "$FAKE_DATE"
D
  chmod +x "$SCRATCH/bin/"* "$SCRATCH/cosign-bin/cosign"
}

run() { # run [tool...] -> RC, OUT (stdout and stderr)
  RC=0
  OUT="$(env PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    COSIGN_OUTCOME="${FAKE_COSIGN_OUTCOME-success}" COSIGN_BIN="${FAKE_COSIGN_BIN:-$SCRATCH/cosign-bin/cosign}" \
    ${FAKE_SUMMARY:+GITHUB_STEP_SUMMARY="$FAKE_SUMMARY"} \
    bash "$R/.github/scripts/bump-binaries.sh" "$@" 2>&1)" || RC=$?
}
done_case() { rm -rf "$SCRATCH"; }

log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
count_log() { grep -cE -- "$1" "$FAKE_LOG" || true; }
out_has() { case "$OUT" in *"$1"*) pass ;; *) fail "$2" "output lacks '$1': $OUT" ;; esac; }
out_lacks() { case "$OUT" in *"$1"*) fail "$2" "output has '$1': $OUT" ;; *) pass ;; esac; }
body() { cat "$FAKE_BODY" 2> /dev/null || true; }
body_has() { case "$(body)" in *"$1"*) pass ;; *) fail "$2" "body lacks '$1': $(body)" ;; esac; }
body_lacks() { case "$(body)" in *"$1"*) fail "$2" "body has '$1': $(body)" ;; *) pass ;; esac; }
# section <tool>: the body's record of that tool (its `### ` heading to the next heading).
section() { body | awk -v h="### $1 " 'index($0, h) == 1 { p = 1; print; next } /^### / { p = 0 } p'; }
section_has() { case "$(section "$1")" in *"$2"*) pass ;; *) fail "$3" "section '$1' lacks '$2': $(section "$1")" ;; esac; }
section_lacks() { case "$(section "$1")" in *"$2"*) fail "$3" "section '$1' has '$2': $(section "$1")" ;; *) pass ;; esac; }
arg() { sed -n "s/^ARG $2=//p" "$R/images/$1/Dockerfile"; }
orig_file() { "$REAL_GIT" -C "$R" show "main:images/$1/Dockerfile"; }
# commits: the subjects of this run's commits, oldest first.
commits() { "$REAL_GIT" -C "$R" log --reverse --format=%s "main..HEAD" 2> /dev/null | sed -n 's/^build(images): bump \([a-z]*\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//'; }
no_git_write() { # no switch, commit or push, no PR listing or creation
  local verb
  for verb in switch commit push; do
    if grep -qE "^git .*(^| )$verb( |$)" "$FAKE_LOG"; then fail "no git $verb ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
  done
  if grep -qE '^gh pr (list|create|close)' "$FAKE_LOG"; then fail "no gh pr call ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
}
nothing_pushed() { # the weekly branch never reached origin and no PR was created or closed
  if "$REAL_GIT" -C "$O" rev-parse -q --verify "refs/heads/$WEEKLY" > /dev/null; then fail "the weekly branch is not on origin ($1)"; else pass; fi
  if grep -qE '^gh pr (create|close)' "$FAKE_LOG"; then fail "no PR is created or closed ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
}
unchanged() { # unchanged <dir> <case>: that Dockerfile is as the last commit had it, in the tree and the index
  if [ "$(cat "$R/images/$1/Dockerfile")" = "$(cd "$R" && "$REAL_GIT" show "HEAD:images/$1/Dockerfile")" ]; then pass; else fail "the $1 Dockerfile is as the last commit had it ($2)"; fi
  if [ -z "$("$REAL_GIT" -C "$R" diff --cached --name-only)" ]; then pass; else fail "the index is clean ($2)"; fi
}
decline_branch() { "$REAL_GIT" -C "$R" push -q origin "main:refs/heads/$1"; }

# --- the grouped run: every tool moved ------------------------------------------------------------------
setup
printf 'RUN swap() { :; }\nswap undici "${UNDICI_VERSION}" x\n' >> "$R/images/node/Dockerfile"
"$REAL_GIT" -C "$R" commit -q -am "swap fixture" && "$REAL_GIT" -C "$R" push -q origin main
run
assert_rc "every tool moved" 0 "$RC"
assert_eq "one commit per tool, in the fixed order" "${ORDER[*]}" "$(commits)"
assert_eq "one push" "1" "$(count_log '^git .* push ')"
assert_eq "one PR created" "1" "$(count_log '^gh pr create')"
if log_has "git -C $R push -u origin $WEEKLY"; then pass; else fail "the weekly branch is pushed" "$(cat "$FAKE_LOG")"; fi
assert_eq "the weekly branch is on origin" "$("$REAL_GIT" -C "$R" rev-parse HEAD)" "$("$REAL_GIT" -C "$O" rev-parse "refs/heads/$WEEKLY")"
assert_eq "the title" "build(images): bump pinned binaries (weekly $DATE)" "$(cat "$FAKE_TITLE")"
if log_has "gh pr create --repo o/r --head $WEEKLY --base main"; then pass; else fail "the PR is made from the weekly branch onto main"; fi
body_has 'Opened by `bump-binaries.yml` (#29)' "the body opens with the workflow line"
body_has "Each checksum below" "the checksum sentence is reworded for several tools"
for t in "${ORDER[@]}"; do
  section_has "$t" "Release notes: https://" "$t: a Release notes line"
  section_has "$t" "Checksum source: " "$t: a Checksum source line"
done
section_has gh "gh 1.0.0 -> 1.1.0" "gh's old and new label"
section_has python "python 3.15.2+20261110 -> 3.15.3+20261117" "python's label carries the build"
section_has python "PYTHON_VERSION=3.15.3 PYTHON_BUILD=20261117 PYTHON_SHA256=$SHA_NEW" "python's three ARG values"
section_has python "DEVC-D11" "python's consumer note"
section_has betterleaks "release.yml@refs/tags/v1.1.0" "betterleaks' signature line"
section_has tofu "release.yml@refs/heads/v1.1" "tofu's signature line"
section_has tofu "$COMMIT" "tofu's signature line names the commit"
for t in gh yq uv tflint node npm python; do section_lacks "$t" "signer identity" "$t's record carries no signature line"; done
section_lacks betterleaks "signer identity \`https://github.com/opentofu" "betterleaks' record carries no tofu line"
section_lacks tofu "betterleaks/betterleaks" "tofu's record carries no betterleaks line"
section_has npm "swapped: undici" "npm's swap note"
section_lacks node "swapped" "the swap note is npm's only"
assert_eq "node moved" "20.1.0" "$(arg node NODE_VERSION)"
assert_eq "npm resolved against node's new pin" "11.0.0" "$(arg node NPM_VERSION)"
for sha in $("$REAL_GIT" -C "$R" log --reverse --format=%H main..HEAD); do
  assert_eq "a commit touches one Dockerfile" "1" "$("$REAL_GIT" -C "$R" show --name-only --format= "$sha" | wc -l | tr -d ' ')"
done
body_lacks "Failed tools" "no failed section"
body_lacks "Declined versions" "no declined section"
done_case

# --- node before npm: when node did not move the pin, npm resolves against the unchanged one ---------
setup
FAKE_CURL_FAIL=SHASUMS256 run node npm
assert_rc "node's leg failed" 1 "$RC"
assert_eq "only npm moved" "npm" "$(commits)"
assert_eq "node's pin is unchanged" "20.0.0" "$(arg node NODE_VERSION)"
assert_eq "npm resolved against the old pin" "10.9.0" "$(arg node NPM_VERSION)"
body_has "- node: resolve" "the failed section names node and resolve"
done_case

# --- named tools run in the fixed order whatever order they are given in ---------------------------------
setup
run python uv gh
assert_rc "named tools" 0 "$RC"
assert_eq "named tools run in the fixed order" "gh uv python" "$(commits)"
assert_eq "tools that were not named are untouched" "4.0.0" "$(arg base YQ_VERSION)"
done_case

# --- partial failure: one resolver fails, another moves -------------------------------------------------
setup
FAKE_CURL_FAIL=tflint run gh tflint
assert_rc "a failed leg fails the run after the PR" 1 "$RC"
assert_eq "only the moved tool is committed" "gh" "$(commits)"
assert_eq "a PR is opened" "1" "$(count_log '^gh pr create')"
body_has "### Failed tools" "the body has a failed section"
body_has "- tflint: resolve" "the failed tool and its step"
section_lacks tflint "Release notes" "a failed tool has no record"
assert_eq "the failed tool's Dockerfile is unchanged" "$(orig_file tofu)" "$(cat "$R/images/tofu/Dockerfile")"
done_case

# --- nothing moved: no branch, no listing, no PR, exit 0 -- also with today's weekly ref on origin ---------
setup
sed -i 's/^ARG GH_VERSION=.*/ARG GH_VERSION=1.1.0/' "$R/images/base/Dockerfile"
"$REAL_GIT" -C "$R" commit -q -am "gh current" && "$REAL_GIT" -C "$R" push -q origin main
decline_branch "$WEEKLY"
FAKE_TAG_GH=v1.1.0 run gh
assert_rc "nothing moved" 0 "$RC"
out_has "gh: up to date at 1.1.0" "says up to date"
no_git_write "nothing moved"
if grep -qE "ls-remote.*weekly" "$FAKE_LOG"; then fail "origin is never asked about the weekly ref" "$(cat "$FAKE_LOG")"; else pass; fi
done_case

# --- every tool failed: no PR, exit 1 --------------------------------------------------------------------------
setup
FAKE_ALL_FAIL=1 run
assert_rc "every tool failed" 1 "$RC"
no_git_write "all failed"
out_has "failed: gh yq uv tofu tflint node npm betterleaks python" "the run names every failed tool"
done_case

# --- one grouped case per step word not covered below ----------------------------------------------------
step_case() { # step_case <word> <checks via the caller>: gh fails with that word, yq moves
  assert_rc "gh fails at $1 and the run ends red" 1 "$RC"
  assert_eq "yq's leg still opens the PR ($1)" "yq" "$(commits)"
  assert_eq "a PR is opened ($1)" "1" "$(count_log '^gh pr create')"
  body_has "- gh: $1" "the failed section names gh and the step ($1)"
  section_lacks gh "Release notes" "gh has no record ($1)"
  assert_eq "gh's pins are unchanged ($1)" "1.0.0 $SHA_OLD" "$(arg base GH_VERSION) $(arg base GH_SHA256)"
}
setup
FAKE_TAG_GH='v1.1.0x' run gh yq
step_case "version shape"
done_case
setup
sed -i '/^ARG GH_VERSION=/d' "$R/images/base/Dockerfile"
"$REAL_GIT" -C "$R" commit -q -am "no gh pin" && "$REAL_GIT" -C "$R" push -q origin main
run gh yq
assert_rc "gh fails at pin read and the run ends red" 1 "$RC"
assert_eq "yq's leg still opens the PR (pin read)" "yq" "$(commits)"
body_has "- gh: pin read" "the failed section names gh and the step (pin read)"
done_case
setup
FAKE_CHECKSUM_GH=NOTHEX run gh yq
step_case "checksum shape"
done_case
setup
FAKE_TAG_GH=v0.9.0 run gh yq
step_case "downgrade"
done_case
setup
mkdir "$R/images/base/Dockerfile.new"
# yq's leg writes the same Dockerfile.new, so run only the legs on the other Dockerfiles for the other tool.
run gh tflint
assert_rc "gh fails at rewrite and the run ends red" 1 "$RC"
assert_eq "tflint's leg still opens the PR (rewrite)" "tflint" "$(commits)"
body_has "- gh: rewrite" "the failed section names gh and the step (rewrite)"
assert_eq "gh's pins are unchanged (rewrite)" "1.0.0 $SHA_OLD" "$(arg base GH_VERSION) $(arg base GH_SHA256)"
done_case

# --- a failed git commit in one leg, then a leg on the same Dockerfile --------------------------------------
setup
FAKE_COMMIT_FAIL=yq run gh yq uv
assert_rc "a failed commit fails the run after the PR" 1 "$RC"
assert_eq "yq is not committed, uv is" "gh uv" "$(commits)"
body_has "- yq: commit" "the failed section names yq and the commit step"
section_lacks yq "Release notes" "yq has no record in the body"
assert_eq "yq's pins are restored" "4.0.0 $SHA_OLD" "$(arg base YQ_VERSION) $(arg base YQ_SHA256)"
assert_eq "uv's leg changed its own ARGs" "0.2.0 $SHA_NEW" "$(arg base UV_VERSION) $(arg base UV_SHA256)"
unchanged base "failed commit"
uv_commit="$("$REAL_GIT" -C "$R" show HEAD:images/base/Dockerfile)"
case "$uv_commit" in *"ARG YQ_VERSION=4.0.0"*) pass ;; *) fail "uv's commit carries no yq change" "$uv_commit" ;; esac
done_case

# --- #378: a failed order-file download is a download failure, not a missing SHA-256 line -----------------------
setup
FAKE_CURL_FAIL=checksums_hashes_order run yq gh
assert_rc "a failed order-file download fails the yq leg" 1 "$RC"
out_lacks "SHA-256 not found" "the failure is not reported as a missing SHA-256 line"
body_has "- yq: resolve" "the failed section names the step"
assert_eq "gh still moved" "gh" "$(commits)"
done_case

# --- declines -----------------------------------------------------------------------------------------------------
setup
decline_branch bump/gh-1.1.0
FAKE_SUMMARY="$SCRATCH/summary.md" run gh yq
assert_rc "a decline is not a failure" 0 "$RC"
out_has "::warning::gh: bump/gh-1.1.0 already exists on origin" "a warning annotation names the branch"
assert_eq "the other tool moved" "yq" "$(commits)"
body_has "### Declined versions" "the body has a declined section"
body_has "- gh: \`bump/gh-1.1.0\`" "the body names the declined tool and branch"
if grep -qF 'bump/gh-1.1.0' "$SCRATCH/summary.md" 2> /dev/null; then pass; else fail "the job summary names the declined branch"; fi
assert_eq "gh's pins are unchanged" "1.0.0 $SHA_OLD" "$(arg base GH_VERSION) $(arg base GH_SHA256)"
done_case
setup
decline_branch bump/gh-1.1.0
decline_branch bump/python-3.15.3-20261117
FAKE_SUMMARY="$SCRATCH/summary.md" run gh python
assert_rc "only declines exit 0" 0 "$RC"
no_git_write "only declines"
if grep -qF 'bump/python-3.15.3-20261117' "$SCRATCH/summary.md" 2> /dev/null && grep -qF 'bump/gh-1.1.0' "$SCRATCH/summary.md"; then pass; else fail "the job summary names every decline" "$(cat "$SCRATCH/summary.md" 2> /dev/null)"; fi
done_case
setup
FAKE_LSREMOTE_FAIL=bump/gh- run gh yq
assert_rc "an ls-remote failure on a decline check fails that leg" 1 "$RC"
body_has "- gh: decline check" "the failed section names the decline check"
assert_eq "yq still moved" "yq" "$(commits)"
done_case

# --- the exit-code outcomes ----------------------------------------------------------------------------------------
setup
run gh bogus
assert_rc "an unknown tool name" 1 "$RC"
assert_eq "no network or git call for an unknown tool" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"
done_case
setup
FAKE_DATE=2026-11-25 run gh
assert_rc "a date that is not eight digits" 1 "$RC"
assert_eq "no network or git call for a bad date" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"
done_case
setup
FAKE_PRLIST_FAIL=1 run gh
assert_rc "a failed gh pr list" 1 "$RC"
nothing_pushed "failed listing"
if grep -qE '^git .* push ' "$FAKE_LOG"; then fail "no push after a failed listing"; else pass; fi
done_case
setup
FAKE_PRLIST_COUNT=500 run gh
assert_rc "a 500-record listing" 1 "$RC"
out_has "may be truncated" "the truncation error"
nothing_pushed "truncated listing"
done_case
setup
FAKE_LSREMOTE_FAIL=bump/weekly run gh
assert_rc "an ls-remote failure on the weekly check" 1 "$RC"
nothing_pushed "weekly ls-remote failure"
if grep -qE '^git .* push ' "$FAKE_LOG"; then fail "no push after the weekly ls-remote failure"; else pass; fi
done_case
setup
decline_branch "$WEEKLY"
run gh
assert_rc "today's weekly branch exists and a tool moved" 1 "$RC"
out_has "::error::$WEEKLY already exists on origin" "the error annotation"
assert_eq "the existing weekly ref is untouched" "$("$REAL_GIT" -C "$R" rev-parse main)" "$("$REAL_GIT" -C "$O" rev-parse "refs/heads/$WEEKLY")"
assert_eq "no PR is created or closed (weekly branch exists)" "0" "$(count_log '^gh pr (create|close)')"
if grep -qE '^git .* push ' "$FAKE_LOG"; then fail "no push when the weekly branch exists"; else pass; fi
done_case
for head in "bump/weekly-$DATE" "bump/weekly-20261201"; do
  setup
  printf '41\t%s\tapp/app\ttrue\tfalse\n' "$head" > "$FAKE_PRLIST"
  run gh
  assert_rc "an open weekly PR not older ($head)" 1 "$RC"
  out_has "#41" "the error names the PR ($head)"
  nothing_pushed "not-older PR ($head)"
  if grep -qE '^git .* push ' "$FAKE_LOG"; then fail "no push with a not-older PR ($head)"; else pass; fi
  done_case
done
setup
FAKE_PUSH_FAIL=1 run gh
assert_rc "a failed push" 1 "$RC"
assert_eq "no PR after a failed push" "0" "$(count_log '^gh pr create')"
done_case
setup
printf '41\tbump/weekly-20261118\tapp/app\ttrue\tfalse\n' > "$FAKE_PRLIST"
FAKE_CREATE_FAIL=1 run gh
assert_rc "a failed gh pr create" 1 "$RC"
assert_eq "nothing is closed after a failed create" "0" "$(count_log '^gh pr close')"
done_case
setup
printf '41\tbump/weekly-20261118\tapp/app\ttrue\tfalse\n42\tbump/weekly-20261111\tapp/app\ttrue\tfalse\n43\tbump/weekly-20261104\tapp/app\ttrue\tfalse\n' > "$FAKE_PRLIST"
FAKE_CLOSE_FAIL=41 run gh
assert_rc "a failed close" 1 "$RC"
assert_eq "every close is attempted" "3" "$(count_log '^gh pr close ')"
out_has "could not close superseded PR #41" "the error names the failed number"
out_lacks "superseded PR #42" "the other closes are not reported as failed"
done_case

# --- the supersede filters, and the body naming the PRs to close ------------------------------------------------------
setup
{
  printf '41\tbump/weekly-20261118\tapp/app\ttrue\tfalse\n'
  printf '42\tbump/weekly-20261111\tapp/app\ttrue\tfalse\n'
  printf '61\tbump/weekly-20261118\tapp\ttrue\tfalse\n'
  printf '62\tbump/weekly-20261118\tother/app\ttrue\tfalse\n'
  printf '63\tbump/weekly-20261118\tapp/app\tfalse\tfalse\n'
  printf '64\tbump/weekly-20261118\tapp/app\ttrue\ttrue\n'
  printf '65\tbump/weekly-2026111\tapp/app\ttrue\tfalse\n'
  printf '66\tbump/weekly-20261118x\tapp/app\ttrue\tfalse\n'
  printf '67\txbump/weekly-20261118\tapp/app\ttrue\tfalse\n'
  printf '68\tbump/gh-1.1.0\tapp/app\ttrue\tfalse\n'
  printf '0\tbump/weekly-20261118\tapp/app\ttrue\tfalse\n'
  printf '07\tbump/weekly-20261118\tapp/app\ttrue\tfalse\n'
  printf 'x\tbump/weekly-20261118\tapp/app\ttrue\tfalse\n'
} > "$FAKE_PRLIST"
run gh
assert_rc "older weekly PRs are superseded" 0 "$RC"
assert_eq "exactly the two real older PRs are closed" "2" "$(count_log '^gh pr close ')"
if log_has "gh pr close 41 --repo o/r --comment Superseded by https://github.com/o/r/pull/99." && log_has "gh pr close 42 --repo o/r"; then pass; else fail "each is closed with a comment naming the new PR" "$(cat "$FAKE_LOG")"; fi
create_line="$(grep -n '^gh pr create' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
close_line="$(grep -n '^gh pr close' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
if [ -n "$create_line" ] && [ -n "$close_line" ] && [ "$create_line" -lt "$close_line" ]; then pass; else fail "the create call comes before the closes"; fi
body_has "### Older weekly PRs closed by this one" "the body names the PRs to close"
body_has "- #41 (\`bump/weekly-20261118\`)" "the body names PR 41"
body_has "- #42" "the body names PR 42"
for n in 61 62 63 64 65 66 67 68 07; do body_lacks "#$n" "PR $n is not in the body"; out_lacks "#$n" "PR $n is not in the output"; done
if grep -qE 'gh pr close (61|62|63|64|65|66|67|68|0|07|x) ' "$FAKE_LOG"; then fail "no filtered record is closed" "$(cat "$FAKE_LOG")"; else pass; fi
if grep -qE -- '--delete-branch|push .*--delete|push .* :|branch -[dD]' "$FAKE_LOG"; then fail "no branch is deleted"; else pass; fi
done_case

# --- a refused npm swap name fails only the npm leg of a grouped run ----------------------------------------------------
setup
printf 'RUN swap() { :; }\nswap ../x "${X}" y\n' >> "$R/images/node/Dockerfile"
"$REAL_GIT" -C "$R" commit -q -am "bad swap" && "$REAL_GIT" -C "$R" push -q origin main
run gh npm
assert_rc "a refused swap name ends the run red" 1 "$RC"
assert_eq "gh still moved" "gh" "$(commits)"
body_has "- npm: swap names" "the failed section names npm and the swap names step"
out_has "the npm leg changes nothing" "the refusal says the npm leg changes nothing"
unchanged node "swap names"
done_case

# --- tofu failing in a grouped run in which gh moves ---------------------------------------------------------------------
tofu_case() { # tofu_case <step word> <case name>
  assert_rc "tofu fails ($2)" 1 "$RC"
  body_has "- tofu: $1" "the failed section names tofu and $1 ($2)"
  assert_eq "tofu's Dockerfile is unchanged ($2)" "$(orig_file tofu)" "$(cat "$R/images/tofu/Dockerfile")"
  assert_eq "gh's leg still opens the PR ($2)" "gh" "$(commits)"
  assert_eq "a PR is opened ($2)" "1" "$(count_log '^gh pr create')"
}
setup
FAKE_COSIGN_FAIL=tofu run tofu gh
tofu_case cosign "verify-blob refusal"
out_has "did not verify" "says the signature did not verify"
done_case
setup
FAKE_COMMIT_RC=1 run tofu gh
tofu_case cosign "failed commit lookup"
assert_eq "no cosign call after a failed commit lookup" "0" "$(count_log '^cosign')"
done_case
for bad in "" "0123456789ABCDEF0123456789ABCDEF01234567" "0123456789abcdef"; do
  setup
  FAKE_COMMIT="$bad" run tofu gh
  tofu_case cosign "malformed commit '$bad'"
  assert_eq "no cosign call after a malformed commit" "0" "$(count_log '^cosign')"
  done_case
done
for bad in "v1.1.0-rc.1" "v1.1" "1.1.0" "v01.1.0x"; do
  setup
  FAKE_TAG_TOFU="$bad" run tofu gh
  tofu_case "version shape" "tag '$bad'"
  assert_eq "no cosign call after a tag refusal ($bad)" "0" "$(count_log '^cosign')"
  assert_eq "no commit lookup for a malformed tag ($bad)" "0" "$(count_log 'commits/')"
  done_case
done
for ext in _SHA256SUMS .sig .pem; do
  setup
  case "$ext" in .sig) k=SHA256SUMS.sig ;; .pem) k=SHA256SUMS.pem ;; *) k="_SHA256SUMS" ;; esac
  FAKE_CURL_FAIL="$k" run tofu gh
  tofu_case resolve "failed download of $ext"
  assert_eq "no tofu verify-blob call after a failed download of $ext" "0" "$(count_log '^cosign verify-blob')"
  done_case
done

# --- betterleaks' verification refusal, and the cosign install gate -----------------------------------------------------
setup
FAKE_COSIGN_FAIL=betterleaks run betterleaks gh
assert_rc "betterleaks fails" 1 "$RC"
body_has "- betterleaks: cosign" "the failed section names betterleaks and cosign"
assert_eq "gh's leg still opens the PR" "gh" "$(commits)"
assert_eq "betterleaks' pins are unchanged" "1.0.0 $SHA_OLD" "$(arg base BETTERLEAKS_VERSION) $(arg base BETTERLEAKS_SHA256)"
done_case
gate_case() { # gate_case <case name>: tofu and betterleaks fail at cosign, gh proceeds, nothing runs cosign
  assert_rc "tofu and betterleaks fail ($1)" 1 "$RC"
  body_has "- tofu: cosign" "tofu names cosign ($1)"
  body_has "- betterleaks: cosign" "betterleaks names cosign ($1)"
  assert_eq "gh's leg still opens the PR ($1)" "gh" "$(commits)"
  assert_eq "no cosign call at all ($1)" "0" "$(count_log '^cosign')"
}
for outcome in failure skipped cancelled ""; do
  setup
  FAKE_COSIGN_OUTCOME="$outcome" run tofu betterleaks gh
  gate_case "COSIGN_OUTCOME '$outcome'"
  done_case
done
setup
FAKE_COSIGN_BIN="$SCRATCH/cosign-bin/missing" run tofu betterleaks gh
gate_case "COSIGN_BIN is not a file"
done_case
setup
chmod 0644 "$SCRATCH/cosign-bin/cosign"
run tofu betterleaks gh
gate_case "COSIGN_BIN is not executable"
done_case
setup
FAKE_COSIGN_BIN=cosign-bin/cosign run tofu betterleaks gh
gate_case "COSIGN_BIN is relative"
done_case

# --- the workflow's shape --------------------------------------------------------------------------------------------------
assert_eq "no strategy" "null" "$(yq '.jobs.bump.strategy' "$WORKFLOW")"
assert_eq "no matrix anywhere" "0" "$(grep -c 'matrix' "$WORKFLOW" || true)"
assert_eq "the job is named bump" "bump" "$(yq '.jobs.bump.name' "$WORKFLOW")"
assert_eq "timeout is 30 minutes" "30" "$(yq '.jobs.bump."timeout-minutes"' "$WORKFLOW")"
assert_eq "the job keeps its if" "vars.BUMP_BINARIES_CLIENT_ID != ''" "$(yq '.jobs.bump.if' "$WORKFLOW")"
assert_eq "the job keeps its environment" "bump-binaries" "$(yq '.jobs.bump.environment' "$WORKFLOW")"
assert_eq "the cosign step has id cosign" "cosign" "$(yq '.jobs.bump.steps[] | select(.name == "Install cosign (pinned)") | .id' "$WORKFLOW")"
assert_eq "the cosign step has no if" "null" "$(yq '.jobs.bump.steps[] | select(.name == "Install cosign (pinned)") | .if' "$WORKFLOW")"
assert_eq "the cosign step continues on error" "true" "$(yq '.jobs.bump.steps[] | select(.name == "Install cosign (pinned)") | .["continue-on-error"]' "$WORKFLOW")"
last='.jobs.bump.steps[-1]'
assert_eq "the script runs with no argument" "bash .github/scripts/bump-binaries.sh" "$(yq "$last.run" "$WORKFLOW")"
assert_eq "COSIGN_OUTCOME is the cosign step's outcome" '${{ steps.cosign.outcome }}' "$(yq "$last.env.COSIGN_OUTCOME" "$WORKFLOW")"
assert_eq "COSIGN_BIN is under the runner's temp directory" '${{ runner.temp }}/cosign-bin/cosign' "$(yq "$last.env.COSIGN_BIN" "$WORKFLOW")"
assert_eq "no TOOL env" "null" "$(yq "$last.env.TOOL" "$WORKFLOW")"

summary
