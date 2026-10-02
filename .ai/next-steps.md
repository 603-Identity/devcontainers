# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1.

**Just done:**
- Fresh-session architect review of [#169](https://github.com/603-Identity/devcontainers/pull/169)
  (#168: a `merge-guard` hook replaces the `gh pr merge` deny rules, so `/resume` can merge a
  cursor-sync PR after your confirmation). No blocking findings: the suite was rerun and a
  planted mutation turned it red. The owner merged it (`80f26ee`).
- Filed the review's follow-ups:
  - #170: quoted, escaped, wrapped and keyword-led merges get past the hook.
  - #171: a quoted `<<WORD` or a here-string hides the lines after it.
  - #172: state the hook's residuals in its header and the threat model.

  None has a milestone yet.
- #166 (plugin pin v0.15.0) was merged earlier.

**Next:** task #147 — reword the tofu pin rule left in `README.md` and `.github/dependabot.yml`
to the consumer-side rule in `images/tofu/Dockerfile`, then green gate, critic-gate, ship.
Model: **sonnet** (coder). P0 can close once it merges.

**HITL Gate: OPEN** -- first anchor of milestone 1 on task #147 (description sha `ebe3ff3e`).
This session ran no `/resume`, so handoff had no valid baseline. A handoff-time verify of the
prior anchor printed `match`. Say go to confirm.

**Open for the owner (non-blocking):**
- **Place #170, #171 and #172** in a milestone (Repo hardening, m4, fits), via
  `/way-of-working:plan-sprint`. #170 and #171 are the hook's own security gaps. A missed
  merge still reaches the normal permission prompt.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01. Each renewal
  extends at most 30 days.
- Amend spec §4 to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account flips to Seuss27 mid-session: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process. From Git Bash, set
  `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
