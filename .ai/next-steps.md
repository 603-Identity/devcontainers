# Next steps

**Now:** Milestone 9, image bumps for node 26 and betterleaks rc.6, `implementing`. Milestone 6 is parked.

**Just done:**
- Milestone 8 (#418) is archived and closed on GitHub, after the roadmap's done entry merged (#472, `0b4544d`). Its leftovers closed through #470 (#457, #386, #387) and #471 (#445); #446 moved to the backlog.
- Created milestone 9, "Image bumps: node 26 and betterleaks rc.6", with #450 and then #449 in it. Its goal is to unblock the red bump PRs #436 and #438.
- First anchor for milestone 9, description sha `41810cec`.

**Next:** task #450 — install `libatomic1` in the node image (or in `base`, if that is where it belongs) so node 26 loads. Record the reason in the Dockerfile, check the Trivy gate and the image size, and run the green gate in WSL. Then `/way-of-working:critic-gate` and `/way-of-working:ship`. Model: **sonnet** (coder). `images/` is a code path, so the PR needs a fresh-session `/way-of-working:architect-review`.

**HITL Gate: OPEN** — first anchor for milestone 9, description sha `41810cec`. Confirm the milestone description is the approved plan. When to move consumers to node 26 is out of scope and stays your call.

**Open for the owner (non-blocking):**
- **Date-bound:** the `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- #463: the interim devcontainer CLI entry (cutover, rebuild, working directory, Windows checks).
- The plugin pin is `v0.17.0`; `v0.29.0` is out, and several releases in between need a migration (new `identities` and `agents.diff_rule` keys, renamed labels, a reach-gate hook). Bumping it is your call.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/9 · parked sprints: `.ai/parked/`
