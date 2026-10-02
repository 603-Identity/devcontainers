# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1.

**Just done:**
- Fresh-session architect review of [#154](https://github.com/603-Identity/devcontainers/pull/154)
  (head `be5dcf4`): no blocking findings, nothing filed. The new smoke case was witnessed by
  mutation: with the `GIT_CONFIG_GLOBAL=/dev/null` origin read reverted, it goes red
  (`other -> b.gitconfig`). The gate went green and the human merged it as `1c6b4a0`, closing #118 and #69.
- Old cursor PR #153 closed.

**Next:** task #124 — make `build.yml` publish on push to `main` only when an image-affecting
path changed (the weekly schedule and manual dispatch still publish), reusing the PR docs-only
scope step, with a test. Then #58. Model: **sonnet** (coder).

**HITL Gate: OPEN** -- first anchor for milestone 1 at task #124, description sha `ebe3ff3e…`
(no baseline: the review session's resume did not run `plan-anchor.sh verify`; a handoff-time
`verify --plan` against the prior anchor printed `match`, so the description is unchanged). A human "go" is needed.

**Open for the owner (non-blocking):** amend spec §4 to the lint's wider scope; run the tag
ruleset's App-token delete negative test once the bump-binaries App exists (#102). Still to
delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. Use the
JaredGroves-603 token for this repo's `gh` calls. Run WSL jobs from the Windows side as one
foreground `wsl` process; from Git Bash set `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
