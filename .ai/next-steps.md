# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review: PR #303 (#85 + #208).

**Just done** (coder session on sonnet, last_commit `6ddf1ec`):
- PR #303 opened, closing #85 and #208, all in `.github/scripts/bump-binaries.sh`: every `resolve_*`
  sets `CHECKSUM_URL` and the bump PR body carries `Checksum source:`; betterleaks takes release
  candidates only while its pin is `X.Y.Z-rc.N`. Tests, README and threat-model line 34 updated.
- Local gate in WSL: the betterleaks, leftover-branch and asset-names suites, `run-gate-tests.sh` and
  shellcheck pass. The docker steps were not run locally (no Dockerfile or workflow changed); CI runs them.
- Critic pass (security-critic, architect, docs-consistency): 2 rounds, converged; no second-opinion round
  (declined). Not the review gate.
- Follow-up #304 filed (rc pin skips GA when a newer rc exists); unmilestoned, for the owner to place.
- Milestone 4 re-anchored to no task without a resume-verified baseline (resume waited on an open
  gate, so it did not verify): `verify --plan` printed `match`, description sha `8bc5e03e` unchanged.

**Next:** `/way-of-working:architect-review 303`, in a new session, on **opus** (architect). Then the
owner merges #303 and picks the next M4 task.

**HITL Gate: OPEN.** The milestone-4 re-anchor lacks a resume-verified baseline. The owner's "go"
releases the review session.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281, #282, #297 and #304 in a milestone (or leave them for a
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
