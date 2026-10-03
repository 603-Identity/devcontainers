# Next steps

**Now:** P1: pilot adoption (milestone 2) -- implementing.

**Just done** (planning session, no code; base `5cc9b30`):
- Decided the org secret-scanning strategy: **Betterleaks v2.0.0-rc.1**, run by a reusable
  workflow in this repo that reads the scanner pin and `org.toml` at `job.workflow_sha`.
  It replaces bc-detect-secrets, so #186's sync is reversed. The plan converged after
  3 adversarial rounds (security-critic + architect). rc.1 was verified against our use
  cases: 35/35 acceptance cases pass, and the dry-run adoption scans are clean across the
  603 and glunk-works repos. The design, the tested `org.toml` and the test suite are in
  [#190](https://github.com/603-Identity/devcontainers/issues/190) (body + 2 verification comments).
- Opened #190 (build), #191 (remove detect-secrets; blocked on the pilot) and #192 (push
  rulesets on Team; owner test). Opened or rewrote migration issues in each consumer repo,
  linked from #190. Marked #187/#188/#189 superseded.
- Turned on Dependabot alerts and security updates for 3 private repos, and as the org
  default for new repos. Two archived repos were skipped.

**Next:** task #10 — pilot the template on terraform-cloudflare-dns and
terraform-microsoft365-entra, per the issue checklist and the
[carried-over adoption steps](https://github.com/603-Identity/devcontainers/issues/10#issuecomment-5952372434)
(auto-merge off); findings go back into the template and README. Secret scanning in the
pilot follows #190 (terraform-cloudflare-dns#47), not the README's detect-secrets steps.
Model: **sonnet** (coder).

**HITL Gate: OPEN**
- First anchor for milestone 2 written without a resume-verified baseline (description sha
  `3c385bea`, unchanged). #10's `updated_at` moved because of this session's comment.
- Run `/way-of-working:plan-sprint` to place #190–#192, which have no milestone. Decide
  whether #190 lands before #10's cloudflare-dns half (recommended).
- #10 needs the owner at VS Code against two real repos.

**Open for the owner (non-blocking):**
- Fix now in other repos: jrg-consulting-site#131 (unverified `curl` gitleaks download) and
  glunk-works/pm-agent-loop#13 (unpinned `gitleaks-action@v3`).
- Run the push-ruleset test (#192).
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01 (milestone 5).
- Decide whether the declined re-prompt option from #5 needs a `DEVC-D` entry. Amend spec §4
  to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account can flip to Seuss27: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
