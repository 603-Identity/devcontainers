
# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`.

**Just done:**
- The owner approved milestone 6's build order as written on 2026-10-07 (description sha `6cbed054…414f61`,
  `verify --plan` match), which closes the first-anchor gate. Step 1's task #304 is anchored.
- `/way-of-working:plan-sprint` placed #356 (regression test for the #349 pin guard) in milestone 6. It is on
  the milestone but not in the written build order; it fits with step 9's test-only fixes.
- Planning only: no code diff, so no critic pass.

**Next:** task #304 — on **sonnet** (coder): build milestone 6 step 1. Fix #304 (betterleaks rc pin skips GA)
and #325 (resolve_yq's missing SHA-256 error is unreachable) in one PR on `.github/scripts/bump-binaries.sh`,
with tests. Run the green gate in WSL, then `/way-of-working:critic-gate` (architect + security-critic) and
`/way-of-working:ship`.

**HITL Gate: NONE OPEN** — next gate: the owner's merge of the #304 + #325 PR. Step 3 later waits on the owner's
live App-token test (#327).

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11) is due 2026-10-29. The owner put M6 first on 2026-10-07 while the tofu and
  tflint vendors have yet to release fixes. The #148 exceptions still expire 2026-11-01: if no fix has shipped by
  late October, re-scan and renew the rest at most 30 days out. #329 rides along.
- Milestone 6 step 3 starts with your live App-token merge test (#327).
- Any other repo that bumps way-of-working to `v0.17.0` reads `incomplete` until it answers `orchestration`,
  and needs the drive-letter mirror after `plugin update` (claude-workbench#347).
- The pilots re-copy the gate and re-pin to `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`; tracked there.
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Merging #370 failed three times on GitHub's side on 2026-10-07 (the web UI, `gh pr merge`, and the REST
  `PUT …/merge`) before it went through. If it happens again, retry later. Reference: `DE33:323121:1CAFFF8:5BE8BCA:6AC679E9`.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host. Run tests in WSL, not Git Bash. `gh issue create` and `gh pr create`
  hang under Git Bash; `gh api ... --input -` with a timeout works. Write `Closes #A, closes #B`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6
