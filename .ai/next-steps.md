# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1. #30's code is complete: PR 1
([#133](https://github.com/603-Identity/devcontainers/pull/133)) and PR 2
([#136](https://github.com/603-Identity/devcontainers/pull/136), `92ff9ef`) have both merged.

**Just done:**
- Fresh-session `architect-review` of #136 on opus, posted against head `b70a731`, gate green
  (commit status). No blocking findings. Verified locally in an isolated sandbox: the `v1.0`
  pin is `6ac20ce`, the called workflows' permissions fit both callers, the lint passes on
  the template, a planted mutation turned exactly its test red, and the docs match the v1.0
  verifier code. Nothing was filed; the review's notes are owner items already listed below.
- The owner merged #136 as `92ff9ef`.
- The owner picked #53 next and decided it: drop the versions. The spec is the
  [decision comment](https://github.com/603-Identity/devcontainers/issues/53#issuecomment-5952319289),
  anchored with #53 in the plan anchor (milestone 1 re-verified `match`).

**Next:** task #53 — drop the version numbers from the README image table exactly as the
[decision comment](https://github.com/603-Identity/devcontainers/issues/53#issuecomment-5952319289)
specifies, on **sonnet** (coder), then `/way-of-working:ship` it as a docs-only PR. README.md is
outside `code_paths`: no critic pass, no `architect-review`. Do not merge.

**HITL Gate: NONE OPEN.** The next gate is the human's merge of the #53 PR.

**Open for the owner (non-blocking):** close #30, or keep it open until spec §7 step 4 (its
step 3 pilots are #10, milestone 2); close
[#137](https://github.com/603-Identity/devcontainers/pull/137), the superseded cursor sync;
amend spec §4 to the lint's wider scope (`push`/`create`, an explicit `permissions:` block,
hosted runners); run the tag ruleset's App-token delete negative test once the bump-binaries
App exists (#102); the not-a-candidate row never disarms (#126, #132); the spec §5 table's
MAJOR-bump correction (#127); buildkit v0.33.0 vs frontend 1.27.1 (#128). Still to delete in
the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. The gate suites are
flaky on this Windows host (a test can exit 127 with no output); CI on Linux is the check of
record.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
