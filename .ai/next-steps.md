# Next steps

**Now:** P0: cross-org images -- awaiting_review, milestone 1.

**Just done:**
- Task #8 (with #101 and #107) is open as
  [#145](https://github.com/603-Identity/devcontainers/pull/145) (`eb96023`): the 17
  `.trivyignore.yaml` exceptions renewed to 2026-11-01, the long header line rewrapped, and
  the tofu pin wording replaced with the consumer-side rule. The re-scan matched every
  entry, and tofu 1.13.1 and tflint 0.64.0 fix none of them, so nothing was removed.
- Critic pass (`security-critic`, `architect`): 1 round, converged, no fixes applied, no
  second-opinion round. Local green gate: gates 1, 2, 4 and 7 passed; the rest did not run
  on this Windows host, so CI is the check of record.
- Leftover, out of #107's scope: README.md and `.github/dependabot.yml` still say "bump
  together". Worth one follow-up change.

**Next:** `/way-of-working:architect-review 145` on **opus** (architect), in a **new
session**: the `architect-review` check is red until a fresh-session review is posted on the
head SHA. Do not approve, do not merge. After the human merges #145, the order is #118 + #69
(one PR, `git-identity.sh`), then #124, then #58.

**HITL Gate: NONE OPEN.** The next gate is the review on #145, then the human's merge.

**Open for the owner (non-blocking):** close
[#137](https://github.com/603-Identity/devcontainers/pull/137), the superseded cursor sync;
amend spec §4 to the lint's wider scope; run the tag ruleset's App-token delete negative test
once the bump-binaries App exists (#102). Still to delete in the UI:
`Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. The gate suites are flaky
on this Windows host (a test can exit 127 or hang with no output); CI on Linux is the check
of record. Use the JaredGroves-603 token for this repo's `gh` calls (the default Seuss27 login
has no push access here).

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
