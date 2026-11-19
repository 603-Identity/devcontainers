# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. CVE-2026-97054 is excepted, image builds
are green again, and elevated pushes now go through the admin-App publish (Procedure B).

**Just done:**
- #625 merged as #628 (`f44f196`): CVE-2026-97054 exceptions for yq, tofu and tflint; rockcraft's
  pebble removed. All five images pass the Trivy gate. #377 merged as #622 (`d399698`) after a
  branch update brought #628 in.
- #627 merged as #632 (`c56b7e3`): the daily Trivy scan of the published images. Its first dispatch
  run on main was clean.
- #423 merged as #635 (`4514575`): zizmor 1.32.0 pinned, with a pin check; the template gate's
  `issue_comment` finding is ignored by a line-keyed `.github/zizmor.yml` entry (the inline ignore
  also hid `pull_request_target`).
- Procedure B in `docs/host-steps.md` replaced by the interim admin-App publish (#637, `5a76663`),
  after its first two live runs (#632, #635). `docs/host-steps.md` is now in `code_paths`.
- #626's spec (comment 7018080079) approved after three escalations, scoped to `main` runs only.
  Filed #634 (scan every flavour before failing the pull-request build).
- Critic pass on #637 (architect, docs-consistency): 4 rounds, converged. The lanes record their
  own.

**Next:** Driver, on **opus** (architect):
- Once #626 is on M6, prep its lane and hand over the lane command; start `lane.sh wait 626`.
- Clean up lane 423 (its worktree holds the draft #635 merged) and confirm lane 627 is gone.
- File the follow-ups: #635's `.ai/project.yml` "two callers" comment, the
  `check-consumer-workflows-test.sh` one-time flake, #632's lost upstream-release cache, and
  #637's unapplied tightenings (listed in its PR body).

**HITL Gate: OPEN** — the owner places #626 on a milestone (its spec 7018080079 is approved;
`lane.sh prep` refuses `bad-issue` until it has one) and re-plans M6 (build order, #397, the
merge-guard cluster, #634 and the #626/#627 placement); re-copies the host-steps start text from
main, which now names only procedure A.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md`.
- way-of-working v0.38.0 is out (the pin is v0.37.0). Its migration is the admin-token move (#1608).
- Leftover spec worktrees under `/tmp/lanes`: clear them with `wowl 603-Identity/devcontainers -SpecSweep`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
