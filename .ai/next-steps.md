# Next steps

**Now:** P0: cross-org images — awaiting_review.

**Just done:**
- Implemented the #21 design spec as PR #39 (closes #21 and #9), head `ffb9cb7`: org-neutral `devc` names, the shared volume narrowed to tofu providers at `~/.cache/shared`, publish gated to `main`, MAJOR 3, VS Code only.
- The local green gate passed and the D3 verify run is in the PR body. The critic pass (architect, security-critic, docs-consistency) ran 3 rounds and converged; the `fable` second-opinion round was offered and declined.
- Accepted residuals are listed in the PR body: `--signer-workflow` is a prefix match, the tofu cache is checked at command start not at exec, and a stale v2 template can take a 3.x image.

**Next:** `/way-of-working:architect-review 39` — post the fresh-session Architect Review on PR #39 and verify the `architect-review` check is green on the head SHA. Model: opus (architect), in a **new session**. The human then merges. After merge, the coder confirms the first publish is tagged `3.<run>`, posts the §6 IAC-D draft on #12 and files the §5 folder-name enforcement follow-up (P0, links #23).
**HITL Gate: NONE OPEN.** The next gate is the fresh-session review on #39, then the human merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
