# Next steps

**Now:** P1: pilot adoption (milestone 2). Implementing.

**Just done** (session ran coder then architect, last_commit `cd67cf6`):
- Both pilots repinned secret-scan to `v1.2`: terraform-cloudflare-dns#56 and
  terraform-microsoft365-entra#41, both merged.
- -dns#58 was the first real image bump (devcontainer-tofu 4.244 → 4.263). It passed
  `verify / verify` after a GitHub 503 rerun, got its architect review and was merged.
  Recorded on #10.
- -dns moved off detect-secrets (-dns#47). The full-history adoption scan was `complete`, and
  its only hit was the deliberate token from -dns#49. The ruleset context was dropped first,
  then -dns#60 merged. Commits in -dns must now be made inside the devcontainer, because the
  Betterleaks hook uses container paths.
- #224 (#191) removed bc-detect-secrets, the #186 sync job and its smoke check from the image.
  #188 and #189 were closed as superseded, and -dns#53 and #62 were closed.
- No `/way-of-working:critic-gate` pass ran on #224 or -dns#60. Both went through the
  fresh-session architect review instead.

**Next:** task #10 — for each pilot, find the Dependabot devcontainer-tofu image bump opened
after #224 published, and report its required checks with `/way-of-working:pr-checks`.
Never merge. Model: **sonnet** (coder).

**HITL Gate: OPEN.** Confirm the milestone 2 plan anchor (description sha `3c385bea...`,
task #10). It was rewritten because this session's #10 comment moved the issue's
`updated_at`. `verify --plan` matched the prior anchor, but this session's resume never ran
`verify`.

**Open for the owner (non-blocking):**
- #10 still needs a PR on -entra showing the `verify / verify` pin blocks (the -entra image bump
  can serve), the checklist ticked, and answers on the forwarded GPG agent (personal and org
  keys?) and a persistent `/tmp`.
- -dns#57: pin `Mocked tofu test` and both Checkov checks to `integration_id` 15368 in the
  ruleset. The `.ai/project.yml` half merged in -dns#60. -dns#59 (`code_paths` scope) and
  -dns#65 are open.
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
