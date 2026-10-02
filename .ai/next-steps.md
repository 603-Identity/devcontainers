# Next steps

**Now:** P1: pilot adoption (milestone 2) -- implementing.

**Just done:**
- #5 built and merged ([#181](https://github.com/603-Identity/devcontainers/pull/181), `4117679`):
  README § Host signing policy (8h `default-cache-ttl`/`max-cache-ttl`), `gpg-check.sh`
  points at it, one threat-model sentence. #5 closed. Critic pass: `docs-consistency`,
  2 rounds, converged; no second-opinion round.
- The #5 session's `plan_anchor` check printed `drift` (issue #5's `updated_at` moved 9s,
  the spec comment's own timestamp); the owner said go. Anchor now re-written for #10.

**Next:** task #10 — pilot the template on terraform-cloudflare-dns and
terraform-microsoft365-entra, per the issue checklist and the
[carried-over adoption steps](https://github.com/603-Identity/devcontainers/issues/10#issuecomment-5952372434)
(auto-merge off); findings go back into the template and README. Then #103 (adoption
runbook). Model: **sonnet** (coder).

**HITL Gate: OPEN** -- first anchor for milestone 2 since the #5 handoff (description sha
`3c385bea`, unchanged), and #10 needs the owner at VS Code against two real repos. The owner
confirms the #10 start, and which pilot goes first, before work proceeds.

**Open for the owner (non-blocking):**
- Merge #178, so `.ai/archive/` stops showing as untracked.
- Decide whether the declined re-prompt option from #5 needs a `DEVC-D` entry.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01 (milestone 5).
  Each renewal extends at most 30 days.
- Amend spec §4 to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account flips to Seuss27 mid-session: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process. From Git Bash, set
  `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
