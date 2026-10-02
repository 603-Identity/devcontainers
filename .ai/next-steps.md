# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1.

**Just done:**
- #25: the threat-model prose pass, with the #54, #69 and #58 gap entries, merged as
  [#142](https://github.com/603-Identity/devcontainers/pull/142) (`f49b191`); closed #25 and #54.
  Docs-only, so no critic pass and no `architect-review`. #69 and #58 stay open for their fixes.
- `/way-of-working:plan-sprint` triaged every unmilestoned issue (each carries a dated
  `[plan-sprint]` comment): #107, #118 and #124 into P0; the rest into "Repo hardening: review
  gate and CI". Nothing staged.
- Proposed P0 order (not published in the milestone): #8 + #101 + #107 in one PR (the
  `.trivyignore.yaml` expiry on 2026-10-28 is the hard date); then #118 + #69 in one PR
  (`git-identity.sh`); then #124 (publish only on image-affecting changes); then #58.

**Next:** task #8 — renew or remove the `.trivyignore.yaml` exceptions before 2026-10-28, on
**sonnet** (coder). Fold in #101 (rewrap the long header line) and #107 (replace the
"moves only together" tofu pin wording with the consumer-side rule, in
`images/tofu/Dockerfile` and `.trivyignore.yaml`). One PR in `code_paths`: green gate, then
`/way-of-working:critic-gate`, then `/way-of-working:ship`. Do not merge.

**HITL Gate: NONE OPEN.** The next gate is the critic-gate pick on the #8 diff, then the
fresh-session `architect-review` and the human's merge.

**Open for the owner (non-blocking):** close
[#137](https://github.com/603-Identity/devcontainers/pull/137), the superseded cursor sync;
amend spec §4 to the lint's wider scope; run the tag ruleset's App-token delete negative test
once the bump-binaries App exists (#102). Still to delete in the UI:
`Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. The gate suites are flaky
on this Windows host (a test can exit 127 with no output); CI on Linux is the check of
record. Use the JaredGroves-603 token for this repo's `gh` calls (the default Seuss27 login
has no push access here).

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
