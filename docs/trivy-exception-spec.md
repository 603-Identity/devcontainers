# Spec template for a Trivy exception task

A maintainer uses this for a task that adds one `.trivyignore.yaml` exception from a failing
`main` build run (see [Adding an exception](trivy-renewal.md#adding-an-exception), which holds
every rule and which this template cites rather than restates). Copy the block below, fill in the
placeholders (`ISSUE`, `BASE_SHA`, `RUN_ID`, `FLAVOUR`, `PATH`, `CVE`), post it as the task's spec
comment, and react to it. The marker line is the way-of-working plugin's spec-comment marker; its
`sha=` is the full commit of `main` the spec is for. The lane then needs no spec drafting. Any
change to image contents still goes through the normal spec flow. This file is in `code_paths`:
what it says decides what an exception lane builds.

```
spec-task: issue=ISSUE base=main sha=BASE_SHA

Spec for #ISSUE: add the `.trivyignore.yaml` exception for CVE on PATH, from build run RUN_ID.

### Goal

Add the exception entry for CVE at PATH (image flavour FLAVOUR), written by `tools/trivy-except.sh`
from failing `main` build run RUN_ID, under the rules of `docs/trivy-renewal.md`, "Adding an
exception".

### Files touched

- `.trivyignore.yaml`: the new entry, and the header lines the section names (the Current entries
  paragraph, with a source line naming run RUN_ID and the tool's pin, no PR number).
- `docs/roadmap.md`: the expiry line, only when its tool list changes.

Steps for the lane:

1. Fetch `main` (`git fetch origin main`).
2. Run `tools/trivy-except.sh RUN_ID FLAVOUR CVE PATH` with the dev token, once per affected path of
   the same binary and flavour group (gh's two paths are one entry; uv and uvx are two runs).
3. Stop and report, with no PR, when a `gh` call is refused, the script exits non-zero, or the
   printed main-ref commit differs from BASE_SHA.

### Done when

- Each printed entry (one per affected path) is the one added to `.trivyignore.yaml`, and nothing
  else in the file changed except its header lines.
- Everything each run prints after its entry (run id, event, head commit, job, main ref and its
  resolved commit) is in the PR description.
- The build check on the PR is CI's to report. A later flavour group for the same CVE shows in
  the PR build's listing, and its entries come from that listing as the section says (the
  maintainer decides; by hand, on the same PR).

### Tests

The `tools/tests/trivy-except-test.sh` suite is unchanged and still passes.

### Out of scope

Renewal; any change to the script, the Dockerfiles, a pin or another entry; apt packages; ids other
than the CVE id above; reachability claims.

### Restated from the issue body

CVE on PATH in FLAVOUR, build run RUN_ID; one exception entry under "Adding an exception".
```
