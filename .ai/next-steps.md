# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Steps 1-8 are done; step 9 (#234) is next and starts
with its design.

**Just done** (architect session on opus, last_commit `6b28e39`):
- Fresh-session architect review of PR #361 at head `89ad6b7`: sound, no findings. Every claim was executed in a
  WSL sandbox, the new suite fails on `main`'s script, and each new guard was witnessed red by mutation.
- The owner merged #361 as `6b28e39`; #341, #334 and #335 are closed.
- Re-anchored milestone 4 on task #234. Its description sha (`3387dd9c…`) is unchanged and `plan-anchor.sh verify
  --plan` printed `match`, but this session's resume did not verify it, so the gate below names it.

**Next:** task #234 — settle the design for M4 step 9 (consumer lint: check a pinned SHA is an ancestor of
`main`) in the issue, on **opus** (architect). Propose it as an issue comment and get the owner's decision;
don't build it yet. The build then goes to **sonnet** (coder), then critic-gate (architect + security-critic),
then a fresh-session architect review.

**HITL Gate: OPEN** — the owner's decision on #234's design (the milestone makes it a human call), and the
milestone 4 re-anchor above.

**Open for the owner (non-blocking):**
- The pilots (terraform-cloudflare-dns, terraform-microsoft365-entra) re-copy the gate and re-pin to
  `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`, per the `v1.4` release notes; tracked in those repos.
- #278 stays open for its plugin half (#343 closed the gate half); consider moving it to the way-of-working
  tracker (it is the other open issue on milestone 4). #356 needs a milestone.
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
