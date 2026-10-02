# Next steps

**Now:** P0: cross-org images -- awaiting_review, milestone 1.

**Just done:**
- [#154](https://github.com/603-Identity/devcontainers/pull/154) open (head `be5dcf4`): `git-identity.sh`
  reads the origin with `GIT_CONFIG_GLOBAL=/dev/null` (#118), plus #69's `smoke.sh` nits and
  threat-model wording; closes #118 and #69. A new smoke case plants an `insteadOf` in
  `~/.gitconfig-identity`.
- Gate green in WSL (shellcheck, gate suites, `build-and-test.sh local`).
- Critic pass: `architect` + `security-critic`, 1 round, fixes applied, not re-run (the human
  called it; later edits were wording/whitespace). No second-opinion round. Nothing blocking;
  residual routes (env-carried git config, PATH shadowing, `.git/config`) are existing accepted gaps.

**Next:** `/way-of-working:architect-review 154` -- fresh-session review of #154; the human
merges. Then #124, then #58. Model: **opus** (architect), in a **new window**.

**HITL Gate: OPEN** -- first anchor for milestone 1, description sha `ebe3ff3e…` (no baseline:
this session's resume did not run `plan-anchor.sh verify`). A human "go" is needed.

**Open for the owner (non-blocking):** amend spec §4 to the lint's wider scope; run the tag
ruleset's App-token delete negative test once the bump-binaries App exists (#102). Still to
delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. Use the
JaredGroves-603 token for this repo's `gh` calls. Open cursor PR #153 carries the previous
ledger; this sync replaces it wholesale, so close #153 or expect a conflict on `.ai/next-steps.md`.
Run WSL jobs from the Windows side as one foreground `wsl` process; from Git Bash set
`MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
