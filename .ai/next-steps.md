# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order step 4 (#278, gate side) is built and in review as PR #343.

**Just done** (coder session on sonnet, last_commit `0b2e8b8`):
- Built #278's gate side: `tools/gate-post.sh` requires the line `Reviewed against head <sha>` in a qualifying
  review's quote-stripped body, re-rendered into `template/` and this repo's gate, with gate-post tests, the gate
  header comment, the threat model's Known gaps and the roadmap updated. Backticks around the SHA and one trailing
  period match (the #339 review wrote ``Reviewed against head `<sha>`.``); tested both ways.
- Critic pass (security-critic, architect, docs-consistency): 2 rounds, converged; the first round's fixes
  (the trailing period, stale gate header comment, threat-model wording) were re-run clean.
- Shipped as PR #343 from `ci/gate-reviewed-against-head-278`; not merged. The plugin half of #278 (the skill posting
  with `commit_id` pinned) stays open as a Known-gaps residual, so #278 stays open.

**Next:** `/way-of-working:architect-review 343` from a NEW session on **opus** (architect), in an isolated sandbox
in WSL. Never approve, never merge.

**HITL Gate: OPEN.** The fresh-session architect-review of PR #343, then the owner's merge. Step 5 needs your call
on #263.

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
