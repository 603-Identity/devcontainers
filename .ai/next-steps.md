# Next steps

**Now:** P0: cross-org images — implementing (#22, the version standard).

**Just done:**
- #21's post-merge steps, all three. build.yml run 36753915960 on `b4a490b` succeeded and pushed base, tofu and node as `3.30`. The IAC-D draft is posted on #12 and the owner confirmed it. The enforcement follow-up is filed as #43.
- Owner removed the old `603identity-cache` and `603identity-trivy-cache` volumes.
- No code this session, so no critic pass ran.

**Next:** task #22 — implement the version standard in the issue body (uv, tools venv on `pyproject.toml` + `uv.lock`, version bumps, digest-pinned `# syntax=`, amd64 guard, dependabot `uv`, smoke assertions). Model: sonnet (coder).
- #7 and #16 are executed alongside it: the `.trivyignore.yaml` tofu 1.11 and npm 11 acceptance line depends on them.
- #22 inherits D2's invariant: the uv cache never goes in the shared `devc-cache` volume.

**HITL Gate: OPEN** — first anchor for milestone 1 in this handoff chain (description sha `ebe3ff3e…`). This session's resume did not verify the prior anchor, so a human "go" confirms the milestone before the coder starts. The next gate after that is the architect review of #22's PR.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
