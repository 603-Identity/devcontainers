# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review: PR #314 (#94 fix), head
`da05a8a`; task #102 follows it.

**Just done** (coder session on sonnet, last_commit `d6625d1`):
- Resumed on #102 and found its sequencing precondition unmet: #94 had to land before the bump-binaries
  App exists (the App token is exactly #94's attacker).
- Probed #94 on a throwaway PR (#313, closed, branch deleted): a non-admin writer (Seuss27) can `PUT`
  another account's formal review body and `PATCH` their comment, leaving author, state and `commit_id`
  unchanged. So the residual was real.
- Built the fix as PR #314 (`Closes #94`): the gate reads each qualifying review's GraphQL
  `userContentEdits` and requires every editor in `REVIEWER_IDS`; a long history, a deleted revision, an
  unreadable editor or a failed lookup fails closed. Ships in the next release, not `v1.3`.
- Critic pass (security-critic, architect, docs-consistency): 3 rounds, converged; second-opinion round
  offered and declined. Local green gate passed: gate suites in WSL, shellcheck, zizmor.
- Filed #315 (an edited review does not re-run the gate) in milestone 4.

**Next:** `/way-of-working:architect-review 314` on **opus** (architect), in a new session. Never
approves or merges; the owner admin-merges.

**HITL Gate: NONE OPEN.** Next gate: the owner merges #314.

**Open for the owner (non-blocking):**
- Task #102 steps 4-6 wait on #314 merging: create the App (`contents: write` + `pull-requests: write`,
  this repo only), a `main`-restricted Environment holding the private key, `BUMP_BINARIES_APP_ID` as a
  repo variable; then a coder PR adds `environment:` to `bump-binaries.yml` and updates the docs.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281, #282, #297 and #304 in a milestone (or leave them for a
  `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- The local plugin cache runs way-of-working 0.14.0 while `.claude/settings.json` pins v0.16.0;
  refresh the plugin so `/resume` uses the `--admin` merge shape #307 admits.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works. Auto mode blocks ruleset edits, branch deletes,
  and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
