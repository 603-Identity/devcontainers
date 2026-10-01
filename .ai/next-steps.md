# Next steps

**Now:** P0: cross-org images -- implementing; task #12 continues.

**Just done:**
- Refreshed the draft IAC-D entry for the image and token model against README.md and
  docs/roadmap.md at `5072b61`, and posted it on #12
  ([comment](https://github.com/603-Identity/devcontainers/issues/12#issuecomment-5935391574)).
  The changes: image major version 4, the credential in `<repo>-home`, the shared volume is
  `devc-tofu-plugins`, the DEVC-D5 uid-1000 obligation, and the token tiers. DEVC-D4 is
  cited only.
- The owner confirmed the wording. That's recorded on #12, and the draft comment is now
  the plan anchor's spec comment.
- No code written this session, so no critic pass applied.

**Next:** task #12 — land the owner-confirmed IAC-D entry (spec:
https://github.com/603-Identity/devcontainers/issues/12#issuecomment-5935391574) in
603-Identity/infrastructure-core. That's one PR there: add the entry to
`docs/iac_migration_roadmap.md` under the next free IAC-D number, verbatim from the spec's
Context/Decision/Consequences, and add `DEVC-D` (603-Identity/devcontainers) to IAC-D48's
series list. Then, here, one docs PR cites that number in `docs/roadmap.md`'s table of IAC-D
decisions that bind this repo. Never merge either.
Model: opus (architect). After #12 the proposed P0 order continues: #43, #30, #53, #25,
then #54/#69/#58, then #8 with #101.

**HITL Gate: NONE OPEN** -- the owner confirmed the IAC-D wording on #12 (2026-10-01).
The milestone 1 anchor verified `match` at handoff. Next gate: the owner merges the
infrastructure-core PR.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
