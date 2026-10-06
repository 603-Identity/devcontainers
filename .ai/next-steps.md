# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing: task #102 (PR #307 merged as
`318d879`).

**Just done** (architect session on opus, last_commit `318d879`):
- Posted the fresh-session architect review on PR #307 (task #262) against head `3732896`: sound,
  nothing blocking. The `architect-review` status went green; every required check passes. `BLOCKED` is
  expected (`restrict-updates-to-main` makes the merge an admin bypass).
- Verified in the review: the admitted shape matches v0.16.0 resume byte for byte; the ruleset claims in
  the header are accurate; v0.16.0 `cursor-sync-pr.sh` agrees on the single-file rule; the merge-guard
  suite passes in a WSL sandbox, and two mutations (old shape re-admitted, `--admin` loosened) go red.
- Filed the review's non-blocking findings in milestone 4: #309 (record `restrict-updates-to-main` in
  `.ai/project.yml` and the threat model), #310 (stale "deny rules on merge" comment), #311 (file check
  should require `status == "modified"`). Wrapped merge forms stay with #170; header/threat-model wording
  with #172.
- Milestone 4 anchor re-written for task #102; a handoff-time verify printed `match` (description sha
  `8bc5e03e` unchanged), but this session's resume never ran verify, so there is still no
  resume-verified baseline.

**Next:** task #102 — provision the bump-binaries GitHub App with its key in a main-restricted
Environment, per #102's spec, on **sonnet** (coder).

**HITL Gate: OPEN.** No resume-verified baseline for the milestone-4 anchor. The owner's "go" releases
it.

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
  refresh the plugin so `/resume` uses the `--admin` merge shape #307 admits (merge-guard, with #307
  merged, blocks the old shape).
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -`
  with a timeout works. Auto mode blocks ruleset edits, required-job removal and branch deletes, and
  edits to the merge-guard hook's own text; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
