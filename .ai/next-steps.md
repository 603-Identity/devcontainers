# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. M6's re-planned build order is applied;
specs for its first three items are being drafted.

**Just done:**
- M6's new description applied (the text staged on #126, sha256 prefix `dd922af1a13a4a82`); the
  plugin's parser reads its build order. `lane.sh groups 6` reads `group none` until specs exist.
- Closed as superseded: #578, #170, #171, #311, #172 and #272 (into #394), #152 (into #574). Closed
  as done: #397 (the re-plan) and #588 (covered by #637, `5a76663`). #531 was already closed.
- #652 (`bce4da2`) merged: the 2026-11-20 findings-mode and plan-sprint passes (M6 and M3 triage,
  M3's order written live).
- Spec sessions launched by the maintainer for #586, #634 and #647.

**Next:** Driver, on **opus** (architect):
- When the spec sessions report posted comments for #586, #634 and #647, review each (lanes skill,
  *Review the posted spec*) and advise the maintainer on approval.
- After each approving reaction, prep its lane on milestone 6, hand over the `wowl` lane command,
  start `lane.sh wait`, then run `lane.sh groups 6`.
- #647 should land before the Trivy exceptions' renewal (expiry 2026-12-17).

**HITL Gate: OPEN** — the maintainer reacts to each posted spec comment for #586, #634 and #647
after the driver review (#586, #570, #572 and #642 also need a fresh maintainer reaction on the
issue itself, since the 2026-11-20 folds edited their bodies); the owner re-copies the host-steps
start text from main, which now names only procedure A.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md`.
- way-of-working v0.38.0 is out (the pin is v0.37.0). Its migration is the admin-token move (#1608).
- Leftover spec worktrees under `/tmp/lanes`: clear them with `wowl 603-Identity/devcontainers -SpecSweep`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
