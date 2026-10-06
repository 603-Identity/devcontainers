# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review: PR #307 (task #262), then
back to #102.

**Just done** (coder session on sonnet, last_commit `3732896`):
- Task #262 built and shipped as PR #307 (branch `ci/merge-guard-admit-admin-262`): merge-guard admits
  resume's v0.16.0 `--admin` cursor-sync merge (still behind an `ask`), refuses `--admin` on any other
  plain `gh pr merge`, and refuses the pre-0.16.0 shape. The header states that decision and a current
  residuals list; fixtures cover the new shape, `--admin` elsewhere and the old shape.
- Critic-gate: security-critic, architect and docs-consistency; 2 rounds, converged (no second-opinion
  round). Round 1 caught a false header claim: `--admin` bypasses only `restrict-updates-to-main`;
  `main-required-checks` has no bypass actors, so the required checks still apply.
- Not in #307, worth filing: record `restrict-updates-to-main` in `.ai/project.yml` and
  `docs/threat_model.md`; fix the stale "deny rules on merge" comment at `.ai/project.yml:61`; harden
  `is_merge` against wrapped `gh pr merge` forms; require `status == "modified"` in the cursor-sync file
  check.
- Milestone 4: first anchor for milestone 4, description sha `8bc5e03e` (no resume-verified baseline:
  the session's resume waited on the then-open gate).

**Next:** `/way-of-working:architect-review 307`, on **opus** (architect), in a **new window**: the
`architect-review` check stays red until a fresh-session review is posted on the head commit. After the
owner merges #307, return to task #102 (bump-binaries GitHub App) on sonnet.

**HITL Gate: OPEN.** The milestone-4 anchor has no resume-verified baseline. The owner's "go" releases it.

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
  refresh the plugin so `/resume` uses the `--admin` merge shape #307 admits (until then merge-guard
  blocks the old shape).
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -`
  with a timeout works. Auto mode blocks ruleset edits, required-job removal and branch deletes, and
  edits to the merge-guard hook's own text; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
