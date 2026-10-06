# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order step 2 merged; step 3 is next, waiting on the owner's go.

**Just done** (architect session on opus, last_commit `e6f753d`):
- Posted the fresh-session review of PR #336 (no blocking findings; the suite and four guard-removal mutations
  were reproduced in an isolated sandbox). The `architect-review` check went green; the owner merged it as
  `e6f753d`, closing #249, #251, #255 and #256.
- Re-anchored milestone 4 on task #315; the description is unchanged since the last anchor.

**Next:** task #315 — build M4 build-order step 3 (#315 + #281 + #282 + #317) as one PR in
`tools/gate-template.yml.in`, re-rendered, on **sonnet** (coder). Then `/way-of-working:critic-gate`
(`architect` + `security-critic`) and `/way-of-working:ship`. Never merge.

**HITL Gate: OPEN.** The owner confirms the start of step 3 (announced at the step 2 handoff). After that: the
fresh-session architect-review of the step 3 PR, then the owner's merge.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along.
- Milestone 4 step 5 needs your call on #263 (fix the Entra rule, or record the gap) before it is built.
  Milestone 6 step 2 starts with your live App-token merge test (#327).
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
