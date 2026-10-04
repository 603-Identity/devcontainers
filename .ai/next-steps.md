# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review on PR #243.

**Just done** (coder session on sonnet, last_commit `ac956ad`):
- Implemented #214 on branch `ci/lint-consumer-code-paths-214` and opened PR #243.
  `tools/check-consumer-workflows.sh` runs each `code_paths` entry from the consumer's own
  `.ai/project.yml` through the gate's CONSUMER `case` block and fails on `touches=0`. README
  and `docs/adopting.md` say to derive the block from the adopter's own `code_paths`.
- Critic pass (security-critic, architect, docs-consistency): 3 rounds, converged. The
  second-opinion round on `fable` was offered and declined. Not the review gate.
- Not run locally: the Docker-based green-gate entries (hadolint, Trivy, zizmor, Go tests,
  image build, `template-proof`); CI runs them. Run 37172129491 (the #238 merge push) finished
  `success`.

**Next:** `/way-of-working:architect-review 243` — post the fresh-session architect review,
verify `architect-review` went green on the head SHA, and file non-blocking findings. Never
approve, never merge. Model: **opus** (architect). Use a **new window**, not `/clear`: this
crosses the review gate.

**HITL Gate: NONE OPEN.** Owner-owned this sprint: the #243 merge, the #93 + #122 decision
(by 2026-10-17), the #233 spike result, the `v1.3` tag.

**Open for the owner (non-blocking):**
- Decide whether #240 joins milestone 4 (it touches the same guard as #160).
- Milestone 5 (Trivy renewal 2026-11) is date-bound: renew or retire the #148 Trivy exceptions
  before 2026-11-01.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch deletes,
  so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
