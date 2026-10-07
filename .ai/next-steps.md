# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Steps 1-7 are done: `v1.4` is published as an
immutable release on `9153da1`. The post-release repin PR #359 is open, awaiting the fresh-session review.

**Just done** (architect session on opus, last_commit `9153da1`):
- Reviewed PR #354 at head `78513cc` (sound, nothing blocking; every claim executed in a WSL sandbox). The
  owner merged it as `3e48929`. Filed #356 (the sibling pin guards have no regression test). Closed #200, #220
  and #263 by hand; #346's `Closes #199, #200, ...` comma list had only auto-closed #199.
- `v1.4`: release notes drafted and checked by a docs-consistency pass. The pass found that
  `docs/adopting.md` step 8 did not mention the `Reviewed against head <sha>` line, fixed in #358
  (`9153da1`). Signed tag `v1.4` → `9153da1`, published by the owner (immutable).
- Opened #359: the template's three pins and this repo's own `decide` pin move to `9153da1 # v1.4`
  (DEVC-D8). Render checks and `run-gate-tests.sh` pass in WSL. No critic pass: a mechanical pin change.

**Next:** `/way-of-working:architect-review 359` on **opus** (architect), in a NEW session, as JaredGroves-603.
This session authored #359, so it cannot review it. Never approve or merge. After the owner merges #359, M4
step 8 (task #341: #341 + #334 + #335, one PR in `tools/check-consumer-workflows.sh`) goes to a sonnet coder.

**HITL Gate: NONE OPEN.** Next gates: the review of #359 and the owner's merge, then the owner's go on step 8
(anchor task #341 at that handoff).

**Open for the owner (non-blocking):**
- The pilots (terraform-cloudflare-dns, terraform-microsoft365-entra) re-copy the gate and re-pin to
  `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`, per the `v1.4` release notes; tracked in those repos.
- #278 stays open for its plugin half (#343 closed the gate half); consider moving it to the way-of-working
  tracker. #356 needs a milestone.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged) and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
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
