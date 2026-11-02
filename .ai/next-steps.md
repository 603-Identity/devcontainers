# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `implementing`. Milestone 6 is parked.

**Just done:**
- PR B (#391) shipped: the dev-App image flavour, `devcontainer-devapp` and `devcontainer-devapp-tofu` (#442, `3440e67`). #391 is closed.
- The architect review of #442 found nothing blocking. Two non-blocking findings are filed in milestone 8: #445 (the `claude-fetch` suite does not witness two guards) and #446 (an intermittent `check-consumer-workflows` test).
- Critic pass on #442 (earlier handoff's record):
  > architect, security-critic, docs-consistency: 3 rounds, converged; the last round returned only tightenings. Critics' own frontmatter models; no second-opinion round. Not the review gate.
- The first publish of the devapp images from `main` is the first push-mode run of the new build path; nobody has exercised it yet.

**Next:** task #393 — on **sonnet** (coder), build PR A, DEVC-D9 and the docs A owns, per section 4 of the [#418 design](https://github.com/603-Identity/devcontainers/issues/418#issuecomment-6584294809) and the issue body. Run `/way-of-working:critic-gate` (docs-consistency) before `/way-of-working:ship`.
PR C (#392) is the parallel lane. The cursor names only #393; start C in a second session, in its own git worktree, with an explicit "go" for #392 (`.ai/state.json` is git-ignored, so a fresh worktree has no cursor and resume will not auto-start there). Shared files are split by section: README's plugin-repair section and the threat model's §157-262 (A takes the auto-merge passages, C the verification rows). After A and C: D (#392 closes), tag v1.6, then E.

**HITL Gate: NONE OPEN.** The next gate is the owner's merge of each PR.

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself. The devapp images add `claude` to the Trivy gate.
- The descriptions of milestone 5 (still about the November 1 renewal) and milestone 3 (still lists #6, now #439) are stale and need a hand edit.
- `orchestration` is `null` in `.ai/project.yml`, and the sprint-orchestrator driver is not shipped, so no loop dispatches into this repo: parallel lanes are separate manual sessions.
- Use the JaredGroves-603 login for this repo and Seuss27 for glunk-works. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · parked sprints: `.ai/parked/`
