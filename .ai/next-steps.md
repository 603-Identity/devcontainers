# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `implementing`. v1.8 is released. What's left on M5: the v1.8 pin bump (#582), the host re-scan script (#569, lane building), then the `.trivyignore.yaml` renewal (#484) before 2026-12-01. Milestone 6 is parked.

**Just done:**
- **#560 and #561** shipped as #563 and #564. **#551** shipped as #568 (`ad1135c`). **#486**, the release workflow, shipped as #579 (`83c4f2c`). It was pushed through an elevated push (Procedure B), and #529 was folded into it.
- **v1.8 was cut by `release.yml`** at `6f8a973` (#581), as the first dry run and then the real dispatch. The tag was created by `603id-devcontainers-release[bot]`, and the Release is immutable. `gh release verify v1.8` passes.
- **`docs/host-steps.md` (#566)** is the standard for host steps: Procedure A is a host clone run, Procedure B an elevated push. The owner starts each host session with the start text kept on the host, copied from GitHub.
- **New issues:**
  - #569, the host re-scan script, split out of #484.
  - Follow-ups #570–#578, unmilestoned.
  - glunk-works/claude-workbench#1608, for the elevated token landing in the container mount.
- **Critic passes:**
  - #566: security-critic, 1 pass and 3 re-checks; all findings closed or recorded as known limits. Docs-consistency, 1 pass.
  - #567: one architect pass, its defects fixed.
  - #582: handed off without a critic pass. It's a mechanical pin bump, and the render and self-pin checks passed.

**Next:** driver, when the #569 lane stops, bundle its single commit and hand the owner one Procedure B paste-in: the owner's risk-acceptance paragraph, then the start text, then the values block. After #569 merges, draft the answer to #484's escalated comment 6957143785: the renewal runs Procedure A with `tools/host/trivy-rescan.sh`. Model: **opus** (architect, as driver).

**HITL Gate: OPEN** — the owner runs the #569 elevated push (Procedure B) and the wow-review for PR #582 and PR #569, then approves and merges each by hand.

**Open for the owner:**
- **#582 (pin v1.8):** run `wow-review` from the `603id-identity` home, then merge by hand. Auto-merge is blocked by `merge-guard.sh` (#578).
- **The two identity homes:** run `wow-review` and `wow-admin` from `~/.config/603id-identity`. The `glunk-identity` home's reviewer App can't reach 603-Identity (HTTP 422), but the containers mount `glunk-identity`'s tokens directory. After any `--revoke`, check both homes.
- **`wow-review` and the usage limit:** a run that hits the usage limit posts `no-outbox` (seen twice on #579). Rerun after the reset. It's worth a claude-workbench issue.
- **Reactions:** approve specs as JaredGroves-603. A Seuss27 reaction doesn't count.
- **#550 (M6):** answer or delete escalated comment 6952215523, then re-spec it slimmer.
- **#427:** pick early warning, stagger, or both, before its step starts.
- **Milestone descriptions:** M5's build order is stale. M3's description is stale. M10 is done apart from its close.
- **Signed tags:** deferred. The v1.8 release attestation verifies; a `gitsign` issue only if you want it.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · host steps: [docs/host-steps.md](../docs/host-steps.md) · parked sprints: `.ai/parked/`
