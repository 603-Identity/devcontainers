# Next steps

**Now:** P0: cross-org images -- implementing. #12 is done; #43 is next.

**Just done:**
- Landed the owner-confirmed image and token model as **IAC-D49** in infrastructure-core
  (603-Identity/infrastructure-core#558, `6b9ed8d`). It also adds `DEVC-D` to IAC-D48's series
  list. The full entry is a subsection under the Decisions Log table, because its obligation
  list doesn't fit in a table cell.
- Cited IAC-D49 in `docs/roadmap.md`'s IAC-D table (#114, `e028abd`). That closes #12.
- No code was written, so no critic pass applied.

**Next:** task #43 — refresh #43's spec against main at `e028abd` and post it as a comment on
#43 for the owner to confirm. Write no code. The body predates #23:
- The marker now belongs in the `<repo>-home` volume. There is no `-gh` volume.
- The per-repo volumes are `-home`, `-tmp`, `-node_modules` and `-venv`.
- The decision it cites as DEVC-D6 was never minted.

Check the plan against README.md's folder-name rule, `docs/threat_model.md`'s "Folder-name
uniqueness is unenforced" gap, IAC-D49 (consumer obligation 4) and DEVC-D3. Settle where
the check runs (the image's start-up script or the template), and how the test covers both
the match and mismatch cases. Never merge.
Model: opus (architect). After #43 the proposed P0 order continues: #30, #53, #25, then
#54/#69/#58, then #8 with #101.

**HITL Gate: NONE OPEN** -- the milestone 1 anchor verified `match` at handoff. Next gate:
the owner confirms the refreshed #43 spec before any code is written.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
