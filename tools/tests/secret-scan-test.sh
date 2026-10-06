#!/usr/bin/env bash
# Tests for tools/secret-scan.sh against a fake `betterleaks`, with a real scratch git repo
# (a base commit and a head commit). Offline. The fake records its arguments and prints a
# scripted JSONL stream, so these test the wrapper's fail-closed decisions; the scanner's own
# behaviour is covered by the acceptance suite in devcontainers#190 and by the self-test caller.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

SCRIPT="$TOOLS_DIR/secret-scan.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Fake scanner. FAKE_BL_MODE picks the scripted outcome; every call appends its argv to the log.
# FAKE_BL_FIRST (optional) is the mode for the first call only.
cat > "$T/betterleaks" <<'B'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_BL_LOG"
n="$(wc -l < "$FAKE_BL_LOG")"
mode="$FAKE_BL_MODE"
if [ "$n" -eq 1 ] && [ -n "${FAKE_BL_FIRST:-}" ]; then mode="$FAKE_BL_FIRST"; fi
finding='{"schema_version":"1","finding":{"rule_id":"org-x","location":{"path":"a b::c.tf","start_line":3}}}'
case "$mode" in
  clean)      echo '{"schema_version":"1","scan":{"state":"complete"}}'; exit 0 ;;
  hostile)    echo '{"schema_version":"1","finding":{"rule_id":"r,x::%0A::warning::y","location":{"path":"p,%0A::q.tf","start_line":"3,col=1"}}}'
              echo '{"schema_version":"1","finding":{"rule_id":"org-pem","location":{"path":"k.pem"}}}'
              echo '{"schema_version":"1","scan":{"state":"complete"}}'; exit 1 ;;
  findings)   echo "$finding"; echo '{"schema_version":"1","scan":{"state":"complete"}}'; exit 1 ;;
  incomplete) echo '{"schema_version":"1","scan":{"state":"incomplete"}}'; exit 0 ;;
  norecord)   echo "config error" >&2; exit 1 ;;
  garbage)    echo 'not json'; exit 0 ;;
  stderrinc)  echo '{"schema_version":"1","scan":{"state":"complete"}}'; echo "incomplete scan: 2 files skipped" >&2; exit 0 ;;
  jsonlinc)   echo '{"schema_version":"1","log":"Incomplete Scan: a path was unreadable"}'; echo '{"schema_version":"1","scan":{"state":"complete"}}'; exit 0 ;;
  zeroline)   echo '{"schema_version":"1","finding":{"rule_id":"org-pem","location":{"path":"z.tf","start_line":0}}}'
              echo '{"schema_version":"1","finding":{"rule_id":"org-neg","location":{"path":"n.tf","start_line":-2}}}'
              echo '{"schema_version":"1","scan":{"state":"complete"}}'; exit 1 ;;
  exit1clean) echo '{"schema_version":"1","scan":{"state":"complete"}}'; exit 1 ;;
esac
B
chmod +x "$T/betterleaks"

# Scratch repo: the base commit holds the given files, the head commit appends to README.
mkrepo() { # [file=content ...]
  rm -rf "$T/repo"; git init -q "$T/repo"
  git -C "$T/repo" config user.email t@t; git -C "$T/repo" config user.name t
  git -C "$T/repo" config commit.gpgsign false
  echo seed > "$T/repo/README"
  local kv
  for kv in "$@"; do printf '%s\n' "${kv#*=}" > "$T/repo/${kv%%=*}"; done
  git -C "$T/repo" add -A; git -C "$T/repo" commit -qm base
  BASE="$(git -C "$T/repo" rev-parse HEAD)"
  echo more >> "$T/repo/README"; git -C "$T/repo" commit -qam head
  HEAD_C="$(git -C "$T/repo" rev-parse HEAD)"
}
printf 'title = "org"\n' > "$T/org.toml"

run() { # [VAR=value ...] -> RC, LOG
  : > "$T/calls.log"
  RC=0
  env BASE_SHA="$BASE" HEAD_SHA="$HEAD_C" REPO_DIR="$T/repo" BETTERLEAKS="$T/betterleaks" \
    ORG_TOML="$T/org.toml" FAKE_BL_LOG="$T/calls.log" FAKE_BL_MODE="${MODE:-clean}" \
    "$@" bash "$SCRIPT" > "$T/out" 2> "$T/err" || RC=$?
  LOG="$(cat "$T/calls.log")"
}
ncalls() { wc -l < "$T/calls.log" | tr -d ' '; }
err_has() { if grep -qF -- "$2" "$T/err"; then pass; else fail "$1" "stderr lacks '$2': $(cat "$T/err")"; fi; }
err_lacks() { if grep -qF -- "$2" "$T/err"; then fail "$1" "stderr has '$2'"; else pass; fi; }
log_has_() { case "$LOG" in *"$2"*) pass ;; *) fail "$1" "scanner argv lacks '$2': $LOG" ;; esac; }
log_lacks_() { case "$LOG" in *"$2"*) fail "$1" "scanner argv has '$2': $LOG" ;; *) pass ;; esac; }

suite "secret-scan"

