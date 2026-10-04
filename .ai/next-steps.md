# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect session on opus, last_commit `9d38b76`):
- Posted the fresh-session `/way-of-working:architect-review` on PR #238 (#160). It was
  correct as scoped, with no blocking findings. `architect-review` went green on `d3e6872`, and
  the owner merged it as `9d38b76`.
- On the merge push, run 37172129491's `Build, test, push and attest` job ran rather than
  skipping. That confirms the new guard lets main publish. The run was still in progress at
  handoff, so check its conclusion.
- Filed #240 (not blocking, unmilestoned): the scope/publish event guard is a denylist.
  `pull_request_target`, `workflow_run` and `issue_comment` get past both clauses. It
  proposes an allowlist. `merge_group` is already caught by the ref clause.

**Next:** task #214 — make `tools/check-consumer-workflows.sh` run each `code_paths` entry from
the consumer's own `.ai/project.yml` through the gate's CONSUMER `case` block and fail on
`touches=0`, plus the README guidance, per the issue body's proposed fix. Then the green gate,
`/way-of-working:critic-gate` (architect + security-critic) and `/way-of-working:ship`.
Model: **sonnet** (coder). `/clear` is fine.

**HITL Gate: NONE OPEN.** Owner-owned this sprint: the #214 PR merge, the #93 + #122 decision
(by 2026-10-17), the #233 spike result, the `v1.3` tag.

**Open for the owner (non-blocking):**
- Decide whether #240 joins milestone 4 (it touches the same guard as #160).
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
