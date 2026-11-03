# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `implementing`. Milestone 6 is parked.

**Just done:**
- PR A (#393) shipped: DEVC-D9 and its docs (#448, `ff2ce9b`). #393 stays open until the v1.6 tag.
  - Critic pass on #448: docs-consistency and security-critic, 3 rounds, converged; the last round returned only tightenings. Critics' own frontmatter models; no second-opinion round. Not the review gate.
- PR C (#392, first half) shipped: `devc-verify` dev-App mode and the plain-mode allowlist (#451, `9af5b4c`).
- The gh 2.103.3 bump merged (#437, `f6d4cc5`).
- Bump PRs #436 (node 26) and #438 (betterleaks rc.6) stay red and must not land until #450 (`libatomic1`) and #449 (`--log-opts` replacement) do.

**Next:** task #392 — on **sonnet** (coder), build PR D of the [#418 design](https://github.com/603-Identity/devcontainers/issues/418#issuecomment-6584294809): the dev-App-only template, `template-proof.sh` against `devcontainer-devapp-tofu`, README and `docs/adopting.md` rewritten for the dev-App route, the real-template self-test with one negative case per surface. Scope is in the #392 body and the "Left for PR D" list in #451. Run the green gate, then `/way-of-working:critic-gate` before `/way-of-working:ship`. PR D closes #392 and touches `code_paths`, so it needs a fresh-session `/way-of-working:architect-review`. After D: the v1.6 tag (closes #393), then PR E (closes #418).

**HITL Gate: NONE OPEN.** The next gate is the owner's merge of PR D.

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- `orchestration` is `null`, so no loop dispatches into this repo.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · parked sprints: `.ai/parked/`
