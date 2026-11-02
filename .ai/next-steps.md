# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `planning`. Milestone 6 (Internal hardening) is parked.

**Just done:**
- parked M6: Owner-directed #418 (dev-App flavour, WB-D42 route step 4) takes priority; M6's step 4 (#389) closed unmerged, resume M6 after milestone 8.
- #418 designed. Three critic rounds (architect, security-critic, docs-consistency) ran on v1, v2 and v3, all on frontmatter defaults with no second-opinion round. Round 3 was not converged; its findings were text-level, and v4 folds them in without a fourth critic pass. The owner took eight decisions. The design of record is the comment on #418 (v4, 2026-11-02).
- The record was updated on GitHub:
  - milestone 8 created, holding #418, #391, #392 and #393;
  - #6, #395, #267 and #139 closed as superseded;
  - milestone 7 closed, with #126 and #132 moved under #396;
  - #26, #27, #28, #391, #392, #393, #396 and #418 rewritten;
  - new issues: #439, infrastructure-core#593 and claude-workbench#1276.

**Next:** on **opus** (architect): `/way-of-working:plan-sprint`. Confirm milestone 8 as the sprint and its build order from the #418 design: A (#393), B (#391) and C (#392, part 1) in parallel, then D (#392), then tag v1.6, then E (self-pins and the previous-template snapshot). Place #439 and the other unmilestoned issues. Then `/way-of-working:handoff` anchors milestone 8.

**HITL Gate: NONE OPEN** — the next gate is the owner confirming milestone 8's plan in `/way-of-working:plan-sprint`, then handoff's first-anchor gate for milestone 8.

**Milestone close:** no milestone to close (previous sprint parked, not archived)

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01. The new devapp images add `claude` to the Trivy gate, and #424 is still open.
- bump-binaries PRs #436 (node 26), #437 (gh) and #438 (betterleaks rc.6) are open.
- Use the JaredGroves-603 login for this repo and Seuss27 for glunk-works. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · design: https://github.com/603-Identity/devcontainers/issues/418#issuecomment-6584294809 · parked sprints: `.ai/parked/`
