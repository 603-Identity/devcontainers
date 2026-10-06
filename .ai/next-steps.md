# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review: PR #323 (task #102), head
`e06817d`.

**Just done** (coder session on sonnet, last_commit `0fefe75`):
- #319 merged as `0fefe75`: the bump-binaries job declares `environment: bump-binaries`, uses `client-id`
  (`BUMP_BINARIES_CLIENT_ID`, now a repo-level variable), and resolves the bot's user id for the commit email.
- First real dispatch of "Bump pinned binaries" (run 3): seven jobs passed, and the App opened #321 (uv)
  and #322 (tofu), both still open. `bump (yq)` failed with `curl: (23)`: `resolve_yq` piped curl into an
  awk that exits on its first match, so awk closed the pipe while curl was still writing and `pipefail`
  failed the step. `sha256_line` (gh, uv, tofu, tflint, node) had the same latent race.
- Built PR #323 (refs #102): checksum files are read into a variable before parsing, with `|| return 1`
  in `sha256_line` because `set -e` does not reach inside `$( )`. The asset-names test's fake curl can
  append a large body after the match and die after the body; every curl-pipe tool is run against both.
- Critic pass (architect, security-critic; no docs touched): round 1 found the lost curl exit status, which
  was fixed; the architect's round 2 on that delta found only a wrong test comment, now fixed. Local green
  gate passed in WSL (shellcheck, all gate suites). No second-opinion round was run.

**Next:** `/way-of-working:architect-review 323` on **opus** (architect), in a new window. Never approves
or merges; the owner admin-merges. Then the owner re-dispatches "Bump pinned binaries" once on `main` and
confirms every matrix job opens a bump PR or reports it is current; that closes #102. #321 and #322 are
real bump PRs that need their own review and merge.

**HITL Gate: NONE OPEN.** Next gate: the owner merges #323.

**Open for the owner (non-blocking):**
- #315 (an edited review does not re-run the gate) is in milestone 4. The `bump-binaries` Environment
  still lets admins bypass its protection rules; turning that off is optional.
- The threat model's credentials row says the App token can "merge a PR"; the ruleset only lets the admin
  role update `main`, so that likely overstates it. Worth a small docs fix.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281, #282, #297, #304 and #317 in a milestone (or leave them for a
  `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition.
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
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
