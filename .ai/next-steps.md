# Next steps

**Now:** P0: cross-org images -- awaiting_review, milestone 1.

**Just done:**
- Task #144 built and shipped as [#150](https://github.com/603-Identity/devcontainers/pull/150)
  (`0a384e0`): `tools/wsl-setup.sh`, the README "Working on this repo from Windows (WSL)"
  section, and the threat model Exceptions entry. `lint.yml` already shellchecks `tools/*.sh`,
  so no workflow change.
- Verified in WSL on a fresh setup: the gate suites, `build-and-test.sh local`,
  `template-proof.sh`, `go vet`/`go test`, and the other `gates.green` entries.
- Critic pass (`security-critic` + `docs-consistency`): 2 rounds, converged; second-opinion
  round offered and declined. Findings fixed: pins now shape-checked, the script runs as root
  from a root-owned temp dir, and the "cannot drift from CI" claim narrowed to Go.
- The issue's "Docker Desktop is connected to the distro" was wrong: the WSL integration had
  to be switched on for Ubuntu (the README section says so).

**Next:** `/way-of-working:architect-review 150` in a **new session** on **opus** (architect).
Once it posts and `architect-review` is green, the human merges #150, which closes #144. After
that: #118 + #69 (one PR, `git-identity.sh`), then #124, then #58, on **sonnet** (coder).

**HITL Gate: OPEN** -- first anchor for milestone 1, description sha `ebe3ff3e…`. This
session's resume never verified the prior anchor, so the handoff could not treat it as a
baseline. The sha is unchanged. The review above is not blocked by it; a human "go" is needed
before #118 + #69 starts.

**Open for the owner (non-blocking):** amend spec §4 to the lint's wider scope; run the tag
ruleset's App-token delete negative test once the bump-binaries App exists (#102). Still to
delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. Use the
JaredGroves-603 token for this repo's `gh` calls (the default Seuss27 login has no push access
here). Long WSL runs from the Windows side need one foreground `wsl` process with its log on
the Windows side: WSL wipes `/tmp` and kills detached jobs when no session is open.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
