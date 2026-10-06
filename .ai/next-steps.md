# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order step 2 (consumer-lint bundle) is built and awaiting review.

**Just done** (coder session on sonnet, last_commit `05ed726`, the head of PR #336):
- Opened PR #336: the consumer lint now treats a bare `./`, `.` or `/` code_paths entry as the repo root, rejects
  YAML merge keys, anchors, aliases and duplicated mapping keys, rejects non-canonical code_paths entries, and
  prints job names through `tojson`. Closes #249, #251, #255, #256.
- Critic pass (`architect` + `security-critic`): 3 rounds, converged (final round tightenings only); no
  second-opinion round. It is not the review gate.
- Follow-ups filed, unmilestoned: #334 (newline in a workflow file name), #335 (misleading warning on a
  non-canonical entry).

**Next:** `/way-of-working:architect-review 336` — in a **new session** on **opus** (architect): post the
fresh-session review of PR #336 and verify the `architect-review` check is green on its head SHA. Never approve or
merge; the owner merges. After that merge, the next M4 build-order step in `docs/roadmap.md`.

**HITL Gate: OPEN.** PR #336 needs the fresh-session review, then the owner's merge.

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
