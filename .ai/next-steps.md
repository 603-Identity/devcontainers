# Next steps

**Now:** P0: cross-org images — awaiting_review; PR #65 built for task #23 (one home volume, read-only root filesystem).

**Just done:**
- Built #23 as PR #65 (head `b1a50d4`): `<repo>-home` volume, shared `devc-cache` nested at `~/.cache` (tofu provider cache only), `--read-only` + tmpfs + `init`, `git-identity.sh` rewriting `~/.gitconfig` at every start, smoke assertions, README table and threat model.
- Owner decisions during the critic pass: npm cache is per repo (deviates from #23's table; noted on #23), image `MAJOR` is 4 in `build.yml`, and the README migration is generic since no repo has adopted yet.
- Critic pass (architect, security-critic, docs-consistency): initial pass + 3 fix-and-re-run rounds, converged (round 3 tightenings plus one low defect, fixed in `b1a50d4` with a smoke case). The final fix was not re-reviewed by a critic. All critics on their default models; no second-opinion round.
- Pilot checks that need real VS Code are a checklist on #10 (milestone 2).

**Next:** `/way-of-working:architect-review 65` in a NEW session, on opus (architect). Do not close #23: the template CI proof (#24) and a live pilot container are still open. After the human merges #65, build #24 (milestone 1 has more open tasks; pick at the next handoff).
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins.
- #58 (unverified tofu `SHA256SUMS` signature) is unmilestoned, for triage.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gate is the human's merge of PR #65 after its architect review.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
