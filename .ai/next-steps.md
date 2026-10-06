# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review.

**Just done** (coder session on sonnet, last_commit `e84ffd8`):
- Built the #92 fix as PR #279 (branch `fix/gate-review-head-sha-92`): `tools/gate-post.sh` counts
  only a formal review, not dismissed or pending, whose `commit_id` is the head SHA; comments
  never count. Template and own gate re-rendered; tests converted; threat model, adopting guide and
  DEVC-D7 (amended) updated. `Closes #92` only.
- Critic pass (architect, security-critic, docs-consistency): 2 rounds, converged, all on their
  default models; no second-opinion round. Round 1 found stale prose, a false "only the author can
  edit a review body" claim and dismissed reviews counting; all fixed.
- Filed #278: the review binds to the head at post time, not the head the reviewer read. #94 stays
  open (a writer may be able to edit another user's review body; unverified).
- Left open on purpose: the unused `issues: read` scope on `post` (follow-up); #276 not included.

**Next:** `/way-of-working:architect-review 279`, in a new session on **opus** (architect). The review
must be a formal PR review against the head SHA: a comment no longer counts under the new gate, and
any later push needs a fresh review. The owner merges.

**HITL Gate: OPEN.** First anchor for milestone 4, description sha `8bc5e03e` (unchanged). This
session's resume did not verify the prior anchor, so there is no baseline. Confirm the milestone 4
description is still the approved plan, then say "go". Later gates: the owner's merge of #279; the
`v1.3` tag (owner-owned, after #92 and #96).

**Open for the owner (non-blocking):**
- Close #233 by hand (#274 did not close it).
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276 and #278 in a milestone (or leave them for a
  `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition.
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
