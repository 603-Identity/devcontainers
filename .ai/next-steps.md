# Next steps

**Now:** P0: cross-org images — implementing; #77 merged (PR #79), task #29 next.

**Just done:**
- PR #79 (#77, NUL-delimited names in the docs-only skip) got its fresh-session architect review (opus) on `8dd9dc5`. The `architect-review` gate went green, and the PR merged as `7348579`. The review reproduced every proof case against `main` as a control, with trees built by `git fast-import` so they could hold `"`, `\`, newline and tab names. Removing `-z`, `read -d ''` or the `[ ! -s ]` guard each reintroduced the bug.
- Non-blocking finding filed as #81: nothing in the repo tests the scope step, and a regression in it leaves every required check green.
- No code written this session, so no critic pass.

**Next:** task #29 — automate the ARG-pinned binary bumps with upstream checksums (a `bump-binaries` workflow), per the issue body. Model: sonnet (coder). Ship it as its own PR via `/way-of-working:critic-gate` then `/way-of-working:ship`; never merge.
- First anchor for milestone 1, description sha `ebe3ff3e…`, task #29. This session's resume didn't verify the prior anchor, though a re-check at handoff printed `match`.
- The skip path has still not run on a real runner. This cursor-sync PR is the first docs-only PR since #76 and should show `build=0`.
- #23 stays open for its live pilot container.
- #68 (README migration seeds from `/etc/skel`; **fix before the infrastructure-core migration runs**), #69, #58 and #81 are unmilestoned, for triage.
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: OPEN** — confirm milestone 1's description and #29 as the next build (first anchor in this cursor chain), then say "go". The gate after that is the fresh-session architect review of #29's PR.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
