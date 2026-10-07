# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Steps 1-7 are done and the template pins `v1.4`.
Step 8 is next, waiting on the owner's go.

**Just done** (architect session on opus, last_commit `34f3f5e`):
- Reviewed PR #359 at head `ef202a6` (sound, no findings; every claim executed in a WSL sandbox, both pin
  guards witnessed red by mutation). The owner merged it as `34f3f5e`: the template's three pins and this
  repo's own `decide` pin now name `9153da1 # v1.4`.
- Anchored task #341 for M4 step 8 (first task anchor on milestone 4; its description re-verified unchanged).

**Next:** task #341 — build M4 step 8 (#341 + #334 + #335) as one PR in `tools/check-consumer-workflows.sh` and
its test, on **sonnet** (coder). Run the gate tests in WSL, then `/way-of-working:critic-gate`, then
`/way-of-working:ship`; the PR body says `Closes #341, closes #334, closes #335`.

**HITL Gate: OPEN** — the owner's go on step 8 (task #341, anchored for the first time at this handoff).
Next gate after that: the fresh-session architect review of the step 8 PR.

**Open for the owner (non-blocking):**
- The pilots (terraform-cloudflare-dns, terraform-microsoft365-entra) re-copy the gate and re-pin to
  `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`, per the `v1.4` release notes; tracked in those repos.
- #278 stays open for its plugin half (#343 closed the gate half); consider moving it to the way-of-working
  tracker. #356 needs a milestone.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged), the other stale
  local `docs/sync-cursor-*` branches the prune skips, and `test/verify-pin-negative-10` on
  terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in WSL, not Git Bash, from a
  CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -` with a
  timeout works (build the JSON with `jq`). Write `Closes #A, closes #B`, never a bare comma list.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
