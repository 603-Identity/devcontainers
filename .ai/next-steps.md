# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review.

**Just done** (coder session on sonnet, last_commit `c6827cf`):
- #240 shipped as PR #265 (branch `ci/build-event-allowlist`): `scope` and `publish` in
  `build.yml` now guard on an event allowlist (`push`, `schedule`, `workflow_dispatch`) plus
  `refs/heads/main`. New `tools/tests/build-workflow-test.sh` pins both `if:` texts; the
  `image-scope.sh` comment no longer says a new trigger fails toward publishing.
- Local checks in WSL: gate-test suites, zizmor and shellcheck pass. The Docker steps of the
  green gate were not run locally (CI runs the build and smoke test).
- Critic pass (architect, security-critic, docs-consistency): 2 rounds, converged, all on the
  critics' default models; no second-opinion round (declined). Round 1 fixed a stale
  `image-scope.sh` comment and two test nits; round 2 was tightenings only. Not the review gate.
- Plan anchor: `plan-anchor.sh verify` printed match at resume and again at handoff, so
  milestone 4 is the approved plan and the gate from the last handoff is closed.

**Next:** `/way-of-working:architect-review 265` in a **new session**, model **opus**
(architect). The `architect-review` check stays red until it is posted on the head SHA.
After the owner merges #265, the `v1.3` release (item 11).

**HITL Gate: NONE OPEN.** Next gate: the owner's merge of #265 after the review. Also
owner-owned this sprint: the #93 + #122 decision (by 2026-10-17), the #233 spike result, the
`v1.3` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
- Place #255, #256 and #263 in a milestone (or leave them for a `/way-of-working:plan-sprint`
  pass).
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch deletes,
  so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
