# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Steps 1-6 are merged (step 6 as `3e48929`, #354).
Step 7 (`v1.4`) is the owner's, and step 8 is next to build.

**Just done** (architect session on opus, last_commit `3e48929`):
- Posted the fresh-session architect review of PR #354 at head `78513cc`. Verdict: sound, nothing blocking. Every
  claim was executed in a WSL sandbox, #348 against real Betterleaks rc.1, and each new test went red under a
  mutation that removed its fix. The owner merged it as `3e48929`; #348-#351 closed.
- Filed #356: the #349 pin-guard fix in `verify-devcontainer-image.yml` and `devcontainer-bump-decision.yml`
  has no regression test. Unmilestoned.
- Closed #200, #220 and #263 by hand. #346 fixed them, but its `Closes #199, #200, ...` comma list only
  auto-closed #199.

**Next:** task #341 — build M4 step 8 (#341 + #334 + #335) as one PR in `tools/check-consumer-workflows.sh` and
its test, per the milestone build order and each issue body, on **sonnet** (coder). Run the green gate in WSL,
then `/way-of-working:critic-gate` (architect + security-critic) and `/way-of-working:ship`. Never merge, never tag.

**HITL Gate: OPEN.** The owner confirms starting step 8. This is the first anchor on task #341: the handoff
verify printed `match`, but no resume-side verify ran this session. Separately, the owner tags `v1.4` (step 7); it does
not block step 8, a lint-only change.

**Open for the owner (non-blocking):**
- Tag `v1.4` on `3e48929` or later; the pilots then re-copy the gate and bump their pins.
- #278 stays open for its plugin half (#343 closed the gate half); consider moving it to the way-of-working
  tracker. #356 needs a milestone.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged) and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- Since #336, the consumer lint rejects YAML anchors and merge keys in every workflow file.
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in WSL, not Git Bash, from a
  CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -` with a
  timeout works (build the JSON with `jq`). Write `Closes #A, closes #B`, never a bare comma list.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
