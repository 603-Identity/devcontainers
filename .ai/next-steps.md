# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `implementing`. Milestone 6 is parked.

**Just done:**
- Fix #453 shipped: `devc-verify` refuses `ENV ALL_PROXY` in dev-App extras, and the template Dockerfile's header names it (#466). PR #465, `58d54dd`. Went in ahead of the tag so the first dev-App verifier release carries it.
  - Fresh-session review of #465 found #466; fixed in the same PR. Handing off without a critic-gate pass on this small diff.
- The owner cut and pushed the signed `v1.6` tag on `58d54dd` (verified: good signature). `build.yml`, Verify self-test and Lint were green on that commit. That closes #393.

**Next:** on **sonnet** (coder), PR E of #418: move the five self-pins to `58d54dd63228e3640327bfcd34d91f64fcc88e60 # v1.6` (README Cutting a release step 2), rotate `tools/devc-verify/templates/previous.devcontainer.json` from `git show v1.6:template/.devcontainer/devcontainer.json`, mark DEVC-D9 shipped, fix the roadmap Status (it still says PR D is in review), and close #418. PR E touches `code_paths`, so it needs a fresh-session `/way-of-working:architect-review`.

**HITL Gate: OPEN.** No baseline anchor was verified this session for milestone 8; the description sha256 is unchanged from the previous anchor. A human go starts PR E. The next gate is the owner's merge of the PR E PR.

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- Follow-up #463: the interim devcontainer CLI entry (cutover, rebuild, working directory, Windows checks).
- Bump PRs #436 (node 26) and #438 (betterleaks rc.6) stay red and must not land until #450 and #449 do.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · parked sprints: `.ai/parked/`
