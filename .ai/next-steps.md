# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1.

**Just done:**
- Fresh-session architect review of [#150](https://github.com/603-Identity/devcontainers/pull/150)
  posted (no blocking findings); `architect-review` went green on `0a384e0`. The human merged
  it as `b754caa`, closing #144.
- Review reproduced the script's pin guards in WSL (traversal, injected sha, Go-version
  disagreement, missing pin all exit 1 before any download) and shellcheck clean.
- Non-blocking finding filed: [#152](https://github.com/603-Identity/devcontainers/issues/152)
  (Node upgrade in `tools/wsl-setup.sh` leaves the old npm tree behind).
- The "gate suites flaky on this Windows host" caveat is retired: run the suites in WSL
  (README "Working on this repo from Windows (WSL)").

**Next:** task #118 — fix the identity-steering hole in the template's `git-identity.sh`,
together with #69 (same script) in one PR cut from `main`; gate in WSL, critic pass, ship.
Then #124, then #58. Model: **sonnet** (coder).

**HITL Gate: OPEN** -- first anchor for milestone 1 at task #118, description sha
`ebe3ff3e…`. This session's resume could not verify the prior anchor (an `awaiting_review`
cursor never reaches that check), so the handoff has no baseline; a verify at handoff
matched. A human "go" is needed before #118 + #69 starts.

**Open for the owner (non-blocking):** amend spec §4 to the lint's wider scope; run the tag
ruleset's App-token delete negative test once the bump-binaries App exists (#102). Still to
delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. Use the
JaredGroves-603 token for this repo's `gh` calls (the default Seuss27 login has no push access
here). Long WSL runs from the Windows side need one foreground `wsl` process with its log on
the Windows side: WSL wipes `/tmp` and kills detached jobs when no session is open. From Git
Bash, set `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path to `wsl`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
