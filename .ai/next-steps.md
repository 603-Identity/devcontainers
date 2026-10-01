# Next steps

**Now:** P0: cross-org images -- awaiting_review; #29 built as PR #83, next is the
fresh-session architect-review.

**Just done:**
- Implemented task #29 (`.github/workflows/bump-binaries.yml` +
  `.github/scripts/bump-binaries.sh`): resolves each ARG-pinned binary's (gh, yq, uv,
  tofu, tflint, node, npm) newest release, takes the checksum from that release's own
  published file, and opens one PR per tool via a scoped GitHub App token. README.md,
  docs/threat_model.md and .github/dependabot.yml updated to match.
- `/way-of-working:critic-gate` (security-critic + docs-consistency, opus): 2
  fix-and-re-run rounds, converged. Round 1: a confirmed command-injection PoC
  (unvalidated upstream data reaching a `sed` rewrite while holding a write token) and
  the App token's self-merge reach given this repo's 0-required-approvals ruleset --
  both fixed. Round 2's fixes introduced 2 more real issues, also fixed; round 3
  confirmed clean. Declined the optional `fable` second-opinion round.
- Shipped as PR #83 (`7d5e183`), labeled `chore` + `area/ci`.
- Left as documented Known gaps, not folded into #29: the App token's self-merge reach
  (a human decides whether to raise `required_approving_review_count` or check comment
  authorship in `architect-review-gate.yml`), and the App itself not yet provisioned
  (`BUMP_BINARIES_APP_ID`/`BUMP_BINARIES_APP_PRIVATE_KEY` unset -- the workflow can't
  run for real until a human creates it).

**Next:** Post the fresh-session architect-review for PR #83
(`/way-of-working:architect-review 83`). Model: opus (architect). Never merge -- the
human merges once the review and every required check are green.
- First anchor for milestone 1 in this cursor chain (description sha `ebe3ff3e…`, no
  task issue -- this is a review step, not a task build): this session's resume
  checked #29's anchor by hand rather than via `plan-anchor.sh verify`, so a human
  should confirm the milestone 1 plan still holds.
- #23 stays open for its live pilot container.
- #68 (README migration seeds from `/etc/skel`; fix before the infrastructure-core
  migration runs), #69, #58 and #81 are unmilestoned, for triage.
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must
  move with the consumers' CI pins (#29's own dry-run testing confirmed tofu's upstream
  newest is already 1.13.0; the Dockerfile itself was not touched by #29).
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core
  (DEVC-D1).

**HITL Gate: OPEN** -- confirm the milestone 1 plan still holds (first anchor in this
cursor chain, no prior verify), then say "go" before the next session's review
auto-starts. The gate after that is the human's merge of PR #83 once the review and
checks are green.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1 · PR:
https://github.com/603-Identity/devcontainers/pull/83
