# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `implementing`. Task #546 comes first, then #484. Milestone 6 is parked.

**Just done:**
- Filed #546: declare `lanes.dir` so spec and lane sessions run here (onboarding item missed at cutover; tracked by glunk-works/claude-workbench#1580). The owner placed it on milestone 5, ahead of #484.
- Drafted and posted #546's spec comment as the dev App (`/way-of-working:spec-task 546`); the owner approved it with a reaction.
  - Critic gate on the spec: architect, security-critic; 3 rounds; converged.
- The plugin pin bump to `v0.37.0` merged as #538 (`7206f4b`).

**Next:** task #546 — declare `lanes.dir` (`/tmp/lanes`) in `.ai/project.yml` per the approved spec comment on #546. Run the container-runnable `gates.green` steps the spec names, then `/way-of-working:critic-gate` and `/way-of-working:ship`. Then task #484 (renew the `.trivyignore.yaml` exceptions before they expire on 2026-12-01). Model: **sonnet** (coder).

**HITL Gate: OPEN** — first anchor for milestone 5 on this machine (no prior cursor): the owner confirms milestone 5 is the plan this sprint works from, with #546 built ahead of #484.

**Open for the owner (non-blocking):**
- #427: pick early warning, stagger, or both, before its step starts.
- Milestone 5's description still lists the build order #484, #427, #329, #477 + #459; it does not name #546.
- Milestone 10 needs owner setup in GitHub settings before it starts: the dedicated release App, the `release` environment, and the `release-tags` bypass.
- `docs/threat_model.md` § Exceptions still says this repo has no devcontainer, untrue since #535 (raised by the spec's security critic); needs an issue.
- `~/.config/glunk-identity/bin/review-gate-state.sh` comes before the plugin's own copy on PATH, and the two files differ.
- Milestone 3's description is stale and needs a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · parked sprints: `.ai/parked/`
