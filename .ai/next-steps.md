# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (coder session on sonnet, last_commit `44bf291`, the head of PR #258):
- Task #198 shipped as PR #258: restored `\\` in both boundary classes of the
  `org-azure-ad-client-secret` rule in `images/base/files/secret-scan/org.toml`, and added a
  smoke check in `tests/smoke.sh` that plants a derived Entra-shaped secret between backslashes
  in a one-commit range and expects the rule to fire.
- Green gate: shellcheck, `tools/tests/run-gate-tests.sh` and `build-and-test.sh local` pass,
  both new checks ok in all three images. The check fails on the old regex (rc 0) and passes on
  the new (rc 1), run by the architect critic.
- Critic pass (`architect` + `security-critic`): 2 rounds, converged (round 2 tightenings-only).
  Round 1 found that the exit-code check scanned all history and passed on either regex; fixed by
  scanning `$bl_leak..$bl_entra`. All critics ran on their default models. This is not the
  fresh-session review the CI gate requires.
- Known gap, not caused by this change: a secret right after a JSON escape such as `\n` is still
  missed (also true upstream).

**Next:** `/way-of-working:architect-review 258`. Model: **opus** (architect), in a **new
session**, not `/clear`: post the fresh-session review, verify the `architect-review` check on the
head SHA, file non-blocking findings. Never approve, never merge. After the merge: #240 (item
10a), then the `v1.3` release (item 11). #255 and #256 are unmilestoned until the owner places
them.

**HITL Gate: NONE OPEN.** The next gate is the owner's merge of #258 after that review. Also
owner-owned this sprint: the #93 + #122 decision (by 2026-10-17), the #233 spike result, the
`v1.3` tag.

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
