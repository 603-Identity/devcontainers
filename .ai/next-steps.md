# Next steps

**Now:** P0: cross-org images — implementing; #76 is reviewed and merged, and #77 (the docs-only skip misses quoted filenames) is next.

**Just done:**
- PR #76 (skip the image build and smoke test on docs-only PRs) reviewed in a fresh session against head `a5ecd9a`, then merged by the human (`c4baf1b`). Verdict: correct for its design. The `case` logic was run against sample diffs, and the scope step ran on a real runner (build path).
- The review found that `git diff --name-only` C-quotes non-ASCII, `"` and `\` paths, so a PR that only adds such a file under `images/` gets `build=0`. Filed as **#77** and added to milestone 1. `publish` on `main` still builds and tests before pushing, so a bad image fails there rather than shipping.
- Plan anchor re-verified against milestone 1 (`match`) and re-anchored on #77.

**Next:** task #77 — read NUL-delimited names in the `Did the images or the template change?` step of `.github/workflows/build.yml` (`git diff -z` into a file under `$RUNNER_TEMP`, fail closed on an empty file, loop with `read -r -d ''`). Prove it on the scratch-repo cases in #76's review comment, including a non-ASCII name. Then `/way-of-working:critic-gate` and `/way-of-working:ship`. Model: sonnet (coder).
- The skip path has still not run on a real runner: the first docs-only PR to merge after #76 (this cursor sync, for one) should show "Build and smoke-test (no push)" green with `build=0` and both slow steps skipped. Check it there.
- #23 stays open for its live pilot container.
- #68 (README migration seeds from `/etc/skel`; **fix before the infrastructure-core migration runs**), #69 and #58 are unmilestoned, for triage.
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gate is the fresh-session architect review of #77's PR, then the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
