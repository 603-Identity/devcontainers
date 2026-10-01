# Next steps

**Now:** P0: cross-org images -- implementing. The #30 spec v5.2 is posted and waits for
the owner's confirmation.

**Just done:**
- Drafted the #30 design spec and revised it through v5.2, posted on #30
  ([comment 5938653643](https://github.com/603-Identity/devcontainers/issues/30#issuecomment-5938653643)).
  It supersedes the v1 comment. Critic pass: 5 rounds (architect + security), the last
  round converged ("ready for a Coder after edits"), plus 1 round on `fable` (second_opinion)
  that found edits only, no design round. The fable reviewer reported its own model as
  `claude-fable-5-1`; the provenance wasn't confirmed independently.
- Ran two live spikes to replace assumptions with evidence (spec Appendices A and B). Spike 1's
  repos are deleted. **Spike 2's repos are archived and need deleting in the UI:**
  `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`.
- Owner decisions recorded in the spec: no soak; no `workflow_run` trigger; writers trusted
  by construction; **auto-merge stays off** until spec §7 step 4's preconditions are met.
- This session wrote no code.

**Next:** task #30 — once the owner confirms spec v5.2, implement PR 1 exactly as spec §6
lists it, run the green gate, then `/way-of-working:critic-gate` before handoff. Don't create
the `devc-automerge-on` tag. Model: sonnet (coder). Also file the four spec §9 issues
(review-gate trust model, OCI labels, docs-only publishing, template pin bump). Two of them
are preconditions for turning auto-merge on.

**HITL Gate: OPEN** -- the owner confirms #30's spec v5.2 before any code. After PR 1
merges, the owner adds the tag ruleset and tags `v1.0` (spec §6). Turning auto-merge on is a
separate owner decision (spec §7 step 4).

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
