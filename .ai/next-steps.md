# Next steps

**Now:** P0: cross-org images -- implementing. #30 PR 1 merged as
[#133](https://github.com/603-Identity/devcontainers/pull/133) (`6ac20ce`); PR 2 is next,
behind the owner's post-merge steps.

**Just done:**
- Fresh-session architect review of #133 posted (opus): no blocking findings. Spec §1-§6
  conformance read, the Go and gate suites run offline in an isolated sandbox, and planted
  mutations confirmed red for each key guard. The vendor re-diff was witnessed from CI.
  `architect-review` went green on `5dd64d1`. No new issues: the notes are already #127,
  #128 and #129.
- The owner merged #133 (`6ac20ce`).
- First anchor for milestone 1 in this handoff, description sha `ebe3ff3e…`. The resume did
  not verify the prior anchor, so the gate below also covers it.

**Next:** task #30 — build #30 PR 2 exactly as
[spec v5.2 §7 step 2](https://github.com/603-Identity/devcontainers/issues/30#issuecomment-5938653643)
lists it, on **sonnet** (coder): the template caller pinned `@<sha of v1.0> # v1.0`, the
template gate's `decide` pin set to the same, `tools/check-consumer-workflows.sh`, README
steps 1-3, the Dockerfile header, and the threat model (§8). Then the local green gate and
`/way-of-working:critic-gate`. Do not create the `devc-automerge-on` tag.

**HITL Gate: OPEN** (owner, before PR 2 can start):
1. Add `selftest` to the live `main-required-checks` ruleset.
2. Create the tag ruleset (spec §6). Read it back through the API and run the App-token
   delete as the negative test.
3. Tag `v1.0` on `6ac20ce`, after `git merge-base --is-ancestor 6ac20ce origin/main`, and
   record its SHA for PR 2.

Turning auto-merge on is a separate owner decision behind spec §7 step 4 (#122, #124, a
pilot).

**Open for the owner:** the not-a-candidate row never disarms (#126, #132); the spec §5
table needs the MAJOR-bump correction (#127); buildkit v0.33.0 vs frontend 1.27.1 (#128).
Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
