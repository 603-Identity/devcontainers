#!/usr/bin/env bash
# Entry point: bash tools/tests/run-gate-tests.sh. Offline; needs bash, jq, yq (mikefarah), git/coreutils.
# Exits 0 only when every suite passes.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in image-scope-test.sh render-gate-test.sh gate-resolve-test.sh gate-post-test.sh decide-bump-test.sh check-consumer-workflows-test.sh; do
  bash "$here/$t" || rc=1
done
if [ "$rc" -eq 0 ]; then echo "ALL GATE TESTS PASSED"; else echo "GATE TESTS FAILED" >&2; fi
exit "$rc"
