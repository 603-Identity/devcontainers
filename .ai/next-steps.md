# Next steps

**Now:** P0: cross-org images — awaiting_review; PR #56 (task #7) is open, head `af222eb`.

**Just done:**
- Moved the tofu image to OpenTofu 1.12.6 (`TOFU_VERSION`/`TOFU_SHA256` in `images/tofu/Dockerfile`, checksum from the release's own SHA256SUMS), opened as PR #56 with `Closes #7`. Local green gate passed; the built image reports `OpenTofu v1.12.6`.
- All 14 tofu-scoped `.trivyignore.yaml` entries still match the 1.12.6 binary, so none were dropped. 1.13.0 (released 2026-09-30) clears 11 of them but is a further minor, not this move.
- Critic pass (security-critic + architect): 2 rounds, converged, no second-opinion round (declined). It found only comment-level gaps, all fixed: the consumer-CI coupling note and the Trivy result are now recorded. It is not the review gate.
- Plan anchor re-verified at handoff: `match`, description sha `ebe3ff3…` unchanged; `task_issue` is null because the next action is a review, not a build.

**Next:** `/way-of-working:architect-review 56` in a new session — model opus (architect). Then the human merges.
- The image moves before the consumers' CI pins: consumers must move `tofu_version` in the same PR that takes the new digest. terraform-cloudflare-dns#40 is open; infrastructure-core and terraform-microsoft365-entra have no issues filed yet. File them.
- Not yet filed: the unsigned `SHA256SUMS` (pre-existing; the threat model's Known gaps names it for Node only). Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).
- #16 waits on an owner decision: npm 12 or an override of the bundled `brace-expansion`/`undici`. Its `.trivyignore.yaml` entries expire 2026-10-28.

**HITL Gate: NONE OPEN** — next gates are the fresh-session architect-review on PR #56, then the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
