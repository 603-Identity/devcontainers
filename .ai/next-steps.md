# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect review session on opus, last_commit `75ac3ea`):
- Fresh-session architect review of PR #248 (#245) posted. It found no blocking issues, and
  the PR's own claim reproduced in the WSL sandbox: the new tests fail with the fix mutated out.
  The gate went green and the owner merged it (`75ac3ea`).
- Filed #251 (non-blocking): the new test's comment still says the gate sees `git diff` paths;
  it reads the GitHub files API. Can ride along with #249.

**Next:** task #202 — make the consumer-lint caller rules (`tools/check-consumer-workflows.sh`,
rule 4) allowlist the `verify` job's keys, with a test for an unexpected key; run the green gate
and `/way-of-working:critic-gate` (architect + security-critic), then `/way-of-working:ship`.
Model: **sonnet** (coder). After it, #198 and #240 are the other coder items that don't wait on
items 4 and 5 (build order is in the milestone description).

**HITL Gate: NONE OPEN.** The next gate is the owner's merge of #202's PR after a fresh-session
architect review. Also owner-owned this sprint: the #93 + #122 decision (by 2026-10-17), the
#233 spike result, the `v1.3` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
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
