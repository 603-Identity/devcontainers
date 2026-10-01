# Next steps

**Now:** P0: cross-org images -- awaiting_review. #30 PR 1 is open as
[#133](https://github.com/603-Identity/devcontainers/pull/133), head `5dd64d1` on
`feat/devc-verify-gate-30`.

**Just done:**
- Owner approved the #30 spec v5.2 (comment 5938713093); the gate was cleared and the plan anchor
  re-anchored to #30's new `updated_at` (the approval comment had bumped it).
- Built PR 1 exactly as spec §6 lists it: the vendored Go verifier `tools/devc-verify`, the two
  reusable workflows, the gate scripts and rendered template gate, `verify-selftest.yml`, and
  the lint, Dependabot, `code_paths` and `required_checks` changes. Local green gate passed.
- Coder-side critic pass (`security-critic` + `architect`): 2 rounds, converged. No
  second-opinion round (declined). It caught two ship-stoppers, now fixed: `job.workflow_ref` in
  job-level `env:` (both reusable workflows would not have started) and scripts committed
  without the exec bit. This is NOT the review CI gate.
- Filed the follow-ups as #122 through #132. #122 and #124 are preconditions for auto-merge.

**Next:** `/way-of-working:architect-review 133` in a **new session** on **opus** (architect).
Post the review, verify `architect-review` is green on the head SHA, file non-blocking findings.
Never approve or merge. Do not create the `devc-automerge-on` tag.

**HITL Gate: NONE OPEN.** After the human merges #133: add `selftest` to the live
`main-required-checks` ruleset, add the tag ruleset, tag `v1.0` (spec §6; check
`git merge-base --is-ancestor <sha> origin/main` first). PR 2 follows (spec §7 step 2).
Turning auto-merge on is a separate owner decision behind spec §7 step 4.

**Open for the owner:** the not-a-candidate row never disarms (#126, #132); the spec §5 table
needs the MAJOR-bump correction (#127); buildkit v0.33.0 vs frontend 1.27.1 (#128). Still to
delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
