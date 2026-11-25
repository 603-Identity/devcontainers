# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. Driver work: all seven specs are
posted and reviewed; wave 1 lanes are being prepped.

**Just done:**
- v1.10 is cut (run 45617971926). The two earlier failures were dispatches on a commit before
  the notes merge and while its push runs were still in progress. #721 pinned the four
  self-pins to v1.10 (`f4a8eba`). PR #722 (README release-dispatch notes) is open.
- Specs posted, reviewed by the driver and reacted: #573, #594, #648, #711, #716, #717.
- #715 escalated (7165290493). Its amend answer is drafted in `.git/wow-answer-715.md` and is
  posted after #717 merges, because it carries #717's tofu cosign check into the redraft.
- Lane order, set by overlaps in the dev-App Exceptions bullet of `docs/threat_model.md`
  (#711, #648, #716 and #594 all edit it) and in `bump-binaries.sh` (#717, #715).

**Next:** Driver, on **opus** (architect):
- Prep lanes #711, #573 and #717 now with `/way-of-working:lanes start` (wave 1).
- After #711 merges: #648 and #716. After #716 merges: #594.
- After #717 merges: the maintainer posts the #715 answer and reruns `-Spec 715`.

**HITL Gate: OPEN** — the maintainer posts the #715 amend answer (.git/wow-answer-715.md) once
#717 merges; hand-checks the tofu 1.13.10 cosign signature on the #717 PR; runs the Procedure B
pushes for #711, #717 and #715; after #711 merges adds verify / verify to the
main-required-checks ruleset; approves and merges PR #722.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md` (M11).
- File the `wow-review` no-outbox report in claude-workbench from a workbench driver session.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
