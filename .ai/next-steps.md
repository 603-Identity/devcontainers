# Next steps

**Now:** P0: cross-org images — implementing; next task #22. PR #61 (closes #16) is reviewed and waits on the human's merge.

**Just done:**
- Fresh-session architect review of PR #61 posted on head `96205cb`: in scope, meets #16's spec, no blocking findings, nothing filed. The `architect-review` gate went green, and the PR is READY.
- The review supplied the proof the PR left out: with the swap removed, npm 12.2.0 carries `brace-expansion` 5.0.9 and `undici` 6.28.0, and the Trivy gate fails on exactly the three removed CVEs. The anti-downgrade and integrity guards were also shown red. All pins match the registry.
- Checked #22's Acceptance against main (`98406d0`): every box is met except "no npm 11 entries", which #61's merge completes.

**Next:** task #22 — close out the version standard. First confirm PR #61 has merged; if it hasn't, stop. Then, on an up-to-date main, re-verify each Acceptance box with one piece of evidence each, post the evidence as one comment on #22, and close it. If any box fails, post what fails and don't close. Model: sonnet (coder).
- Milestone 1 has more open tasks after #22; pick the next one at the following handoff.
- The tofu Trivy entries expire 2026-10-28 (#8). 1.13.0 clears 11 of the 14 and must move together with the consumers' CI pins: terraform-cloudflare-dns#40, terraform-microsoft365-entra#25, infrastructure-core#544.
- #58 (unverified tofu `SHA256SUMS` signature) is unmilestoned, for triage.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1). This is outside #22's acceptance.

First anchor for milestone 1 with task #22, description sha `ebe3ff3e…`. The prior anchor verified `match` at this handoff, but this session's resume did not run the verify.

**HITL Gate: OPEN** — (1) merge PR #61; (2) confirm the milestone 1 / #22 anchor above, then say go.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
