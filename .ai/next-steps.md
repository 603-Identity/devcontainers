# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review: PR #319 (task #102), head
`40adb55`.

**Just done** (coder session on sonnet, last_commit `6ce0f50`):
- #94 merged as `6ce0f50` (PR #314): the gate requires every editor in a review's edit history to be in
  `REVIEWER_IDS`. That was #102's sequencing precondition.
- The owner created the `603-bump-binaries` App, installed it, and set up the `bump-binaries` Environment
  (restricted to `main`, holding the key). Verified read-only: `BUMP_BINARIES_CLIENT_ID` is now a
  **repo-level** variable and the Environment copy is gone (it had been on the Environment, which a
  job-level `if:` cannot see).
- Built PR #319 (refs #102): the job declares `environment: bump-binaries`, uses `client-id`, and
  resolves the bot's user id (`gh api /users/<slug>[bot]`) for the commit email; `APP_ID` became
  `BOT_USER_ID` in the script and three tests; threat model and README updated.
- Critic pass (security-critic, architect, docs-consistency): 2 rounds, converged; second-opinion round
  offered and declined. Local green gate passed: gate suites in WSL, shellcheck, zizmor.

**Next:** `/way-of-working:architect-review 319` on **opus** (architect), in a new window. Never approves
or merges; the owner admin-merges. Then the owner dispatches "Bump pinned binaries" once on `main` and
confirms every matrix job opens a bump PR or reports it is current; that closes #102.

**HITL Gate: NONE OPEN.** Next gate: the owner merges #319.

**Open for the owner (non-blocking):**
- #315 (an edited review does not re-run the gate) is filed in milestone 4. The Environment still lets
  admins bypass its protection rules; turning that off is optional.
- The threat model's credentials row says the App token can "merge a PR"; the ruleset only lets the admin
  role update `main`, so that likely overstates it. Worth a small docs fix.
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
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
