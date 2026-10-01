# Next steps

**Now:** P0: cross-org images -- implementing. #43's spec is confirmed; implementation next.

**Just done:**
- Landed the owner-confirmed image and token model as **IAC-D49** in infrastructure-core
  (603-Identity/infrastructure-core#558), and cited it in `docs/roadmap.md` (#114,
  `e028abd`). That closed #12.
- Refreshed #43's spec against `main` at `e028abd` and posted it on #43. The owner confirmed
  it: warn on a mismatch (never block), marker at `~/.devc-owner`. The spec comment is the
  approved spec and is pinned in the plan anchor.
- No code was written, so no critic pass applied.

**Next:** task #43 — implement the folder-name collision check per the owner-confirmed spec
comment https://github.com/603-Identity/devcontainers/issues/43#issuecomment-5935655420:
- `images/base/files/owner-check.sh`, called first in the template's `postStartCommand`.
- `tests/smoke.sh` and `tests/template-proof.sh` cases, as the spec lists them.
- The threat model, README rule 3, and **DEVC-D6** in `docs/roadmap.md` (amend DEVC-D3's
  "enforces" to "detects").

Run the green gate and `/way-of-working:critic-gate`, then `/way-of-working:ship`. Never merge.
Model: sonnet (coder). After #43 the proposed P0 order continues: #30, #53, #25, then
#54/#69/#58, then #8 with #101.

**HITL Gate: NONE OPEN** -- the owner confirmed #43's spec; the milestone 1 anchor verified
`match`. Next gate: the fresh-session architect-review on the #43 PR.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
