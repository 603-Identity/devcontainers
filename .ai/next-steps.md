# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `implementing`. The renewal (#484) merged as #601 (`899e0c1`), so the exceptions now expire 2026-12-17. Next on M5 is #602, then #427, #329, and #477 with #459, per the milestone's build order. Milestone 6 is parked.

**Just done:**
- **#569** (host re-scan script) shipped as #590 (`9cc7bd9`), with a fix in #596. **#582** (pin v1.8) merged.
- **#484** ran Procedure A with `tools/host/trivy-rescan.sh` at `fa72985`: exit 0, results sha256 `53de901b…`. The lane opened PR #601. The first review asked for changes because the gh entry's statement said "no fixed gh release", but gh v2.105.0 ships x/net 0.62.0. At the maintainer's direction the driver changed that one line (`86295e0`) and explained it in a PR comment. The second review passed, and #601 merged.
- **Filed:**
  - #602 (M5, item 5): bump gh to 2.105.0 and drop its CVE-2026-78661 exception.
  - #600 on new milestone M11, "Trivy renewal from CI evidence": move the no-ignore re-scan into CI and add the expiry warning, so renewals stop needing a host session.
- **M5's description:** #602 added as item 5; #427 cut down to its stagger option (its early warning moved to #600); the Plan and Critic gate lines updated to match.
- **Critic passes:**
  - #484: the lane's critic-gate outcome is recorded in its own session, not here.
  - The driver's one-line statement edit (`86295e0`) was handed off without a critic pass. The fresh-session review on #601 covered it.

**Next:** task #602 — driver: once the maintainer has reacted to #602, hand over `wowl 603-Identity/devcontainers -Spec 602`. After the spec is approved, start its lane with `/way-of-working:lanes start 602`. First, clean up the merged #484 lane. Model: **opus** (architect, as driver).

**HITL Gate: OPEN** — the maintainer reacts to #602 so spec-task can read it, then approves its spec comment; later approves and merges the #602 PR by hand.

**Open for the owner:**
- **#602:** react to the issue as JaredGroves-603, since the dev App filed it.
- **#600 (M11):** react before it is specced, and pick the early-warning form (a tracking issue or a red non-required check).
- **#427:** go or no-go on staggering expiry dates before its step starts.
- **The #484 lane session** may still be open, and its worktree is one commit behind the merged branch. Close it.
- **Leftover lane files:** `/tmp/lanes/569-push`, `/tmp/lanes/486-push` and `/tmp/lanes/486-critic` are no longer needed.
- **Carried over:**
  - #550 (M6): answer or delete escalated comment 6952215523.
  - M3's description is stale; M10 needs only its close.
  - `wow-review` posts `no-outbox` at the usage limit.
  - Signed tags are deferred.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · host steps: [docs/host-steps.md](../docs/host-steps.md) · parked sprints: `.ai/parked/`
