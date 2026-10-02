# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1. #30's code is complete: PR 1
([#133](https://github.com/603-Identity/devcontainers/pull/133)) and PR 2
([#136](https://github.com/603-Identity/devcontainers/pull/136), `92ff9ef`) have both merged.
An owner decision comes before the next task.

**Just done:**
- Fresh-session `architect-review` of #136 on opus, posted against head `b70a731`, gate green
  (commit status). No blocking findings. Verified locally in an isolated sandbox: the `v1.0`
  pin is `6ac20ce`, the called workflows' permissions fit both callers, the lint passes on
  the template, a planted mutation turned exactly its test red, and the docs match the v1.0
  verifier code. Nothing was filed; the review's notes are owner items already listed below.
- The owner merged #136 as `92ff9ef`.
- The milestone-1 plan anchor re-verified `match`. No task is anchored (`task_issue: null`),
  so the next `/way-of-working:resume` waits.

**Next:** owner decision (the HITL Gate below), then the chosen milestone-1 task on **opus**
(architect) for its spec, or straight to a coder if it is small. Do not create the
`devc-automerge-on` tag.

**HITL Gate: OPEN.** For the owner to decide:
1. Close #30 now, with spec §7 step 3 (pilots) carried by #10 in milestone 2 and step 4
   (turning auto-merge on) behind its preconditions (#122, #124, a pilot), or keep #30 open
   until step 4 is decided.
2. Pick the next task: the rest of milestone 1, or move to milestone 2 (#10 pilots). #8 has
   a date: the `tofu` image's Trivy exceptions expire 2026-10-30.
3. Close [#137](https://github.com/603-Identity/devcontainers/pull/137), the earlier cursor
   sync (PR 2 built, review next). This PR replaces it.

**Open for the owner (non-blocking):** amend spec §4 to the lint's wider scope (`push`/`create`,
an explicit `permissions:` block, hosted runners); run the tag ruleset's App-token delete
negative test once the bump-binaries App exists; the not-a-candidate row never disarms (#126,
#132); the spec §5 table's MAJOR-bump correction (#127); buildkit v0.33.0 vs frontend 1.27.1
(#128). Still to delete in the UI: `Seuss27/devc-spike2-host` and
`glunk-works/devc-spike2-consumer`. The gate suites are flaky on this Windows host (a test can
exit 127 with no output); CI on Linux is the check of record.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
