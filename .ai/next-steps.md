# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `implementing`. Milestone 6 is parked.

**Just done:**
- #418 designed. The design of record is the v4 comment on #418, after three critic rounds (architect, security-critic, docs-consistency, on frontmatter defaults, no second-opinion round) and eight owner decisions. Round 3 did not converge; its findings were text-level, and v4 folds them in without a fourth pass.
- The record was updated on GitHub:
  - #6, #395, #267 and #139 closed as superseded; milestone 7 closed;
  - #26, #27, #28, #391, #392, #393, #396 and #418 rewritten;
  - new issues filed: #439, infrastructure-core#593 and claude-workbench#1276.
- Milestone 6 parked (#440, `cfc22d8`): the owner-directed #418 takes priority.
- Planning pass: all 21 recommendations accepted. Each issue carries a `[plan-sprint]` triage comment.
  - **Milestone 8:** #386 and #387 (fixed inside PR A); #429, #431 and #432 (fixed inside PR C).
  - **Milestone 6:** the hardening and identity-rollout issues, with #397 first when it is unparked.
  - **Milestone 5:** #427.
  - **Left unmilestoned:** #126 and #132.
  - **Due dates:** milestone 5 on 2026-11-24, milestone 8 on 2026-12-18.
- First anchor for milestone 8, description sha `259b98722de5953495b6e7bc4b4c4a568229913f9483b32a1c8058761441cf47`, task #391.

**Next:** task #391. On **sonnet** (coder), build PR B, the dev-App image flavour, per section 1 and the B row of the [#418 design](https://github.com/603-Identity/devcontainers/issues/418#issuecomment-6584294809). Run `/way-of-working:critic-gate` (architect, security-critic) before `/way-of-working:ship`. PR A (#393) and PR C (#392) may run in parallel. After them: D (#392), tag v1.6, then E.

**HITL Gate: OPEN** — this is the first anchor for milestone 8 (the sha above). The owner confirms it and says go before work starts.

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01. The devapp images add `claude` to the Trivy gate, and #424 is still open. No issue tracks the renewal itself yet.
- The descriptions of milestone 5 (still about the November 1 renewal) and milestone 3 (still lists #6, now #439) are stale. They need a hand edit.
- bump-binaries PRs #436 (node 26), #437 (gh) and #438 (betterleaks rc.6) are open.
- Use the JaredGroves-603 login for this repo and Seuss27 for glunk-works. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · parked sprints: `.ai/parked/`
