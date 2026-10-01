# Next steps

**Now:** P0: cross-org images -- implementing; next task #4 (a decision, not a build).

**Just done:**
- #68 shipped: PR #105 merged as `d914d2a` (README migration seeds from `/home/app`).
- #98 closed: image and every consumer moved to OpenTofu 1.13.0. Image PR #106 merged as
  `28f388c`; consumer PRs terraform-cloudflare-dns #44, terraform-microsoft365-entra #26,
  infrastructure-core #548 and glunk-works/bounty-infra #155. Post-merge real-infra and
  tenant plan runs were green; bounty-infra's production apply was deliberately not run.
  1.13's `tofu init` rewrote one lock file in infrastructure-core (committed and baselined).
- Critic pass: handing off without one (the #106 diff touched `images/`; it merged on the
  human's own review path, no `/way-of-working:critic-gate` ran this session).
- #8 (Trivy exception renewal, due 2026-10-30) now has only the 17 tflint entries to renew;
  every tofu-only exception is gone.

**Next:** task #4 — decide whether the images should ship the claude CLI. Draft a
recommendation (the issue argues against adding it to `base` and `tofu`; keep its
plugin-hook mode finding either way), bring it to the human, and on their decision record it
as a DEVC-D in `docs/roadmap.md` and comment on #4. No image change unless the decision is
to add it. Model: opus (architect). After #4 the proposed P0 order continues: #75, #12, #43,
#30, #53, #25, then #54/#69/#58, then #8 with #101.

**HITL Gate: OPEN** -- #4 is a decision: the human must choose whether the images ship the
claude CLI before anything is recorded or changed. The milestone 1 plan anchor verified
`match`, so no anchor gate is open. This session will wait for a human "go", not auto-start.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
