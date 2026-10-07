#!/usr/bin/env bash
# Entry point: bash tools/tests/run-gate-tests.sh. Offline; needs bash, jq, yq (mikefarah), git/coreutils.
# Exits 0 only when every suite passes.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in image-scope-test.sh last-publish-sha-test.sh build-workflow-test.sh render-gate-test.sh gate-resolve-test.sh gate-post-test.sh decide-bump-test.sh check-consumer-workflows-test.sh merge-guard-test.sh secret-scan-lint-test.sh secret-scan-test.sh secret-scan-guard-test.sh bump-betterleaks-test.sh bump-asset-names-test.sh bump-leftover-branch-test.sh; do
  bash "$here/$t" || rc=1
done
if [ "$rc" -eq 0 ]; then echo "ALL GATE TESTS PASSED"; else echo "GATE TESTS FAILED" >&2; fi
exit "$rc"
