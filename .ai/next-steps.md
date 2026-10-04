# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (coder session on sonnet, last_commit `2c0efa4`):
- Built #87 as PR #236, merged: job-level `if: vars.BUMP_BINARIES_APP_ID != ''` on
  `bump-binaries.yml`. README and the threat model's Known gaps now describe the skip and the
  repo-level-variable rule (set the variable last, after the key secret).
- Critic pass on #236: architect + security-critic, 2 rounds, converged. Subagent pre-review
  only, not the attested review. Accepted: deleting the variable later skips the job silently.
- Checks: zizmor clean in WSL. The image-build and Trivy gate entries were not run (workflow
  and docs diff only).

**Next:** task #160 — restore `publish`'s own event/ref guard in `.github/workflows/build.yml`
alongside `needs.scope` (the issue body has the exact `if:`), then the green gate,
`/way-of-working:critic-gate` (architect + security-critic) and `/way-of-working:ship`.
Model: **sonnet** (coder). `/clear` is fine.

**HITL Gate: NONE OPEN.** Owner-owned this sprint: the #93 + #122 decision (by 2026-10-17),
merges, the #233 spike result, the `v1.3` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11) is date-bound: renew or retire the #148 Trivy exceptions
  before 2026-11-01.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch deletes,
  so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
