# Next steps

**Now:** Milestone 9, image bumps for node 26 and betterleaks rc.6, `implementing`. Milestone 6 is parked.

**Just done:**
- #474 (`libatomic1` in the node image) got its fresh-session architect review at head `4c82469`. The review reproduced the fix in a WSL sandbox: the full build passed with #436's node 26 pins, and node 26 failed to load once the layer was removed. It merged as `8b91360` and closed #450.
- #474's critic pass: 2 rounds, converged. #475 was filed from it (pre-commit's `nodeenv` and Node 26+). The record, copied from #474's body:
    > architect, security-critic and docs-consistency ran on the diff: 2 rounds, converged (round 1 findings fixed, round 2 re-run on the fixes came back with none). All rounds ran on the critics' own default models; no second-opinion round was run (offered, declined).
- #436's branch was brought up to date with `main` by update-branch (`7a68215`, no force-push). Every required check on it is green except `architect-review`.
- Milestone 9's anchor was re-verified (`match`, sha `41810cec`) and re-taken on #449.

**Next:** task #449 — replace betterleaks `--log-opts` in `tools/secret-scan.sh`, `tests/smoke.sh` and `tools/tests/secret-scan-test.sh` with a caller-side `git log -p ... | betterleaks stdin --git-diff` scan. It must keep the full-ancestry property: every commit, merges included, binary content as text. Run the green gate in WSL, once as pinned and once with #438's rc.6 pins applied temporarily. Then `/way-of-working:critic-gate` (security-critic included) and `/way-of-working:ship`. Model: **sonnet** (coder). The PR needs a fresh-session `/way-of-working:architect-review`.

**HITL Gate:** NONE OPEN. Next gate: your merge of #449's PR after its architect review.

**Open for the owner (non-blocking):**
- **#436 (node 26.13.0):** run `/way-of-working:architect-review 436` in a new opus window. It is a bot PR, so the review relies on CI rather than local execution. Before merging, decide when consumers move to node 26: the merge publishes the image.
- **Date-bound:** the `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- #463: the interim devcontainer CLI entry (cutover, rebuild, working directory, Windows checks).
- The plugin pin is `v0.17.0`, and `v0.29.0` is out. Several releases in between need a migration. Bumping it is your call.
- `~/.config/glunk-identity/bin/review-gate-state.sh` comes before the plugin's own copy on PATH, and the two files differ. It gave the same answer on #474.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/9 · parked sprints: `.ai/parked/`
