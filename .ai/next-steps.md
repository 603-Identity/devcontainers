# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect session on opus, last_commit `b16dc49`):
- Fresh-session architect review of PR #253 (#202) posted. No blocking findings; the
  `architect-review` check went green on head `bf2734a`. The owner merged it as `b16dc49`.
- Reproduced in a WSL sandbox: the suite, #202's own repro, extra job keys rejected, key
  order not mattering, `tojson` escaping, and a mutation that turned the new tests red.
- Filed the critic-pass leftovers as issues: #255 (a YAML merge key `<<:` gets past every
  caller rule, confirmed on #253's head) and #256 (the "only job must be" findings echo job
  names raw; a newline in a job name reaches the log as a `::` line, reproduced on `main`).

**Next:** task #198 — restore the backslash boundary in the Entra client-secret rule in
`images/base/files/secret-scan/org.toml` so it matches the tested draft, with a regression
test. Model: **sonnet** (coder). Then `/way-of-working:critic-gate` (architect +
security-critic) and `/way-of-working:ship`. After it, #240 (item 10a), then the `v1.3`
release (item 11). #255 and #256 are unmilestoned until the owner places them.

**HITL Gate: NONE OPEN.** The next gate is the owner's merge of the #198 PR after its
fresh-session architect review. Also owner-owned this sprint: the #93 + #122 decision (by
2026-10-17), the #233 spike result, the `v1.3` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
- Place #255 and #256 in a milestone (or leave them for a `/way-of-working:plan-sprint` pass).
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
