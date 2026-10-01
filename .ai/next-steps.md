# Next steps

**Now:** P0: cross-org images -- implementing; next task #68.

**Just done:**
- PR #99 (#8's renewal of the Trivy exceptions to 2026-10-30) merged as `bb031ce`.
  #8 stays open for the next review before 2026-10-30.
- Ran /way-of-working:plan-sprint over the unmilestoned backlog. Added #58, #68, #69, #75,
  #98 and #101 to P0. Created milestone 4, "Repo hardening: review gate and CI" (due
  2026-12-15), with its build order in its description. Filed #102 (provision the
  bump-binaries App, after #94) and #103 (adoption runbook, P1). Every placement has a
  dated `[plan-sprint]` triage comment.
- Closed #18 and #19 as resolved by #16: `.trivyignore.yaml` has no npm entries left.
- Proposed P0 working order, which is context only because the anchored description is
  unchanged: #68, #98, #4, #75, #12, #43, #30, #53, #25, then #54/#69/#58, then #8 with
  #101 (aim for about 2026-10-23). If #98 stalls in the consumer repos, move it to P1
  and do #8 against the current pins.

**Next:** task #68 — in README.md's "Migrating from the old layout" command, replace
`cp -a /etc/skel/. /to/` with `cp -a /home/app/. /to/`, then run the local green gate and
/way-of-working:ship. Model: sonnet (coder). README.md is outside code_paths, so no
architect-review gate applies.

**HITL Gate: OPEN** -- no session-start baseline for milestone 1's plan anchor: the planning
session that wrote this cursor did not run /way-of-working:resume, so the anchor counts as a
first anchor. The description sha is unchanged (`ebe3ff3e…`), and plan-anchor.sh verify
printed `match` at handoff. A human "go" at the next resume closes it.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
