# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review: PR #248 (#245) is
open and needs a fresh-session architect review.

**Just done** (coder session on sonnet, last_commit `bfa0a38`):
- #245 shipped as PR #248 (`bfa0a38`): rule 2b of `tools/check-consumer-workflows.sh` strips a
  leading `./` from each `code_paths` entry before sampling, with a test for each direction.
- Critic pass (architect, security-critic, docs-consistency): 2 rounds, converged, all on the
  critics' own default models. The one finding acted on was a wrong comment (the gate reads the
  GitHub files API, not `git diff`). The full green gate passed.
- Filed #249: a bare `./` or `.` entry still fails open in rule 2b (same shape as #245); not in
  #248, deliberately.

**Next:** `/way-of-working:architect-review 248` in a **new window** (the fresh-session review
is an integrity property, not just context hygiene). Model: **opus** (architect). File any
non-blocking findings; never approve or merge. After it, the coder work that doesn't wait on
items 4 and 5 is #202, #198, #240 (build order is in the milestone description).

**HITL Gate: NONE OPEN** for #248. The next gate is the owner's merge of #248 after that review.
Also owner-owned this sprint: the #93 + #122 decision (by 2026-10-17), the #233 spike result,
the `v1.3` tag.

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
