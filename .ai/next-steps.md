# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting the review of #295.

**Just done** (architect session on opus, last_commit `e39ccdf`):
- `v1.3` released (build-order item 11). The owner pushed the signed tag on `2f3bacc` and published
  it as an immutable GitHub Release. Release immutability is now on for the repo. A docs-consistency
  pass checked the notes: 2 rounds, converged (round 1 fixed the step-2 pin pairing and the #94
  overclaim).
- Reopened #94. It auto-closed on #279's merge, but the DEVC-D7 amendment says #279 only narrowed it.
- Opened PR #295. It re-points the template's `decide`, `verify` and `secret-scan` pins, and this
  repo's own `decide` pin, to `v1.3`, re-renders the template gate, and adds DEVC-D8 (signed tag +
  immutable Release per version) with the matching threat-model edit. Render checks, the gate tests
  in WSL and zizmor are green. Handed off without a critic-gate pass (mechanical pins + docs, owner's
  call).
- Milestone 4 re-anchored without a resume-verified baseline: `verify --plan` printed `match`,
  description sha `8bc5e03e` unchanged.

**Next:** `/way-of-working:architect-review 295` in a **new window** (this session wrote the diff).
Model: **opus** (architect). Never approve or merge. After the merge, pick the next milestone-4 task
with the owner (#86 is next in the build order).

**HITL Gate: OPEN.** The re-anchor above, the human merge of #295 once `architect-review` is green,
then the owner's pick of the next M4 task.

**Open for the owner (non-blocking):**
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
