# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Steps 1-8 are done; step 9 (#234) is built and open
as PR #365, awaiting its fresh-session architect review.

**Just done** (coder session on sonnet, last_commit `736047f`, PR #365 head):
- Built #234 per the [settled design](https://github.com/603-Identity/devcontainers/issues/234#issuecomment-6037027799)
  in `tools/check-consumer-workflows.sh`, its tests, and the header, `docs/adopting.md`, `docs/threat_model.md`
  and README edits. Resume's `plan-anchor.sh verify` printed `match`, which cleared the re-anchor gate.
- Critic pass on the diff (architect, security-critic, docs-consistency): 2 rounds, converged (round 2
  tightenings only); no second-opinion round. Declined tightenings: also clearing `GIT_GRAFT_FILE`/`GIT_SSL_*`
  from git's env, and rejecting a `//host/share` override path.
- The lint covers only the verify, decide and secret-scan pins, as designed; other `uses:` references to this
  repo are not checked.

**Next:** `/way-of-working:architect-review 365` on **opus** (architect), in a **new session**: post the review
on PR #365's head, verify `architect-review` goes green on that SHA, file non-blocking findings. The human then
merges.

**HITL Gate: NONE OPEN.** Next gate: the human's merge of #365.

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