mkrepo
MODE=clean run
assert_rc "clean scan passes" 0 "$RC"
log_has_ "full ancestry, merges, text" "--log-opts=-m --text $HEAD_C"
log_has_ "redacted" "--redact"
log_has_ "no allow signatures" "--no-allow-signatures"
log_has_ "explicit ignore file" "--ignore-file"
log_has_ "org config when the base has none" "-c $T/org.toml"
for bad in --disable-rule --isolate-rule --confidence --allow-signature " -v" " -a" "--validate" "--analyze" " -o " "--output"; do
  log_lacks_ "never passes$bad" "$bad"
done

MODE=findings run
assert_rc "findings fail" 1 "$RC"
err_has "annotation carries file and line" "::error file=a_b__c.tf,line=3::org-x at a_b__c.tf:3"
err_has "rotate, don't rewrite" "rotate the secret"
err_lacks "file name cannot inject a workflow command" "file=a b::c.tf"
assert_eq "findings are never retried" 1 "$(ncalls)"

MODE=hostile run
assert_rc "hostile fields still fail" 1 "$RC"
err_has "rule id and non-numeric line are sanitized, no line property" "::error file=p__0A__q.tf::r_x___0A__warning__y at p__0A__q.tf"
err_has "a finding with no start_line is a file-level annotation" "::error file=k.pem::org-pem at k.pem"
err_lacks "no injected warning command" "::warning"
err_lacks "no injected property" ",col="
err_lacks "no escape sequence survives" "%0A"

MODE=norecord run
assert_rc "an error with no scan record fails" 1 "$RC"
err_has "says it did not complete" "scan did not complete"
MODE=garbage run
assert_rc "unparseable output fails" 1 "$RC"
MODE=incomplete run
assert_rc "incomplete fails" 1 "$RC"
assert_eq "incomplete is retried once" 2 "$(ncalls)"
MODE=clean run FAKE_BL_FIRST=incomplete
assert_rc "incomplete then complete passes" 0 "$RC"
MODE=exit1clean run
assert_rc "exit 1 with a complete record and no findings still fails" 1 "$RC"
# #199: the wrapper's own 'incomplete scan' text check, which a complete record and exit 0 must not bypass.
MODE=stderrinc run
assert_rc "a complete record with 'incomplete scan' on stderr fails" 1 "$RC"
err_has "and says it did not complete" "scan did not complete (state: incomplete"
MODE=jsonlinc run
assert_rc "a complete record with 'incomplete scan' in the JSONL fails" 1 "$RC"
err_has "and says it did not complete too" "scan did not complete (state: incomplete"

# #220: a start_line below 1 is not a line to anchor an annotation at.
MODE=zeroline run
assert_rc "findings with a start_line of 0 or below fail" 1 "$RC"
err_has "a start_line of 0 is a file-level annotation" "::error file=z.tf::org-pem at z.tf"
err_has "a negative start_line is a file-level annotation" "::error file=n.tf::org-neg at n.tf"
err_lacks "no line=0" "line=0"
err_lacks "no negative line" "line=-"

for v in BETTERLEAKS_CONFIG BETTERLEAKS_CONFIG_TOML BETTERLEAKS_VALIDATE BETTERLEAKS_ANALYZE; do
  MODE=clean run "$v=x"
  assert_rc "$v set is refused" 1 "$RC"
  assert_eq "$v refused before any scan" "" "$LOG"
done

MODE=clean run HEAD_SHA=main
assert_rc "a ref instead of a SHA" 1 "$RC"
MODE=clean run BASE_SHA=0123
assert_rc "a short base SHA" 1 "$RC"
MODE=clean run HEAD_SHA=0000000000000000000000000000000000000000
assert_rc "a head commit that is not in the checkout" 1 "$RC"
MODE=clean run BASE_SHA=0000000000000000000000000000000000000000
assert_rc "a base commit that is not in the checkout" 1 "$RC"
MODE=clean run ORG_TOML="$T/nope.toml"
assert_rc "missing org config" 1 "$RC"

# The base commit's config is used, and is linted; the head's is ignored.
mkrepo 'betterleaks.toml=[extend]
path = "/usr/local/share/devc/secret-scan/org.toml"'
MODE=clean run
assert_rc "an allowed repo config passes" 0 "$RC"
log_lacks_ "the repo config, not the org path, is passed to -c" "-c $T/org.toml"

mkrepo 'betterleaks.toml=useDefault = false'
MODE=clean run
assert_rc "a weakening repo config at the base fails" 1 "$RC"
assert_eq "and the scanner never ran" "" "$LOG"
err_has "says why" "not an allowed repo config"

mkrepo
printf 'useDefault = false\n' > "$T/repo/betterleaks.toml"
git -C "$T/repo" add -A; git -C "$T/repo" commit -qm 'head adds a config'
HEAD_C="$(git -C "$T/repo" rev-parse HEAD)"
MODE=clean run
assert_rc "a config added only in the head is not read" 0 "$RC"
log_has_ "so the org config is used" "-c $T/org.toml"

mkrepo '.betterleaksignore=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
MODE=clean run
assert_rc "an ignore file at the base" 0 "$RC"

summary
