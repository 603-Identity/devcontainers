# Next steps

**Now:** P0: cross-org images — awaiting_review; #24 is built and merged as PR #71, and PR #76 (skip the image build on docs-only PRs) awaits its architect review.

**Just done:**
- #24 built as PR #71: `tests/template-proof.sh`, run as a step of the required "Build and smoke-test (no push)" job and mirrored in `gates.green`; threat model updated. Reviewed in a fresh session against its head `6c27b54`, then merged by the human (`7b9839d`). The CLI's own setup succeeds under `--read-only`, and the Linux path passed in CI.
- Critic pass on #71 (architect + docs-consistency): 2 rounds, converged; round 1 found the devcontainer CLI's Linux uid rewrite (it leaves `/workspace/.venv` unwritable), decided by the human: the template now sets `updateRemoteUserUID: false`.
- PR #72 was branched off #71's pre-squash commit and conflicted after the squash-merge; closed and replaced by **PR #76** (`a5ecd9a`), the same one-file change cherry-picked onto `main`. A docs-only PR skips the image build, smoke test and template proof; the job still runs and passes, since its name is a required check. **No critic pass ran on it** (small workflow change; zizmor clean, `case` logic checked on sample file lists). Its skip path is unexercised: #76's own CI takes the build path because it touches `.github/`.
- Plan anchor re-verified against milestone 1 (`match`); `task_issue` is null on this cursor because the next action is a review, not one issue's build.

**Next:** `/way-of-working:architect-review 76` in a **new session** on opus (architect); review #76's own change only (the `Did the images or the template change?` step and three `if:` lines). Then the human merges it.
- After #76 merges, the first docs-only PR is where the skip path first runs: check that "Build and smoke-test (no push)" reports green with `build=0` and skips the build. Re-running #73's checks after the merge would show it.
- #23 stays open for its live pilot container.
- #68 (README migration seeds from `/etc/skel`; **fix before the infrastructure-core migration runs**), #69 and #58 are unmilestoned, for triage.
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gate is the fresh-session architect review of PR #76, then the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
