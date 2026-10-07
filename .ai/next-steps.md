
# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Every build-order step is merged. It awaits
#370's review, the owner's merges of #370 and #371, then the archive.

**Just done** (architect session on opus, from `35a459e`):
- Found #278's gate half already merged (#343, #358). Its skill half shipped in way-of-working `v0.17.0`, but
  only for `--pin` runs, so the rest is filed upstream as glunk-works/claude-workbench#346.
- Bumped the way-of-working pin to `v0.17.0` as PR #370 (`c20b347`): `orchestration: null` (the owner's
  answer to the release's migration). Installed locally, with the `c:\` record mirrored from the `C:\` one.
  Both are at the tag's `49aa33a`. Resume's merge command is unchanged, so merge-guard needs no change.
- Filed glunk-works/claude-workbench#347: the plugin's pin-bump procedure leaves out that mirror step.
- Opened #371 (`bc48d33`): milestone 4's done entry in `docs/roadmap.md`, which was missing from `main` and
  which archive-sprint's precondition 3 needs. Merging it is the #278 disposition.
- No critic pass ran on #370: a two-line config diff, left to the architect review.
- Anchored milestone 4 again: description sha `3387dd9c…` unchanged, but this session's resume did not verify
  the prior anchor and the anchor carries `task_issue: null`, so the gate below names it.

**Next:** on **opus** (architect), in a fresh session: `/way-of-working:architect-review 370`. After the owner
merges #370 and #371, close #278 pointing at claude-workbench#346, then run `/way-of-working:archive-sprint`
for milestone 4.

**HITL Gate: OPEN** — (1) the milestone 4 first anchor above; (2) the owner's merge of #371, which settles
#278. #370 merges after its review.

**Open for the owner (non-blocking):**
- Any other repo that bumps way-of-working to `v0.17.0` reads `incomplete` until it answers `orchestration`,
  and needs the drive-letter mirror after `plugin update` (claude-workbench#347).
- The pilots re-copy the gate and re-pin to `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`; tracked there.
- #356 needs a milestone.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the stale local `docs/sync-cursor-*` branches the prune skips (none has a merged PR), and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host. Run tests in WSL, not Git Bash. `gh issue create` and `gh pr create`
  hang under Git Bash; `gh api ... --input -` with a timeout works. Write `Closes #A, closes #B`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
