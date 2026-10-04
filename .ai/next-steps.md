# Next steps

**Now:** P1: pilot adoption (milestone 2). Implementing.

**Just done** (session ran coder, last_commit `7a9e126`):
- #10 closed. Both pilots took a real devcontainer-tofu 4.267 bump through the review path
  (terraform-cloudflare-dns#66, terraform-microsoft365-entra#42, merged, containers rebuilt).
- The `verify / verify` pin blocks a merge: throwaway PR -entra#43 dropped the digest, the check
  went red and the PR was `BLOCKED`; closed unmerged.
- Owner decisions recorded on #10: the forwarded GPG agent exposing the personal and org keys is
  intended, and persistent `/tmp` (`<repo>-tmp`) is intended and already in the README.
- No code diff in this repo, so no `/way-of-working:critic-gate` pass applied.

**Next:** task #103 — write the adoption runbook from the pilot findings, with a rollback step,
linked from #26, #27 and #28. Same PR: a README line that the forwarded GPG agent exposes the
personal and org keys on purpose, plus the small README issues #204, #205, #206, #182 and #183;
check #212's items against #215 first. Run `/way-of-working:critic-gate` (docs-consistency) before
shipping. Never merge. Model: **sonnet** (coder). `/clear` is fine for this switch.

**HITL Gate: NONE OPEN.** Next gate is the owner's merge of the runbook PR, then closing
milestone 2.

**Open for the owner (non-blocking):**
- Delete branch `test/verify-pin-negative-10` on terraform-microsoft365-entra (auto mode blocks
  branch deletes).
- -dns#57: pin `Mocked tofu test` and both Checkov checks to `integration_id` 15368 in the
  ruleset. -dns#59 (`code_paths` scope) and -dns#65 are open.
- #190 (Betterleaks) is bigger than this milestone and probably belongs in a later one. Still to
  do under it: lint that a consumer's pinned SHA is an ancestor of `main`. Cosign is bumped by
  hand; a Betterleaks bump also means a new `vX.Y` tag.
- Other repos still on detect-secrets have their own migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31 and
  trust-anchors#73.
- #220 is open.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo. Run
  tests in WSL, not Git Bash. Auto mode blocks ruleset edits, required-job removal and branch
  deletes, so switch to manual for those.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
