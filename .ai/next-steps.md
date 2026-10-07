# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`.

**Just done:**
- Milestone 6 step 1 merged: #376 (`f18264a`) closes #304 (betterleaks rc pin now reaches GA past a later line's
  rc) and #325 (yq's missing-SHA-256 error is reachable).
- The fresh-session architect review of #376 found no blocking issues. It reproduced the claims in a WSL sandbox
  and turned both new guards red with mutations. It filed #377, #378 and #379 (non-blocking bump-binaries
  tightenings).
- Critic pass on #376 (from its PR body): 2 rounds (architect + security-critic, then an architect delta re-run),
  converged; all critics ran on their frontmatter defaults, no second-opinion round.

**Next:** task #159 — on **sonnet** (coder): build milestone 6 step 2 per the owner's decision comment
(https://github.com/603-Identity/devcontainers/issues/159#issuecomment-6020939218). In `build.yml`'s `scope` job,
diff HEAD against the newest `main` `build.yml` run whose `publish` **job** concluded `success`. Use `build=1`
when the lookup fails or finds nothing. Add `actions: read` to `scope` only, with tests for found / none /
lookup failed / publish skipped. Then update `build.yml`'s comment and `docs/threat_model.md`. Run the green gate in
WSL, then `/way-of-working:critic-gate` (architect + security-critic) and `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — next gate: the owner's merge of the #159 PR. Step 3 later waits on the owner's live
App-token test (#327).

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11) is due 2026-10-29. The #148 exceptions still expire 2026-11-01: if the
  tofu and tflint vendors have not shipped fixes by late October, re-scan and renew the rest at most 30 days out.
  #329 rides along.
- Milestone 6 step 3 starts with your live App-token merge test (#327).
- #356 (regression test for the #349 pin guard) is on milestone 6 but not in the written build order. It fits
  with step 9's test-only fixes. #377-#379 are unmilestoned.
- Any other repo that bumps way-of-working to `v0.17.0` reads `incomplete` until it answers `orchestration`,
  and needs the drive-letter mirror after `plugin update` (claude-workbench#347).
- The pilots re-copy the gate and re-pin to `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`; tracked there.
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host. Run tests in WSL, not Git Bash. `gh issue create` and `gh pr create`
  hang under Git Bash; `gh api ... --input -` with a timeout works. Write `Closes #A, closes #B`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6
