# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Steps 1-8 are done; step 9 (#234) is open as PR #365,
back to the coder: a required check is red, so the architect review is on hold.

**Just done** (architect session on opus, `9b968de`):
- Started `/way-of-working:architect-review 365` and stopped before posting: `shellcheck (scripts)` is red on
  head `736047f` (SC2120: `lint_up` in `tools/tests/check-consumer-workflows-test.sh` reads `${1:-$WF}` but is
  never passed an argument). The PR body's "shellcheck clean" is wrong. No review was posted; the owner chose to
  hold it until the fix lands. Every other required check except `architect-review` is green.
- First plan anchor for milestone 4 with task #234 and its design comment; the description is unchanged.

**Next:** task #234 — on **sonnet** (coder), fix SC2120 on PR #365's branch by changing `lint_up` to use `"$WF"`
(`lint()` takes arguments, so leave it as it is), run shellcheck with CI's own command line, re-run the suite in WSL, push (no
force-push), fix the PR body's shellcheck claim, and confirm the other required checks are green on the new head.
Then `/way-of-working:handoff` for a fresh-session `/way-of-working:architect-review 365` on opus.

**HITL Gate: OPEN** — first anchor for milestone 4 with task #234; the owner's "go" clears it. Next gate: the
owner's merge of #365 after the review is posted on the new head.

**Open for the owner (non-blocking):**
- The pilots (terraform-cloudflare-dns, terraform-microsoft365-entra) re-copy the gate and re-pin to
  `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`, per the `v1.4` release notes; tracked in those repos.
- #278 stays open for its plugin half (#343 closed the gate half); consider moving it to the way-of-working
  tracker (it is the other open issue on milestone 4). #356 needs a milestone.
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
  CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git Bash; `gh api ... --input -` with a
  timeout works (build the JSON with `jq`). Write `Closes #A, closes #B`, never a bare comma list.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
