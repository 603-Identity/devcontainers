# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Implementing build-order step 1, task #260.

**Just done** (architect session on opus, last_commit `d80daaf`):
- Fresh-session architect reviews on the bump PRs. The owner merged #321 (uv, `eb4baf0`), #322 (tofu,
  `62eac3e`) and #326 (yq, `d80daaf`). #102 is closed; the second bump dispatch passed every matrix job.
- `/way-of-working:plan-sprint`: every unmilestoned issue is placed, each with a dated `[plan-sprint]` triage
  comment. New milestone 6 (Internal hardening, due 2027-02-26) holds this repo's own merge-guard,
  bump-binaries, CI, test-only and docs items, moved out of milestone 4. New milestone 7 (Auto-merge
  readiness, trigger-gated) holds #267, #126 + #132 and #139 (moved from milestone 3). #329 is in milestone 5
  with #148.
- Rewrote milestone 4's description (new build order, file-bundled PRs, `v1.4`) and moved its due date to
  2026-11-13. The anchor was re-taken on this session's own edit (verify: `match`) and now names #260.
- Closed #330 unmerged; this sync replaces it.

**Next:** task #260 — on **sonnet** (coder): add a root `LICENSE` (Apache-2.0 full text, `Copyright 2026 Jared
Groves`) and a README.md license section, per the issue body. It is docs-only and outside `code_paths`, so it
needs no critic pass or review gate. Ship it as a PR; never merge. After that, milestone 4's description
gives the order (consumer-lint bundle next).

**HITL Gate: NONE OPEN.** Next gate: the owner merges #260's PR.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along.
- Milestone 4 step 5 needs your call on #263 (fix the Entra rule, or record the gap) before it is built.
  Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged), and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
