# Next steps

**Now:** P0: cross-org images -- implementing; next task #12.

**Just done:**
- #75 decided and closed: DEVC-D5, the template keeps the app user at uid 1000 on every
  host. It's a DEVC-D because no repo has adopted the template yet. The README has a
  one-line Linux note. PR #111 merged as `bffc5b8`. The review gate was exempt (docs only).
- Commented on #12 with DEVC-D5's consumer obligation (Linux uid 1000), as DEVC-D5's
  consequences require, and noted that #12's draft predates #23.
- No code written this session, so no critic pass applied.

**Next:** task #12 — refresh the draft IAC-D entry for the image and token model (the
2026-09-30 comment on #12) against `README.md` and `docs/roadmap.md` at HEAD: image major
version, the volumes #23 renamed and folded, DEVC-D4, and DEVC-D5's Linux uid-1000 rule
(latest comment on #12). Post the refreshed draft as a new comment on #12, then stop: the
owner confirms the wording before anything is written in infrastructure-core.
Model: opus (architect). After #12 the proposed P0 order continues: #43, #30, #53, #25,
then #54/#69/#58, then #8 with #101.

**HITL Gate: NONE OPEN** -- the milestone 1 plan anchor verified `match` at handoff. Next
gate: the owner confirms the refreshed IAC-D wording on #12.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
