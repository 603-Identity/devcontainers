# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing; next task not yet picked.

**Just done** (architect session on opus, last_commit `e3869b4`):
- Posted the fresh-session architect review on PR #284 (#96) against head `a31eb24`.
  `architect-review` is green on that SHA (commit status). Verdict: sound, no blocking findings.
  The owner merged it as `e3869b4`, closing #96.
  Executed in an isolated sandbox in WSL: the gate suites, both render checks and shellcheck
  passed. With the numeric uid test removed, the new test goes red. With the numeric test
  removed and a single space in `REVIEWER_IDS`, it passes.
- No findings filed. Two notes stay in the review only: the test covers the doubled space but
  not leading or trailing spaces (all three reduce to the same thing after padding), and #96's
  optional `read -ra` cleanup was not taken.
- Plan anchor for milestone 4 re-verified at this handoff: `match`, description unchanged
  (sha `8bc5e03e`). Resume did not verify it, because the status was `awaiting_review`.

**Next:** pick the next milestone-4 task with the owner and hand it off to a coder session.
Model: **opus** (architect) for the pick.

**HITL Gate: OPEN.** The `v1.3` tag (owner-owned, now that #92 and #96 are merged) and the
owner's pick of the next M4 task.

**Open for the owner (non-blocking):**
- Close #233 by hand (#274 did not close it).
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281 and #282 in a milestone (or leave them for a
  `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition. #94 stays open (narrowed by #279, unverified).
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -`
  with a timeout works. Auto mode blocks ruleset edits, required-job removal and branch deletes, so
  switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
