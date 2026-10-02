# Next steps

**Now:** P0: cross-org images -- awaiting review. #30 PR 2 is built and open as
[#136](https://github.com/603-Identity/devcontainers/pull/136) (`b70a731`); its fresh-session
architect review is next.

**Just done:**
- The owner's post-#133 steps were verified, not assumed: `selftest` is in the live
  `main-required-checks` ruleset, the `release-tags` tag ruleset exists and was read back,
  and `v1.0` is `6ac20ce`, an ancestor of `main`. The plan anchor for milestone 1 verified
  `match`, so the first-anchor gate is closed.
- Built #30 PR 2 per spec v5.2 §7 step 2: the consumer caller pinned to `v1.0`, the template
  gate's `decide` pin set to the same SHA, `tools/check-consumer-workflows.sh` with its tests,
  README steps 1-3, the Dockerfile header and the threat model.
- Critic pass on #136: security-critic, architect and docs-consistency, 4 rounds, cap reached.
  Each round found real defects and each was fixed. The last small edit (a job-shape check in
  the lint) was not re-run through a critic; it has tests. This is not the attested review.

**Next:** `/way-of-working:architect-review 136`, on **opus** (architect), in a **new
session**, not the one that built it. Then the human merges. Do not create the
`devc-automerge-on` tag.

**HITL Gate: NONE OPEN.** The next gate is the human's merge of #136 once `architect-review`
is green on its head SHA. Owner items that do not block the review: amend spec §4 to the
lint's wider scope (`push`/`create`, an explicit `permissions:` block, hosted runners); run
the tag ruleset's App-token delete negative test once the bump-binaries App exists; turning
auto-merge on stays a separate decision behind spec §7 step 4 (#122, #124, a pilot).

**Open for the owner:** the not-a-candidate row never disarms (#126, #132); the spec §5
table needs the MAJOR-bump correction (#127); buildkit v0.33.0 vs frontend 1.27.1 (#128).
Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
The gate suites are flaky on this Windows host's shared `/tmp`; they pass with a short
private `TMPDIR`, and CI on Linux is the check of record.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
