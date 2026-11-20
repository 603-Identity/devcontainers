# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`. CVE-2026-97054 is excepted, image builds
are green again, and elevated pushes now go through the admin-App publish (Procedure B).

**Just done:**
- #626 merged as #640 (`bc0848d`): the "Adding an exception" procedure, `tools/trivy-except.sh` and the
  exception spec template. Its spec was refreshed onto the current base first (comment 7024131510).
  Lanes 423, 627 and 626 cleaned up.
- Follow-ups: #642 filed (#637's unapplied tightenings); the flake re-occurrence added to #446.
- `/way-of-working:plan-sprint findings`: 22 review-finding issues unpacked into 46 findings and
  closed. 8 folded (into #570, #572, #586, #642, which makes a spec on those need a fresh maintainer
  reaction), 6 declined as done or covered, 32 combined into #643-#651.
- `/way-of-working:plan-sprint`: 25 issues placed on M6 and 7 on M3 (description written live, order
  31, 489, 475, 605, 524, 522, 575, 650, 556, 526, 514, 521, 26, 27, 28, 439); #531, #588, #480 and
  #578 left unmilestoned with reasons. M6's new 47-item description is staged (HITL Gate).
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
- Once the owner has applied M6's staged description, run `lane.sh groups 6` and hand over spec
  commands for the first lane-able items (#586, #634, #647 lead the order).
- #647 should land before the Trivy exceptions' renewal (expiry 2026-12-17).

**HITL Gate: OPEN** — the owner places #626 on a milestone (its spec 7018080079 is approved;
`lane.sh prep` refuses `bad-issue` until it has one) and re-plans M6 (build order, #397, the
merge-guard cluster, #634 and the #626/#627 placement); re-copies the host-steps start text from
main, which now names only procedure A.; plan-sprint 2026-11-20 staged: milestone 6's new
description (read /tmp/tmp.TWUtTBosmd/description-m6.txt, then run /tmp/tmp.TWUtTBosmd/staged.sh;
the same text is on #126, sha256 prefix dd922af1a13a4a82), then close #578, #170, #171, #311,
#172, #272, #152 and #397 by hand; verify and close #531 and #588.

**Open for the owner (non-blocking):**
- The Trivy exceptions expire 2026-12-17. Renew them per `docs/trivy-renewal.md`.
- way-of-working v0.38.0 is out (the pin is v0.37.0). Its migration is the admin-token move (#1608).
- Leftover spec worktrees under `/tmp/lanes`: clear them with `wowl 603-Identity/devcontainers -SpecSweep`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6 · host steps: [docs/host-steps.md](../docs/host-steps.md)
