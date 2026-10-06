# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Awaiting review: the three bump PRs the
bump-binaries App opened, #321 (uv), #322 (tofu) and #326 (yq).

**Just done** (coder session on sonnet, last_commit `742221f`):
- #323 merged as `742221f`: bump-binaries reads each checksum file before parsing and fails when a transfer
  dies. Re-dispatch of "Bump pinned binaries" then passed all eight matrix jobs; the commits are authored by
  `603-bump-binaries[bot]`. #321 and #322 came from the first dispatch, #326 from the second.
- Closed #102 (App, `main`-restricted Environment key, `BUMP_BINARIES_CLIENT_ID` repo variable, docs; every
  checklist item evidenced in its closing comment).
- Housekeeping: pruned the merged local branches; filed #327 (the threat model says the App token can merge
  to `main`; the ruleset's only bypass is the admin role, so test it once and reword).
- Each bump PR's only non-passing item is the `architect-review` status ("No fresh-session review posted
  against this commit yet"): expected, since `images/` is in `code_paths`.

**Next:** `/way-of-working:architect-review 321` on **opus** (architect), in a new window, then 322 and 326,
each against its own head. A bump PR changes one Dockerfile ARG pair, so each review is: the version is
the newest release, the sha256 matches the upstream checksum file (the same asset the Dockerfile
downloads), nothing else changed. Never approves or merges; the owner admin-merges each.

**HITL Gate: NONE OPEN.** Next gate: the owner merges each bump PR after its review.

**Open for the owner (non-blocking):**
- #315 (an edited review does not re-run the gate) and #327 (the App-token wording, with a live test) are in
  milestone 4. The `bump-binaries` Environment still lets admins bypass its protection rules; turning that
  off is optional.
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before 2026-11-01.
- Place #255, #256, #263, #276, #278, #281, #282, #297, #304 and #317 in a milestone (or leave them for a
  `/way-of-working:plan-sprint` pass). #267 is unmilestoned on purpose: it is an auto-merge (#139)
  precondition.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- The local plugin cache runs way-of-working 0.14.0 while `.claude/settings.json` pins v0.16.0;
  refresh the plugin so `/resume` uses the `--admin` merge shape #307 admits.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash, from a CRLF-stripped copy. `gh issue create` and `gh pr create` hang under Git
  Bash; `gh api ... --input -` with a timeout works (build the JSON with `jq`). Auto mode blocks
  ruleset edits, branch deletes, and pushes or PRs not explicitly asked for; switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
