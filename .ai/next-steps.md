# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review.

**Just done** (coder session on sonnet, last_commit `5cfc65e`):
- #233 dogfood built and shipped as PR #274 (head `d3b9ec8`, branch `ci/dogfood-rendered-gate-233`):
  this repo's gate is the rendered template (only the `decide` pin, v1.2, differs),
  `render-gate.sh --check-masked` is new and runs on it from `render-gate-test.sh`, and
  `docs/threat_model.md` states the `post` job's write scopes. Green gate run in WSL
  (shellcheck, gate tests, zizmor).
- Critic pass (architect, security-critic, docs-consistency): 4 fix-and-re-run rounds, cap
  reached, no second-opinion round. The architect converged. The security-critic kept finding
  smaller parser differentials (decoy marker, NEL, NUL). **The last two fixes (`grep -a`, and
  `^ {18}#` comment indent in the `code_paths` region test) got no critic re-run**; the PR body
  says so. Accepted, not fixed: `code_paths` arms not compared to `project.yml`, pin SHA not
  tied to a tag.

**Next:** `/way-of-working:architect-review 274`, in a NEW session, on **opus** (architect).
Look first at the two unreviewed fixes. Then the owner merges #274. After that: #92 + #94,
#96, and the `v1.3` tag (owner-owned, after items 4-7).

**HITL Gate: NONE OPEN.** Next gate: the owner's merge of #274 after its architect review.
The plan anchor was re-written for milestone 4 with no task issue (the next action is a
review, not one issue's build), so `/way-of-working:resume` waits for a "go".

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
- Place #255, #256 and #263 in a milestone (or leave them for a `/way-of-working:plan-sprint`
  pass). #267 is unmilestoned on purpose: it is an auto-merge (#139) precondition.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` hangs under Git Bash; `gh api .../issues --input -`
  works. Auto mode blocks ruleset edits, required-job removal and branch deletes, so switch to
  manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
