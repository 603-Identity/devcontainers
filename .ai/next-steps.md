# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `implementing`. Task #546 is done and merged; the owner has asked for a repo hygiene pass next, then #484. Milestone 6 is parked.

**Just done:**
- Task #546 shipped as PR #548 (`705d46b`): `lanes.dir: /tmp/lanes` declared in `.ai/project.yml`. The `603id-review` App passed it; its one finding (the PR body's closing keyword would have closed glunk-works/claude-workbench#1580 early) was fixed in the body.
  - Critic gate: architect, 1 round, converged, no defects; ran on the critic's own default model, no second-opinion round.
- Still to check by hand after the merge: `/way-of-working:resume` prints a `Lanes:` line, and `wowl 603-Identity/devcontainers -SpecSweep` no longer refuses. Then mark glunk-works/claude-workbench#1580 done.

**Next:** repo hygiene pass, not yet a task issue: a proper root `CLAUDE.md`; a separate updated `docs/threat_model.md` (its Exceptions section still says this repo has no devcontainer, untrue since #535); an audit of other basic hygiene gaps. A first look found no `CLAUDE.md`, `SECURITY.md`, `CONTRIBUTING.md`, PR or issue templates, or `.editorconfig`. File each as its own task issue and PR. Model: **opus** (architect). Then task #484 (renew the `.trivyignore.yaml` exceptions before they expire on 2026-12-01).

**HITL Gate: OPEN** — the owner decides where the repo hygiene work is tracked (CLAUDE.md, threat model update, hygiene audit) and which milestone each issue goes on, since milestone writes are the owner's; it is not yet a task issue, so nothing auto-starts.

**Open for the owner (non-blocking):**
- #427: pick early warning, stagger, or both, before its step starts.
- Milestone 5's description still lists the build order #484, #427, #329, #477 + #459; it does not name #546 or the hygiene work.
- Milestone 10 needs owner setup in GitHub settings before it starts: the dedicated release App, the `release` environment, and the `release-tags` bypass.
- `~/.config/glunk-identity/bin/review-gate-state.sh` comes before the plugin's own copy on PATH, and the two files differ.
- Milestone 3's description is stale and needs a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · parked sprints: `.ai/parked/`
