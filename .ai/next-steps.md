# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `planning`. Milestone 9 (image bumps: node 26 and betterleaks rc.6) is archived. Milestone 6 is parked.

**Just done:**
- Milestone 9 archived: its roadmap entry merged as `bfaf673` (#482), and its final cursor is snapshotted in `.ai/archive/M9-next-steps.md`.
- Backlog triaged with `/way-of-working:plan-sprint` (2026-11-03). Filed #484 (the December `.trivyignore.yaml` renewal) on milestone 5. Placed #459 and #477 on milestone 5, #463 and #475 on milestone 3, and #443, #446, #452, #460 and #479 on milestone 6. Left #126, #132, #444 (a duplicate of #446) and #480 unmilestoned on purpose. Milestone 5's description now has the build order #484, #427, #329, then #477 + #459.

**Milestone close:** closed, milestone 9 "Image bumps: node 26 and betterleaks rc.6" (read-back `closed`, 0 open issues).

**Next:** `/way-of-working:handoff` to anchor milestone 5 (Trivy renewal 2026-11, due 2026-11-24, 5 open issues) and set task #484 first. The 36 `.trivyignore.yaml` exceptions expire 2026-12-01. #427 needs the owner's pick between its early-warning and stagger options before it is built. Model: **opus** (architect) for the anchor, then **sonnet** to build.

**HITL Gate:** NONE OPEN.

**Open for the owner (non-blocking):**
- **#438** is still open and is superseded by #478. Close it.
- #463: the interim devcontainer CLI entry (cutover, rebuild, working directory, Windows checks).
- #475 and #477: node 26 follow-ups. #479 and #480: follow-ups from #478.
- The plugin pin is `v0.17.0`, and `v0.29.0` is out. Several releases in between need a migration. Bumping it is your call.
- `~/.config/glunk-identity/bin/review-gate-state.sh` comes before the plugin's own copy on PATH, and the two files differ.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · parked sprints: `.ai/parked/`
