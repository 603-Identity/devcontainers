# Next steps

**Now:** P0: cross-org images -- awaiting_review. #43 is implemented and open as PR #117.

**Just done:**
- Implemented #43 as PR #117 (`418d5b2`): `owner-check.sh`, its template call, smoke and
  template-proof cases, the threat model and README updates, and DEVC-D6.
- Local green gate passed on the finished tree. The critic pass (security-critic,
  architect, docs-consistency) ran 2 rounds on default models and converged; its findings
  were fixed. It is not the review gate.
- Filed the follow-ups: #118 (`git-identity.sh` reads the origin through the home volume's
  git config) and infrastructure-core#559 (IAC-D49 text after #117 merges).

**Next:** `/way-of-working:architect-review 117` -- the fresh-session architect review of
PR #117; post it, verify the `architect-review` check on the head SHA, file non-blocking
findings. Never approve, never merge. Model: opus (architect), in a **new window**: this
crosses the review gate. After #117 merges the proposed P0 order continues: #30, #53, #25,
then #54/#69/#58, then #8 with #101; #118 is unmilestoned for triage.

**HITL Gate: NONE OPEN** -- the human reviews and merges #117 after the review goes green.
Next gate: that merge. The milestone 1 anchor re-verified `match`; this cursor holds no task
issue, so the next `/way-of-working:resume` waits for a human "go", as intended.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
