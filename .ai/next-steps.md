# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing; #164 picked, coder next.

**Just done** (architect session on opus, last_commit `1b0716f`):
- The owner picked #164 (build-order item 13): `resolve_yq` reads the tarball's hash, but the
  image pins the raw binary. Author MEMBER; the issue body is the spec (no spec comment).
- First anchor for #164 without a resume-verified baseline (resume waited on the pick before it
  verified): `verify --plan` printed `match`, description sha `8bc5e03e` unchanged.

**Next:** task #164 — make `resolve_yq` in `.github/scripts/bump-binaries.sh` read the raw
`yq_linux_amd64` hash (what `images/base/Dockerfile` checks against `YQ_SHA256`), and add a
gate-test fixture that fails when any tool's resolver asset name differs from the one the
Dockerfile downloads. Green gate in WSL, then `/way-of-working:critic-gate` (`architect` +
`security-critic`, per the milestone) and `/way-of-working:ship`.
Model: **sonnet** (coder).

**HITL Gate: OPEN.** The #164 anchor needs a human "go" (first anchor, no resume-verified
baseline). The `v1.3` tag (build-order item 11, owner-owned) is unblocked: items 4-7 are closed.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281 and #282 in a milestone (or leave them for a
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
