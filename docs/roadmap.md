# devcontainers — roadmap

This repo's own record: where the shared images stand, what comes next, and which decisions
bind them. The org-wide migration roadmap and the IAC-D decision log of record are in
[603-Identity/infrastructure-core `docs/iac_migration_roadmap.md`](https://github.com/603-Identity/infrastructure-core/blob/main/docs/iac_migration_roadmap.md).
This file points into that log and does not duplicate it.

## Status

The three images (`base`, `tofu`, `node`) are published to GHCR as public packages, each
with signed build provenance and an SBOM. They serve 603-Identity and glunk-works, and the
packages must stay public (DEVC-D3). Since #2 they are built on Ubuntu 26.04. The
`main-required-checks` ruleset and the `architect-review` gate protect `main`, and
`.ai/project.yml` records both.

No repo has adopted the template yet. The first pilots are terraform-cloudflare-dns and
terraform-microsoft365-entra (#10).

## Next action

The next piece of work is set by the open milestone on this repo, since
`planning.kind: github_milestones`. With no open milestone, run
`/way-of-working:plan-sprint` to triage the open issues into one.

Two dates are fixed:
- #8: the `tofu` image's Trivy exceptions expire on 2026-10-30 (renewed 2026-10-01 under #8, which stays open for the next review).
- GitHub's `ubuntu-latest` moves to 26.04 between 2026-10-19 and 2026-11-19. Until then CI
  runners (24.04) and the images (26.04) differ.

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

#### DEVC-D2: Git identity is chosen by the origin's org, from host files that declare their own orgs

**Resolved** 2026-09-30, in the design spec on #20.

**Context.** The host identity files gained a `[credential]` section whose helper is a host
path (`gh.exe`). Linking the whole file into the container's global git config let it
displace the image's `gh auth git-credential`, and every HTTPS fetch and push failed.

**Decision.**
- Identity is chosen by the org in `/workspace`'s `origin` URL. The host's `~/.gitconfig.d/`
  is mounted read-only, and each `*.gitconfig` file names the orgs it serves in
  `[devcontainer] org` keys. No account or org name goes into the public images.
- Projection is allowlist-only: `user.name`, `user.email`, `user.signingkey`,
  `commit.gpgsign` and `tag.gpgsign`. The host file is never included or linked.
- `includeIf "hasconfig:remote.*.url:..."` was rejected. Its patterns are case-sensitive
  (GitHub URLs are not), scp-style SSH remotes need separate patterns, cross-org forks fire
  both rules with last-wins precedence, and a relative `path=` resolves through the symlink.

**Why DEVC-D and not IAC-D.** Under DEVC-D1's own test, no other repo has to change *yet*,
because none has adopted the template. The image major version is 2 because a template
from before this change gets no identity from the new image.

**Consequences.** #12 must record the host-wide identity / per-repo credential split in
the `IAC-D` entry for the image and token model. A comment on #12 carries this when the
PR lands.

#### DEVC-D3: Org-neutral names, one publisher, VS Code only

**Resolved** 2026-09-30, in the design spec on #21 (which also folds #9).

**Context.** The images become the shared devcontainer images for 603-Identity and
glunk-works. Several names assumed one org, and the cross-org move joins two orgs' supply
chains.

**Decision.**
- The org-named paths and volumes were renamed to the org-neutral token `devc`
  (`/opt/devc`, `/usr/local/share/devc`, `devc-cache`, `devc-trivy-cache`). The org stays
  only where it names the publisher: the source repo, `ghcr.io/603-identity/*`, the
  attestation signer and the OCI source label.
- One publisher, 603-Identity/devcontainers. The GHCR packages must stay public.
- The shared `devc-cache` volume mounts at `~/.cache/shared` and holds only the tofu
  provider cache, which `tofu init` verifies against the consuming repo's lock. pre-commit,
  pip and npm caches stay per container: none is verified on every use. (Superseded by
  #23: the shared volume is now `devc-tofu-plugins`, mounted at `~/.cache/tofu-plugins`
  only, and holds only the tofu provider cache; everything else, npm's cache included, is
  per repo in the `<repo>-home` volume.)
- Only `main` publishes. Consumers pin the signer workflow and `refs/heads/main` when
  they verify, on every new digest.
- The image MAJOR goes from 2 to 3, because paths moved. (#23 moved them again, so it
  goes to 4.) This overrides #21's "no MAJOR
  bump" line.
- VS Code is the only supported editor. Volume names keep keying on the checkout folder
  name, so folder-name uniqueness is a documented host rule, not enforced here. The
  residual: a collision merges two repos' trust domains (up to five per-repo volumes; four
  after #23 folded `-gh` and `-claude` into `-home`).
- Prose names 603-Identity and glunk-works. Host rules say "every checkout on the host",
  which covers the other orgs there.
- Tokens are recorded in the owning org's credential ledger.

**Why DEVC-D and not IAC-D.** These are this repo's own obligations as publisher. What
consumers in every org must do is carried by #12's `IAC-D` entry.

**Consequences.** #12 carries the consumer obligations. A follow-up enforces folder-name
uniqueness at container start. glunk-works has no credential ledger yet, a named gap in
the threat model.

#### DEVC-D4: No image ships the `claude` CLI; plugin repair uses the extension's own binary

**Resolved** 2026-10-01 by the repo owner, on #4.

**Context.** A container kept loading an old way-of-working plugin version through two pin
bumps. The documented fix (refresh the marketplace, reinstall the plugin) needs the CLI, and
the container had none, so plugin state was repaired by hand-editing the CLI's internal
files. The VS Code extension turns out to carry a native `claude` binary
(`resources/native-binary/claude`, about 240 MB, no node or npm). The linux-x64 build of
2.1.286 was checked: it runs in the base image and has the `plugin` and `plugin marketplace`
commands the fix needs.

**Decision.**
- No image ships the CLI: not `base`, not `tofu`, not `node`.
- Plugin repair uses the extension's bundled binary, documented in the README under
  "Repairing Claude Code plugin state". It is the same release as the extension, so there is
  only one CLI version writing `~/.claude/plugins/`.
- Rejected:
  - *CLI in the `node` image only:* doesn't help `base` or `tofu` containers, and an
    image-pinned CLI drifts from the self-updating extension, bringing back the
    two-versions-of-plugin-state failure that caused the incident.
  - *CLI in `base`:* the same skew in every image, plus about 240 MB and a new pinned tool,
    with its CVE surface, in every repo of both orgs.
  - *No CLI and no documented repair:* leaves the next person hand-editing internal files.
  - *Scripting the manual repair:* hard-codes undocumented internals that break silently on
    an update.
- The plugin's `SessionStart` hook (`hooks/ai-cursor-banner.sh`) is stored as mode `100644`
  and run directly, so any install that doesn't set the executable bit leaves it failing
  silently. That's the plugin's defect, filed upstream as glunk-works/claude-workbench#214.

**Why DEVC-D and not IAC-D.** The images don't change, so no consuming repo has to.

**Consequences.** The README recipe depends on a path that's internal to the extension. If
the extension moves it, the recipe stops finding the binary, and this decision should be
revisited, not worked around by adding the CLI to an image without a new decision.

#### DEVC-D5: The template keeps the app user at uid 1000 on every host

**Resolved** 2026-10-01, on #75. The setting shipped in #71; this records it.

**Context.** On a Linux host the Dev Containers CLI rewrites the `remoteUser`'s uid to the
host user's uid by default, then chowns only `/home/app`. The dependency volumes
(`node_modules`, `.venv`) and the shared tofu-plugin cache stay owned by uid 1000, so the
container can't write them. Docker Desktop on macOS and Windows maps ownership itself, so
those hosts aren't affected either way.

**Decision.**
- `template/.devcontainer/devcontainer.json` sets `"updateRemoteUserUID": false`. The app
  user is uid 1000 on every host.
- Cost: on a Linux host whose own uid isn't 1000, the container can read the `/workspace`
  bind mount but not write it. The README's consuming instructions name this host rule, and
  `docs/threat_model.md` lists it under Known gaps.
- Rejected:
  - *The CLI's default:* every volume except the home volume becomes unwritable, on every
    Linux host whose uid isn't 1000. That breaks more than the bind mount does.
  - *Chowning the volumes at container start:* needs a root step on every start, which
    `--cap-drop=ALL` and `no-new-privileges` rule out by design.

**Why DEVC-D and not IAC-D.** No repo has adopted the template yet, so no other repo has
to change (the same test as DEVC-D2). The host rule it creates for consumers is carried by
#12's `IAC-D` entry, like DEVC-D3's.

**Consequences.** #12's `IAC-D` entry must include the Linux host rule (uid 1000, or no
write access to `/workspace`). A comment on #12 carries this when the PR lands. The
template proof doesn't exercise the trade-off, because its CI fixture is world-writable.

### Org-wide IAC-D decisions that bind this repo

Each of these is recorded in full in infrastructure-core's log. They are cited here only.

| Id | Summary | Where it shows up here |
|----|---------|------------------------|
| IAC-D14 | Work branches live on the org repo, not a personal fork, because fork PRs silently ran no CI. The same "absent-check trap" is why required-check names are read from each workflow's `name:` field and never typed from memory. | Branches on `603-Identity/devcontainers`; `ruleset.required_checks` |
| IAC-D48 | Each repo numbers its own decisions in a local series; shared and org-wide decisions stay `IAC-D`. Repos that plan sprints as milestones keep a README-only `sprints/`. | DEVC-D1; `decisions` and `sprints_dir` in `.ai/project.yml`; `sprints/` |

The image and token model will be recorded as an `IAC-D` entry (#12), and cited here once
it is.
