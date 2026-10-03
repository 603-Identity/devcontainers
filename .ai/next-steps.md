# Next steps

**Now:** P1: pilot adoption (milestone 2) -- implementing.

**Just done** (coder session, base `8d2398f`):
- Piloted terraform-cloudflare-dns for [#10](https://github.com/603-Identity/devcontainers/issues/10):
  adoption PR #45 merged (image 4.244 with Betterleaks, `secrets / scan` caller). The container
  checklist passed in VS Code; `docker diff` showed only the expected init and `/vscode` entries.
- Ruleset there now requires `architect-review`, `verify / verify` and `secrets / scan`, each pinned
  to `integration_id: 15368`; read back on #10. Real PRs proved the pins (#50 merged after review),
  the secret scan blocking a made-up token (#49, closed), and Dependabot parsing (#48 closed).
- #210 merged: the README's pre-commit hook needs `safe.directory` through `env` and a
  `.betterleaksignore`. Critic pass on it: 2 rounds, converged (docs-consistency and
  security-critic; no second-opinion round).
- Filed [#211](https://github.com/603-Identity/devcontainers/issues/211) (annotation has no
  `line=`) and [#212](https://github.com/603-Identity/devcontainers/issues/212) (README and
  template findings from the pilot).

**Next:** task #10 — pilot the template on terraform-microsoft365-entra, per the issue checklist
and the [carried-over adoption steps](https://github.com/603-Identity/devcontainers/issues/10#issuecomment-5952372434)
(auto-merge off); follow the README's Secret scanning adoption order; fold in #211 and #212 as
they apply. The entra repo has no `.devcontainer` yet and only the way-of-working `.ai/project.yml`.
Model: **sonnet** (coder).

**HITL Gate: OPEN**
- #10 needs the owner at VS Code against terraform-microsoft365-entra.
- The ruleset change on that repo needs the owner's go-ahead (it is a live change).
- Milestone 2's description is unedited (sha unchanged, verified at handoff); it does not list
  #190-#192, #182, #183.

**Open for the owner (non-blocking):**
- After the pilots: #191 removes bc-detect-secrets and #186, and the follow-up PR drops
  `Secret scan (detect-secrets)` from each pilot's ruleset; close #187-#189 when #191 lands.
- A Dependabot image bump taking the review path is the precondition for #139.
- Decide whether the image should ship a wrapper script for the betterleaks hook's `env` prefix.
- Still to do under #190: lint that a consumer's pinned SHA is an ancestor of `main`. Cosign
  (pinned in `bump-binaries.yml`) is bumped by hand; a Betterleaks bump also means a new `vX.Y` tag.
- Fix now in other repos: jrg-consulting-site#131 and glunk-works/pm-agent-loop#13.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01 (milestone 5).
- Decide whether the declined re-prompt option from #5 needs a `DEVC-D` entry. Amend spec §4
  to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account can flip to Seuss27: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process; run tests in WSL, not
  Git Bash. Open the devcontainer from PowerShell, not Git Bash. GPG signing can time out on a
  pinentry prompt on the Windows side; a retry after entering the passphrase works.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
