# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Planning.

**Just done** (last_commit `33b864b`):
- P1 (milestone 2) archived; roadmap marks it done at `00b6a2e` (#228). #190 moved to milestone 4.
- Deep record: nothing to compact (roadmap holds status and decisions only; backlog is GitHub issues).

**Milestone close:** closed, milestone 2 "P1: pilot adoption", read back `closed` with 0 open issues.

**Next:** plan milestone 4: read its description and open issues, order them, and put the plan
through the owner's gate. `/way-of-working:plan-sprint` can help triage. Model: **opus**
(architect). `/clear` is fine.

**HITL Gate: NONE OPEN.** Next gate is the owner's approval of the milestone 4 plan.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11) is date-bound: renew or retire the #148 Trivy exceptions
  before 2026-11-01.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo. Run
  tests in WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch
  deletes, so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
