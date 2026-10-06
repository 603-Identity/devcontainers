# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing: task #102 (bump-binaries GitHub
App), waiting on the owner's App setup.

**Just done** (architect session on opus, last_commit `6ce0f50`):
- Posted the fresh-session architect review on PR #314 (#94 fix) against head `da05a8a`. Verdict: sound,
  no blocking findings. Every gate suite was run in a WSL sandbox and five planted mutations were all caught.
  The #313 probe review's live `userContentEdits` shows Seuss27's edit, so the new check would reject it.
  The gate went green on the PR's own `pull_request_review` run.
- The owner merged #314 (`6ce0f50`); #94 is closed. The fix ships in the next release, not `v1.3`.
- Filed #317 (non-blocking): in `gate-post-test.sh`, the edit-history fixture order disagrees with
  the case names (GitHub lists newest first).
- Milestone 4: first anchor with task #102, description sha `8bc5e03e` (unchanged). There is no
  resume-verified baseline because this session's resume waited on `awaiting_review`.

**Next:** task #102 — once the owner has done steps 4-6 below, switch `bump-binaries.yml` from the
deprecated `app-id` input (`BUMP_BINARIES_APP_ID`) to `client-id`, add `environment: bump-binaries`,
update the docs, and ship it as a PR. On **sonnet** (coder). Never merge.

**HITL Gate: OPEN.** (1) #102 steps 4-6 are the owner's: create the App (`contents: write` +
`pull-requests: write`, this repo only), a `main`-restricted Environment `bump-binaries` holding the
private key, and the App's **Client ID** (not the App ID) as repo variable `BUMP_BINARIES_CLIENT_ID`.
(2) The milestone-4 anchor has no resume-verified baseline. The owner's "go" after (1) releases both.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281, #282, #297, #304 and #317 in a milestone (or leave them for
  a `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition. #315 is in milestone 4.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra, and the local
  `fix/gate-review-editor-94` here.
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
