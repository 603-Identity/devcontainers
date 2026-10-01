# Next steps

**Now:** P0: cross-org images -- implementing; next task #75.

**Just done:**
- #4 decided and closed: DEVC-D4, no image ships the claude CLI. PR #109 merged as
  `1788b7a`. Its fresh-session review was exempt (docs only, no `code_paths` touched).
- No code written this session, so no critic pass applied.

**Next:** task #75 — record `updateRemoteUserUID: false`
(`template/.devcontainer/devcontainer.json`) as a decision. Pick its prefix per DEVC-D1's
test: the template is copied into every consuming repo, glunk-works included, which points
to IAC-D in infrastructure-core's log. If it lands as IAC-D, stop and bring the cross-repo
entry to the human before writing in infrastructure-core; otherwise add the DEVC-D entry to
`docs/roadmap.md`. Either way add a one-line Linux note to `README.md`'s Consuming section
(host uid must be 1000, or `/workspace` is read-only), shipped as one PR.
Model: opus (architect). After #75 the proposed P0 order continues: #12, #43, #30, #53,
#25, then #54/#69/#58, then #8 with #101.

**HITL Gate: NONE OPEN** -- the milestone 1 plan anchor verified `match` at handoff. Next
gate: human approval of an IAC-D entry if #75 takes that prefix.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
