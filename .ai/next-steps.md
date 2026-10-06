# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing #86.

**Just done** (architect session on opus, last_commit `6eadcc4`):
- Fresh-session architect review of #295 (v1.3 repin + DEVC-D8). No blocking findings. The
  sandbox run, the gate tests and two planted mutations all behaved. The owner merged it as
  `6eadcc4`.
- Filed #297 (non-blocking): an immutable release's tag can still be deleted by deleting the
  release first, so "admins included" overstates it. Also, `v1.0` is lightweight too.
- The owner picked #86 as the next M4 task, with the fix of skipping a tool whose remote
  `bump/<tool>-<version>` branch already exists.
- Milestone 4 re-anchored on #86 without a resume-verified baseline: `verify --plan` printed
  `match`, description sha `8bc5e03e` unchanged.

**Next:** task #86 — in `.github/scripts/bump-binaries.sh`, skip a tool with a notice when its
remote `bump/<tool>-<version>` branch already exists (`git ls-remote --exit-code origin
refs/heads/$branch`), alongside the open-PR skip. Never force-push or delete the branch. Add a
gate test for the leftover-branch case, run the green gate, then `/way-of-working:critic-gate`
and `/way-of-working:ship`. Model: **sonnet** (coder).

**HITL Gate: OPEN.** The re-anchor above: a human "go" starts #86. Next gate: the architect
review of #86's PR.

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
