# Next steps

**Now:** P0: cross-org images — awaiting_review; PR #56 (task #7) is reviewed and READY, waiting on the human's merge.

**Just done:**
- Posted the fresh-session architect review on PR #56 (head `af222eb`), as a comment only. Verdict: in scope, correct, no blocking findings. The `architect-review` gate went green; the PR reads MERGEABLE/CLEAN.
- The review reproduced the PR's claims in an isolated sandbox. The checksum matches upstream `tofu_1.12.6_SHA256SUMS`. The binary reports v1.12.6. The tofu allowlist entries equal the binary's HIGH findings exactly, with none stale. The comment's 1.13.0 claim holds. A checksum mutation and a dropped allowlist entry both go red. The full image build and smoke were taken from CI's `pull_request` run on the same SHA: the sandbox has no buildx, and passing the host Docker config would expose its credential store.
- Filed the review's non-blocking finding as #58: OpenTofu signs its `SHA256SUMS` (cosign and GPG), unverified here, and the threat model's Known gaps names this gap for Node only. #58 is unmilestoned, for triage. The 1.13.0 move (clears 11 of the 14 tofu entries) is left to #8's re-review before the 2026-10-28 expiry.
- Consumer coordination: opened terraform-microsoft365-entra#25 (CI `tofu_version` 1.11.14 → 1.12.6, raise `required_version`). infrastructure-core already tracks its move in infrastructure-core#544 (it builds its own devcontainer, so no digest coupling yet). terraform-cloudflare-dns#40 is open.
- Plan anchor re-verified at handoff: `match`, description sha `ebe3ff3…` unchanged; `task_issue` stays null until #16 has a decision.

**Next:** after the human merges PR #56 and decides #16 (npm 12, or an override of the bundled `brace-expansion`/`undici`), record the decision on #16 as its spec, re-anchor on #16 with `/way-of-working:handoff`, and hand #16 to the coder. Model: opus (architect).
- #16's `.trivyignore.yaml` entries expire 2026-10-28, the same day as #8's tofu entries.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: OPEN** — the human's merge of PR #56, and the owner decision on #16.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
