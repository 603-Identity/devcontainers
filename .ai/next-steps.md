# Next steps

**Now:** Milestone 6, Internal hardening, in `implementing`.

**Just done:**
- Milestone 6 step 2 merged: #381 (`a5c3d90`) closes #159. `build.yml`'s `scope` job now diffs HEAD against the
  commit of the newest `main` run whose `publish` job succeeded, and builds whenever that lookup fails.
- The fresh-session architect review of #381 found no blocking issues. It reproduced the claims in a WSL sandbox,
  and five of six planted mutations went red. The one survivor is the same-tree check in `image-scope.sh`, which
  is unreachable by design. It filed #383: a dispatch on a tag named `main` older than b4a490b publishes old
  images (pre-existing).
- Critic pass on #381 (from its PR body):
    2 rounds (architect + security-critic + docs-consistency), converged. All critics ran on their frontmatter
    defaults; no second-opinion round.

**Next:** task #309 — on **sonnet** (coder): build milestone 6 step 3 as one docs PR (`Closes #309, closes #310,
closes #327, closes #297`). Each issue's body is the spec:
- #309: name `restrict-updates-to-main` next to threat-model invariant 6. Give its one bypass actor (admin role,
  `pull_request` mode), and say that `main-required-checks` has no bypass actors, so `--admin` never skips a
  required check. The `ruleset:` schema takes one name, so record the second ruleset as a stated residual in
  `.ai/project.yml`'s `ruleset:` comment. Resume's drift check does not watch it.
- #310: reword the `.ai/project.yml` `.claude/` comment as "the plugin pin, the merge-guard hook, and the
  force-push deny rules".
- #327: the owner's live test (2026-10-07, recorded in #327) is done. All three App-token attempts were refused:
  merge (`405`), a ref update of `main` (`422`), and deleting a `v*` tag (`422`). Reword the bump-binaries
  credentials row from those results, naming `restrict-updates-to-main`'s bypass list as the control and keeping
  the real residuals. Then drop "not tried" from the tag-deletion negative test in Known gaps.
- #297: the immutable-release tag "cannot be moved; can be deleted only after deleting its release, and the name
  can never be reused". Note that `immutable-releases` is `enforced_by_owner: false`. In DEVC-D8's Context,
  write "`v1.0` and `v1.1` lightweight".

Then `/way-of-working:critic-gate` (docs-consistency) and `/way-of-working:ship`. `.ai/project.yml` is in
`code_paths`, so the PR needs the architect review.

**HITL Gate: NONE OPEN** — next gate: the owner's merge of the step 3 docs PR.

**Open for the owner (non-blocking):**
- Milestone 5 (Trivy renewal 2026-11) is due 2026-10-29. The #148 exceptions still expire 2026-11-01: if the
  tofu and tflint vendors have not shipped fixes by late October, re-scan and renew the rest at most 30 days out.
  #329 rides along.
- #356 (regression test for the #349 pin guard) is on milestone 6 but not in the written build order. It fits
  with step 9's test-only fixes. #377-#379 and #383 are unmilestoned.
- Any other repo that bumps way-of-working to `v0.17.0` reads `incomplete` until it answers `orchestration`,
  and needs the drive-letter mirror after `plugin update` (claude-workbench#347).
- The pilots re-copy the gate and re-pin to `9153da1b6eb4ff2d845cb41efaabab3882529130 # v1.4`; tracked there.
- The `bump-binaries` Environment still lets admins bypass its protection rules; turning that off is optional.
- terraform-cloudflare-dns: its gate lists `.terraform.lock.hcl` and `.devcontainer/*` that its `code_paths`
  do not; confirm during the #212 pilot follow-ups, along with whether it should cover `.claude/` (from #214).
- -dns#57, -dns#59 and -dns#65 are open. Other detect-secrets repos have migration issues:
  checkov-ledger-action#16, infrastructure-core#560, tenant-posture-assessment#31, trust-anchors#73.
- Use `GH_TOKEN="$(gh auth token --user JaredGroves-603)"` for `gh` calls on this repo, and run commits,
  pushes and PRs from the Windows host. Run tests in WSL, not Git Bash. `gh issue create` and `gh pr create`
  hang under Git Bash; `gh api ... --input -` with a timeout works. Write `Closes #A, closes #B`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/6
