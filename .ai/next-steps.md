# Next steps

**Now:** P1: pilot adoption (milestone 2) -- implementing.

**Just done:**
- P1 planned. The owner approved the build order with #103 (adoption runbook) added as
  step 3: #5, then #10, then #103. First anchor for milestone 2, description sha `3c385bea`.
- #5 decided: option 1, raise the host GPG cache TTL. Spec recorded as
  [a comment on #5](https://github.com/603-Identity/devcontainers/issues/5#issuecomment-5961624408)
  and anchored.

**Next:** task #5 — build the host signing policy per the anchored spec comment: document
an 8h `default-cache-ttl`/`max-cache-ttl` in the host `gpg-agent.conf` in README.md's host
setup, point `images/base/files/gpg-check.sh` at it, run the green gate, then
`/way-of-working:critic-gate` (`docs-consistency` for README.md) and `/way-of-working:ship`.
Model: **sonnet** (coder).

**HITL Gate: NONE OPEN** -- the owner approved the plan and the #5 decision in-session.
Next gate: the owner merges the #5 PR.

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
