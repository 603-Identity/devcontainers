# Next steps

**Now:** P0: cross-org images — awaiting_review; #24 is built as PR #71, and PR #72 is stacked on it.

**Just done:**
- #24 built as PR #71 (`6c27b54`): `tests/template-proof.sh`, run as a step of the required "Build and smoke-test (no push)" job and mirrored in `gates.green`; threat model updated. CI green on it; only `architect-review` is red, as expected. The CLI's own setup succeeds under `--read-only` (the risk the #65 review left open).
- Critic pass on #71 (architect + docs-consistency): 2 rounds, converged; round 1 found the Linux uid rewrite by the devcontainer CLI (it leaves `/workspace/.venv` unwritable), decided by the human: the template now sets `updateRemoteUserUID: false`. The Linux path ran for the first time in #71's CI and passed.
- PR #72 (`9035e44`, branch `ci/smoke-on-image-changes`): a docs-only PR skips the image build, smoke test and template proof; the job still runs and passes, since its name is a required check. **Handed off without a critic pass** (small workflow change; zizmor clean, `case` logic checked on sample file lists). Its skip path is unexercised: #72's own CI took the build path because it touches `.github/`.
- Plan anchor re-verified against milestone 1 (`match`); `task_issue` is null on this cursor because the next action is a review, not one issue's build.

**Next:** `/way-of-working:architect-review 71`, then `/way-of-working:architect-review 72`, each in a **new session** on opus (architect). #72 carries #71's commit, so review #71 first and review #72's own change only (the `Did the images or the template change?` step and three `if:` lines). Then the human merges #71, then #72. #71 closes #24; #23's live pilot container stays open.
- The first docs-only PR after #72 merges (this cursor sync may be it) is where the skip path first runs: check that "Build and smoke-test (no push)" still reports green and skips the build.
- #68 (README migration seeds from `/etc/skel`; **fix before the infrastructure-core migration runs**), #69 and #58 are unmilestoned, for triage.
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gate is the fresh-session architect review of PR #71, then of PR #72, then the human's merge of each.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
