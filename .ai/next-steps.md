# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing: #85 + #208 for a coder session.

**Just done** (architect session on opus, last_commit `c46372c`):
- #299 (#86) and its cursor sync #301 merged.
- The owner picked the next M4 work: #85 and #208, as one PR. Both are in
  `.github/scripts/bump-binaries.sh`, and both issue bodies give the fix shape.
- Milestone 4 re-anchored to task #85 without a resume-verified baseline (resume waited on an
  open gate, so it did not verify): `verify --plan` printed `match`, description sha `8bc5e03e`
  unchanged.

**Next:** task #85 — in one PR closing #85 and #208, in `.github/scripts/bump-binaries.sh`:
- (#85) Have each `resolve_*` set `CHECKSUM_URL` (the URL the checksum is actually read from)
  alongside `RELEASE_URL`, and add `Checksum source: $CHECKSUM_URL` to the bump PR body.
- (#208) Make `resolve_betterleaks` consider prereleases only while the current pin is
  `X.Y.Z-rc.N`, and only stable releases once it is on GA. Add a
  `tools/tests/bump-betterleaks-test.sh` case (pin `2.0.0`, only `v2.1.0-rc.1` newer) that
  expects `up to date`. Update the script header, the README's "Updating a pinned tool" section
  and the threat-model text that describe the prerelease exception.
- Run the green gate in WSL, then `/way-of-working:critic-gate` and `/way-of-working:ship`.

Model: **sonnet** (coder).

**HITL Gate: OPEN.** The milestone-4 re-anchor to #85 lacks a resume-verified baseline. The
owner's "go" releases the coder session.

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
