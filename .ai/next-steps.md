# Next steps

**Now:** P0: cross-org images — awaiting_review; PR #61 (closes #16) is open, head `96205cb`.

**Just done:**
- Built #16 from its spec (comment `5918784180`): `images/node/Dockerfile` moves to npm 12.2.0, then swaps npm's bundled `brace-expansion` (5.0.12) and `undici` (6.29.0) for integrity-checked registry releases pinned as ARGs. The build asserts the versions and fails if a later npm bundles a copy at or above a pin. The three npm `.trivyignore.yaml` entries are removed; README and `docs/threat_model.md` updated.
- Local green gate passes (shellcheck via its container image, not installed locally). CI on #61: every check green except `architect-review`, which waits on the fresh-session review.
- Critic pass (security-critic, architect, docs-consistency): 3 rounds, converged; no second-opinion round (declined). It fixed a fail-open guard, the collapsed `RUN` continuations, and stale docs.
- Not done: the spec's "show the gate red on 11.20.0 without the entries"; the PR body says so.

**Next:** `/way-of-working:architect-review 61`, in a NEW session on opus (architect). Then the human merges. After that, `.ai/project.yml`'s milestone has no task left in this cursor: pick the next one (#27 is the Node wave, where consumers take npm 12 in CI).
- The tofu Trivy entries expire 2026-10-28 (#8). 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins: terraform-cloudflare-dns#40, terraform-microsoft365-entra#25, infrastructure-core#544.
- #58 (unverified tofu `SHA256SUMS` signature) is unmilestoned, for triage.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: OPEN** — PR #61's fresh-session architect review, then the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
