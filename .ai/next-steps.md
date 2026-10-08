# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`.

**Just done:**
- Milestone 6 step 3 merged: #385 (`adc86df`) closes #309, #310, #327 and #297. The threat model now names
  `restrict-updates-to-main` beside invariant 6, the bump-binaries App-token row is reworded from the owner's
  live test (#327), and the immutable-release wording is corrected. `.ai/project.yml`'s comments record the
  second ruleset as a stated residual.
- The fresh-session architect review of #385 found no blocking issues. It checked every claim against the live
  rulesets, `immutable-releases` and the tag objects, and confirmed in a WSL sandbox that the `.ai/project.yml`
  change is comment-only. It filed #386 (the tag-ruleset entry's "negative test passed" covers only a `v*`
  delete) and #387 (the DEVC-D7 paragraph omits `restrict-updates-to-main`).
- Critic pass on #385 (from its PR body):
    2 rounds (docs-consistency), converged. The critic ran on its frontmatter default; no second-opinion round.

**Next:** task #170 — on **sonnet** (coder): build milestone 6 step 4 as one PR in `.claude/hooks/merge-guard.sh`
and `tools/tests/merge-guard-test.sh` (`Closes #170, closes #171, closes #311`). Each issue's body is the spec:
- #170: make quoted, escaped, wrapper-led and keyword-led `gh pr merge` shapes block. Add every row of its
  reproduction table as a must-block test case.
- #171: detect a heredoc start only in unquoted text, and never on `<<<`. Add both of its cases as must-block.
- #311: in the cursor-sync file check, require exactly one row, `.ai/next-steps.md` with status `modified`. Add
  fixtures for `removed`, `renamed` and a mode-only change, then drop the residual line from the hook header.

Then `/way-of-working:critic-gate` (architect + security-critic) and `/way-of-working:ship`. `.claude/` is in
`code_paths`, so the PR needs the architect review.

**HITL Gate: NONE OPEN** — next gate: the owner's merge of the step 4 PR.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11) is due 2026-10-29. The #148 exceptions still expire 2026-11-01: if the
  tofu and tflint vendors have not shipped fixes by late October, re-scan and renew the rest at most 30 days out.
  #329 rides along.
- #356 (regression test for the #349 pin guard) is on milestone 6 but not in the written build order. It fits
  with step 9's test-only fixes. #377-#379, #383, #386 and #387 are unmilestoned.
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
