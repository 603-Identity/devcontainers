# Next steps

**Now:** P1: pilot adoption (milestone 2) -- implementing.

**Just done** (planning session, no code; base `6854248`):
- Ran plan-sprint on the 8 unmilestoned issues: #190, #191, #192, #182 and #183 went into
  milestone 2 (order #5, #190, #10, #191, #192, #103); #187–#189 stay unmilestoned as
  superseded. Each has a triage comment. The anchor still verifies (`match`).
- Earlier in the sitting: decided the org secret-scanning strategy (Betterleaks v2.0.0-rc.1
  via a reusable workflow in this repo; design and verification in
  [#190](https://github.com/603-Identity/devcontainers/issues/190)), opened #190–#192, and
  turned on Dependabot alerts and security updates for 3 private repos plus the org default.

**Next:** task #10 — pilot the template on terraform-cloudflare-dns and
terraform-microsoft365-entra, per the issue checklist and the
[carried-over adoption steps](https://github.com/603-Identity/devcontainers/issues/10#issuecomment-5952372434)
(auto-merge off); findings go back into the template and README. Secret scanning in the
pilot follows #190 (terraform-cloudflare-dns#47), not the README's detect-secrets steps.
Model: **sonnet** (coder).

**HITL Gate: OPEN**
- First anchor for milestone 2 written without a resume-verified baseline (description sha
  `3c385bea`, unchanged). #10's `updated_at` moved because of this session's comment.
- Sequencing resolved 2026-10-03: plan-sprint placed #190, #191, #192, #182 and #183 in
  milestone 2 (order #5, #190, #10, #191, #192, #103; its description is unedited, so a
  `/way-of-working:handoff` re-anchor is what lists them). #190 lands before #10.
  #187–#189 stay unmilestoned as superseded; close them when #191 lands.
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
