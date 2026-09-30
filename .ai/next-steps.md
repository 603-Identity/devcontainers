# Next steps

**Now:** P0: cross-org images — awaiting review.

**Just done:**
- Implemented the #20 design spec as [PR #35](https://github.com/603-Identity/devcontainers/pull/35) (head 945a2aa, branch `feat/20-git-identity-projection`): `git-identity.sh` rewrite, template mount, Dockerfile, `MAJOR` 2, `smoke.sh`, README, threat model, DEVC-D2. The PR's required CI checks were green when this was written.
- Full local green gate passed. Critic gate (security-critic, architect, docs-consistency): 2 rounds, converged with tightenings only; the optional `second_opinion` round was offered and skipped.
- Added one thing the spec does not list: a seventh deny reason for a failed `mktemp` (fails closed; the PR body says so).
- Acceptance check passed from PowerShell: `devcontainer up` on a 603-Identity origin and a glunk-works origin gave the right `user.email` and only gh's credential helper. `git ls-remote` was not run (needs a gh token in the `<repo>-gh` volume).
- Commented on #25 (#35 delivers three of its threat-model items) and on #12 (the identity/credential split it must record).

**Next:** `/way-of-working:architect-review 35` in a genuinely new session, then the human merges #35. Model: opus (architect).
**HITL Gate: NONE OPEN** — the next gate is that review and the merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
