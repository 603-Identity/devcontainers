# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Every build-order step is merged; the sprint is done
pending #278's disposition, then the archive.

**Just done** (architect session on opus, `344d625`):
- Posted the fresh-session architect review of PR #365 (#234, consumer pin provenance) at head `810b219`: no
  blocking findings. Reproduced in a WSL sandbox (consumer-lint suite, five planted mutations each caught) and
  live against github.com (template pins pass; a PR-only SHA and a mislabeled tag each fail; `--no-provenance`
  exits 3). `architect-review` went green as a commit status; the owner merged it as `344d625`, closing #234.
- No findings filed; two notes stay in the review body (TLS/proxy env not cleared; one finding per file).
- Anchored milestone 4 again: description sha `3387dd9c…` unchanged, but this session's resume did not verify
  the prior anchor and the anchor carries `task_issue: null`, so the gate below names it.

**Next:** on **opus** (architect): once the owner settles #278 — move its plugin half to the way-of-working
tracker and close it here, or take it off the milestone — run `/way-of-working:archive-sprint` for milestone 4.

**HITL Gate: OPEN** — (1) the milestone 4 first anchor above; (2) the owner's disposition of #278, the last open
issue on the milestone, which archive-sprint's close step would otherwise stop on.

**Open for the owner (non-blocking):**
- The pilots (terraform-cloudflare-dns, terraform-microsoft365-entra) re-copy the gate and re-pin to
  `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`, per the `v1.4` release notes; tracked in those repos. The
  pilots can now run `tools/check-consumer-workflows.sh` with the provenance check (needs network).
- #356 needs a milestone.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along. Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged), the other stale
  local `docs/sync-cursor-*` branches the prune skips, and `test/verify-pin-negative-10` on
  terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in WSL, not Git Bash, from a
  CRLF-stripped copy; a whole-suite `run-gate-tests.sh` exceeds `review-sandbox.sh run`'s timeout, so run the
  touched suite and take the rest from CI's `selftest`. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Write `Closes #A, closes #B`,
  never a bare comma list.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
