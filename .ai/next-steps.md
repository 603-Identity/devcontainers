# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Implementing build-order step 2 (consumer-lint bundle).

**Just done** (coder session on sonnet, last_commit `77b37fb`):
- Task #260: the owner merged PR #332, so the repo has a root Apache-2.0 `LICENSE` and a README License
  section. #260 is closed; build-order step 1 is complete. Docs-only, so no critic pass ran.

**Next:** task #249 — on **sonnet** (coder): build-order step 2 as one PR in `tools/check-consumer-workflows.sh`
and its test, closing #249 + #251 + #255 + #256 (the bare `./` or `.` entry and YAML merge-key fail-open paths,
raw job-name echoes, a wrong test comment), per each issue body. It touches the consumer lint, so run
`/way-of-working:critic-gate` (`architect` + `security-critic`) before handing off. Ship it as a PR; never merge.

**HITL Gate: NONE OPEN.** Next gate: the owner merges the step 2 PR.

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

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) Â· sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
