# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `implementing`. Milestone 6 is parked.

**Just done:**
- Task #456 shipped: the template no longer sets any VS Code settings, and VS Code attach to a dev-App container is documented as unsupported (PR #462, `cf80967`). Amends DEVC-D9 and DEVC-D3's note. #458 closed as not planned.
  - Architect review posted on #462 at its head; no blocking findings.
  - Critic pass (architect, security-critic, docs-consistency, critics' own frontmatter models, no second-opinion round): initial pass plus 4 re-run rounds; **cap reached, not fully converged**. The last edit (absolute `--workspace-folder`, run outside the checkout) and the adopting.md cutover note got no critic re-run; the review covered them. Not the review gate.
- Follow-up #463 filed: the interim devcontainer CLI entry (cutover restarts the legacy container, no rebuild procedure, `exec` working directory, Windows checks) is untested from PowerShell.

**Next:** the owner cuts the signed v1.6 tag on `main` (README Cutting a release step 1) once `build.yml` publishes green on `cf80967`; that tag closes #393. Then, on **sonnet** (coder), PR E: self-pin to v1.6, add `previous.devcontainer.json`, mark DEVC-D9 shipped, fix the roadmap Status (it still says PR D is in review), and close #418. PR E touches `code_paths`, so it needs a fresh-session `/way-of-working:architect-review`.

**HITL Gate: OPEN.** First anchor for milestone 8 in this cursor: no baseline was verified this session, though the description sha256 equals the previous anchor's. The next gates are the owner's signed v1.6 tag and the owner's merge of PR E.

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- `orchestration` is `null`, so no loop dispatches into this repo.
- Bump PRs #436 (node 26) and #438 (betterleaks rc.6) stay red and must not land until #450 and #449 do.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · parked sprints: `.ai/parked/`
