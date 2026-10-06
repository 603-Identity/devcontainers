# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing; #128 is next.

**Just done** (architect session on opus, last_commit `996ddd6`):
- Closed #233 by hand. #274 (merged as `d334c02`) did its work but did not close it.
- The owner picked #128 (build-order item 12) as the next task, "for now". Items 1-10a are
  closed, so the build order's next step is item 11, the `v1.3` tag. It is owner-owned and not
  yet tagged; it does not block #128.
- First anchor for #128, description sha `8bc5e03e`: this session's resume did not verify the
  prior anchor (the gate was open), so there was no baseline. The handoff-time
  `verify --plan` against the prior anchor printed `match`.

**Next:** task #128 — Move Go and buildkit together (M4 build-order item 12), per #128's spec.
Model: **sonnet** (coder). Critic gate: `architect` + `security-critic`. Then
`/way-of-working:ship` and a fresh-session opus architect review.

**HITL Gate: OPEN.** Owner "go" on the first #128 anchor (above). Separately, the `v1.3` tag
(owner-owned) is still outstanding and does not block #128.

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
