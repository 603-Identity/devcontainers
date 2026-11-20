# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. Driver work: lanes run from approved
specs; two specs are escalated to the maintainer.

**Just done:**
- Merged from lanes: #654 (#586, review gate covers `.betterleaksignore` and `rulesets/`),
  #655 (#647, renewal evidence age bound, pebble residual), #657 (#634, local mode scans every
  flavour, `7ad7835`), #660 (#570), #661 (#572), #663 (#394, merge-guard hook replaced by
  `gh pr merge` deny rules, `2a9427c`).
- #659 filed and merged as #662 (`6df2137`) through Procedure B: the first run that handed the
  owner a link to the fixed block instead of a pasted copy.
- #665 filed (Procedure B runs the reader search and stops on any hit), split out of #642.
- #642 escalated: the maintainer answered with `choice=amend`, narrowing it to parts (a) and (b).
- #571 escalated (non-converging comparison rules); the driver's proposed answer narrows it and
  stops the lane on any live-read difference. Not yet posted.
- Sessions open when #663 merged keep running the deleted hook (non-blocking errors) until they
  restart; new sessions load the deny rules.

**Next:** Driver, on **opus** (architect):
- When the #424 and #574 lane PRs are reviewed, run `/way-of-working:pr-checks` and check each
  diff against its spec. For #424, the PR build log must show the differential decision line and
  no `pull-failed` or `scan-failed` line (the decision step runs before `out/` exists).
- Review the #642 redraft, the #571 respec and the #665 spec as each is posted; prep each
  approved lane. #665 lands after #642 (both edit Procedure B's block).

**HITL Gate: OPEN** — the maintainer approves the #424 and #574 lane PRs; answers #571's
escalation (spec-task-answer, then -Spec 571); reacts on #665 and runs -Spec 665; reacts to the
#642 redraft after the driver review.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md`.
- way-of-working v0.38.0 is out (the pin is v0.37.0).

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
