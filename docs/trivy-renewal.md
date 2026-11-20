# Renewing and adding Trivy exceptions

This is the one place the renewal and exception rules are written. A renewal spec cites the rules
below, and an exception spec cites [Adding an exception](#adding-an-exception), instead of
restating them. The file is in `code_paths` (`.ai/project.yml`), so an edit to the rules goes
through the review gate, as an edit to [`.trivyignore.yaml`](../.trivyignore.yaml) does.

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
  ancestor of it;
- the artifact's `Vulnerability DB UpdatedAt` value (in its Trivy section) is a date at most 7 days
  before the renewal date (UTC), the date the shared `expired_at` is counted from under
  [The rules](#the-rules).

The ancestry check is the one that carries the weight. A run on a tag named `main` also reports
`headBranch` `main`, so the branch field alone proves nothing.

The lane uses the newest run, by creation time, that meets every condition. The age bound exists
because an old vulnerability database can miss a CVE published since, so an old run cannot back a
fresh 30-day expiry.

Fetch it with `gh run download <run id> --name trivy-evidence`, by run id and artifact name, and
check the run with `gh run view <run id>` (event, `headBranch`, `headSha`, job conclusion). The
renewal PR cites the run id, the artifact digest (the build run's step summary shows both) and the
`Vulnerability DB UpdatedAt` value.

Both commands need Actions read on the lane's token (the dev-token row of
[`threat_model.md`](threat_model.md)'s *Credential holders* table records what is observed: reads
of this repo's runs, jobs and job logs; it records no artifact download). When either is refused,
the lane stops and reports, opens no PR, and the renewal goes to [Fallback](#fallback).

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

## Adding an exception

An exception is an entry for a finding upstream has not fixed. It is an ordinary lane that runs
[`tools/trivy-except.sh`](../tools/trivy-except.sh), which writes the entry from a failing `main`
build run; a maintainer posts [`docs/trivy-exception-spec.md`](trivy-exception-spec.md), filled in,
as the task's spec comment, so the lane needs no spec drafting. Any change to image contents still
goes through the normal spec flow. A renewal never adds an id or a path (see The rules).

- **The trigger and the input.** A new finding usually first appears as a `trivy-daily.yml` issue.
  The input is the run id of a failing `build.yml` run on `main` (a push, schedule or dispatch
  run), and the finding: image flavour, path and CVE id. A pull-request run is not an input: the
  script refuses it. When no such `main` run exists yet, a maintainer dispatches `build.yml` on
  `main`.
  A `main` run's head commit must be reachable from `main`: checked against the main ref's commit (`origin/main` unless the test override `TRIVY_EXCEPT_MAIN_REF` names another; never fetched by the script), which the script prints for the code owner to confirm.
  The event and branch check only filters: a run on a tag named `main` (which `release-tags` does
  not cover) also reports `head_branch` `main`, as [Which run qualifies](#which-run-qualifies)
  says, so the ancestry check carries the weight, and that check relies on squash-only merges, as
  the `GITHUB_TOKEN` row of [`threat_model.md`](threat_model.md) words it: with merge commits a PR
  branch's unreviewed commits would be ancestors too. Unlike Which run qualifies: the job must
  have failed, no `trivy-evidence` artifact or Base commit check is used, push runs are accepted,
  and the ancestry check is against the main ref rather than the lane's base. Before running the
  script, the operator brings `origin/main` up to date (a fetch of `main`), so a run newer than
  the checkout's last fetch is not refused as a commit the checkout does not have. The flavour is
  the one whose scan failed: in `push` mode, which the `main` runs the script reads use,
  `build-and-test.sh` runs under `set -euo pipefail`, so the first failing scan ends the run and
  later flavours are never scanned.
- **Who runs it.** The exception lane, with the dev token, which reads this repo's Actions runs,
  jobs and job logs. When any `gh` call the script makes is refused, or the script exits non-zero
  for any other reason, the lane stops and reports, and opens no PR. The lane also stops when the
  main-ref commit the script prints differs from its spec's base commit (a renewal or re-pin
  merged since the spec was posted would otherwise give a second `expired_at` or a different pin),
  and the maintainer re-posts the spec on the new base.
- **A CVE in more than one flavour group.** Because the first failing flavour ends a `push`-mode
  run, a `main` run names one group's path, and the lane ships with the PR's build check pending
  (the lane-proceeds rule in `CLAUDE.md`). The exception PR's own pull-request build runs in
  `local` mode, which scans every flavour before it fails, so that one run names every failing
  flavour group for the same CVE. The extra entries for the later groups come in one fix round on
  the same PR, written by hand under this section's rules (the script refuses the PR's own
  pull-request run), with that PR build run's id in the PR description.
- **When an entry is allowed.** Only for a pinned upstream release binary whose pin is the latest
  upstream release (the release `bump-binaries.sh` resolves for that tool). That check stands in
  for "no release with the fix exists", checked against the pin rather than asserted. A pin behind
  the latest release is not an exception case: re-pinning is its own task. A bump PR to the latest
  release whose own build is red is not covered by this route either (main's pin is behind); the
  maintainer decides it as its own task. "Latest" means the release `bump-binaries.sh` resolves for
  the tool (for node and npm, the line it resolves them on), so a binary `bump-binaries.sh` does
  not resolve (claude, the Python tools from `uv.lock`, or anything else outside its tool list) is
  not admitted by this procedure, by script or by hand; it is its own task.
- **Apt packages are not admitted.** The gate runs Trivy with `--ignore-unfixed`, so an apt finding
  with no fixed build never fails it; one that does fail has a fixed version, which the image
  build's `apt-get upgrade` installs once the archive ships it to the pinned series. A fixed
  version the archive does not ship to that series is filed as its own task, since an entry for a
  package (not a path) is something the header rules, the threat model and the renewal rules do not
  allow today.
- **What the entry must be.** One id; `paths` scoped to the one binary, listing each in-image path
  that binary has. Only gh has two: its binary is at `usr/local/bin/gh` in the base, tofu and node
  flavours and at `usr/local/libexec/gh-real` in the dev-App flavours (where `usr/local/bin/gh` is
  a wrapper script), as the retired gh entries listed. uv and uvx are two separate binaries, each
  with its own entry and one path. A finding that fails more than one table path in the same
  flavour group (a CVE in code both uv and uvx carry, for example) takes one script run and one
  entry per path, all in the same PR, which is still one exception. A statement in the existing
  style ("HIGH or CRITICAL in MODULE VERSION compiled into upstream TOOL PIN; no fixed upstream
  release."); and the shared `expired_at` the other entries carry, so the next renewal handles it
  with the rest, or 30 days after the script's run date (UTC) when the file has no entries. A
  shared `expired_at` of today or earlier would make the new entry lapse at once, so the script
  refuses it; a lapsed file plus a new finding is the maintainer's decision, as its own task. A
  shared date inside the 10-day early-warning window is taken as it is, and the next renewal
  renews the new entry with the rest.
- **Reachability.** A new entry's statement makes no reachability claim. The only reachability
  evidence the repo produces is the Binaries section of the `trivy-evidence` artifact and of
  Procedure A results, which covers a fixed set of paths and symbols; extending it is its own task.
- **The lines that change with an entry, by hand, in the same PR.** The `.trivyignore.yaml`
  header's Current entries paragraph: the per-tool lines saying which ids each tool carries, the
  sentence naming what kind of CVE every entry is when the new entry is of another kind, and a
  source line in the style of the existing CVE-2026-97054 one naming the entry's run id and the
  tool's pin, with no PR number, since the entry does not come from the no-ignore scan the
  paragraph opens with (the "Pins at the scan" list is left as that scan's pins); and the
  `docs/roadmap.md` expiry line that names which tools carry exceptions. Everything the script
  prints after the entry (the run id, event, head commit, job, and the main ref with its resolved
  commit) goes in the PR description, as a renewal cites its run.
- **What the script's checks are worth.** The script runs in the lane's own container, which
  controls its environment, its PATH and its checkout, and its output reaches the PR only as text
  the lane pastes, so the script's checks are self-attested by the lane. The control of record is
  the code owner's check on GitHub before approving (the `main-approval` ruleset), made from run
  RUN_ID itself: its workflow is `build.yml`, its event is push, schedule or dispatch, its
  `head_branch` is `main` and its head commit and the printed main-ref commit are on `main`; its
  *Build, test, push and attest* job failed; the CVE row sits under the target line in the
  flavour's group of that job's log; and the pin equals the tool's latest upstream release.
- **An exception PR changes nothing else.** Removing a package, re-pinning a tool, or editing or
  removing another entry is its own task. A renewal still never adds an id or a path.
- **The script,** `tools/trivy-except.sh [--dry-run] RUN_ID FLAVOUR CVE PATH`:
  A `main` run's head commit must be reachable from `main`: checked against the main ref's commit (`origin/main` unless the test override `TRIVY_EXCEPT_MAIN_REF` names another; never fetched by the script), which the script prints for the code owner to confirm.
  It refuses every run that is not a `main` run. It reads this repo's Actions runs, jobs and job
  logs, and the tools' upstream releases, which the dev token has (it passes
  `--allow-escape-sequences` for the log, because `gh` refuses a log holding terminal escapes).
  Ids other than CVE ids (GHSA or GO ids) and binaries outside its table (gh, yq, uv, uvx, tofu and
  tflint) are written by hand under the same rules, with the same checks shown in the PR
  description. The suite is `tools/tests/trivy-except-test.sh`.
- **The spec template,** [`docs/trivy-exception-spec.md`](trivy-exception-spec.md): a maintainer
  posts it, filled in, as the task's spec comment and reacts.

## Fallback

When no qualifying run exists (CI unavailable, the evidence step failed, a lapsed entry already
failed the build, the newest run's database is older than the bound, or the lane's token is refused
the run read or the artifact download), use Procedure A of [`docs/host-steps.md`](host-steps.md)
with `tools/host/trivy-rescan.sh`. The renewal rules above apply to its results file unchanged. The
same bound applies to it: its `Vulnerability DB UpdatedAt` date (`tools/host/trivy-rescan.sh` writes
that line) is at most 7 days before the renewal date, and a results file older than that backs no
renewal.
