# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, ending in `v1.4`. Build-order steps 1-5 are merged;
step 6 (the secret-scan follow-ups) is ready to implement.

**Just done** (architect session on opus, last_commit `0f909f7`):
- The owner merged step 5, PR #346, and its cursor-sync PR #352.
- The owner decided to fix #348, not record it: drop the trailing boundary group from
  `org-azure-ad-client-secret`. Recorded at
  https://github.com/603-Identity/devcontainers/issues/348#issuecomment-6025865438.
- First anchor for milestone 4 in this cursor, description sha `3387dd9c…`. This session's resume did not
  verify the prior anchor; `plan-anchor.sh verify --plan` printed `match` at handoff. The anchor now names
  #348 and the decision comment.

**Next:** task #348 — on **sonnet** (coder), build M4 step 6 as one PR from `main`: #348 per the owner
decision above (remove the trailing boundary group, add two smoke checks, update the rule comment), plus
#349, #350 and #351 per their issue bodies. Then run the green gate, `/way-of-working:critic-gate` and
`/way-of-working:ship`. `v1.4` (step 7) waits for step 6; never tag or release without the owner.

**HITL Gate: OPEN.** First anchor for milestone 4 in this cursor (see Just done): the owner confirms with a
"go" in the next session. Then the architect review of the step 6 PR; the `v1.4` tag is itself an owner gate.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged) and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- Since #336, the consumer lint rejects YAML anchors and merge keys in every workflow file; an adopter
  whose own workflows use them must write the keys out.
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
