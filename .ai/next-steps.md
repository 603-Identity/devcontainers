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

**Next:** task #8 — re-scan the tofu image against the latest tofu and tflint, drop
every `.trivyignore.yaml` exception that no longer matches, and renew the rest (no fixed
upstream release, at most 30 days out) before 2026-10-28 -- model: sonnet (coder). If
clearing them means bumping tofu past consumers' CI pins (1.13.0 clears 11 of 14), stop
and ask first. One PR; it touches `code_paths`, so critic gate, then a fresh-session
architect-review.

**HITL Gate: OPEN** -- first anchor for milestone 1 with a task: description sha
`ebe3ff3e…` (unchanged), task #8, no spec comment. There's no valid baseline because
this session's resume didn't run verify. Confirm, then say "go". Inside the task, a tofu
bump past consumers' CI pins is the owner's call.

- PR #90 is still open; close it unmerged, because #95 replaced it.
- #68, #69, #58, #81, #85, #86, #87, #92, #93, #94, #96 are unmilestoned, for triage.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
