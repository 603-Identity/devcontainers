# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. The driver is running lanes while the owner re-plans
M6. Image builds are blocked on CVE-2026-97054 until PR #628 (#625) merges.

**Just done:**
- #550 merged as #623 (`167f3e5`): a root `CLAUDE.md`, gated through `code_paths`.
- CVE-2026-97054 (Go `net/http`) turned every image build red. Filed #625. Its first two spec drafts escalated,
  so the owner posted a short spec of their own. The #625 lane opened PR #628, which adds a yq exception and
  deletes rockcraft's `/usr/bin/pebble`. The base image now passes. The tofu image fails on the same CVE in
  `tofu` and `tflint`, both already at their latest upstream release (build report on #628, comment
  7014442873).
- Filed #626 (a procedure and script for adding an exception) and #627 (a daily scan of the published
  images), after #625's critic loops. #626's spec escalated. #627's spec was approved and its lane prepped.
- #423 re-specced under the owner's amend answer. The spec was approved and its lane prepped. It ends in a
  Procedure B hand-off. The 1.32.0 index digest the driver read is
  `sha256:3014cc8f68f663935f69b3c3e0e41f5ce102b268d97db13db0f62208747f860d`.
- #377's PR #622: the diff matches the spec. Its build is red only on the CVE.
- Critic passes: the driver session wrote no code, so it ran no critic gate. The lanes and spec sessions
  record their own.

**Next:** Driver, on **opus** (architect):
- Act on the owner's #628 tofu/tflint choice: relay the fix round to the #625 lane, then read the new build
  across all five images.
- Restart `lane.sh wait` for 625, 423 and 627.
- Check the Procedure B bundles for #423 and #627 when they land.
- After #628 merges, rerun #622's build.
- Review #626's respec when it posts.
- Clean up the #550, #553 and #607 lanes once their sessions exit.

**HITL Gate: OPEN** — the owner decides PR #628's tofu/tflint finding (CVE-2026-97054 in
`usr/local/bin/tofu` and `usr/local/bin/tflint`, both at their latest upstream release: two more path-scoped
entries in the same fix round, or a separate issue); answers #626's escalation 7012712712 (driver recommends
choice=apply) and re-specs it; re-plans M6 (build order, #397, the merge-guard cluster #394 versus #170,
#171, #311, #172 and #272, and placement of #626 and #627, which the driver put on M6 to prep its lane).
Owner decisions carried, not blocking: claude-workbench#368 and the proposed #170/#171 issue edits.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md`. #612's note on token reach
  still applies.
- way-of-working v0.38.0 is out (the pin is v0.37.0). Its migration is the admin-token move (#1608).
- Leftover spec worktrees under `/tmp/lanes`: clear them with `wowl 603-Identity/devcontainers -SpecSweep`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
