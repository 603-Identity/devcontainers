# Next steps

**Now:** P0: cross-org images — awaiting_review; PR #79 (fixes #77, the docs-only skip missing quoted filenames) is open and needs the fresh-session architect review.

**Just done:**
- Task #77 implemented on `ci/docs-only-skip-nul-names` (`8dd9dc5`), PR #79: the `Did the images or the template change?` step reads `git diff -z` from a file under `$RUNNER_TEMP`, fails closed on an empty file, and loops with `read -r -d ''`. Case patterns unchanged.
- Proved by running the step's own `run:` block in scratch repos, old step as control: names with `"`, `\`, a newline or non-ASCII under `images/` go from `build=0` to `build=1`; docs-only stays `build=0`; a rename out of `images/` gives `build=1`; an empty diff fails closed. zizmor clean. `shellcheck` was not available locally and no script file changed.
- Critic pass: `architect` only, 2 rounds, converged (round 2 tightenings only; one wording nit accepted as-is: the comment credits `set -e` with the empty-list failure, which the explicit check gives). No second-opinion round was offered or run, and `security-critic` was not selected.
- Plan anchor re-verified against milestone 1 (`match`) and refreshed with no task issue.

**Next:** `/way-of-working:architect-review 79` in a **new session**, model opus (architect). It verifies the `architect-review` check on the head SHA and files non-blocking findings; it never approves or merges. Then the human merges.
- The skip path has still not run on a real runner: the first docs-only PR to merge after #76 should show "Build and smoke-test (no push)" green with `build=0` and both slow steps skipped. This cursor sync PR is a candidate.
- #23 stays open for its live pilot container.
- #68 (README migration seeds from `/etc/skel`; **fix before the infrastructure-core migration runs**), #69 and #58 are unmilestoned, for triage.
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gate is the fresh-session architect review of PR #79, then the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
