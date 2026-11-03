# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `planning`. #418 is closed; five other issues are still open in the milestone. Milestone 6 is parked.

**Just done:**
- PR E (#468) shipped: the owner merged it as `9cbbe84`. The five self-pins name `58d54dd # v1.6`, `previous.devcontainer.json` is rotated from the v1.6 template, the adopt-only-once caveats are gone, and the roadmap marks DEVC-D9 shipped. #418 is closed.
  - The architect review was posted as a comment on #468 before the merge. Read it there for any findings it filed.
  - Handing off without a critic pass on #468 (the owner's call; the diff was mechanical).
- Hand-off note: no baseline anchor was verified this session; the milestone 8 description sha is still `259b9872…`, the same as the previous anchor.

**Next:** on **opus** (architect), decide the five issues still open in milestone 8 (#457, #446, #445, #387, #386): move them to another milestone or build them here. If the sprint is done after that, run `/way-of-working:archive-sprint`. It needs the sprint's done entry in `docs/roadmap.md` on `main` first.

**HITL Gate: NONE OPEN.** The next gate is the owner's decision on those five issues.

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- Follow-up #463: the interim devcontainer CLI entry (cutover, rebuild, working directory, Windows checks).
- Bump PRs #436 (node 26) and #438 (betterleaks rc.6) stay red and must not land until #450 and #449 do.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · parked sprints: `.ai/parked/`
