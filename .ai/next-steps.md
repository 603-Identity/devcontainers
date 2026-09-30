# Next steps

**Now:** P0: cross-org images — implementing (#21's post-merge steps).

**Just done:**
- Fresh-session architect review posted on PR #39 at head `ffb9cb7`: no blocking findings, `architect-review` green. Every claim was reproduced in an isolated sandbox: the acceptance greps, the build, smoke and Trivy gate, the D2 guards going red when violated, the shared-volume init from the node image, and the D3 verify (positive and negative).
- The human merged #39 as `b4a490b`; #21 and #9 closed. The first publish from `main` is build.yml run 36753915960 (run #30).
- Non-blocking review finding filed as #41 (prose wrap, and the template header comment repeats itself).

**Next:** Finish #21's post-merge steps. Model: sonnet (coder).
1. Confirm build.yml run 36753915960 on `b4a490b` succeeded and published base, tofu and node tagged `3.30`.
2. Post on #12 the IAC-D draft specified in §6 of the #21 design spec (issue comment 5915473715). The repo is public, so it must carry no private internals.
3. File the §5 folder-name enforcement follow-up as a P0 issue in milestone 1, linking #23.

**HITL Gate: OPEN** — first anchor for milestone 1 in this handoff chain (description sha `ebe3ff3e…`). It re-verified as `match` at handoff, but this session's resume did not verify it, so a human "go" confirms the milestone before the coder starts. The next gate after that is the owner confirming the #12 draft and landing it in infrastructure-core.

Owner action from #39, if not done yet: `docker volume rm 603identity-cache 603identity-trivy-cache` (delete them, don't migrate).

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
