# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review on #288 (#128).

**Just done** (coder session on sonnet, last_commit `fbe9a25`):
- #128 built and opened as PR #288 on `chore/go-1.26.8-buildkit-0.33.1`: Go 1.26.3 -> 1.26.8 and
  buildkit v0.33.0 -> v0.33.1 together (go.mod, go.sum, vendor/modules.txt, every setup-go pin,
  the gate comment in `.ai/project.yml`, the `TestBuildkitMatchesFrontend` mapping).
  `PreviousSyntax` deliberately untouched, per #128.
- Local green gate: all steps pass in WSL. The `go test` step ran with `GOTOOLCHAIN=go1.26.8`
  because WSL's Go is 1.26.3; a literal `GOTOOLCHAIN=local` run needs 1.26.8 installed first.
- Critic gate: `architect` + `security-critic`, 1 round, no blocking findings. One cosmetic nit
  (a test comment's wording) was applied without a re-run. Plan anchor re-verified `match`.

**Next:** `/way-of-working:architect-review 288`. Model: **opus** (architect), in a **new
window**: the gate needs a fresh session. #288 touches `tools/` and `.github/`, so
`architect-review` stays red until it is posted on the head SHA.

**HITL Gate: NONE OPEN.** The next gate is the owner's merge of #288. The `v1.3` tag
(build-order item 11, owner-owned) is still outstanding and does not block it.

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
