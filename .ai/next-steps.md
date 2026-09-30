# Next steps

**Now:** P0: cross-org images — implementing, between tasks (PR #51 merged as `ec979d7`; the next task isn't picked yet).

**Just done:**
- Posted the fresh-session architect review on PR #51 (head `f5838aa`), as a comment only. Verdict: in scope, correct, no blocking findings. The gate went green and the human merged it; #47, #48 and #49 are closed.
- The review built the base image in an isolated sandbox. Smoke passes at head. Reverting the helper to a bare `gh` turns the new absolute-path check and the credential-trace checks red. A planted `~/.local/bin/gh` receives credential traffic under the old helper and not under #51's.
- Filed the two non-blocking findings: #53 (the README Node row still carries `Node.js 24 + npm 11`) and #54 (Known gaps should record that tools other than gh resolve through the prepended `~/.local/bin`). Neither is milestoned yet.
- Plan anchor for milestone 1: `/way-of-working:resume` did not verify it (it waited), so this handoff re-verified it. `match`, description sha `ebe3ff3…` unchanged.

**Next:** agree with the human on the next milestone-1 task and hand it to the coder. Model: opus (architect). Don't start a task before the human picks it.
- Candidates: #53 and #54 (small follow-ups; milestone them first), and #7/#16, which unblock #22's `.trivyignore.yaml` tofu 1.11 and npm 11 entries.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: OPEN** — the human's pick of the next milestone-1 task.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
