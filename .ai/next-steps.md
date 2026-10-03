# Next steps

**Now:** P1: pilot adoption (milestone 2) -- awaiting_review.

**Just done** (coder session, last_commit `4f62a7d`):
- Resumed on #211 and fixed `tools/secret-scan.sh`: each finding now prints
  `::error file=<path>,line=<n>::<rule> at <path>:<n>`; `line=` only for a numeric `start_line`
  (a path-rule finding is a file-level annotation); the `safe` filter still covers path and rule id.
- Tests: `line=`, a finding with no `start_line`, hostile path/rule id/`start_line`; WSL shellcheck
  and `run-gate-tests.sh` pass. The Docker and Go gate steps were left to CI.
- Critic pass (`security-critic` + `architect`): 2 rounds, converged; no second-opinion round (declined).
- Opened [PR #218](https://github.com/603-Identity/devcontainers/pull/218) for #211.

**Next:** `/way-of-working:architect-review 218` -- fresh session, **opus** (architect); the PR touches
`tools/`, so the review gate applies. The human merges. Then the new `vX.Y` tag and the template pin
bump need the owner's go-ahead.

**HITL Gate: NONE OPEN** for the review. Next gate: the tag push and the pin bump after #218 merges.

**Open for the owner (non-blocking):**
- Close #217 (the earlier cursor-sync PR for #211) as superseded by this sync.
- #10, still to do: one real image bump through the review path (the precondition for #139); a
  PR on -entra showing the `verify / verify` pin blocks; tick #10's checklist; answer whether the
  forwarded GPG agent should expose the personal and org keys, and whether a persistent `/tmp` is
  intended.
- Check #212's items against #215 and close what it covers.
- After the pilots: #191 removes bc-detect-secrets and #186, and the follow-up PR drops
  `Secret scan (detect-secrets)` from each pilot's ruleset; close #187-#189 when #191 lands.
- Decide whether the image should ship a wrapper script for the betterleaks hook's `env` prefix.
- Still to do under #190: lint that a consumer's pinned SHA is an ancestor of `main`. Cosign
  (pinned in `bump-binaries.yml`) is bumped by hand; a Betterleaks bump also means a new `vX.Y` tag.
- Fix now in other repos: jrg-consulting-site#131 and glunk-works/pm-agent-loop#13.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01 (milestone 5).
- Decide whether the declined re-prompt option from #5 needs a `DEVC-D` entry. Amend spec §4
  to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account can flip to Seuss27: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process; run tests in WSL, not
  Git Bash. Open the devcontainer from PowerShell, not Git Bash. GPG signing can time out on a
  pinentry prompt on the Windows side; a retry after entering the passphrase works.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
