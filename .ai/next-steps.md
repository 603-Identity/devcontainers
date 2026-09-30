# Next steps

**Now:** P0: cross-org images — implementing; #16 is next (PR #56 merged as `a525b99`, closing #7).

**Just done:**
- The human merged PR #56 (OpenTofu 1.12.6) after its fresh-session architect review, and the cursor sync #59.
- The owner decided #16: npm 12. The check before recording it found that npm 12.2.0 (`latest`, 2026-09-30) still bundles the vulnerable `brace-expansion` 5.0.9 and `undici` 6.28.0. So the decision became npm 12 plus an override of the two bundled copies, and the spec is posted on #16 (comment `5918784180`).
- Plan anchor re-verified at handoff: `match`, description sha `ebe3ff3…` unchanged. It is now anchored on #16 and that spec comment.

**Next:** task #16 — build the spec in https://github.com/603-Identity/devcontainers/issues/16#issuecomment-5918784180: npm 12.2.0 in `images/node/Dockerfile`, then swap the bundled `brace-expansion` (5.0.12) and `undici` (newest 6.x in `^6.25.0`) for integrity-checked registry releases, pinned as ARGs and asserted in the build. Remove the three npm `.trivyignore.yaml` entries. Then the green gate, `/way-of-working:critic-gate`, and `/way-of-working:ship` with `Closes #16`. Model: sonnet (coder).
- The tofu Trivy entries expire 2026-10-28 (#8). 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins: terraform-cloudflare-dns#40, terraform-microsoft365-entra#25, infrastructure-core#544.
- #58 (unverified tofu `SHA256SUMS` signature) is unmilestoned, for triage.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gates are the critic-gate pick on #16's diff, then its fresh-session architect review and the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
