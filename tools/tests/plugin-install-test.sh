#!/usr/bin/env bash
# Proves images/devapp/files/plugin-install.sh (#503) against a stub `claude`. Offline. The script
# is copied to a scratch directory with `sed` rewriting exactly two lines (the claude path and
# TMPDIR) so no test hook ships in the real script; the rest runs as shipped, including its fixed
# PATH, so `jq` and GNU `timeout` must be real packages in /usr/local/bin or /usr/bin.
# Needs bash, jq, timeout, sha256sum.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/images/devapp/files/plugin-install.sh"
PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL [plugin-install] $1" >&2; [ -z "${2:-}" ] || echo "     $2" >&2; }
t() { # t <description> <command...>: passes when the command succeeds
  local d=$1; shift
  if "$@"; then pass; else fail "$d"; fi
}

echo "== plugin-install"
for tool in jq timeout; do
  if [ ! -x "/usr/local/bin/$tool" ] && [ ! -x "/usr/bin/$tool" ]; then
    echo "plugin-install-test: $tool is required in /usr/local/bin or /usr/bin (the script fixes its PATH; install the distro package)" >&2
    exit 1
  fi
done
command -v sha256sum >/dev/null || { echo "plugin-install-test: sha256sum is required" >&2; exit 1; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/tmp"

# The copy under test: exactly two lines change.
for pat in '^CLAUDE=/usr/local/bin/claude$' '^TMPDIR=/tmp; export TMPDIR$'; do
  [ "$(grep -c -- "$pat" "$SCRIPT")" -eq 1 ] || { echo "plugin-install-test: '$pat' does not match exactly once" >&2; exit 1; }
done
sed -e "s|^CLAUDE=/usr/local/bin/claude\$|CLAUDE=$W/bin/claude|" \
    -e "s|^TMPDIR=/tmp; export TMPDIR\$|TMPDIR=$W/tmp; export TMPDIR|" "$SCRIPT" > "$W/plugin-install.sh"
changed=$(diff "$SCRIPT" "$W/plugin-install.sh" | grep -c '^>')
[ "$changed" -eq 2 ] || { echo "plugin-install-test: the sed changed $changed lines, not 2" >&2; exit 1; }

cat > "$W/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "cwd=$(pwd) gcg=${GIT_CONFIG_GLOBAL-unset} cfg=${CLAUDE_CONFIG_DIR-unset} argv=$*" >> "$STUB_LOG"
for v in GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GIT_DIR GIT_WORK_TREE GIT_EXEC_PATH GIT_ASKPASS GIT_SSH_COMMAND LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT BASH_ENV ENV; do
  [ -z "${!v+x}" ] || echo "LEAK $v" >> "$STUB_LOG"
done
[ "${GIT_CEILING_DIRECTORIES-unset}" = "$(dirname "$(pwd)")" ] || echo "LEAK ceiling" >> "$STUB_LOG"
case "$*" in
  "plugin marketplace list"*) name=marketplace-list ;;
  "plugin list"*) name=plugin-list ;;
  "plugin marketplace add"*) name=add ;;
  "plugin marketplace remove"*) name=remove ;;
  "plugin install"*) name=install ;;
  "plugin update"*) name=update ;;
  *) exit 99 ;;
