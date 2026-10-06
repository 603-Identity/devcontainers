# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order steps 1-4 are merged; step 5 is next, implementing.

**Just done** (architect session on opus, last_commit `d6342db`):
- Posted the fresh-session architect-review of PR #343 (#278, gate side) at head `0b2e8b8`, executed in the WSL
  review sandbox: gate tests green, and two mutations (dropping the check; dropping the trailing-period
  alternatives) turned the matching cases red. No findings filed. `architect-review` went green; the owner merged
  it as `d6342db`. #278 stays open for the plugin half (posting with `commit_id` pinned).

**Next:** task #263 — build M4 step 5 as one PR (#199 + #200 + #220 + #263) on **sonnet** (coder), per the owner's
decision on #263 (https://github.com/603-Identity/devcontainers/issues/263#issuecomment-6020938636: fix the Entra
rule, don't record the gap). Green gate, then `/way-of-working:critic-gate` (architect + security-critic), then
`/way-of-working:ship`. Never merge; the secret-scan tag waits for `v1.4` (step 6).

**HITL Gate: NONE OPEN.** Next gates: the fresh-session architect-review of the step 5 PR and the owner's merge,
then the `v1.4` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- Place #341 in a milestone (it fits beside M4's lint work, or #234).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branches `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged) and
  `ci/gate-reviewed-against-head-278` (#343 merged), and `test/verify-pin-negative-10` on
  terraform-microsoft365-entra.
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
