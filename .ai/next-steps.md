# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, ending in `v1.4`. Steps 1-5 are merged; step 6 (the
secret-scan follow-ups) is built and open as PR #354, awaiting the fresh-session review.

**Just done** (coder session on sonnet, last_commit `78513cc`):
- Built step 6 as one PR: #348 (trailing boundary dropped, two smoke checks, rule comment), #349 (pin guard
  `^[^@]+@[0-9a-f]{40}$`, also applied to `verify-devcontainer-image.yml` and
  `devcontainer-bump-decision.yml` at the owner's call), #350 (stderr reduced and prefixed) and #351
  (finding records skipped in the incomplete-scan check). PR #354 closes #348-#351.
- Green gate passed locally in WSL, except `go test` for `devc-verify` (WSL Go 1.26.3 < the module's 1.26.8;
  untouched by this diff, CI covers it).
- Critic pass: `security-critic` + `architect`, 1 fix round, converged (all models at their frontmatter
  defaults; no second-opinion round).
- Milestone 4 anchor re-verified (`match`); it now carries no task issue.

**Next:** `/way-of-working:architect-review 354` — on **opus** (architect), in a NEW session, as
JaredGroves-603 (the gate counts only that reviewer). Never approve or merge. The owner merges #354, then
owns `v1.4` (step 7); never tag or release without the owner.
Known leftovers, non-blocking: `err.log` is still grepped raw for `incomplete scan` (fails closed, only
mislabels); the sibling pin guards have no tests of their own.

**HITL Gate: NONE OPEN.** Next gates: the architect review of #354 and the owner's merge, then the `v1.4` tag.

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

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) Â· sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
