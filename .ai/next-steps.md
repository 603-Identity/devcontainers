# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `implementing`. The plan is anchored, and task #484 comes first. Milestone 6 is parked.

**Just done:**
- Backlog triaged with `/way-of-working:plan-sprint` (2026-11-03): ledger PRs #485 (`d363b3d`) and #487 (`43e04b4`). Filed #484, the December `.trivyignore.yaml` renewal, on milestone 5. Rewrote milestone 5's description with the build order #484, #427, #329, then #477 + #459. Closed #444 as a duplicate of #446.
- Filed #486, the release-workflow design (a dedicated GitHub App creates the tags, unsigned), on new milestone 10, "Release workflow", due 2026-12-18.
- Anchored milestone 5 at its post-edit description. The anchor re-verified as `match` against this session's own edit.

**Next:** task #484 — renew the `.trivyignore.yaml` exceptions before they expire on 2026-12-01. Re-scan every image at its current pins, remove each exception whose finding no longer appears, and renew the rest at most 30 days out with each justification re-checked. Run the gate suite in WSL, then `/way-of-working:critic-gate` (architect + security-critic) and `/way-of-working:ship`. Model: **sonnet** (coder).

**HITL Gate:** NONE OPEN — next gate: the owner's merge of #484's PR. Step 2 (#427) needs the owner's pick between its early-warning and stagger options before it is built.

**Open for the owner (non-blocking):**
- #427: pick early warning, stagger, or both, before step 2 starts.
- Milestone 10 needs owner setup in GitHub settings before it starts: the dedicated release App, the `release` environment, and the `release-tags` bypass.
- The plugin pin is `v0.17.0`, and `v0.29.0` is out. Several releases in between need a migration. Bumping it is your call.
- `~/.config/glunk-identity/bin/review-gate-state.sh` comes before the plugin's own copy on PATH, and the two files differ.
- Milestone 3's description is stale and needs a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · parked sprints: `.ai/parked/`
