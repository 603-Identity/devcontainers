# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order steps 1-4 are merged; step 5 (PR #346) is reviewed and waiting on the
owner's merge.

**Just done** (architect session on opus, last_commit `ef5f90f`):
- Posted the fresh-session architect review of https://github.com/603-Identity/devcontainers/pull/346 at head
  `b94ea24`: no blocking findings. Reproduced in a WSL sandbox (gate tests, five mutations each turning a test
  red, the #263 rule against pinned Betterleaks 2.0.0-rc.1); the image smoke check was taken from CI. The
  `architect-review` gate went green on that head; `/way-of-working:pr-checks` verdict: READY (admin merge).
- Filed the PR's four non-blocking findings, unmilestoned: #348 (a second secret straight after another is not
  reported), #349 (the guard's SHA-pin check accepts a branch named `x@<40hex>`), #350 (unfiltered `err.log`
  tail on the did-not-complete path), #351 ("incomplete scan" text inside a finding record).

**Next:** once the owner has merged #346, on **opus** (architect): check that M4 steps 3-5 are all on `main`,
then prepare the `v1.4` release (M4 step 6) and stop for the owner to approve and cut the tag. The pilots
re-copy the gate and bump their pins in their own repos.

**HITL Gate: OPEN.** The owner's merge of #346:
`gh pr merge 346 --repo 603-Identity/devcontainers --squash --admin --match-head-commit b94ea2481e4f8bc0d016383c14f7b3cb541c014c`.
Then the `v1.4` tag is itself an owner gate.

**Open for the owner (non-blocking):**
- Place #348-#351 (from the #346 review) in a milestone; #349 and #350 change the tagged secret-scan surface.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- Place #341 in a milestone (it fits beside M4's lint work, or #234).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged) and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- Since #336, the consumer lint rejects YAML anchors and merge keys in every workflow file; an adopter
  whose own workflows use them must write the keys out.
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
