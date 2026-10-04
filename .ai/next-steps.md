# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. PR #243 is reviewed and waiting for
the owner's merge.

**Just done** (architect session on opus, last_commit `d87f89e`):
- Posted the fresh-session architect review on PR #243 (#214) against head `ac956ad`.
  `architect-review` is green on that SHA (commit status) and the PR reads `CLEAN`. Verdict:
  sound. Executed in an isolated sandbox in WSL: the suite, shellcheck, two planted mutations,
  and a lint of terraform-microsoft365-entra and terraform-cloudflare-dns at their `main`.
- Filed #245 (non-blocking): a `./`-prefixed `code_paths` entry gets a false finding whose
  obvious fix makes the gate fail open. Not milestoned.
- Plan anchor for milestone 4 re-verified at this handoff: `match`, description unchanged.
  (Resume did not verify it, because the status was `awaiting_review`.)

**Next:** once the owner has merged #243, pick the next milestone-4 task with the owner and
hand it off to a coder session. #245 is a candidate if the owner milestones it. Model:
**opus** (architect) for the pick.

**HITL Gate: OPEN.** The #243 merge (owner) and the owner's pick of the next M4 task. Also
owner-owned this sprint: the #93 + #122 decision (by 2026-10-17), the #233 spike result, the
`v1.3` tag.

**Open for the owner (non-blocking):**
- Decide whether #240 and #245 join milestone 4.
- Milestone 5 (Trivy renewal 2026-11) is date-bound: renew or retire the #148 Trivy exceptions
  before 2026-11-01.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra, and the merged
  local branch `docs/sync-cursor-243-review` here (auto mode refused the delete).
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch deletes,
  so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
