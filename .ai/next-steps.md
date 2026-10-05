# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (coder session on sonnet, last_commit `bf2734a`):
- Shipped #202 as PR #253: rules 4 and 5 of `tools/check-consumer-workflows.sh` now require the
  `verify` and `secrets` job's keys to be exactly `permissions` and `uses`, with a `strategy:` and
  a `concurrency:` test per rule. The README and both template caller comments state the rule.
  Green gate: shellcheck and `tools/tests/run-gate-tests.sh` in WSL. The docker and Go entries were
  not run locally (the diff does not touch them); CI runs them.
- Critic pass (architect + security-critic, both on opus): 2 rounds, converged. Round 1 fixes: the
  null-job jq error, the finding wording, the raw key echo (now `tojson`), stale docs. No
  second-opinion round (declined).
- Accepted, not fixed in #253: the two older "only job must be" findings (lines 318 and 352) still
  echo key names without `tojson`; `keys | join(",")` could be `keys == [...]`; no test pins the
  escaping; duplicate keys pass the lint.

**Next:** `/way-of-working:architect-review 253` — the fresh-session architect review of PR #253.
Model: **opus** (architect), in a NEW session; it must not be the session that wrote the diff.
After it merges, #198 and #240 are the other coder items that don't wait on items 4 and 5 (build
order is in the milestone description). The owner should also decide whether to file two issues
from the critic pass: (1) an inline YAML merge key (`<<: {strategy: …}`) in a caller gets past the
whole lint, because `yq -o=json` drops it (older than #202, affects every rule; parse with
`--yaml-fix-merge-anchor-to-spec` or reject `<<`); (2) the raw key-name echo at lines 318 and 352.

**HITL Gate: NONE OPEN.** The next gate is the owner's merge of #253 after the fresh-session
architect review. Also owner-owned this sprint: the #93 + #122 decision (by 2026-10-17), the #233
spike result, the `v1.3` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
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
