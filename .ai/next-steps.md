# Next steps

**Now:** P0: cross-org images — implementing; next task #23 (one home volume, read-only root filesystem).

**Just done:**
- PR #61 merged (`1dc3ec4`), so npm 12 is in and the npm Trivy entries are gone.
- #22 (version standard) closed as completed on `3970b98`: each of its five Acceptance boxes was re-verified with file:line evidence, posted as one comment on #22.
- The post-merge `Build images` run on `1dc3ec4` was still in progress at close; the PR's required smoke check had passed before the merge.

**Next:** task #23 — build the layout in #23's Change section: template and base-image changes, the `tests/smoke.sh` mount-point ownership assertions, the README volumes table, and the threat-model boundary. Open a PR; do not close #23. Acceptance boxes needing the template CI proof (#24) or a live pilot container are reported as deferred, not claimed. Model: sonnet (coder).
- Milestone 1 has more open tasks after #23; pick the next one at the following handoff.
- The tofu Trivy entries expire 2026-10-28 (#8). 1.13.0 clears 11 of the 14 and must move together with the consumers' CI pins: terraform-cloudflare-dns#40, terraform-microsoft365-entra#25, infrastructure-core#544.
- #58 (unverified tofu `SHA256SUMS` signature) is unmilestoned, for triage.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

No critic pass: this session wrote no code.

**HITL Gate: NONE OPEN** — next gate is the human's merge of the #23 PR after its architect review.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
