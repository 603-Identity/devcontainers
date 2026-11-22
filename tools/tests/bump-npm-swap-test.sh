#!/usr/bin/env bash
# Tests the node image's bundled-package swap note in bump-binaries.sh (#518). The npm path reads the
# `swap <name> ...` call lines of images/node/Dockerfile before it cuts a branch: with none, the PR
# body is today's; with some, a fixed paragraph names the packages and the removal a human pushes if
# the build fails; a call line whose name fails ^[a-z0-9][a-z0-9._-]*$ stops the script before any
# git switch, push or commit and before `gh pr create`. Nothing downloads or reads the npm tarball.
# Each case runs in a scratch root holding a copy of the script and a node Dockerfile: the fixture
# (fixtures/node-swap/Dockerfile, the real block as it stood before #510), the fixture plus a second
# call line, a bad-name copy, or a no-swap one (the fixture with its call line removed). The "not npm"
# case runs the `gh` tool with a base Dockerfile and the fixture as the node Dockerfile. Fake `gh`,
# `git` and `curl` stand in for the network and log every call; the fake gh writes the `pr create`
# body to a file, and a fake `node` (exit 0) stands in for the engines.node `satisfies` check.
# Offline; needs bash, awk and jq.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT_DIR/.github/scripts/bump-binaries.sh"
# shellcheck disable=SC2153 # FIXTURES comes from lib.sh
FIXTURE="$FIXTURES/node-swap/Dockerfile"
suite "bump-binaries (npm swap note)"

INTEGRITY="sha512-$(printf 'A%.0s' $(seq 1 86))=="
GH_SHA=$(printf 'a%.0s' $(seq 1 64))
GH_OLD=$(printf 'b%.0s' $(seq 1 64))
NOTE_TEXT="bundled-package swap block"
LAST_PROSE="run on this PR like any other."
# shellcheck disable=SC2016,SC1003 # a literal Dockerfile line: no expansion, trailing backslash wanted
CALL='    swap undici "${UNDICI_VERSION}" "${UNDICI_INTEGRITY}"; \'

# setup <tool> <node Dockerfile source>: a scratch root with a copy of the script, the node
# Dockerfile, and (for gh) a base Dockerfile. The registry packument offers npm 99.0.0, far above
# every pin here; the fake gh answers cli/cli with v2.103.0, whose checksums file carries the
# linux amd64 tarball's line.
setup() {
  TOOL="$1"
  SCRATCH="$(mktemp -d)"
  R="$SCRATCH/root"
  mkdir -p "$R/.github/scripts" "$R/images/base" "$R/images/node" "$SCRATCH/bin"
  cp "$SCRIPT" "$R/.github/scripts/"
  cp "$2" "$R/images/node/Dockerfile"
  printf 'ARG GH_VERSION=2.102.0\nARG GH_SHA256=%s\n' "$GH_OLD" > "$R/images/base/Dockerfile"
  cp "$R/images/node/Dockerfile" "$SCRATCH/node.orig"
  : > "$SCRATCH/calls.log"
  export FAKE_LOG="$SCRATCH/calls.log" FAKE_BODY="$SCRATCH/body.txt" FAKE_INTEGRITY="$INTEGRITY" FAKE_GH_SHA="$GH_SHA"
  cat > "$SCRATCH/bin/gh" <<'G'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
case "$1 $2" in
  "api repos/cli/cli/releases/latest") printf 'v2.103.0\thttps://example.test/gh\n' ;;
  "pr list") echo 0 ;;
  "pr create")
    while [ $# -gt 0 ]; do [ "$1" = --body ] && printf '%s' "$2" > "$FAKE_BODY"; shift; done ;;
  *) ;;
esac
G
  cat > "$SCRATCH/bin/git" <<'G'
#!/usr/bin/env bash
echo "git $*" >> "$FAKE_LOG"
exit 0
G
  cat > "$SCRATCH/bin/node" <<'N'
#!/usr/bin/env bash
exit 0
N
  cat > "$SCRATCH/bin/curl" <<'C'
#!/usr/bin/env bash
url=""
while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) url="$1"; shift ;; esac; done
echo "curl $url" >> "$FAKE_LOG"
case "$url" in
  https://registry.npmjs.org/npm)
    printf '{"versions":{"99.0.0":{"engines":{"node":">=20.0.0"},"dist":{"integrity":"%s"}}}}\n' "$FAKE_INTEGRITY" ;;
  */gh_2.103.0_checksums.txt) printf '%s  gh_2.103.0_linux_amd64.tar.gz\n' "$FAKE_GH_SHA" ;;
  *) exit 22 ;;
esac
C
  chmod +x "$SCRATCH/bin/"*
}

