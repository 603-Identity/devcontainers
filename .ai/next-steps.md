# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Steps 1-8 are done; step 9 (#234) is open as PR #365,
fixed and waiting for its fresh-session architect review.

**Just done** (coder session on sonnet, `810b219`):
- Fixed the red `shellcheck (scripts)` check on PR #365: `lint_up` now uses `"$WF"` (SC2120). The check is green on
  head `810b219`, and every required check except `architect-review` is green. The PR body's "shellcheck clean" is
  now true, so it was left as is.
- No critic pass ran on this one-line fix; #365's own critic pass ran in its build session (architect +
  security-critic + docs-consistency, 2 rounds, converged).
- Re-anchored milestone 4: description sha `3387dd9c…` unchanged, but this session did not verify the prior anchor
  and the new anchor carries `task_issue: null`, so the gate below names it.

**Next:** `/way-of-working:architect-review 365` — on **opus** (architect), in a NEW window: the fresh-session
review of PR #365 (task #234) at head `810b219`. Verify the `architect-review` check goes green on the head SHA.
Never approve, never merge.

**HITL Gate: OPEN** — the milestone 4 re-anchor above (first anchor, `task_issue: null`); the owner's "go" clears
it. Next gate: the owner's merge of #365 once the review is posted and every required check is green.

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
