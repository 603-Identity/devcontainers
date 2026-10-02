# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1.

**Just done:**
- Fresh-session architect review of [#163](https://github.com/603-Identity/devcontainers/pull/163)
  (#58) posted. No blocking findings: the tofu `SHA256SUMS` repeat recipe was executed, and it
  verifies and fails on a wrong tag commit, an empty sha, a tampered file and a wrong pin. The
  owner merged it (`16c931f`).
- Plan-sprint triage (2026-10-02):
  - Closed #101 and #107 as completed. #145 fixed both, but its "Closes" line only closed #8.
  - P0 now holds #147.
  - #148 (Trivy exceptions expire 2026-11-01) moved to the new milestone 5, "Trivy renewal
    2026-11" (due 2026-10-29).
  - #152, #159, #160, #161 and #164 went to Repo hardening (m4). Fix #164 before #102's App
    runs.
- Opened [#166](https://github.com/603-Identity/devcontainers/pull/166): plugin pin to
  way-of-working v0.15.0 (no migration). Handed off without a critic pass on it (a one-line
  pin bump).

**Next:** task #147 — reword the tofu pin rule left in `README.md` and `.github/dependabot.yml`
to the consumer-side rule in `images/tofu/Dockerfile`, then green gate, critic-gate, ship.
Model: **sonnet** (coder). P0 can close once it merges.

**HITL Gate: OPEN** -- first anchor of milestone 1 on task #147 (description sha `ebe3ff3e`).
This session's resume did not verify the prior anchor, so handoff had no valid baseline. A
handoff-time verify of the prior anchor printed `match`. Say go to confirm.

**Open for the owner (non-blocking):**
- **#166 needs `/way-of-working:architect-review 166`** in a fresh opus session (`.claude/` is a
  code path), then your merge.
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
