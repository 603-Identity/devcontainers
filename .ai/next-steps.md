# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1. #30 is closed and its code merged.
The README image-table versions are dropped.

**Just done:**
- #53: the version numbers are out of the README image table, exactly as the owner's
  [decision comment](https://github.com/603-Identity/devcontainers/issues/53#issuecomment-5952319289)
  specified. Merged as [#140](https://github.com/603-Identity/devcontainers/pull/140)
  (`f2529a0`); docs-only, so no critic pass and no `architect-review`.
- The owner picked #25 next, with the three threat-model gap entries folded into its PR.

**Next:** task #25 — the
[threat-model prose pass](https://github.com/603-Identity/devcontainers/issues/25#issuecomment-5914808846),
on **opus** (architect), then `/way-of-working:ship` it as a docs-only PR. #4, #43 and #30 have all
landed, so the file can describe the final state. One PR also folds in the gap entries #54, #69
and #58, which edit the same file (three separate edits would conflict). Extend what PR #35
already delivered rather than adding it twice. #69 and #58 are documented only: no change to
`git-identity.sh` or the tofu Dockerfile, and no `Closes` on them, since their fixes stay open.
README.md and `docs/threat_model.md` are outside `code_paths`: no critic pass, no
`architect-review`. Do not merge.

**HITL Gate: NONE OPEN.** The next gate is the human's merge of the #25 PR.

**Open for the owner (non-blocking):** close
[#137](https://github.com/603-Identity/devcontainers/pull/137), the superseded cursor sync;
amend spec §4 to the lint's wider scope (`push`/`create`, an explicit `permissions:` block,
hosted runners); run the tag ruleset's App-token delete negative test once the bump-binaries
App exists (#102); step 4, turning auto-merge on, is #139; the not-a-candidate row never
disarms (#126, #132); the spec §5 table's MAJOR-bump correction (#127); buildkit v0.33.0 vs
frontend 1.27.1 (#128). Still to delete in the UI: `Seuss27/devc-spike2-host` and
`glunk-works/devc-spike2-consumer`. The gate suites are flaky on this Windows host (a test can
exit 127 with no output); CI on Linux is the check of record. Use the JaredGroves-603 token for
this repo's `gh` calls (the default Seuss27 login has no push access here).

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
