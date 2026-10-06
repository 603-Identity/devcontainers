# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect session on opus, last_commit `0e127f7`):
- Fresh-session architect review of #279 (the #92 fix), posted as a formal review on head
  `e84ffd8`. Reproduced in a WSL sandbox: the gate suites passed, both render checks passed, and
  mutations to the head-SHA check, the dismissed/pending filter and the comment read each
  turned their tests red. No blocking findings. `architect-review` went green; the owner merged
  it as `0e127f7`, closing #92.
- Filed the review's two non-blocking findings: #281 (dismissing a qualifying review does not
  re-run the gate, so its green status stays) and #282 (the `post` job's `issues: read` scope is
  now unused).
- Milestone 4 description re-verified, sha `8bc5e03e`, unchanged; the owner confirmed it.

**Next:** task #96 — in `tools/gate-post.sh`'s reviewer check, say the numeric uid test is
load-bearing (it alone stops a missing ID matching a doubled space in `REVIEWER_IDS`); optionally
normalise `REVIEWER_IDS` with `read -ra`. Re-render the template and this repo's gate, add a
gate-post test for a null id with a doubled-space `REVIEWER_IDS`, run the gate suites in WSL,
then `/way-of-working:critic-gate` and `/way-of-working:ship`. Model **sonnet** (coder).

**HITL Gate: NONE OPEN.** Next gates: the owner's merge of the #96 PR after its fresh-session
architect review; then the `v1.3` tag (owner-owned, after #92 and #96).

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
