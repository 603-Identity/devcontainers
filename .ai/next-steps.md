# Next steps

**Now:** P1: pilot adoption (milestone 2). Implementing.

**Just done** (session ran coder, last_commit `7a9e126`):
- Found the post-#224 devcontainer-tofu bumps: terraform-cloudflare-dns#66 (4.263 → 4.267) and
  terraform-microsoft365-entra#42 (4.244 → 4.267). Each passes every required check except
  `architect-review`, which has no review posted on the head commit.
- Proved the `verify / verify` pin blocks a merge. Throwaway PR -entra#43 dropped the digest from
  the `FROM` line; the check went red (`does not match the allowed pattern`), the PR was
  `BLOCKED`, and it was closed unmerged. Evidence is on #10. The first attempt went red for the
  wrong reason (a truncated Dockerfile) and was redone.
- No code diff in this repo, so no `/way-of-working:critic-gate` pass applied.

**Next:** task #10 — run `/way-of-working:architect-review` on -dns#66 and -entra#42 in a fresh
session, verify the gate with `/way-of-working:pr-checks`, and record both on #10. Never merge.
Model: **opus** (architect). Open a new window, not `/clear`: this is a review boundary.

**HITL Gate: NONE OPEN.** Next gate is the owner's merge of the two bump PRs.

**Open for the owner (non-blocking):**
- #10 still needs answers on the forwarded GPG agent (personal and org keys?) and a persistent
  `/tmp`.
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra (auto mode blocks
  branch deletes).
- -dns#57: pin `Mocked tofu test` and both Checkov checks to `integration_id` 15368 in the
  ruleset. -dns#59 (`code_paths` scope) and -dns#65 are open.
- Other repos still on detect-secrets have their own migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31 and
  trust-anchors#73.
- Check #212's items against #215 and close what it covers. #220 is open.
- Still to do under #190: lint that a consumer's pinned SHA is an ancestor of `main`. Cosign
  is bumped by hand; a Betterleaks bump also means a new `vX.Y` tag.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo. Run
  tests in WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch
  deletes, so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
