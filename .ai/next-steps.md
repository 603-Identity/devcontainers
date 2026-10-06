# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting the review of #292.

**Just done** (coder session on sonnet, last_commit `a1fe4f7`):
- #164 built and shipped as PR #292: `resolve_yq` reads the raw `yq_linux_amd64` hash, and the new
  `tools/tests/bump-asset-names-test.sh` fails when a resolver's asset differs from its Dockerfile's.
- Critic pass (`architect` + `security-critic`): 2 rounds, converged (round 2 tightenings only), all
  on the critics' default models. A pre-review only; it does not satisfy the `architect-review` check.
- The plan anchor re-verified `match` this session (description sha `8bc5e03e`), so no re-anchor gate.
- Accepted, out of scope: the test's fake `curl` serves one body for any URL, so it checks the asset
  name, not which checksum file is read.

**Next:** `/way-of-working:architect-review 292` in a **new window** (the review must be a fresh
session). Model: **opus** (architect). Never approve or merge; the human merges once the
`architect-review` check is green.

**HITL Gate: NONE OPEN.** Next gate is the human merge of #292. The `v1.3` tag (build-order item 11,
owner-owned) is unblocked: items 4-7 are closed.

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
