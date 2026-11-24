# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. Driver work: no lanes live; specs
for #573 and #711 wait on the maintainer's amend answers.

**Just done:**
- Merged: #712 (#694, Procedure B rewritten around `wow-publish`, `75f1174`), and the bump PRs
  #696 to #700 (tofu, npm, python, uv, betterleaks rc.10; `main` at `e088c33`). Lanes 694 and
  the earlier ones cleaned up.
- The bump PRs' first reviews ended `no-outbox` on the host; `wow-review --rerun` cleared them.
  A prompt for a claude-workbench report on that was handed to the owner.
- Filed #715 (one grouped bump PR per weekly run). Plan sprint: findings #708, #710, #713 and
  #714 went to #716 (review follow-ups) and #717 (tofu signature check in the bump job) or were
  declined, and the sources were closed. #716, #717 and #715 are M6 items 57 to 59, written with
  `milestone-desc.sh` (`live ok`).
- #711's issue body gained a settled publish shape (lane pushes everything outside `.github/`;
  the caller alone goes through `wow-publish` onto the lane branch). Its redraft escalated as
  7134190722 having dropped the byte-rule-plus-whitelist pin check; an amend answer restoring it
  is drafted.
- #573 escalated as 7134021112 (the standing of an elevated window outside Procedure B); an
  amend answer choosing option (a), untrusted outside Procedure B, is drafted.
- A note on #649: betterleaks rc.9 and rc.10 change the default rules, so the next release
  notes need the upgrade line.

**Next:** Driver, on **opus** (architect), from a new session so specs carry its `-Driver` name:
- Once the amend answers are posted, hand over `-Spec 573` and `-Spec 711`; review each posted
  or escalated spec before the maintainer reacts.
- Hand over `-Spec` for #716, #717, #715, #648 and #594 as the maintainer reacts on each issue;
  prep each approved lane with `/way-of-working:lanes start`.

**HITL Gate: OPEN** — the maintainer posts the drafted amend answers on #573 (escalation
7134021112, option a, .git/wow-answer-573.md) and #711 (escalation 7134190722,
.git/wow-answer-711.md); reacts on issues #716, #717, #715, #648 and #594 before their spec
runs; cuts a release containing 26dc53c before the #711 lane can build.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md` (M11).
- File the `wow-review` no-outbox report in claude-workbench from a workbench driver session.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
