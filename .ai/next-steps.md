# Next steps

**Now:** P0: cross-org images — awaiting_review (PR #51 open, waiting on the fresh-session architect review, then the human's merge).

**Just done:**
- PR #45 merged by the human. Cut `fix/47-48-49-followups` from `main` and opened PR #51 (head `f5838aa`), closing #47, #48 and #49 as their owner-decision comments specify.
- Local green gate passed on the round-1 fix tree (hadolint, shellcheck on `tests/smoke.sh`, `build-and-test.sh local`); later rounds changed comments and one doc phrase only.
- Critic pass on PR #51: docs-consistency, security-critic and architect, 3 rounds, converged, all on the critics' own default models; no second-opinion round (declined). Round 1 caught my `exclude-patterns` line on the github-actions group instead of `uv` `python-tools`, now fixed. The rest were wording: the helper comments now say the absolute path is accidental-shadowing hygiene, and `docs/threat_model.md` boundary 8 records it.
- Known gap, not fixed: other tools (git, pre-commit, tofu) still resolve through the prepended `~/.local/bin`. The owner kept that PATH order; worth a threat-model known-gaps note.

**Next:** run `/way-of-working:architect-review 51` in a fresh session. Model: opus (architect). Never approve or merge.
- #22 stays open: the `.trivyignore.yaml` tofu 1.11 and npm 11 entries wait on #7 and #16.
- Not yet recorded: the version standard as an IAC-D in infrastructure-core (DEVC-D1).

**HITL Gate: OPEN** — the fresh-session architect review of PR #51, then the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
