# Next steps

**Now:** P0: cross-org images -- awaiting review, milestone 1.

**Just done:**
- Merged cursor-sync [#173](https://github.com/603-Identity/devcontainers/pull/173) (`038d7f6`)
  through `/resume`'s merge offer, the first use of the #169 hook path.
- Task #147: [#174](https://github.com/603-Identity/devcontainers/pull/174) (`4fb262c`) states
  the consumer-side tofu pin rule in `README.md` (the pin section and step 3 of "Updating a
  pinned tool"), `.github/dependabot.yml` and the PR body `bump-binaries.sh` writes. Node keeps
  "bump together"; the `# syntax=` rule is untouched. The last two were not in #147's list but
  carried the same stale rule.
- Critic pass: docs-consistency, architect and security-critic, 2 rounds, converged. The
  second-opinion round was offered and skipped. Not the fresh-session review.
- Gate: the gate tests and `go test` ran before the last two edits; shellcheck on
  `bump-binaries.sh` ran after. The docker-based entries were left to CI.

**Next:** `/way-of-working:architect-review 174` in a fresh opus session (`.github/` is a code
path), then your merge. P0 can close once #174 merges.
Model: **opus** (architect).

**HITL Gate: OPEN** -- first anchor of milestone 1 (description sha `ebe3ff3e`). This
session's `/resume` did not verify the prior anchor, so handoff had no valid baseline. Say go
to confirm.

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
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls. The
  architect-review gate counts only JaredGroves-603, so run `gh auth switch --user
  JaredGroves-603` before posting it.
- Run WSL jobs from the Windows side as one foreground `wsl` process. From Git Bash, set
  `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
