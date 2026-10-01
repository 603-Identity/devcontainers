# Next steps

**Now:** P0: cross-org images -- implementing; #29 merged (PR #83), next is #14.

**Just done:**
- Fresh-session architect-review of PR #83 (#29's bump-binaries automation), against
  head `24f9009`: no blocking findings; every guard (input shape, downgrade, exact
  two-line `ARG` rewrite) witnessed red by mutation in the review sandbox, and 5 of 7
  resolvers reproduced the current pins' checksums byte-for-byte from live upstream.
- `shellcheck (scripts)` was red on `7d5e183` (SC2015 in `bump-binaries.sh`); a `coder`
  subagent spawned by the reviewing session fixed it as `24f9009` at the human's
  direction -- disclosed in the posted review. No critic-gate pass on that 9-line fix;
  the reviewer read it as a diff instead.
- PR #83 merged as `49985fa`; #29 closed.
- Non-blocking review findings filed: #85 (cite the checksum URL in bump PRs), #86 (a
  closed-unmerged bump PR's leftover branch jams that tool weekly), #87 (skip the job
  while the App is unprovisioned).

**Next:** task #14 — make `architect-review-gate.yml` count only a qualifying comment or
review whose `author_association` is OWNER, MEMBER or COLLABORATOR, per the issue body;
update docs/threat_model.md (the issue/PR/review-text row, boundary 6, and the Known gaps
entry #83 added on the gate's author check) to match; ship via `/way-of-working:critic-gate` then `/way-of-working:ship`. Model: sonnet (coder).
- Why #14 now: it closes the gap where #83's App token (or any commenter on this public
  repo) can satisfy the gate -- the prerequisite for provisioning the bump App.
- First anchor for milestone 1 in this cursor chain (description sha `ebe3ff3e…`, task
  #14): resume's verify printed drift and was overridden by "go", so no baseline; a
  plan-only verify at handoff printed match (description unchanged).
- #8's Trivy exceptions expire 2026-10-28; tofu 1.13.0 clears 11 of 14 and must move
  with consumers' CI pins -- a manual bump until the App exists.
- #23 stays open for its live pilot container. #68, #69, #58, #81, #85, #86, #87 are
  unmilestoned, for triage.

**HITL Gate: OPEN** -- confirm #14 is the right next task (first anchor, no prior
verify), then say "go". After that: the fresh-session architect-review of #14's PR, then
the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