esac
f="$STUB_DIR/$name.json"
case "$name" in
  *-list)
    n=$(cat "$STUB_DIR/$name.count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/$name.count"
    [ "$n" -lt 2 ] || [ ! -f "$STUB_DIR/$name.2.json" ] || f="$STUB_DIR/$name.2.json" ;;
esac
if [ "$name" = install ] && [ -n "${STUB_REWRITE:-}" ]; then
  jq -S . "$STUB_WS/.claude/settings.json" > "$STUB_DIR/rewrite"
  cat "$STUB_DIR/rewrite" > "$STUB_WS/.claude/settings.json"
  printf '\n' >> "$STUB_WS/.claude/settings.json"
fi
[ ! -f "$f" ] || cat "$f"
rc=0
[ ! -f "$STUB_DIR/$name.rc" ] || rc=$(cat "$STUB_DIR/$name.rc")
exit "$rc"
STUB
chmod +x "$W/bin/claude"

PLUGIN=way-of-working@claude-workbench
REPO=glunk-works/claude-workbench
N=0
CW='' SD='' LOG='' OUT='' ERR='' RC=''

newcase() { # newcase <name>: a fresh workspace, stub dir and log
  N=$((N + 1))
  local d="$W/c$N-$1"
  CW="$d/ws"; SD="$d/stub"; LOG="$d/log"; OUT="$d/out"; ERR="$d/err"
  mkdir -p "$CW" "$SD"
}
settings() { # settings <repo> <ref>: the pinned plugin, in a fresh .claude/settings.json
  mkdir -p "$CW/.claude"
  jq -n --arg r "$1" --arg f "$2" --arg p "$PLUGIN" \
    '{extraKnownMarketplaces: {"claude-workbench": {source: {source: "github", repo: $r, ref: $f}}}, enabledPlugins: {($p): true}}' \
    > "$CW/.claude/settings.json"
}
mkt_json() { # mkt_json <ref>
  jq -n --arg r "$REPO" --arg f "$1" '[{name: "claude-workbench", source: "github", repo: $r, ref: $f, installLocation: "/x"}]'
}
plug_json() {
  jq -n --arg p "$PLUGIN" '[{id: $p, version: "0.30.0", scope: "user", enabled: true, projectEnabled: false}]'
}
ok_json() { echo '{"command":"x","outcome":"ok","message":"fine"}' > "$SD/$1.json"; }
fresh_install() { # empty lists, then the post-install lists
  echo '[]' > "$SD/marketplace-list.json"; echo '[]' > "$SD/plugin-list.json"
  mkt_json v0.30.0 > "$SD/marketplace-list.2.json"; plug_json > "$SD/plugin-list.2.json"
  ok_json add; ok_json install
}
run() { # run [VAR=val ...]: the script in $CW; sets RC, writes $OUT/$ERR
  ( cd "$CW" && env STUB_LOG="$LOG" STUB_DIR="$SD" STUB_WS="$CW" "$@" sh "$W/plugin-install.sh" > "$OUT" 2> "$ERR" )
  RC=$?
}
run_args() { ( cd "$CW" && env STUB_LOG="$LOG" STUB_DIR="$SD" STUB_WS="$CW" sh "$W/plugin-install.sh" "$@" > "$OUT" 2> "$ERR" ); RC=$?; }
argv() { sed 's/.*argv=//' "$LOG" 2>/dev/null; }
nocalls() { [ ! -s "$LOG" ]; }
snapshots() { find "$W/tmp" -mindepth 1 | wc -l; }

# 1. no settings file
newcase nofile; run
t "1: no file: exit 0" [ "$RC" -eq 0 ]; t "1: no stub call" nocalls

# 2. no enabledPlugins
newcase noenabled; mkdir "$CW/.claude"; echo '{}' > "$CW/.claude/settings.json"; run
t "2: exit 0" [ "$RC" -eq 0 ]; t "2: no stub call" nocalls

# 3. fresh install
newcase fresh; settings "$REPO" v0.30.0; fresh_install
before=$(snapshots); run
want="plugin marketplace list --json
plugin list --json
plugin marketplace add --scope user --json -- $REPO#v0.30.0
plugin install --scope user --json -- $PLUGIN
plugin marketplace list --json
plugin list --json"
t "3: exit 0" [ "$RC" -eq 0 ]
t "3: the call sequence" [ "$(argv)" = "$want" ]
t "3: reports what it installed" grep -q "installed $PLUGIN at $REPO#v0.30.0" "$ERR"
t "15b: a successful run leaves nothing under TMPDIR" [ "$(snapshots)" -eq "$before" ]

# 4. fast path
newcase fast; settings "$REPO" v0.30.0
mkt_json v0.30.0 > "$SD/marketplace-list.json"; plug_json > "$SD/plugin-list.json"; run
t "4: exit 0" [ "$RC" -eq 0 ]
t "4: only the two list calls" [ "$(argv)" = "plugin marketplace list --json
plugin list --json" ]
t "4: silent" [ ! -s "$ERR" ]

# 5. ref bump: re-pointed, so it updates even with equal versions
newcase repoint; settings "$REPO" v0.30.0
mkt_json v0.29.0 > "$SD/marketplace-list.json"; plug_json > "$SD/plugin-list.json"
mkt_json v0.30.0 > "$SD/marketplace-list.2.json"; plug_json > "$SD/plugin-list.2.json"
ok_json remove; ok_json add
echo '{"command":"install","outcome":"ok","installedVersion":"0.29.0","availableVersion":"0.29.0"}' > "$SD/install.json"; run
want="plugin marketplace list --json
plugin list --json
plugin marketplace remove --scope user --json -- claude-workbench
plugin marketplace add --scope user --json -- $REPO#v0.30.0
plugin install --scope user --json -- $PLUGIN
plugin update --scope user -- $PLUGIN
plugin marketplace list --json
plugin list --json"
t "5: exit 0" [ "$RC" -eq 0 ]
t "5: remove, add, install, update, then verify" [ "$(argv)" = "$want" ]

# 6. add fails, with control characters in the message
newcase addfail; settings "$REPO" v0.30.0
echo '[]' > "$SD/marketplace-list.json"; echo '[]' > "$SD/plugin-list.json"
jq -nc '{command: "marketplace-add", outcome: "failed", message: "\u001b]0;x\u0007 boom"}' > "$SD/add.json"; echo 1 > "$SD/add.rc"
before=$(snapshots); run
t "6: exit 1" [ "$RC" -eq 1 ]
t "6: the banner names the plugin" grep -q "$PLUGIN" "$ERR"
t "6: no ESC in stderr" bash -c "! LC_ALL=C grep -q \$'\\033' '$ERR'"
t "6: no BEL in stderr" bash -c "! LC_ALL=C grep -q \$'\\007' '$ERR'"
t "6: the sanitised message is kept" grep -q 'boom' "$ERR"
t "6: no install call" bash -c "! grep -q 'plugin install' '$LOG'"
t "15b: a failed run leaves nothing under TMPDIR" [ "$(snapshots)" -eq "$before" ]

# 7. the CLI rewrites the tracked file: detect, do not restore
newcase rewrite; settings "$REPO" v0.30.0; fresh_install
cp "$CW/.claude/settings.json" "$W/orig7"; before=$(snapshots); run STUB_REWRITE=1
t "7: exit 1" [ "$RC" -eq 1 ]
t "7: the rewritten bytes stay (nothing restored)" bash -c "! cmp -s '$W/orig7' '$CW/.claude/settings.json'"
snap=$(grep -o "$W/tmp/plugin-install-settings\.[A-Za-z0-9]*" "$ERR" | head -n 1)
t "7: the banner names a snapshot" [ -n "$snap" ]
t "7: the snapshot is the original bytes" cmp -s "$W/orig7" "$snap"
t "7: no new file under .claude" [ "$(find "$CW/.claude" -type f | wc -l)" -eq 1 ]
t "15b: only the integrity failure keeps a snapshot" [ "$(snapshots)" -eq $((before + 1)) ]
rm -f "$snap"

# 7b. D7 regression: a pre-planted symlink is never written through
newcase planted; settings "$REPO" v0.30.0; fresh_install
ln -s "$W/target7b" "$CW/.claude/planted"; run STUB_REWRITE=1
t "7b: exit 1" [ "$RC" -eq 1 ]
t "7b: the symlink target was not created" [ ! -e "$W/target7b" ]
t "7b: only settings.json and the planted link under .claude" [ "$(find "$CW/.claude" -mindepth 1 | wc -l)" -eq 2 ]
rm -f "$(grep -o "$W/tmp/plugin-install-settings\.[A-Za-z0-9]*" "$ERR" | head -n 1)"

# 9. invalid entries, one per run
bad() { # bad <label> <repo> <ref> [plugin-key]
  newcase "bad-$1"; settings "$2" "$3"
  if [ -n "${4:-}" ]; then
    jq --arg k "$4" '.enabledPlugins = {($k): true}' "$CW/.claude/settings.json" > "$SD/s" && cat "$SD/s" > "$CW/.claude/settings.json"
  fi
  run
  t "9: $1: exit 1" [ "$RC" -eq 1 ]
  t "9: $1: no stub call" nocalls
  t "9: $1: no file x anywhere" bash -c "[ -z \"\$(find '$W' -name x -type f)\" ]"
  [ -z "${5:-}" ] || t "9: $1: the value is not echoed" bash -c "! grep -qF -- \"\$1\" '$ERR'" _ "$5"
}
bad ref-injection "$REPO" 'v1;touch x' '' 'v1;touch x'
bad ref-space "$REPO" 'v1 x' '' 'v1 x'
bad ref-dots "$REPO" '../x' '' '../x'
bad ref-newline "$REPO" $'v1\nx' '' ''
bad repo-three a/b/c v1 '' 'a/b/c'
bad repo-dash -y/x v1 '' '-y/x'
bad repo-flag --scope/x v1 '' '--scope/x'
bad repo-dotdot a/.. v1 '' 'a/..'
bad plugin-dash "$REPO" v1 '-x@claude-workbench' '-x@claude-workbench'

# 10. enabled but not pinned
newcase unpinned; mkdir "$CW/.claude"
jq -n --arg r "$REPO" '{extraKnownMarketplaces: {"claude-workbench": {source: {source: "github", repo: $r, ref: "v0.30.0"}}, gitm: {source: {source: "git", url: "https://example.test/x.git", ref: "v1"}}, noref: {source: {source: "github", repo: "a/b"}}}, enabledPlugins: {"a@undeclared": true, "b@gitm": true, "c@noref": true, "way-of-working@claude-workbench": true}}' > "$CW/.claude/settings.json"
fresh_install; run
t "10: exit 0" [ "$RC" -eq 0 ]
t "10: three warnings" [ "$(grep -c 'is enabled but not pinned' "$ERR")" -eq 3 ]
t "10: only the pinned one is installed" [ "$(grep -c 'plugin install' "$LOG")" -eq 1 ]

# 11. enabled=false
newcase disabled; mkdir "$CW/.claude"
jq -n --arg r "$REPO" '{extraKnownMarketplaces: {"claude-workbench": {source: {source: "github", repo: $r, ref: "v0.30.0"}}}, enabledPlugins: {"way-of-working@claude-workbench": false}}' > "$CW/.claude/settings.json"; run
t "11: exit 0" [ "$RC" -eq 0 ]
t "11: no stub call" nocalls
t "11: no warning" bash -c "! grep -q warning '$ERR'"

# 12. refused files
newcase symfile; mkdir "$CW/.claude"; settings "$REPO" v0.30.0; cp "$CW/.claude/settings.json" "$W/t12a"; rm "$CW/.claude/settings.json"
ln -s "$W/t12a" "$CW/.claude/settings.json"; before=$(cksum < "$W/t12a"); run
t "12: symlinked file: exit 1" [ "$RC" -eq 1 ]; t "12: symlinked file: no stub call" nocalls
t "12: symlinked file: target untouched" [ "$(cksum < "$W/t12a")" = "$before" ]
newcase symdir; mkdir -p "$W/t12b"; settings "$REPO" v0.30.0; mv "$CW/.claude/settings.json" "$W/t12b/"; rmdir "$CW/.claude"
ln -s "$W/t12b" "$CW/.claude"; before=$(cksum < "$W/t12b/settings.json"); run
t "12: symlinked .claude: exit 1" [ "$RC" -eq 1 ]; t "12: symlinked .claude: no stub call" nocalls
t "12: symlinked .claude: target untouched" [ "$(cksum < "$W/t12b/settings.json")" = "$before" ]
newcase big; settings "$REPO" v0.30.0; head -c 70000 /dev/zero | tr '\0' ' ' >> "$CW/.claude/settings.json"; run
t "12: 70000 bytes: exit 1" [ "$RC" -eq 1 ]; t "12: 70000 bytes: no stub call" nocalls
newcase dirfile; mkdir -p "$CW/.claude/settings.json"; run
t "12: a directory: exit 1" [ "$RC" -eq 1 ]; t "12: a directory: no stub call" nocalls

# 13. invalid JSON
newcase badjson; mkdir "$CW/.claude"; echo '{not json' > "$CW/.claude/settings.json"; run
t "13: exit 1" [ "$RC" -eq 1 ]; t "13: banner" grep -q 'CANNOT READ' "$ERR"; t "13: no stub call" nocalls

# 14. the marketplace list fails
newcase listfail; settings "$REPO" v0.30.0; echo '[]' > "$SD/plugin-list.json"; echo 1 > "$SD/marketplace-list.rc"; run
t "14: exit 1" [ "$RC" -eq 1 ]; t "14: could not read" grep -q 'could not read' "$ERR"

# 15. extras are reported and never removed; the fast path still holds
newcase extras; settings "$REPO" v0.30.0
{ jq -n --arg r "$REPO" '[{name: "claude-workbench", source: "github", repo: $r, ref: "v0.30.0"}, {name: "elsewhere", source: "github", repo: "x/y", ref: "v1"}]'; } > "$SD/marketplace-list.json"
jq -n --arg p "$PLUGIN" '[{id: $p, scope: "user", enabled: true}, {id: "other@elsewhere", scope: "user", enabled: true}]' > "$SD/plugin-list.json"; run
t "15: exit 0" [ "$RC" -eq 0 ]
t "15: only the two list calls" [ "$(argv)" = "plugin marketplace list --json
plugin list --json" ]
t "15: the extra plugin is named" grep -q 'other@elsewhere' "$ERR"
t "15: the extra marketplace is named with its source" grep -q 'marketplace elsewhere (x/y#v1)' "$ERR"
t "15: the removal recipe is printed" grep -q 'marketplace remove <M> --scope user' "$ERR"

# 15c. the caller's TMPDIR and CLAUDE_CONFIG_DIR do not win
newcase env; settings "$REPO" v0.30.0; fresh_install; mkdir "$CW/evil-tmp"
find "$CW" | sort > "$W/ws15c.before"; run TMPDIR="$CW/evil-tmp" CLAUDE_CONFIG_DIR="$W/evil" GIT_CONFIG_SYSTEM=/x GIT_CONFIG_NOSYSTEM=1 GIT_EXEC_PATH=/x GIT_ASKPASS=/x GIT_SSH_COMMAND=x LD_LIBRARY_PATH=/x LD_AUDIT=/x LD_PRELOAD=/x GIT_CONFIG=/x BASH_ENV=/x ENV=/x GIT_DIR=/x GIT_WORK_TREE=/x GIT_CONFIG_COUNT=1 GIT_CONFIG_PARAMETERS=x
t "15c: exit 0" [ "$RC" -eq 0 ]
t "15c: the stub saw none of the scrubbed variables and the git ceiling" bash -c "! grep -q LEAK '$LOG'"
t "15c: the six calls of case 3" [ "$(argv | wc -l)" -eq 6 ]
t "15c: nothing created in the workspace" bash -c "find '$CW' | sort | cmp -s - '$W/ws15c.before'"
t "15c: the stub saw no CLAUDE_CONFIG_DIR" bash -c "! grep -v 'cfg=unset' '$LOG' | grep -q ."
t "15c: every cwd is under the script's TMPDIR" bash -c "! grep -v 'cwd=$W/tmp/' '$LOG' | grep -q ."

# 15d. the guard: a workspace that contains the scratch space
newcase guard; mkdir -p "$W/.claude"; settings "$REPO" v0.30.0; cp "$CW/.claude/settings.json" "$W/.claude/settings.json"
before=$(snapshots)
( cd "$W" && env STUB_LOG="$LOG" STUB_DIR="$SD" STUB_WS="$W" sh "$W/plugin-install.sh" > "$OUT" 2> "$ERR" ); RC=$?
t "15d: exit 1" [ "$RC" -eq 1 ]; t "15d: no stub call" nocalls
t "15d: nothing left under TMPDIR" [ "$(snapshots)" -eq "$before" ]
rm -rf "$W/.claude"
newcase sibling; mkdir -p "$W/tm"; CW="$W/tm"; mkdir -p "$CW/.claude"
jq -n --arg r "$REPO" '{extraKnownMarketplaces: {"claude-workbench": {source: {source: "github", repo: $r, ref: "v0.30.0"}}}, enabledPlugins: {"way-of-working@claude-workbench": true}}' > "$CW/.claude/settings.json"
fresh_install; run
t "15d: a sibling named like a prefix is not refused" [ "$RC" -eq 0 ]

# 15e. a .git or .claude planted directly under TMPDIR (the persistent volume) is refused
for planted in .git .claude; do
  newcase "tmpplant$planted"; settings "$REPO" v0.30.0; fresh_install; mkdir "$W/tmp/$planted"; before=$(snapshots); run
  t "15e: $planted under TMPDIR: exit 1" [ "$RC" -eq 1 ]
  t "15e: $planted under TMPDIR: the refusal banner" grep -q 'REFUSED: A .git OR .claude' "$ERR"; t "15e: $planted under TMPDIR: no stub call" nocalls
  t "15e: $planted under TMPDIR: nothing left behind" [ "$(snapshots)" -eq "$before" ]
  rmdir "$W/tmp/$planted"
done

# 15f. one invalid entry beside an installed pin: no install work, still exit 1
newcase invalidfast; settings "$REPO" v0.30.0
jq '.enabledPlugins["-x@claude-workbench"] = true' "$CW/.claude/settings.json" > "$SD/s" && cat "$SD/s" > "$CW/.claude/settings.json"
mkt_json v0.30.0 > "$SD/marketplace-list.json"; plug_json > "$SD/plugin-list.json"; run
t "15f: exit 1" [ "$RC" -eq 1 ]
t "15f: the invalid-entry banner" grep -q 'IS INVALID' "$ERR"
t "15f: only the two list calls" [ "$(argv)" = "plugin marketplace list --json
plugin list --json" ]

# 16. arguments
newcase args; settings "$REPO" v0.30.0; run_args --check
t "16: exit 2" [ "$RC" -eq 2 ]; t "16: no stub call" nocalls

# 8. over every case's log
logs=("$W"/c*/log)
t "8: no confirmation flags" bash -c "! cat \"\${@}\" | sed 's/.*argv=//' | grep -Eq -- '(^| )(-y|--yes|--accept-command)( |\$)'" _ "${logs[@]}"
t "8: add/remove/install/update all carry --scope user" bash -c "! cat \"\${@}\" | sed 's/.*argv=//' | grep -E '^plugin (marketplace (add|remove)|install|update) ' | grep -qv -- '--scope user'" _ "${logs[@]}"
t "8: no claude call ran in a workspace" bash -c "! cat \"\${@}\" | grep -Eq 'cwd=$W/(c[0-9]+-[a-z0-9-]+/ws|tm)( |\$)'" _ "${logs[@]}"
t "8: every claude call ran under the script's TMPDIR" bash -c "! cat \"\${@}\" | grep -v 'cwd=$W/tmp/' | grep -q ." _ "${logs[@]}"
t "8: every call had GIT_CONFIG_GLOBAL=/dev/null" bash -c "! cat \"\${@}\" | grep -v 'gcg=/dev/null' | grep -q ." _ "${logs[@]}"

echo "plugin-install: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
