# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `implementing`. Every M5 task has merged; the sprint closes once the roadmap marks it done. #600 on M11 is the time-critical work in flight. Milestone 6 is parked.

**Just done:**
- **#602** merged as #606 (`cce1ce6`): gh 2.105.0, and gh's CVE-2026-78661 exception is gone. **#329** merged as #608 (`18d347e`): the missing tofu 1.13.1 history entry.
- **#427** closed: staggering was a no-go, superseded by #600. **#600's** early-warning form was decided (a red check that is not required, on PRs and on the weekly and dispatch runs) and written into its issue body. Its spec was approved, then refreshed onto `18d347e` as comment 6993985602, and its lane is prepped.
- **#550:** amend answered, respec approved (6989945681). It now waits behind **#607** (filed today), which settles a root `CLAUDE.md` against the host-steps start text. #607's escalation was answered with `apply`; its respec is pending.
- **Milestones:** M10 closed (v1.8 was cut by the release workflow). #463 closed as superseded by the launcher, with #605 filed for the leftover `docs/adopting.md` text. #556 moved to M3 ahead of #26, which now targets Python 3.15. The M3, M5, M6 and M11 descriptions were updated to match.
- **Critic passes:** this driver session wrote no code. Each lane records its own critic-gate outcome.

**Next:** Driver: open a docs PR marking M5 done in `docs/roadmap.md` (last change `18d347e`, #608 for #329), with M10 done in the same PR (#486 shipped as #579). After the owner merges it, run `/way-of-working:archive-sprint` for M5. In parallel, drive #600's lane on M11: hand over the Procedure B push, then run `/way-of-working:pr-checks` and review the PR against its spec. Model: **opus** (architect, as driver).

**HITL Gate: OPEN** — the owner merges the M5 roadmap PR before archive-sprint; the owner runs the Procedure B push for #600 and approves its PR by about 2026-12-10; the owner approves the #607 respec, and #607 merges before #550.

**Open for the owner:**
- **#600 timing:** the exceptions expire 2026-12-17. The CI evidence needs #600 merged and one weekly or dispatch run before the renewal lane.
- **Host sessions after #607 merges:** user-level hooks, plugins and MCP servers (claude.ai connectors included) will stop a host session. Disable them, or launch without them.
- **The #329 lane session** may still be open. Close it so the lane can be cleaned up.
- **M6's build order** is stale beyond #607 and #550 (#553, #479, #452 and #396 are missing). Fix it at unpark.
- **Leftover lane files:** `/tmp/lanes/569-push`, `486-push`, `486-critic` and `484-host-results.md`. The permission check blocked removing them from the container.
- **Carried over:** `wow-review` posts `no-outbox` at the usage limit. Signed tags are deferred.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · host steps: [docs/host-steps.md](../docs/host-steps.md) · parked sprints: `.ai/parked/`
