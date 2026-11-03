# Next steps

**Now:** Milestone 9, image bumps for node 26 and betterleaks rc.6, `implementing`. Every task has landed and the milestone has no open issues; its roadmap entry and its close are what is left. Milestone 6 is parked.

**Just done:**
- #478 (task #449) merged as `0ea2b97` after a fresh-session architect review at head `7ecf450` (no blocking findings; the reviewer re-ran the suite and eight mutations). The secret scan now pipes `git log -p` into `betterleaks stdin --git-diff`. The same PR moved the pin to rc.6 and replaced the rc.1 Trivy exceptions with 26 rc.6 ones, so it supersedes #438.
- #478's critic pass: 4 rounds, converged. The record, copied from #478's body:
    > architect, security-critic and docs-consistency ran on the diff: 4 rounds (initial pass plus 3 fix-and-re-run rounds), converged. Rounds 1 to 3 each returned findings that were fixed; round 4 returned only tightenings, which were applied. All rounds ran on the critics' own default models; no second-opinion round was run (offered, declined).
- #436 (node 26.13.0) landed as `df6523d`. Follow-ups filed: #479 (smoke case for the README pre-commit hook, from the review) and #480 (should the scan look inside committed archives?).

**Next:** mark milestone 9 done in `docs/roadmap.md` as its own docs PR, in the style of the milestone 8 entry, naming #450, #449 (`0ea2b97`, #478), #436 (`df6523d`) and the follow-ups #479 and #480. Then run `/way-of-working:archive-sprint`, which closes milestone 9 and seeds the next cursor. Nothing is left to build. Model: **sonnet** (coder), mechanical.

**HITL Gate:** NONE OPEN. Next gate: your merge of the roadmap PR; archive-sprint then closes the milestone.

**Open for the owner (non-blocking):**
- **#438** is still open and is superseded by #478. Close it.
- **Date-bound:** the `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- #463: the interim devcontainer CLI entry (cutover, rebuild, working directory, Windows checks).
- #475 and #477: node 26 follow-ups (pre-commit's `nodeenv` and `libatomic1`; the node image's Node 24 prose and LABEL).
- The plugin pin is `v0.17.0`, and `v0.29.0` is out. Several releases in between need a migration. Bumping it is your call.
- `~/.config/glunk-identity/bin/review-gate-state.sh` comes before the plugin's own copy on PATH, and the two files differ.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/9 · parked sprints: `.ai/parked/`
