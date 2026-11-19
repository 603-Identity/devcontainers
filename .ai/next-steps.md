# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`, unparked after M5 was archived. The restored
step (PR #389) is gone: #389 closed unmerged, so M6 needs re-planning.

**Just done:**
- M5 archived and its milestone closed (#613, `a4f433c`). #600's CI Trivy evidence merged (#611, `961d771`).
- #607 merged as #616 (`83c2192`): the host start text and Rule 1 agree on `CLAUDE.md`. Re-copy the start text.
- #553 done in three PRs: the 1.29 frontend and BuildKit v0.35.0 bump (#614, `40dea5c`), the v1.9 notes (#619),
  v1.9 cut by `release.yml` at `4a01a31`, and the self-pins moved to it (#620, `5ec9ba1`). #452 closed as
  superseded by #614.
- #378 and #379 folded into #377. Its spec is approved and its lane is prepped. #423's spec escalated (see Gate).
- Critic passes, this driver session: #619 had one docs-consistency round, which found no defects; its five
  tightenings were applied. #620 (the v1.9 pins) shipped without a critic-gate pass; its fresh-session review ran.
  The lanes record their own. All critics ran on their frontmatter defaults; no second-opinion round.

**Next:** Driver, on **opus** (architect): drive the #377 lane (it closes #378 and #379). When its PR is up, run
`/way-of-working:pr-checks` and review the diff against the spec. Prep #550's lane once its spec is refreshed
and reacted to. Review #423's respec when it posts. Clean up the #553 and #607 lanes once their sessions exit.

**HITL Gate: OPEN** — M6 was unparked over a stale cursor: its restored next action named PR #389, which closed
unmerged, so the owner re-plans M6 (its build order, #397, and the merge-guard cluster: #394 versus #170, #171,
#311, #172 and #272); the owner answers #423's escalation (amend, splitting off the Dependabot-carry procedure)
and refreshes then reacts to #550's spec. Owner decisions carried from the park, not blocking:
claude-workbench#368 and the proposed #170/#171 issue edits.

**Open for the owner (non-blocking):**
- Trivy exceptions expire 2026-12-17. Check the manual `build.yml` run's `trivy-evidence` artifact, then start
  the renewal lane per `docs/trivy-renewal.md`. #612's token-reach note says the lane may need Actions read.
- Follow-ups filed by the reviews: #612 (#611's findings), the #616 and #614 review findings, including where the
  host clone sits relative to the launch folder.
- way-of-working v0.38.0 is out (pin is v0.37.0); its migration is the admin-token move (#1608).
- Leftover files under `/tmp/lanes` (`*-push`, `486-critic`, `484-host-results.md`) and old spec worktrees:
  clear them with `wowl 603-Identity/devcontainers -SpecSweep`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
