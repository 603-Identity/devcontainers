# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect session on opus, last_commit `3816de1`):
- Fresh-session architect review of PR #258 (#198) posted. No blocking findings; the
  `architect-review` check went green on head `44bf291`. The owner merged it as `3816de1`.
- Reproduced in a WSL sandbox with the published image's betterleaks: the new smoke check
  passes on the PR. Reverting the old regex on both sides, the leading side only, or the
  trailing side only each turns both new checks red.
- Filed #263 (pre-existing, also upstream): a secret right after an escape such as `\n` is
  still missed by the Entra rule. Reproduced: rc 1 after `\`, rc 0 after `\n`.
- Plan anchor: milestone 4 description unchanged since the last anchor (`plan-anchor.sh verify
  --plan` printed match at handoff), but this session's resume never verified it, so there is
  no verified baseline. Gate opened below.

**Next:** task #240 — in `.github/workflows/build.yml`, replace the event denylist on both the
`scope` and `publish` jobs with an allowlist (`push`, `schedule`, `workflow_dispatch`), keeping
the `refs/heads/main` clause, so a new trigger fails closed; pin the `publish.if` text with a
test. Model: **sonnet** (coder). Then `/way-of-working:critic-gate` (architect +
security-critic) and `/way-of-working:ship`. After it, the `v1.3` release (item 11).

**HITL Gate: OPEN.** No verified plan-anchor baseline this session: confirm milestone 4 is still
the approved plan, then say go. Next gate: the owner's merge of the #240 PR after its
fresh-session architect review. Also owner-owned this sprint: the #93 + #122 decision (by
2026-10-17), the #233 spike result, the `v1.3` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
- Place #255, #256 and #263 in a milestone (or leave them for a `/way-of-working:plan-sprint`
  pass).
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch deletes,
  so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
