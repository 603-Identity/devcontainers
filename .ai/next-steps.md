# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1.

**Just done:**
- [#145](https://github.com/603-Identity/devcontainers/pull/145) merged as `2b7b352`
  (task #8 with #101 and #107): the `.trivyignore.yaml` exceptions renewed to 2026-11-01
  and the tofu pin rule reworded.
- Fresh-session architect review of #145 posted on `eb96023`; `architect-review` went
  green. Reproduced locally in the review sandbox: the gate passes, every exception still
  matches a live finding, and a back-dated entry turns the gate red.
- Filed from that review: #147 (README.md and `.github/dependabot.yml` still state the old
  lockstep rule) and #148 (track the 2026-11-01 expiry now that #8 is closed).

**Next:** task #144 — make WSL this repo's local Linux environment: a pinned setup
script, its lint.yml shellcheck entry, the README section, and the threat model
Exceptions entry, per the issue's "Done when". On **sonnet** (coder), then
`/way-of-working:critic-gate` and `/way-of-working:ship`. After #144 closes: #118 + #69 (one
PR, `git-identity.sh`), then #124, then #58.

**HITL Gate: OPEN** -- first anchor for milestone 1, description sha `ebe3ff3e…`. This
session's resume never verified the prior anchor, so the handoff could not treat it as a
baseline. The sha is unchanged, but a human "go" is needed before #144 starts.

**Open for the owner (non-blocking):** amend spec §4 to the lint's wider scope; run the tag
ruleset's App-token delete negative test once the bump-binaries App exists (#102). Still to
delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. The
gate suites are flaky on this Windows host (a test can exit 127 or hang with no output); CI
on Linux is the check of record until #144 lands. Use the JaredGroves-603 token for this
repo's `gh` calls (the default Seuss27 login has no push access here). The review sandbox
needs `DOCKER_CONFIG` pointed at its own home, with buildx copied in, to build images on this
host.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
