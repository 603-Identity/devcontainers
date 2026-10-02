# Next steps

**Now:** P1: pilot adoption (milestone 2) -- planning.

**Just done:**
- P0: cross-org images archived and milestone 1 closed. The roadmap records P0 as done
  (#177, `0c3271d`).
- `/way-of-working:plan-sprint` placed #170, #171 and #172 (the merge-guard follow-ups) in
  milestone 4 (Repo hardening), in that order.
- Opened #178: ignore `.ai/archive/`, where archive-sprint snapshots each sprint's ledger.
- Retro routed upstream: a "confirmed again" on glunk-works/claude-workbench#209, plus new
  issues #219 (`.ai/archive/` ignore check) and #220 (plan-sprint's uncommitted ledger
  blocks archive-sprint).

**Milestone close:** closed -- milestone 1 (P0: cross-org images), 0 open issues, plan anchor verified.

**Next:** plan P1: pilot adoption (milestone 2). Confirm the build order, #5 (host signing
policy) then #10 (the pilot), pick the first task, and hand off with that task anchored.
Model: **opus** (architect).

**HITL Gate: OPEN** -- first anchor for milestone 2, description sha `e54dcdde`. Confirm the
description is the approved P1 plan.

**Open for the owner (non-blocking):**
- Merge #178, so `.ai/archive/` stops showing as untracked.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01 (milestone 5).
  Each renewal extends at most 30 days.
- Amend spec §4 to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account flips to Seuss27 mid-session: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process. From Git Bash, set
  `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
