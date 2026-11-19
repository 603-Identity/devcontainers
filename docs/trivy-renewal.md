# Renewing the Trivy exceptions

This is the one place the renewal rules are written. A renewal spec cites this file instead of
restating it. It is in `code_paths` (`.ai/project.yml`), so an edit to the rules goes through the
review gate, as an edit to [`.trivyignore.yaml`](../.trivyignore.yaml) does.

A renewal is an ordinary lane. The evidence comes from CI, not from a host session: on every
scheduled and manually dispatched run on `main`, `build.yml`'s `publish` job runs
`.github/scripts/trivy-evidence.sh` over the five images it just built (no ignore file) and uploads
the results as the `trivy-evidence` workflow artifact. The file has the format
`tools/host/trivy-rescan.sh` writes: Base commit, Pins, Images, Trivy, one Findings section per
image, then Binaries.

## Early warning

`trivy-expiry.yml` lists every entry that expires within 10 days (already-expired ones too) and
fails when there are any. It runs on pull requests and on scheduled and dispatched runs on `main`.
It is **not** a required check and must not be added to the `main-required-checks` ruleset. It is a
separate workflow so that its red run never changes a `build.yml` run's conclusion.

`trivy-daily.yml` is the earlier warning for a new finding. Every day it scans the newest published
image of each flavor (library packages only, with `.trivyignore.yaml` and the build gate's severity
settings) and opens one issue per vulnerability id, titled `Trivy daily scan: <id> in the published
images`, or comments on the open one when its findings change. The issue carries what an exception
needs: image, path, package, installed and fixed versions, the pinned version and whether upstream
has a newer release. It is **not** a required check and must not be added to the
`main-required-checks` ruleset.

## Which run qualifies

The evidence is the `trivy-evidence` artifact of a `build.yml` run that meets all of these:

- its event is `schedule` or `workflow_dispatch`;
- its `headBranch` is `main`;
- its job `Build, test, push and attest` concluded success;
- it carries an artifact named `trivy-evidence` (a failed evidence step leaves none);
- its head commit equals the artifact's Base commit line, and is the renewal lane's base or an
  ancestor of it.

The ancestry check is the one that carries the weight. A run on a tag named `main` also reports
`headBranch` `main`, so the branch field alone proves nothing.

Fetch it with `gh run download <run id> --name trivy-evidence`, by run id and artifact name, and
check the run with `gh run view <run id>` (event, `headBranch`, `headSha`, job conclusion). The
renewal PR cites the run id and the artifact digest (the build run's step summary shows both).

## The rules

- The Pins section equals the `ARG` values at the lane's base.
- Never add an id or a path. An entry whose id and path no longer appear in the evidence's findings
  is removed.
- Every remaining entry gets one shared `expired_at`, at most 30 days after the renewal date, and a
  refreshed statement.
- A CVE-2026-78661 entry is renewed only when the evidence's Binaries section shows the parser
  symbols (`html.Parse`, `html.(*parser)`, `html.fosterParent`) absent for that entry's path.
  Otherwise the lane stops and escalates.
- The lane also updates the Current entries header paragraph of `.trivyignore.yaml` (run id, base
  commit, Trivy and DB versions, pins, expiry) and the expiry date line in `docs/roadmap.md`.

## Fallback

When no qualifying run exists (CI unavailable, the evidence step failed, or a lapsed entry already
failed the build), use Procedure A of [`docs/host-steps.md`](host-steps.md) with
`tools/host/trivy-rescan.sh`. The rules above apply to its results file unchanged.
