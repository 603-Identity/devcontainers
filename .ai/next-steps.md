
# Next steps

**Now:** Milestone 6, Internal hardening, in `planning`.

**Just done:** Archived milestone 4 (Repo hardening: review gate and CI). Its last change merged as `344d625`, and
the way-of-working `v0.17.0` pin merged after it as `b670f57` (#370). #278 is closed, and the rest of it is tracked
as glunk-works/claude-workbench#346.

**Milestone close:** closed: milestone 4, "Repo hardening: review gate and CI" (`verify --plan` match, 0 open issues).

**Next:** on **opus** (architect): plan M6. Sequence milestone 6's 22 open issues into a build order.
`/way-of-working:plan-sprint` can help triage. Anchoring the plan is `/way-of-working:handoff`.

**HITL Gate: OPEN**: first anchor for milestone 6, description sha `6cbed054…414f61`. The next gate is the
owner's approval of the M6 build order.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11) is due 2026-10-29. Renew or retire the #148 Trivy exceptions before
  2026-11-01; #329 rides along. On 2026-10-07 the owner chose M6 first because little has changed for the renewal.
- Milestone 6 step 2 starts with your live App-token merge test (#327).
- Any other repo that bumps way-of-working to `v0.17.0` reads `incomplete` until it answers `orchestration`,
  and needs the drive-letter mirror after `plugin update` (claude-workbench#347).
- The pilots re-copy the gate and re-pin to `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`; tracked there.
- #356 needs a milestone.
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
