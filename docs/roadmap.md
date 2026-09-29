# devcontainers — roadmap

This repo's own record: where the shared images stand, what comes next, and which decisions
bind them. The org-wide migration roadmap and the IAC-D decision log of record are in
[603-Identity/infrastructure-core `docs/iac_migration_roadmap.md`](https://github.com/603-Identity/infrastructure-core/blob/main/docs/iac_migration_roadmap.md).
This file points into that log and does not duplicate it.

## Status

The three images (`base`, `tofu`, `node`) are published to GHCR as public packages, each
with signed build provenance and an SBOM. Since #2 they are built on Ubuntu 26.04. The
`main-required-checks` ruleset and the `architect-review` gate protect `main`, and
`.ai/project.yml` records both.

No repo has adopted the template yet. The first pilots are terraform-cloudflare-dns and
terraform-microsoft365-entra (#10).

## Next action

The next piece of work is set by the open milestone on this repo, since
`planning.kind: github_milestones`. With no open milestone, run
`/way-of-working:plan-sprint` to triage the open issues into one.

Two issues have fixed dates:
- #8: the `tofu` image's Trivy exceptions expire on 2026-10-28.
- #9: GitHub's `ubuntu-latest` moves to 26.04 between 2026-10-19 and 2026-11-19.

## Planning and backlog

- Devcontainer work, and planning for it, lives on this repo's issues, cited `#N`.
- Each sprint is one milestone on this repo, and its issues are the task list.
- **This repo is public.** An issue here must not quote a private repo's internals. Link to
  the private issue instead. Items that started in infrastructure-core's private tracker
  were restated here (#4, #5, #6), and their originals were closed with a link.

## Decisions

A decision made for this repo alone is numbered `DEVC-D1`, `DEVC-D2`, and so on, and recorded
in full in this section. A decision that would make another repo change too, such as the
image and token model or a toolchain version, belongs in infrastructure-core's log as an
`IAC-D` entry instead (DEVC-D1, applying IAC-D48).

### DEVC-D decisions

#### DEVC-D1: Repo-local decisions use `DEVC-D`; shared and org-wide decisions stay `IAC-D`

**Resolved** 2026-09-29 by the repo owner, when this repo adopted the way-of-working v0.13.0
schema.

**Context.** The v0.13.0 schema needs a non-null `decisions.log`. IAC-D48 sets the org
pattern: each repo keeps a local series, and anything shared is `IAC-D`.

**Decision.**
- A decision that affects only this repo is numbered `DEVC-D<N>` and recorded in full here.
- A decision that affects more than one repo, or the whole org, is numbered `IAC-D<N>` and
  recorded in infrastructure-core's log. This file cites it in the table below.
- When a decision is unclear, ask whether any other repo would have to change because of
  it. Almost every change to what the images contain passes that test, because consuming
  repos pin CI to the same versions.

**Consequences.** Each series has a single numbering authority. IAC-D48 says a new repo adds
its prefix to that decision's series list; adding `DEVC-D` there is tracked in #12.

### Org-wide IAC-D decisions that bind this repo

Each of these is recorded in full in infrastructure-core's log. They are cited here only.

| Id | Summary | Where it shows up here |
|----|---------|------------------------|
| IAC-D14 | Work branches live on the org repo, not a personal fork, because fork PRs silently ran no CI. The same "absent-check trap" is why required-check names are read from each workflow's `name:` field and never typed from memory. | Branches on `603-Identity/devcontainers`; `ruleset.required_checks` |
| IAC-D48 | Each repo numbers its own decisions in a local series; shared and org-wide decisions stay `IAC-D`. Repos that plan sprints as milestones keep a README-only `sprints/`. | DEVC-D1; `decisions` and `sprints_dir` in `.ai/project.yml`; `sprints/` |

The image and token model will be recorded as an `IAC-D` entry (#12), and cited here once
it is.
