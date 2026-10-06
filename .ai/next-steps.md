# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing; next task not yet picked.

**Just done** (architect session on opus, last_commit `2f3bacc`):
- Posted the fresh-session architect review on PR #292 (#164) against head `a1fe4f7`.
  `architect-review` went green on that SHA (commit status). Verdict: no blocking findings.
  The owner merged it as `2f3bacc`, closing #164.
- Executed in a WSL review sandbox: shellcheck clean, gate suite green, and four planted mutations
  (resolver back to the tarball, Dockerfile switched to the tarball, a tool missing from `TOOLS`,
  gh pointed at a decoy) each turned the new test red. The PR's awk filter on the real yq v4.53.6
  `checksums` returns the pinned `YQ_SHA256`.
- No findings filed. The review body states the test's limits (one fake body for every URL, the
  dispatch-line format the coverage check parses, offline only).
- Milestone 4 re-anchored without a resume-verified baseline (resume ran on `awaiting_review`, so
  it did not verify): `verify --plan` printed `match`, description sha `8bc5e03e` unchanged.

**Next:** pick the next milestone-4 task with the owner and hand it off to a coder session.
Model: **opus** (architect) for the pick.

**HITL Gate: OPEN.** The owner's pick of the next M4 task, and the `v1.3` tag (build-order
item 11, owner-owned).

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
