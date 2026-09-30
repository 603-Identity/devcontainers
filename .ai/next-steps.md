# Next steps

**Now:** P0: cross-org images — implementing; #7 is next (PR #51 merged as `ec979d7`).

**Just done:**
- Posted the fresh-session architect review on PR #51 (head `f5838aa`), as a comment only. Verdict: in scope, correct, no blocking findings. The gate went green and the human merged it; #47, #48 and #49 are closed.
- The review built the base image in an isolated sandbox. Smoke passes at head. Reverting the helper to a bare `gh` turns the new absolute-path check and the credential-trace checks red. A planted `~/.local/bin/gh` receives credential traffic under the old helper and not under #51's.
- Filed the review's two non-blocking findings as #53 (README Node row versions) and #54 (Known-gaps note for `~/.local/bin` shadowing). Both are now on milestone 1.
- The human picked #7, then #16, as next. Plan anchor re-verified at handoff: `match`, description sha `ebe3ff3…` unchanged. It is now anchored on #7.

**Next:** task #7 — move the tofu image to the newest OpenTofu 1.12.x. Bump `TOFU_VERSION`/`TOFU_SHA256` in `images/tofu/Dockerfile`, taking the checksum from the release's `SHA256SUMS`. Then re-check the `.trivyignore.yaml` entries scoped to `usr/local/bin/tofu` and drop any that no longer match. The issue's smoke and README bullets are already covered: smoke reads the ARG, and the README table has no versions since #51. Then the green gate, `/way-of-working:critic-gate`, and `/way-of-working:ship` with `Closes #7`. Model: sonnet (coder).
- #16 waits on an owner decision: npm 12 or an override of the bundled `brace-expansion`/`undici`. Its `.trivyignore.yaml` entries expire 2026-10-28.
- #7's coordination: the consuming repos' CI pins move in the same window (terraform-cloudflare-dns#40; infrastructure-core and terraform-microsoft365-entra still owed).
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gates are the critic-gate pick on #7's diff, then its fresh-session architect review and the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