run() {
  RC=0
  OUT="$(env PATH="$SCRATCH/bin:/usr/bin:/bin" REPO=o/r APP_SLUG=app BOT_USER_ID=1 GH_TOKEN=t \
    bash "$R/.github/scripts/bump-binaries.sh" "$TOOL" 2>&1)" || RC=$?
}
body() { cat "$FAKE_BODY" 2> /dev/null || true; }
body_has() { case "$(body)" in *"$1"*) pass ;; *) fail "$2" "body lacks '$1': $(body)" ;; esac; }
body_lacks() { case "$(body)" in *"$1"*) fail "$2" "body has '$1': $(body)" ;; *) pass ;; esac; }
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
no_tgz() { # no download of any .tgz
  if grep -E '^curl .*\.tgz' "$FAKE_LOG" > /dev/null; then fail "no .tgz request ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
}
opened() { # the PR was opened: a branch cut, pushed, committed and a PR created
  local verb
  for verb in switch commit push; do
    if grep -qE "^git .*(^| )$verb( |$)" "$FAKE_LOG"; then pass; else fail "git $verb ran ($1)" "$(cat "$FAKE_LOG")"; fi
  done
  if log_has "gh pr create"; then pass; else fail "the PR is created ($1)" "$(cat "$FAKE_LOG")"; fi
}
assert_untouched() { # nothing was switched, committed, pushed or opened, and the Dockerfile is as it was
  local verb
  for verb in switch push commit; do
    if grep -qE "^git .*(^| )$verb( |$)" "$FAKE_LOG"; then fail "no git $verb ($1)" "$(cat "$FAKE_LOG")"; else pass; fi
  done
  if log_has "gh pr create"; then fail "no PR is created ($1)"; else pass; fi
  if cmp -s "$SCRATCH/node.orig" "$R/images/node/Dockerfile"; then pass; else fail "the node Dockerfile is untouched ($1)"; fi
}
done_case() { rm -rf "$SCRATCH"; }

# variant files, built from the fixture
VAR="$(mktemp -d)"
trap 'rm -rf "$VAR"' EXIT
grep -vxF -- "$CALL" "$FIXTURE" > "$VAR/noswap"
awk -v c="$CALL" '{ print } $0 == c { sub(/undici/, "semver", c); print c }' "$FIXTURE" > "$VAR/two"
for n in '../x' 'Undici' '@scope/x'; do
  awk -v c="$CALL" -v n="$n" '$0 == c { sub(/undici/, n); } { print }' "$FIXTURE" > "$VAR/bad-$(printf '%s' "$n" | tr -c 'A-Za-z0-9' '_')"
done
awk -v c="$CALL" '$0 == c { print "    swap"; next } { print }' "$FIXTURE" > "$VAR/bad-empty"

# the variants differ from the fixture exactly as intended
if grep -qxF -- "$CALL" "$FIXTURE"; then pass; else fail "the fixture holds the undici call line"; fi
assert_eq "the no-swap copy has no swap call line" "0" "$(grep -cE '^[[:space:]]*swap([[:space:]]|$)' "$VAR/noswap" || true)"
assert_eq "the no-swap copy still has the swap() definition" "1" "$(grep -c 'swap() {' "$VAR/noswap" || true)"
assert_eq "the two-call copy has two call lines" "2" "$(grep -cE '^[[:space:]]*swap[[:space:]]' "$VAR/two" || true)"

# --- no swap call: no note, the body is today's ---------------------------------------------
setup npm "$VAR/noswap"
run
assert_rc "npm bump with no swap call" 0 "$RC"
opened "no swap call"
body_lacks "$NOTE_TEXT" "no note without a swap call"
last="$(body | awk 'NF { l = $0 } END { print l }')"
assert_eq "the body's last non-empty line is the existing last prose line" "architect-review because \`images/\` is a code_path) $LAST_PROSE" "$last"
no_tgz "no swap call"
done_case

# --- the fixture: the note names undici and the removal -------------------------------------
setup npm "$FIXTURE"
run
assert_rc "npm bump with the fixture" 0 "$RC"
opened "fixture"
body_has "$NOTE_TEXT (swapped: undici)." "the note names undici"
body_has "remove that package's \`swap\` line and both its ARGs from \`images/node/Dockerfile\`" "the note names the removal"
body_has "inputs table" "the note names the threat-model row"
body_has "$LAST_PROSE" "the existing prose is still in the body"
no_tgz "fixture"
done_case

# --- two swap calls: both names, in file order ----------------------------------------------
setup npm "$VAR/two"
run
assert_rc "npm bump with two swap calls" 0 "$RC"
opened "two calls"
body_has "$NOTE_TEXT (swapped: undici, semver)." "the note names both packages in file order"
no_tgz "two calls"
done_case

# --- not npm: the fixture as the node Dockerfile changes nothing for a gh bump ---------------
setup gh "$FIXTURE"
run
assert_rc "gh bump with the fixture as the node Dockerfile" 0 "$RC"
opened "gh"
body_lacks "$NOTE_TEXT" "no note on a gh bump"
body_has "$LAST_PROSE" "the gh body is the usual one"
no_tgz "gh"
done_case

# --- a bad package name: refused before any branch is cut -----------------------------------
for c in 'bad-___x:../x' 'bad-Undici:Undici' 'bad-_scope_x:@scope/x' 'bad-empty:'; do
  file="${c%%:*}"; name="${c#*:}"
  setup npm "$VAR/$file"
  run
  assert_rc "a swap call named '${name:-<empty>}' is refused" 1 "$RC"
  case "$OUT" in *"::error::npm: a swap call in images/node/Dockerfile has no valid package name"*) pass ;; *) fail "the fixed error line for '${name:-<empty>}'" "$OUT" ;; esac
  if [ -n "$name" ]; then
    case "$OUT" in *"$name"*) fail "the rejected name '$name' is not echoed" "$OUT" ;; *) pass ;; esac
  fi
  assert_untouched "'${name:-<empty>}'"
  no_tgz "'${name:-<empty>}'"
  done_case
done

summary
