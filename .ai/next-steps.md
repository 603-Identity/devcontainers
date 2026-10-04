# Next steps

**Now:** P1: pilot adoption (milestone 2). Awaiting the owner's review of the sprint close.

**Just done** (session ran coder, last_commit `e7baa64`):
- #103 closed: `docs/adopting.md` is the ordered adoption runbook with rollback (#228), linked from
  the README and from #26, #27 and #28. `docs/adopting.md` is now in `load_bearing_docs` (#229).
- Folded into #228 and closed: #204, #205, #182, #183; #206 and #212 were already covered by
  the README (#215, #191).
- Critic pass on #228: docs-consistency, security-critic and architect, 4 fix-and-re-run rounds,
  cap reached. docs-consistency converged; the last security round's fixes (step 2 ruleset values,
  rollback ruleset order) were not re-reviewed by a critic. Hermetically verified only: no
  wave repo has yet followed the runbook (live check deferred to #26 to #28).

**Next:** the owner decides where #190 (Betterleaks) belongs: it is the only open issue left in
milestone 2 and is bigger than this milestone. Then run `/way-of-working:archive-sprint` to close
milestone 2 and seed the next cursor. Model: **sonnet** (mechanical). `/clear` is fine.

**HITL Gate: OPEN.** Owner moves #190 (or closes the sprint as is), then approves archiving.

**Open for the owner (non-blocking):**
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- -dns#57 (pin `Mocked tofu test` and both Checkov checks to `integration_id` 15368), -dns#59,
  -dns#65 are open.
- Other repos still on detect-secrets have their own migration issues: checkov-ledger-action#16,
  infrastructure-core#560, tenant-posture-assessment#31 and trust-anchors#73. #220 is open.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo. Run
  tests in WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch
  deletes, so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
