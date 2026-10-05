# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect session on opus, last_commit `d334c02`):
- Posted the fresh-session architect review on #274 (#233 dogfood); the `architect-review`
  gate went green on `d3b9ec8` and the owner merged it as `d334c02`. No blocking findings.
  Both unreviewed critic fixes hold: `grep -a` is witnessed by the NUL test (a mutation
  turns it red); the `^ {18}#` pin is correct but has no test of its own and disagrees with
  the `own_arms` check, filed as #276 (low, test coverage).
- #233 is still open: #274 did not close it. Close it by hand.

**Next:** task #92 — fix #92 and #94 together, as DEVC-D7 decides: in `tools/gate-post.sh`,
count only formal PR reviews whose `commit_id` is the head SHA (comments stop counting).
Re-render `template/` and this repo's gate with `tools/render-gate.sh`, add tests, run the
green gate in WSL, then `/way-of-working:critic-gate` and `/way-of-working:ship`. Model
**sonnet** (coder). #276 can ride along.

**HITL Gate: OPEN.** First anchor for milestone 4, description sha `8bc5e03e`. This
session's resume did not verify the prior anchor; the handoff's `verify --plan` printed
`match`. Confirm the milestone 4 description is still the approved plan and that #92 + #94
comes next, then say "go". Later gates: the owner's merge of the #92/#94 PR after its
architect review; the `v1.3` tag (owner-owned, after #92 + #94 and #96).

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
- Place #255, #256, #263 and #276 in a milestone (or leave them for a
  `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge
  (#139) precondition.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` hangs under Git Bash; `gh api .../issues --input -`
  works. Auto mode blocks ruleset edits, required-job removal and branch deletes, so switch to
  manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
