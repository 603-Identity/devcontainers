# Next steps

**Now:** P0: cross-org images -- implementing; #14 is merged (PR #89).

**Just done:**
- Fresh-session architect-review of PR #89 at `3ac5421`. The live `pull_request_review`
  run logged "Qualifying review found", so `REVIEWER_IDS` works. The human merged it
  (`8e1d252`).
- Filed #96: the numeric uid test in the gate is load-bearing (it stops a missing ID
  matching a doubled space in `REVIEWER_IDS`), and the comment doesn't say so.
- Filed 603-Identity/terraform-cloudflare-dns#43: that repo's gate, the source of this one,
  counts a review from anyone.
- Closed #23 (owner's choice). Its met items are ticked, with evidence in a comment:
  `tests/smoke.sh`, `tests/template-proof.sh` (both run in `build.yml`), the README and
  the threat model. The empty `docker diff` on a pilot container moved to #10, whose
  volume bullet now describes the new layout.

**Next:** pick the next P0 issue from milestone 1 -- model: opus (architect). #8 has a
deadline: its Trivy exceptions expire 2026-10-28.

**HITL Gate: OPEN** -- (1) no valid anchor baseline (resume doesn't run verify on an
awaiting_review cursor), so this is milestone 1's anchor again: description sha
`ebe3ff3e…`, no task issue, unchanged since the last handoff. (2) Which P0 issue is
next is the owner's call. Confirm both, then say "go".

- PR #90 is still open; close it unmerged, because #95 replaced it.
- #8's Trivy exceptions expire 2026-10-28; tofu 1.13.0 clears 11 of 14 and must move
  with consumers' CI pins -- manual until the bump App exists.
- #68, #69, #58, #81, #85, #86, #87, #92, #93, #94, #96 are unmilestoned, for triage.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
