# Next steps

**Now:** P0: cross-org images -- awaiting_review; #14 implemented, PR #89 open.

**Just done:**
- #14 implemented as PR #89 (`361b277`): `architect-review-gate.yml` counts a comment or
  review only from an OWNER, MEMBER or COLLABORATOR (fails closed; a skipped match is
  logged with its association). `docs/threat_model.md` updated: the issue/PR/review-text
  row, boundary 6, the Known gaps entry, plus a new Known gaps entry for the
  committer-date reuse path.
- Critic pass (security-critic, architect, docs-consistency): 2 rounds, converged
  (initial + 1 fix round, tightenings-only); no second-opinion round. Wording-only edits
  to the Known gaps bullet landed after the last re-run. Local gate: zizmor only.
- Not fixed, documented in the threat model: reviews are dated by the head commit's
  committer date (backdatable); a same-repo branch can edit the gate in its own PR.
  Follow-up issues not yet filed.

**Next:** `/way-of-working:architect-review 89` -- fresh session, model: opus (architect).
Also check, on the PR's own `pull_request` run after the review is posted, that the log says
"Qualifying review found": the Actions token may read the owner's private org membership as
CONTRIBUTOR and skip the review (fails closed, would block merge).

**HITL Gate: OPEN** -- first anchor for milestone 1 in this cursor chain (description sha
`ebe3ff3e…`, no task issue): no baseline verify ran this session. Confirm and say "go";
after that, the review of PR #89, then the human's merge.

- #8's Trivy exceptions expire 2026-10-28; tofu 1.13.0 clears 11 of 14 and must move
  with consumers' CI pins -- manual until the bump App exists (its #14 prerequisite lands
  with PR #89).
- #23 stays open for its live pilot container. #68, #69, #58, #81, #85, #86, #87 are
  unmilestoned, for triage.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
