# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing: #245 is next for a
coder session.

**Just done** (architect session on opus, last_commit `6660921`):
- PR #243 (#214) merged as `6660921`.
- #240 and #245 joined milestone 4 (owner's call). The milestone description's build order
  gained 3a (#245, before the waves) and 10a (#240, after #198); the critic-gate line names
  both. Re-anchored on the edited description (`aa8c259…`, verified `match` before and after
  the edit) and on task #245.
- Recommended order for the coder work that doesn't wait on items 4 and 5: #245, #202, #198,
  #240. In parallel, an opus session can run the #233 spike and draft the #93 + #122 decision
  for the owner, since items 6-8 wait on both.

**Next:** task #245 — In `tools/check-consumer-workflows.sh` rule 2b, strip a leading `./`
from each `code_paths` entry before building samples and in the reverse-direction match (or
reject a `./`-prefixed entry as its own finding naming the form), add a test for each
direction per the issue, run the green gate, run `/way-of-working:critic-gate` (architect +
security-critic), then `/way-of-working:ship`. Model: **sonnet** (coder).

**HITL Gate: NONE OPEN** for #245. The next gate is the owner's merge of #245's PR after a
fresh-session architect review. Also owner-owned this sprint: the #93 + #122 decision (by
2026-10-17), the #233 spike result, the `v1.3` tag.

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
