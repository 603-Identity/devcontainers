# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI, re-scoped 2026-10-06 to what the adoption waves copy,
pin or run, ending in `v1.4`. Build-order step 3 is built and in review as PR #339.

**Just done** (coder session on sonnet, last_commit `1621702`):
- Built step 3 as PR #339 (head `582d257`, `ci/gate-rerun-on-edit-315-281-282-317`): the gate re-runs on an
  edited or dismissed review, `post` drops its unused `issues: read` scope, and the gate-post edit-history
  fixtures are newest first. Closes #315, #281, #282, #317. The template and both rendered gate copies match.
- Local gate green in WSL (gate tests, shellcheck, zizmor, `render-gate.sh --check` and `--check-masked`); the
  Docker image build and smoke steps were not run, since no image files changed.
- Critic pass (`architect`, `security-critic`, `docs-consistency`): 2 rounds, converged, all on the critics' own
  default models, no second-opinion round. Round 1 caught a half-done fixture swap and a fork-PR overclaim in the
  docs; both fixed.
- Not verified live, stated in the PR: that `post` needs no issues scope (read from the code; tests stub `gh`), and
  that a fork PR's edited or dismissed run has a read-only token (GitHub's documented rule).

**Next:** `/way-of-working:architect-review 339`, in a NEW session on **opus** (architect): post the review and
verify `architect-review` goes green on the head. Never approve, never merge. After the owner's merge: step 4
(#220), then step 5, which needs the owner's call on #263.

**HITL Gate: NONE OPEN.** The next gate is that review of #339, then the owner's merge.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01; #329 rides
  along.
- Milestone 4 step 5 needs your call on #263 (fix the Entra rule, or record the gap) before it is built.
  Milestone 6 step 2 starts with your live App-token merge test (#327).
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- Delete the local branch `docs/sync-cursor-bumps-merged` (its PR #330 was closed unmerged), and
  `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- Since #336, the consumer lint rejects YAML anchors and merge keys in every workflow file; an adopter
  whose own workflows use them must write the keys out.
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
