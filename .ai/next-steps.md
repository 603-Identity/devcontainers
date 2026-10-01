# Next steps

**Now:** P0: cross-org images -- implementing; next task #30 (spec first).

**Just done:**
- Posted the fresh-session architect review on PR #117 (#43, `owner-check.sh`). It had no
  findings. The `architect-review` gate went green on the head SHA, and the owner merged
  #117 (`a33a99d`). This session wrote no code, so no critic pass applied.

**Next:** task #30 — draft the design spec for the reusable image-attestation verify
workflow, its template caller and the image-bump auto-merge policy. Post it as a comment on
#30 with the open questions for the owner, and don't implement until the owner confirms it.
Model: opus (architect). After #30 the proposed P0 order continues: #53, #25, then
#54/#69/#58, then #8 with #101. #118 is unmilestoned and waits for triage.

**HITL Gate: OPEN** -- there's no session-start baseline for milestone 1's plan anchor. This
session's `/way-of-working:resume` didn't run a verify, because the prior cursor named no
task issue. The handoff re-verify printed `match` and the description sha
(`ebe3ff3e…`) is unchanged, so a human "go" clears this gate. Next gate: the owner confirms
#30's spec.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
