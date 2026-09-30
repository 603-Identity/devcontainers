# Next steps

**Now:** P0: cross-org images — awaiting_review (PR #45 reviewed, waiting on the human's merge).

**Just done:**
- Fresh-session architect review of PR #45 (#22's version standard) posted as a comment on head `39817f1`. No blocking findings. The `architect-review` gate went green; `/way-of-working:pr-checks` verdict: READY.
- Verified independently: the gh, uv and `dockerfile:1.27` pins against their upstream sources, and a mutation witness of `build-and-test.sh`'s early exit. Build and smoke were not witnessed (the PR edits `.github/` and `uv.lock`); the CI log is recorded in the review as informational.
- Filed the three non-blocking findings: #47 (Dependabot group), #48 (credential helper via PATH), #49 (README versions). Owner decisions are recorded as comments on each.
- Owner decisions on #45's open questions: keep `ENV PATH` prepended; handle `bc-detect-secrets` with #47's `exclude-patterns`, not an `ignore`.

**Next:** after the human merges PR #45, cut one branch from `main` and implement #47, #48 and #49 as one follow-up PR, each as its owner-decision comment specifies. Model: sonnet (coder).
- #22 stays open after #45 merges: the `.trivyignore.yaml` tofu 1.11 and npm 11 entries wait on #7 and #16.
- Not yet recorded: the version standard as an IAC-D in infrastructure-core (DEVC-D1).

**HITL Gate: OPEN** — the human's merge of PR #45. The follow-up needs #45 on `main`, since it edits lines #45 introduces.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
