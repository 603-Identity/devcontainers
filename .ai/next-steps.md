# Next steps

**Now:** P0: cross-org images — implementing.

**Just done:**
- Confirmed #21 as P0's next task. The milestone 1 anchor verified `match` at resume and again at this handoff. The owner closed the gate.
- Design spec for #21 posted: [#21 comment](https://github.com/603-Identity/devcontainers/issues/21#issuecomment-5915473715). It folds #9 and feeds #12. It goes past the issue text in three places, each forced by the cross-org move:
  - the shared cache volume holds only tofu providers, at `~/.cache/shared`;
  - only `main` publishes, and consumers pin the signer workflow and `refs/heads/main`;
  - the image MAJOR goes to 3, per `build.yml`'s own rule.
- Critic pass on the spec (architect and security-critic): 2 rounds, converged.
- Owner answers recorded in the spec: tokens go in the owning org's ledger (glunk-works has none yet, a named gap), and prose names 603-Identity and glunk-works.

**Next:** task #21 — implement the design spec at https://github.com/603-Identity/devcontainers/issues/21#issuecomment-5915473715 as one PR that closes #21 and #9. Apply every §2 change and meet every §4 acceptance box: run the local green gate and the D3 verify commands by hand, and paste their output in the PR body. Run `/way-of-working:critic-gate` on the diff, then `/way-of-working:ship`. After merge, post the §6 IAC-D draft on #12 and file the §5 folder-name enforcement follow-up. Model: sonnet (coder).
**HITL Gate: NONE OPEN.** The next gate is the fresh-session `/way-of-working:architect-review` on the #21 PR, then the human merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
