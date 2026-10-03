# Next steps

**Now:** P1: pilot adoption (milestone 2) -- implementing.

**Just done** (coder session, base `61a0129`):
- Built the org secret scan for [#190](https://github.com/603-Identity/devcontainers/issues/190)
  in four PRs, three merged: #197 (reusable workflow `secrets / scan`, org rules, fail-closed
  wrapper, config lint), #201 (template caller + `check-consumer-workflows.sh` rule), #203
  (README adoption section, `--no-verify` deny rules). The `v1.1` tag is pushed on `5bccf29`,
  the commit the template pins.
- #207 (PR B: image install, smoke test, `bump-binaries.sh betterleaks` with a cosign
  signature check, Trivy exceptions) is open and green, waiting on the owner.
- Handing off without a `/way-of-working:critic-gate` pass; the PRs went through the repo's
  review gate.

**Next:** task #10 — pilot the template on terraform-cloudflare-dns and
terraform-microsoft365-entra, per the issue checklist and the
[carried-over adoption steps](https://github.com/603-Identity/devcontainers/issues/10#issuecomment-5952372434)
(auto-merge off); findings go back into the template and README. Secret scanning in the pilot
follows the README's Secret scanning section (caller pinned at `v1.1`; terraform-cloudflare-dns#47),
not the detect-secrets steps. Model: **sonnet** (coder).

**HITL Gate: OPEN**
- #207 needs the owner's review and merge. Its 7 Trivy exceptions for the Betterleaks binary
  (expire 2026-11-01) are a security call; reachability from a scan was not checked.
- #10 needs the owner at VS Code against two real repos.
- Milestone 2's description is unedited, so it does not list #190-#192, #182, #183; the anchor
  re-verified `match` this session.

**Open for the owner (non-blocking):**
- After #10: #191 removes bc-detect-secrets and #186; close #187-#189 when it lands.
- Still to do under #190: lint that a consumer's pinned SHA is an ancestor of `main`.
- Cosign (pinned in `bump-binaries.yml`) is bumped by hand; a Betterleaks bump also means a
  new `vX.Y` tag.
- Fix now in other repos: jrg-consulting-site#131 and glunk-works/pm-agent-loop#13.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01 (milestone 5).
- Decide whether the declined re-prompt option from #5 needs a `DEVC-D` entry. Amend spec §4
  to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account can flip to Seuss27: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process; run tests in WSL, not
  Git Bash.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
