# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `planning`. Milestone 9 (image bumps: node 26 and betterleaks rc.6) is archived. Milestone 6 is parked.

**Just done:**
- Milestone 9 archived: its roadmap entry merged as `bfaf673` (#482), and its final cursor is snapshotted in `.ai/archive/M9-next-steps.md`.

**Milestone close:** closed, milestone 9 "Image bumps: node 26 and betterleaks rc.6" (read-back `closed`, 0 open issues).

**Next:** plan milestone 5 (Trivy renewal 2026-11, due 2026-11-24, 2 open issues). The `.trivyignore.yaml` exceptions expire 2026-12-01 and each renewal extends at most 30 days. `/way-of-working:plan-sprint` can help triage, as a suggestion only; `/way-of-working:handoff` anchors the plan. Model: **opus** (architect).

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
