# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review.

**Just done** (coder session on sonnet, last_commit `a31eb24`):
- Task #96: the reviewer check's comment in `tools/gate-post.sh` now says the numeric uid test is
  load-bearing (it alone stops a missing ID matching a doubled, leading or trailing space in
  `REVIEWER_IDS`). Mirrored into the template and this repo's gate; `render-gate.sh` checks pass.
  Added a `gate-post-test` case (null id, doubled-space `REVIEWER_IDS`) that fails without the
  numeric test. Gate suites and shellcheck pass in WSL. Shipped as PR #284.
- Critic pass (architect + security-critic): 2 rounds, converged (wording tightenings applied,
  delta re-check clean). No second-opinion round.
- Milestone 4 description re-verified, sha `8bc5e03e`, unchanged.

**Next:** `/way-of-working:architect-review 284` — fresh-session architect review of PR #284
(the #96 fix, head `a31eb24`); the `architect-review` check stays red until it is posted. Model
**opus** (architect), in a new session.

**HITL Gate: NONE OPEN.** Next gates: the owner's merge of #284 after that review; then the
`v1.3` tag (owner-owned, after #92 and #96).

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

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) Â· sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
