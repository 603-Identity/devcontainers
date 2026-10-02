# Next steps

**Now:** P0: cross-org images -- awaiting_review, milestone 1.

**Just done:**
- [#163](https://github.com/603-Identity/devcontainers/pull/163) open for #58 (head `56ae52d`):
  - `tofu_1.13.0_SHA256SUMS` was verified by hand against its cosign keyless signature. The
    signer identity, issuer and source commit are recorded beside `TOFU_SHA256`, with a repeat
    recipe that binds the signature to the tag commit and the pin and fails closed.
  - `docs/threat_model.md` Known gaps now names every ARG-pinned upstream's signing or
    provenance mechanism, and README's bump checklist names the record. No build change.
- Green gate passes on `56ae52d` (shellcheck and the gate tests in WSL; they don't run in Git Bash).
- Critic pass: security-critic, docs-consistency, architect -- 3 rounds, converged. Round 2
  found a fail-open in the recipe (an empty workflow-sha skipped cosign's check), fixed and
  reproduced. A second-opinion round on fable was offered and declined.
- Filed #164: `resolve_yq` reads the tarball's hash, but the image pins the raw binary.

**Next:** `/way-of-working:architect-review 163`, in a **new session** (fresh-session review
gate). Model: **opus** (architect). Wait for the PR's `Build and smoke-test (no push)` check to
go green first. After it merges, pick the next task in milestone 1.

**HITL Gate: NONE OPEN** -- the milestone 1 anchor re-verified (`match`) at this handoff,
refreshed with no task issue (the next action is a review, not a task build). Next gate: the
fresh-session architect review on #163, then the owner's merge.

**Open for the owner (non-blocking):**
- **Merging #163 publishes images.** It touches `images/`, so it publishes a full tag set, and
  every consumer gets a Dependabot PR for a comments-only change. Merge just after Monday's
  scheduled rebuild to avoid the extra round.
- **Close #162 unmerged.** This PR supersedes it. Merging this docs-only PR is the live proof
  that `publish` skips: watch the `scope` job give `build=0`.
- Amend spec §4 to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account can flip to Seuss27: use the JaredGroves-603 token for this repo's
  `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process. From Git Bash, set
  `MSYS_NO_PATHCONV=1` before passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
