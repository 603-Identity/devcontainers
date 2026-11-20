# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. Driver work: no lanes live; #571's
lane waits on the v0.40.0 plugin pin.

**Just done:**
- Merged from lanes: #667 (#574, retire the README's WSL section) and #668 (#424, differential
  PR Trivy gate, `5988f20`). The #668 build log showed the differential decision line, five
  `0 added` count lines and no fallback line. Both lanes cleaned up.
- #571's redraft (spec comment 7046555473) reviewed against `2a9427c` and a live read of both
  branch rulesets (no stop-rule trigger); the maintainer reacted.
- #642 escalated again (yes-keyed throw routing); the maintainer posted the amend answer
  7046906219. #665 still has no spec comment.
- PR #670 opened: way-of-working pin v0.37.0 to v0.40.0 (no `.ai/project.yml` change; the
  review gate workflow is unchanged since v0.36.0). Handed off without a critic pass (one-line
  pin bump). Its auto-merge arm was refused by the `gh pr merge` deny rule.

**Next:** Driver, on **opus** (architect):
- After #670 merges and start of day upgrades the installed plugin: start the #571 lane
  (`/way-of-working:lanes start 571 6 docs/ruleset-readback-comment architect,docs-consistency`)
  and hand over its `wowl` line.
- Review the #642 spec from `-Spec 642` and the #665 spec once posted, before the maintainer
  reacts; prep each approved lane. #665 lands after #642 (both edit Procedure B's block).

**HITL Gate: OPEN** — the maintainer approves PR #670 (pin bump, after its architect review);
runs wowl 603-Identity/devcontainers -Spec 642 under the amend answer 7046906219 and reacts after
the driver review; reacts on #665 and runs -Spec 665; decides whether to narrow the gh pr merge
deny rule so agents can arm auto-merge.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md`.
- Auto-merge: the repo allows it and `main-approval` requires a code-owner approval with no
  bypass actor; only `.claude/settings.json`'s `gh pr merge` deny rule stops an agent arming it.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
