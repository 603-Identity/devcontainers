# Next steps

**Now:** P0: cross-org images -- awaiting_review; #14 is PR #89, revised after its first
fresh-session review, head `3ac5421`.

**Just done:**
- Fresh-session architect-review of PR #89 at `361b277` (the `author_association`
  check): posted, then the live `pull_request_review` run skipped the owner's own review
  as `CONTRIBUTOR`, because 603-Identity membership is private and stays private. That run
  executed the PR's own gate copy, not main's (#91).
- The same session then revised the PR, so it can no longer review it. In `3cff983` the gate
  counts a review only from a numeric user ID in `REVIEWER_IDS`, today `281693088`
  (JaredGroves-603). In `3ac5421` it ignores `> ` quoted lines, and the header comments and
  threat model are corrected. #91 is folded in.
- Critic pass on the revision (security-critic, docs-consistency): 2 rounds, converged.
  The second-opinion round was offered and declined. Local gate: hadolint, Trivy and zizmor
  ran clean; shellcheck isn't installed here, and the image build and template proof
  weren't run (no files they cover changed).
- Filed: #91 (gate header comment, closed by #89), #92 (bind a review to the head SHA),
  #93 (a PR runs its own gate copy), #94 (an allowlisted comment can be edited into a
  qualifying one by a write-access token).
- This cursor supersedes the one in PR #90; close #90 unmerged.

**Next:** `/way-of-working:architect-review 89` -- fresh session, model: opus (architect).
The review's own `pull_request_review` run is the live test of `REVIEWER_IDS`: its log must
say "Qualifying review found".

**HITL Gate: OPEN** -- no valid anchor baseline (resume doesn't run verify on an
awaiting_review cursor), so this is milestone 1's anchor again: description sha
`ebe3ff3e…`, no task issue. A verify against the prior anchor printed match at handoff.
Confirm and say "go". After that: the review of PR #89, then the human's merge.

- #8's Trivy exceptions expire 2026-10-28; tofu 1.13.0 clears 11 of 14 and must move
  with consumers' CI pins -- manual until the bump App exists.
- #23 stays open for its live pilot container. #68, #69, #58, #81, #85, #86, #87 are
  unmilestoned, for triage; so are #92, #93, #94.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
