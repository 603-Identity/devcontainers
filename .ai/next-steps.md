# Next steps

**Now:** P1: pilot adoption (milestone 2) -- blocked on the owner's `v1.2` tag push.

**Just done** (architect session, last_commit `e28b10b`):
- Posted the fresh-session architect review on #218, which went green. The review ran in a WSL
  sandbox: the suite passed, two planted mutations were each caught, and the root cause was
  confirmed on terraform-cloudflare-dns#49. The owner merged #218 (`d83d655`, closes #211) and #219.
- Filed #220 (non-blocking): a `start_line` of 0 still emits `line=0`.
- First plan anchor for milestone 2 written at handoff, description sha `3c385bea...`. It equals
  the prior anchor (`verify --plan` printed match), but this session's resume never verified it,
  so it is a gate.

**Next:** after the owner pushes `v1.2`, open a PR that repins
`template/.github/workflows/secret-scan.yml` from `5bccf29 # v1.1` to
`d83d655d756c1f91ce3fbb5674696654626f080f # v1.2`. Check first that the tag resolves to that SHA.
Model: **sonnet** (coder). The PR touches `template/`, so the review gate applies.

**HITL Gate: OPEN.** The owner pushes the `v1.2` tag on `d83d655`, after
`git merge-base --is-ancestor d83d655 origin/main`. The session does not cut it. The owner also
confirms the milestone 2 anchor above.

**Open for the owner (non-blocking):**
- #10, still to do: one real image bump through the review path (the precondition for #139); a
  PR on -entra showing the `verify / verify` pin blocks; tick #10's checklist; answer whether the
  forwarded GPG agent should expose the personal and org keys, and whether a persistent `/tmp` is
  intended.
- Check #212's items against #215 and close what it covers.
- After the pilots: #191 removes bc-detect-secrets and #186, and the follow-up PR drops
  `Secret scan (detect-secrets)` from each pilot's ruleset; close #187-#189 when #191 lands.
- Decide whether the image should ship a wrapper script for the betterleaks hook's `env` prefix.
- Still to do under #190: lint that a consumer's pinned SHA is an ancestor of `main`. Cosign
  (pinned in `bump-binaries.yml`) is bumped by hand; a Betterleaks bump also means a new `vX.Y` tag.
- Fix now in other repos: jrg-consulting-site#131 and glunk-works/pm-agent-loop#13.
- **#148 is date-bound:** renew or retire the Trivy exceptions before 2026-11-01 (milestone 5).
- Decide whether the declined re-prompt option from #5 needs a `DEVC-D` entry. Amend spec §4
  to the lint's wider scope.
- Run the tag ruleset's App-token delete negative test once the bump-binaries App exists (#102).
- Still to delete in the UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- The active `gh` account can flip to Seuss27: pass
  `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for this repo's `gh` calls.
- Run WSL jobs from the Windows side as one foreground `wsl` process; run tests in WSL, not
  Git Bash. Open the devcontainer from PowerShell, not Git Bash. GPG signing can time out on a
  pinentry prompt on the Windows side; a retry after entering the passphrase works.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
