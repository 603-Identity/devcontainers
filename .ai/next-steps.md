# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order step 3 merged; step 4 is next, waiting on the owner's go.

**Just done** (architect session on opus, last_commit `18cc928`):
- Posted the fresh-session review of PR #339 (no blocking findings; the suite and three guard-removal mutations
  were reproduced in an isolated sandbox in WSL). The `architect-review` check went green; the owner merged it as
  `18cc928`, closing #315, #281, #282 and #317.
- Filed the review's one non-blocking finding as #341 (the consumer lint does not check the gate's
  `pull_request_review` trigger types). It has no milestone yet.
- Re-anchored milestone 4 on task #278; the description is unchanged since the last anchor. The previous
  ledger called step 4 "#220". The milestone's build order puts #278 at step 4 and #220 in step 5.

**Next:** task #278 — build M4 build-order step 4 on **sonnet** (coder), gate-side option only: the gate also
requires the literal line `Reviewed against head ${HEAD_SHA}` in the qualifying review's quote-stripped body, in
`tools/gate-template.yml.in` / `tools/gate-post.sh`, re-rendered, with gate-post tests and the threat model's Known
gaps updated. Decide and test whether backticks around the SHA match: the #339 review wrote the line as
``Reviewed against head `<sha>`.`` Then `/way-of-working:critic-gate` and `/way-of-working:ship`. Never merge.

**HITL Gate: OPEN.** The owner confirms the start of step 4 (#278). After that: the fresh-session
architect-review of the step 4 PR, then the owner's merge.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along.
- Milestone 4 step 5 (#199 + #200 + #220 + #263) needs your call on #263 (fix the Entra rule, or record the gap)
  before it is built. Milestone 6 step 2 starts with your live App-token merge test (#327).
- Place #341 in a milestone (it fits beside M4's lint work, or #234).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged), and
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
