# Next steps

**Now:** P0: cross-org images -- awaiting_review, milestone 1.

**Just done:**
- [#157](https://github.com/603-Identity/devcontainers/pull/157) open for #124 (head `8e2dca5`):
  the docs-only scope step is now `.github/scripts/image-scope.sh`; a new `scope` job gates
  `publish` on push to `main`; schedule, dispatch and unknown events always publish. Pinned by
  `tools/tests/image-scope-test.sh`, run by `run-gate-tests.sh`. It also closes #81 on merge.
- First CI run was red on the non-ASCII cases (character count where `fast-import` needs bytes);
  fixed in `8e2dca5`, the gate-test and selftest checks are green on it.
- Critic pass: none ran on this diff (handed off without one, by choice of the session).

**Next:** `/way-of-working:architect-review 157`, in a **new session** (fresh-session review
gate). Model: **opus** (architect). Wait for the PR's `Build and smoke-test (no push)` check to
go green first. After it merges, task #58 is next in the milestone.

**HITL Gate: OPEN** -- first anchor for milestone 1 at a review (not a task build), description
sha `ebe3ff3e…`; no baseline because this session's resume did not run `plan-anchor.sh verify`,
but a handoff-time `verify --plan` against the prior anchor printed `match`. A human "go" is needed.

**Open for the owner (non-blocking):** the first docs-only push to `main` after #157 merges is
the live proof that `publish` skips (watch the `scope` job). Amend spec §4 to the lint's wider
scope; run the tag ruleset's App-token delete negative test once the bump-binaries App exists
(#102). Still to delete in the UI: `Seuss27/devc-spike2-host` and
`glunk-works/devc-spike2-consumer`. The active `gh` account can flip to Seuss27: use the
JaredGroves-603 token for this repo's `gh` calls. Run WSL jobs from the Windows side as one
foreground `wsl` process; from Git Bash set `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
