# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect session on opus, last_commit `978df75`; no code):
- #233 spike done, by reading and tracing only: result posted at
  https://github.com/603-Identity/devcontainers/issues/233#issuecomment-6004449672. No
  blocker: every PR here takes the plain-review row (no `.devcontainer/`, so never a bump
  candidate), the self-pin costs one gated bump per release (Dependabot's actions group), and
  the ruleset needs no edit (`architect-review` has no source binding).
- The owner approved the spike result on 2026-10-05, so the dogfood build goes ahead.
- Resume found git drift past `last_commit` (#268, #270 merged after the last handoff); the
  owner said go. Re-anchored milestone 4 on #233 and the spike comment.

**Next:** task #233 — build the dogfood per the issue body and the approved spike comment
(link above): replace this repo's gate with the rendered template, editing only the
`>>> CONSUMER` regions (`decide` pinned at `v1.2`, `d83d655…`); add CONSUMER-region masking to
`tools/render-gate.sh --check` and run it on this repo's copy from `render-gate-test.sh`; state
the `post` job's write scopes in `docs/threat_model.md`; update the `triggers_on` comment in
`.ai/project.yml`. Green gate in WSL, then `/way-of-working:critic-gate` (architect,
security-critic) and `/way-of-working:ship`. Model **sonnet** (coder).

**HITL Gate: OPEN.** Milestone 4 was re-anchored without a baseline the resume itself
verified (it waited on git drift and never ran `plan-anchor.sh verify`). The handoff's own
`verify --plan` printed match, description sha `8bc5e03e…`. The owner confirms with a "go" at
the next resume. After that: the owner's merge of the #233 PR after its architect review.
Owner-owned this sprint: the `v1.3` tag after items 4-7.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
- Place #255, #256 and #263 in a milestone (or leave them for a `/way-of-working:plan-sprint`
  pass). #267 is unmilestoned on purpose: it is an auto-merge (#139) precondition.
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
