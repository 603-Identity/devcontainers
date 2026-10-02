# Next steps

**Now:** P0: cross-org images -- done. Milestone 1 has no open issues; ready to archive.

**Just done:**
- Fresh-session architect review of [#174](https://github.com/603-Identity/devcontainers/pull/174)
  (#147: the tofu pin rule in `README.md`, `.github/dependabot.yml` and the
  `bump-binaries.sh` PR body now say a consumer moves `tofu_version` in the PR that takes the
  image digest). No findings: the tree has no stale copy left, and the bump-PR text renders.
  The owner merged it (`6f63aec`).
- Merged cursor-sync #175 through `/resume`'s offer.

**Next:** `/way-of-working:archive-sprint` to retire P0 and close milestone 1.
Model: **opus** (architect).

**HITL Gate: OPEN** -- first anchor for milestone 1, description sha `ebe3ff3e`. This
session's `/resume` did not run `plan-anchor.sh verify`, so handoff had no valid baseline. The
sha matches the one you confirmed with "go" this session. Say go to confirm.

**Done here means:** milestone 1's issues are closed. No repo has adopted the template yet;
the pilots are tracked in #10.

**Open for the owner (non-blocking):**
- **Place #170, #171 and #172** in a milestone (Repo hardening, m4, fits) via
  `/way-of-working:plan-sprint`. #170 and #171 are the merge-guard hook's own security gaps.
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
