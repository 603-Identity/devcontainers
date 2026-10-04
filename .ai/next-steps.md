# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (planning session on opus, last_commit `96c7a2e`; no code):
- Planned milestone 4. The owner approved the build order; it is the milestone description.
  Gate fixes land once in `tools/gate-*.sh` and ship in `v1.3` before the M3 waves.
- Filed #233 (run this repo on the rendered template gate, spike first) and #234 (ancestor
  check for pinned SHAs, split from #190). Closed #190 (built) and #41 (rewrap later).
  Moved #125 to milestone 3; unmilestoned #152.
- Triage comments on #87, #102, #92, #93, #94, #96, #122, #126, #132 record the sequencing:
  the #93 + #122 trust-model decision is due 2026-10-17; the App ID stays a repo-level variable.
- First anchor for milestone 4, description sha `c2598f10…aeca0f`.

**Next:** task #87 — skip `bump-binaries.yml`'s job while the App is unprovisioned
(job-level `if:` on the repo-level `BUMP_BINARIES_APP_ID`), then the green gate,
`/way-of-working:critic-gate` (architect + security-critic) and `/way-of-working:ship`.
Model: **sonnet** (coder). `/clear` is fine.

**HITL Gate: OPEN.** First anchor for milestone 4: the owner confirms the milestone
description as anchored, then says go. Also owner-owned this sprint: the #93 + #122 decision
(by 2026-10-17).

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
