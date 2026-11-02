# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. Step 4 is built and open as PR #389.

**Just done:**
- Milestone 6 step 4 built as #389 (branch `fix/merge-guard-step4`, `5f7507c`; `Closes #170, closes #171, closes #311`).
  The first build followed the issues and fixed the hook's bash-lexer emulation shape by shape. Four critic
  rounds did not converge: each fix opened a new parser gap, and some shapes the committed hook blocked came
  through. An Opus design review concluded the hook can only be a seatbelt against mistakes, because the agent's
  shell holds the owner's admin login. The owner chose the fail-closed tripwire: the hook now refuses any command
  that holds `merge` as a word, unless it is the one admitted `/resume` cursor-sync shape. Mentions in commit
  messages and PR bodies are blocked on purpose, so such text goes in a file (`git commit -F`,
  `--body-file`, `gh api --input`). #311's status check and its fixtures are kept. Tests run in WSL.
- The owner asked whether anything besides the cursor-sync merge needs the hook. A read of the workbench plans
  found nothing else; the question is filed as claude-workbench#368 for a keep, drop or redesign decision.
- Critic pass on #389 (this session):
    Parser version: 4 rounds (architect, security-critic, docs-consistency), not converged, abandoned on the
    owner's decision; its security-critic round 4 was stopped by a safety classifier twice and never ran.
    Tripwire version: 2 rounds on the three critics; the last security-critic round found no reachable bypass
    beyond the documented residuals. The final small fixes (brace and escape refusals, empty `$()`) were tested
    but not re-read by a critic. All critics ran on their frontmatter defaults; no second-opinion round.

**Next:** on **opus** (architect), in a new window: `/way-of-working:architect-review 389`. `.claude/` is in
`code_paths`, so #389 needs that fresh-session review before the owner's merge. Read the hook header's
residuals first: it is a seatbelt, not a lock.

**HITL Gate: NONE OPEN** — next gate: the architect review of #389, then the owner's merge.

**Open for the owner (non-blocking):**
- claude-workbench#368: should `/resume`'s cursor-sync `--admin` merge exist? If it is dropped, a later PR deletes
  the hook for plain deny rules. No hook work until that is decided.
- #170 and #171 were written for the parser approach; #389 meets their rows by a different mechanism and says
  `Closes` on both. Rewrite #170 and close #171 as superseded first if preferred. The issue text and a new issue
  for the agent-credential decision (the agent's shell should not hold a bypass login; may supersede #262's
  `--admin` path; #172 tracks the threat-model half) have not been drafted or filed.
- After #389: milestone 6 goes on with its written build order. #356 fits with step 9's test-only fixes;
  #377-#379, #383, #386 and #387 are unmilestoned.
- Milestone 5 (Trivy renewal 2026-11) is due 2026-10-29. The #148 exceptions still expire 2026-11-01: if the
  tofu and tflint vendors have not shipped fixes by late October, re-scan and renew the rest at most 30 days out.
  #329 rides along.
- Any other repo that bumps way-of-working to `v0.17.0` reads `incomplete` until it answers `orchestration`,
  and needs the drive-letter mirror after `plugin update` (claude-workbench#347).
- The pilots re-copy the gate and re-pin to `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`; tracked there.
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host. Run tests in WSL, not Git Bash. `gh issue create` and `gh pr create`
  hang under Git Bash; `gh api ... --input -` with a timeout works. Write `Closes #A, closes #B`.
- Once #389 is checked out, its hook refuses any command with the word `merge` in it: write commit messages
  and PR bodies to a file with the Write tool and pass them by name.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6
