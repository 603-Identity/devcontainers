# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. #86 built and shipped as PR #299, awaiting the fresh-session review.

**Just done** (coder session on sonnet, last_commit `9a4ab6f`, branch `fix/bump-skip-leftover-branch`):
- `bump-binaries.sh` skips a tool whose remote `bump/<tool>-<version>` branch exists: a closed-PR leftover warns and skips, a branch with no PR (orphan) fails loudly, an `ls-remote` failure is an error. Exact ref match, `gh auth setup-git` first, never force-push or delete. New test `bump-leftover-branch-test.sh`; README note on declining a version.
- Green gate: shellcheck and `tools/tests/run-gate-tests.sh` pass in WSL. The Docker-based entries were not run locally; CI runs them.
- Critic pass (architect + security-critic): 2 rounds, converged (round 2 tightenings only; two small tightenings applied after it without a re-run). Not the review CI gate.
- Opened #299 against `main`.

**Next:** `/way-of-working:architect-review 299` in a NEW session. Model: **opus** (architect). It
posts the review, verifies `architect-review` green on the head SHA and files non-blocking
findings. Never approve or merge.

**HITL Gate: OPEN.** First anchor for milestone 4 on a non-task cursor, description sha
`8bc5e03e` unchanged, no resume-verified baseline this session: a human "go" starts the review.
Next gate: the human's merge of #299.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281, #282 and #297 in a milestone (or leave them for a
  `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition. #94 stays open (narrowed by #279, unverified).
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -`
  with a timeout works. Auto mode blocks ruleset edits, required-job removal and branch deletes, so
  switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
