# Next steps

**Now:** P1: pilot adoption (milestone 2). Implementing.

**Just done** (architect session, last_commit `8e81a50`):
- The owner pushed `v1.2` (annotated, peels to `d83d655`).
- Posted the fresh-session architect review on #222, which went green. The review ran in a WSL
  sandbox: the consumer lint and gate suites passed, and a planted tag-pin mutation was caught.
  No findings were filed. The owner merged #222 (`8e81a50`), so the template now pins
  secret-scan `v1.2`.
- Both pilots still pin secret-scan `5bccf29 # v1.1`, and no open PR in either repo bumps it.

**Next:** task #10 — in `terraform-cloudflare-dns` and `terraform-microsoft365-entra`, open one
PR each that repins `.github/workflows/secret-scan.yml` to
`d83d655d756c1f91ce3fbb5674696654626f080f # v1.2`, byte for byte the template's line. Check
first that no open PR in that repo already does it. Never merge. Model: **sonnet** (coder).

**HITL Gate: OPEN.** Confirm the milestone 2 plan anchor (description sha `3c385bea...`, now
naming task #10). `verify --plan` matched the prior anchor, but this session never ran a
resume-time verify, so it is a gate.

**Open for the owner (non-blocking):**
- #10, still to do: one real image bump through the review path (the precondition for #139); a
  PR on -entra showing the `verify / verify` pin blocks; tick #10's checklist; answer whether the
  forwarded GPG agent should expose the personal and org keys, and whether a persistent `/tmp` is
  intended.
- Check #212's items against #215 and close what it covers. #220 is open (non-blocking).
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
  Git Bash (Git Bash hangs the consumer-lint suite). Open the devcontainer from PowerShell, not
  Git Bash. GPG signing can time out on a pinentry prompt on the Windows side; a retry after
  entering the passphrase works.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/2
