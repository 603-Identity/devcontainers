# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing: task #262, then back to #102.

**Just done** (architect session on opus, last_commit `e3ee745`):
- Fresh-session architect review of PR #303 (#85 + #208) posted; the gate went green on the head
  commit. The owner merged it as `e3ee745`. Two cosmetic observations went in the review body only;
  nothing was filed.
- #262 added to milestone 4 at the owner's direction. It is a prerequisite of the claude-workbench
  orchestrator plan (v9 § 8.5). Its ordering condition is met: claude-workbench#229 shipped in
  v0.16.0, and `.claude/settings.json` pins `v0.16.0`. This change supersedes the #271
  not-planned decision.
- Milestone 4 re-anchored to task #262 without a resume-verified baseline (resume waited on an open
  gate, so it did not verify): `verify --plan` printed `match`, description sha `8bc5e03e` unchanged.

**Next:** task #262 — teach `.claude/hooks/merge-guard.sh` to admit resume's v0.16.0 cursor-sync
merge (`gh pr merge <N> --repo <repo> --squash --admin --match-head-commit <oid>`) and keep refusing
`--admin` on any other `gh pr merge`. Add fixtures for the new shape, `--admin` elsewhere and the
old shape, and update the header's residuals. Then run critic-gate, ship and hand off for architect
review. On **sonnet** (coder). After #262 merges, return to **#102** (bump-binaries GitHub App).

**HITL Gate: OPEN.** The milestone-4 re-anchor lacks a resume-verified baseline. The owner's "go"
releases the coder session.

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
- The local plugin cache runs way-of-working 0.14.0 while `.claude/settings.json` pins v0.16.0;
  refresh the plugin so `/resume` uses the `--admin` merge shape #262 admits.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -`
  with a timeout works. Auto mode blocks ruleset edits, required-job removal and branch deletes, so
  switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
