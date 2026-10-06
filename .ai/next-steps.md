# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order steps 1-4 are merged; step 5 is open as PR #346, awaiting review.

**Just done** (coder session on sonnet, last_commit `b94ea24`):
- Built M4 step 5 as one PR, https://github.com/603-Identity/devcontainers/pull/346 (#199 + #200 + #220 + #263):
  the Entra rule treats a literal `\n`, `\r` or `\t` as a leading boundary (owner decision on #263), with a smoke
  check; `start_line` below 1 gives a file-level annotation; tests for the "incomplete scan" check and for the
  workflow's pin/event guard (new `secret-scan-guard-test.sh`, which also pins the guard's input sources).
- Green gate passed (the host's `go test` cannot run: go 1.26.3 vs `go.mod` 1.26.8; no Go change). Critic pass:
  1 round, converged (architect + security-critic, no second-opinion round); no blocking findings, the suggested
  test and comment fixes were applied. The four non-blocking findings are in the PR body.

**Next:** `/way-of-working:architect-review 346` on **opus** (architect), in a NEW session: the fresh-session
review the gate requires, at the PR's current head. Never approve or merge; the secret-scan tag waits for `v1.4`
(step 6).

**HITL Gate: NONE OPEN.** Next gates: that review, then the owner's merge of #346, then the `v1.4` tag.

**Open for the owner (non-blocking):**
- Place the #346 findings that are outside #263's spec: a second secret right after another is not reported
  (the trailing boundary eats the backslash); the guard's pin check is anchored only at the end; an unfiltered
  `err.log` tail on the did-not-complete path; the "incomplete scan" grep also reads finding records.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- Place #341 in a milestone (it fits beside M4's lint work, or #234).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged) and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- Since #336, the consumer lint rejects YAML anchors and merge keys in every workflow file; an adopter
  whose own workflows use them must write the keys out.
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
