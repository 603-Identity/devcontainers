# Next steps

**Now:** Milestone 4, Repo hardening: review gate and CI. Implementing.

**Just done** (architect session on opus, last_commit `791500d`; no code):
- Fresh-session architect review of #265 (#240) posted on head `c6827cf`: no findings,
  `architect-review` green. The owner merged it as `791500d`.
- The owner decided the open milestone 4 questions:
  - #93 + #122: DEVC-D7, in #268 (docs PR, open). Human writers are trusted, the bump App is
    not. #92 + #94 close by counting only formal reviews bound to the head SHA.
  - #233: spike, then dogfood the rendered template gate.
  - #126 + #132: moved out of milestone 4. They stay #139 preconditions beside the new #267
    (a reviewer App check run, the auto-merge precondition).
  - `v1.3` ships after items 4-7, not now.
- Recorded on the issues (#92, #93, #94, #122, #126, #132, #139, #233) and in the milestone 4
  description, which this session edited. Re-anchored right after the edit; the baseline
  verify printed match.

**Next:** task #233 — run the time-boxed spike, per its spec comment
https://github.com/603-Identity/devcontainers/issues/233#issuecomment-6000851079. Confirm the
three spike questions by reading and tracing, without building; post the result on #233 and
stop for the owner. Model **opus** (architect). Then the dogfood build, #92 + #94, #96, and
the `v1.3` tag.

**HITL Gate: NONE OPEN.** Next gate: the owner reviews the #233 spike result before the
dogfood build starts. Also the owner merges #268 and this cursor sync. Owner-owned this
sprint: the `v1.3` tag.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11): renew or retire the #148 Trivy exceptions before
  2026-11-01.
- Place #255, #256 and #263 in a milestone (or leave them for a `/way-of-working:plan-sprint`
  pass). #267 is unmilestoned on purpose: it is an auto-merge (#139) precondition.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its
  `code_paths` do not (the new lint warns); confirm during the #212 pilot follow-ups, along with
  whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31,
  trust-anchors#73. #220 is open. #251 (stale test comment) can ride along with #249.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run
  commits, pushes and PRs from the Windows host (WSL's `gh` is Seuss27, no push). Run tests in
  WSL, not Git Bash. `gh issue create` hangs under Git Bash; `gh api .../issues --input -`
  works. Auto mode blocks ruleset edits, required-job removal and branch deletes, so switch to
  manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/4
