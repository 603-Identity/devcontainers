# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review on PR #238.

**Just done** (coder session on sonnet, last_commit `d3e6872`):
- Built #160 as PR #238 (open, not merged): `publish` in `.github/workflows/build.yml` now carries
  its own event/ref guard alongside `needs.scope`, with a comment saying the repeat is deliberate.
- Critic pass: architect + security-critic, 1 round, converged; no fixes were needed. The
  one worthwhile finding (the why-comment) was applied afterwards and the critics were not
  re-run on that comment-only delta. Subagent pre-review only, not the attested review.
- Checks: zizmor clean in WSL. Image build and Trivy gate entries not run (workflow-only diff).
- Accepted: the event check is a denylist, so a future `pull_request_target` or `merge_group`
  trigger would need its own look (`scope` has the same gap). No test pins the guard text.

**Next:** `/way-of-working:architect-review 238` in a **new window** (the fresh-session review is
an integrity property; `/clear` does not satisfy it). Model: **opus** (architect).

**HITL Gate: NONE OPEN.** Owner-owned this sprint: the PR #238 merge, the #93 + #122 decision
(by 2026-10-17), the #233 spike result, the `v1.3` tag.

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
