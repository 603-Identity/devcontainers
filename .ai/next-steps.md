# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Task #102 is closed, and no next task is
picked yet.

**Just done** (architect session on opus, last_commit `d80daaf`):
- Posted fresh-session architect reviews (comment only) on the three bump PRs. Each was untrusted (App author), so
  each was reviewed without local execution: the sha256 was checked against the upstream checksum file by hand, and
  the build and smoke results came from CI witness runs. The owner merged #321 (uv 0.12.23, `eb4baf0`), #322
  (tofu 1.13.1, `62eac3e`) and #326 (yq 4.54.1, `d80daaf`).
- The #102 fix is proven end to end: the second "Bump pinned binaries" dispatch, on `742221f`, passed every
  matrix job, and #326 was its yq PR.
- Filed #329 (unmilestoned): after #322, `.trivyignore.yaml:16` and the tofu Dockerfile's version history
  still name 1.13.0 as the pin. The tofu `SHA256SUMS` signature record still covers 1.13.0 only, which
  README's checklist allows. Re-running cosign is optional.

**Next:** on **opus** (architect), with the owner, pick the next milestone-4 task (the milestone's open
issues are the candidates; #327 and #310 are small docs fixes). Then write its spec on the issue and hand
off to a coder session with a `task #N — ` cursor.

**HITL Gate: OPEN.** The owner picks the next milestone-4 task. No task is anchored, so resume waits.

**Open for the owner (non-blocking):**
- #315 (an edited review does not re-run the gate) and #327 (the App-token wording, with a live test) are in
  milestone 4. The `bump-binaries` Environment still lets admins bypass its protection rules; turning that
  off is optional.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281, #282, #297, #304, #317 and #329 in a milestone (or leave them for
  a `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
