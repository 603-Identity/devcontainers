# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Step 8 is built and its PR is open, waiting on the
fresh-session architect review.

**Just done** (coder session on sonnet, last_commit `89ad6b7`):
- Built M4 step 8 as PR #361 (head `89ad6b7`): `tools/check-consumer-workflows.sh` lints the gate's `on:` triggers
  (#341; a gate copied before v1.4 now fails, not warns), prints control characters as `?` so a file name cannot
  forge a `::` line (#334), and no longer double-reports a non-canonical `code_paths` entry (#335, per pattern).
  Gate tests, shellcheck and the lint's own suite pass in WSL; Docker-based gate entries were not re-run (nothing
  in the diff touches them).
- Critic pass: security-critic + architect, 3 rounds (2 fix rounds), converged; the `fable` second-opinion
  round was offered and declined. Round 2 caught a `..` defect the round-1 fix had introduced.
- Anchor: milestone 4's description sha is unchanged (`3387dd9c…`), but this handoff had no verified baseline, so the
  anchor is re-established and the gate below is open on it.

**Next:** `/way-of-working:architect-review 361` in a **new** session on **opus** (architect). The owner then
merges #361. After it: M4 step 9, if the milestone has one (read milestone 4 before assuming).

**HITL Gate: OPEN** — the fresh-session architect review of PR #361, then the owner's merge.

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

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) Â· sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
