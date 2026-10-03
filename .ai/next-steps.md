# Next steps

**Now:** P1: pilot adoption (milestone 2) -- implementing.

**Just done** (status session, base `7774909`):
- Piloted terraform-microsoft365-entra for [#10](https://github.com/603-Identity/devcontainers/issues/10)
  on 2026-10-03: all of the README's container checks passed (results in #10's comments), the lock
  finding is fixed by entra#39, and ruleset 22495585 now pins `architect-review`, `verify / verify`
  and `secrets / scan` to `integration_id: 15368` (read back from the effective rules; the entra
  `.ai/project.yml` matches).
- README findings from both pilots merged in #215 and #216.
- #10 stays **open** on owner-side items (below); the owner is not at the console.

**Next:** task #211 — make `tools/secret-scan.sh` emit `::error file=<path>,line=<n>::<rule>` with
the file in the message too, keeping the `safe` filter on every interpolated field; add a test that
the annotation carries `line=`; green gate, `/way-of-working:critic-gate`, `/way-of-working:ship`.
Model: **sonnet** (coder).

**HITL Gate: NONE OPEN** for #211's code change. Next gate: pushing the new `vX.Y` tag after #211
merges, and bumping the template's pin, need the owner's go-ahead.

**Open for the owner (non-blocking):**
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
