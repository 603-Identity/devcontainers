# Next steps

**Now:** Milestone 8, dev-App flavour and template (#418), in `implementing`. Milestone 6 is parked.

**Just done:**
- PR D (#392) shipped: the dev-App-only template, the real-template self-tests, `template-proof.sh` on `devcontainer-devapp-tofu`, and the README, `docs/adopting.md` and threat model rewrite (#455, `7f2cbb6`). #392 is closed.
  - Critic pass on #455: architect, security-critic, docs-consistency, 3 fix-and-re-run rounds, converged; the last round returned no false statements. Critics' own frontmatter models; no second-opinion round. Not the review gate.
- The fresh-session review of #455 filed #456 (remove the template's VS Code settings; the owner reframed it to land **before the v1.6 tag**), #457 (measure `appPort` reach on the Windows host) and #458 (askpass keys in `.vscode/settings.json`).
- Build run for `7f2cbb6` (the publish) was still in progress when this was written.
- First anchor for milestone 8 in this cursor: no baseline was verified this session; the description sha256 (`259b9872…`) equals the previous anchor's.

**Next:** task #456 — on **sonnet** (coder), take the VS Code settings out of the template before the v1.6 tag, per [#456](https://github.com/603-Identity/devcontainers/issues/456): delete `customizations.vscode` and its comment, drop the four keys from `TestRealTemplateShape` and ban `customizations`, keep the `postStartCommand` `rm` and the `postAttachCommand` warning, rewrite README, `docs/adopting.md` and the threat model so the launcher (interim: the devcontainer CLI from PowerShell) is the only entry and VS Code attach is unsupported, amend DEVC-D9 and DEVC-D3's note in `docs/roadmap.md`, and close or narrow #458. Run the green gate, then `/way-of-working:critic-gate` before `/way-of-working:ship`. It touches `code_paths`, so it needs a fresh-session `/way-of-working:architect-review`.
After #456: the owner cuts the signed `v1.6` tag on `main` (README "Cutting a release" step 1) once `build.yml` publishes green (closes #393), then PR E (self-pins to v1.6, `previous.devcontainer.json`, DEVC-D9 shipped, roadmap Status; closes #418).

**HITL Gate: OPEN.** A human "go" is needed before #456 starts (the first-anchor line above). The next gates are the owner's merge of the #456 PR after a fresh-session architect review, then the owner's `v1.6` tag.

**Open for the owner (non-blocking):**
- The `.trivyignore.yaml` exceptions expire 2026-12-01, and no issue tracks the renewal itself.
- The descriptions of milestone 5 and milestone 3 are stale and need a hand edit.
- `orchestration` is `null`, so no loop dispatches into this repo.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`. Run tests in WSL.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/8 · parked sprints: `.ai/parked/`
