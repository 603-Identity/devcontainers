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

P0: cross-org images (milestone 1) is done. Its last change merged as `6f63aec` (#174).

P1: pilot adoption (milestone 2) is done. Its last change merged as `00b6a2e` (#228, the
adoption runbook). The pilots, terraform-cloudflare-dns and terraform-microsoft365-entra, have
adopted the template (#10 closed). The waves (#26 to #28) follow `docs/adopting.md`. Org secret
scanning (#190) moved to milestone 4.

## Next action

The next piece of work is set by the open milestone on this repo, since
`planning.kind: github_milestones`. With no open milestone, run
`/way-of-working:plan-sprint` to triage the open issues into one.

Two dates are fixed:
- #148: the `tofu` and `tflint` Trivy exceptions expire on 2026-11-01. Renew or retire them
  before then; each renewal extends at most 30 days.
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
  name, so folder-name uniqueness is a documented host rule, not prevented here (DEVC-D6
  detects a collision at start). The residual: a collision merges two repos' trust domains (up to five per-repo volumes; four
  after #23 folded `-gh` and `-claude` into `-home`).
- Prose names 603-Identity and glunk-works. Host rules say "every checkout on the host",
  which covers the other orgs there.
- Tokens are recorded in the owning org's credential ledger.

**Why DEVC-D and not IAC-D.** These are this repo's own obligations as publisher. What
consumers in every org must do is carried by #12's `IAC-D` entry.

**Consequences.** #12 carries the consumer obligations. A follow-up **detects** a
folder-name collision at container start (DEVC-D6); nothing prevents one. glunk-works has no credential ledger yet, a named gap in
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

#### DEVC-D6: A start-up check warns on a folder-name collision; it detects, it doesn't prevent

**Resolved** 2026-10-01 by the repo owner, on #43. DEVC-D3 left folder-name uniqueness a
host rule and promised a follow-up; this is it.

**Context.** The template names every per-repo volume after the checkout folder. Two
checkouts of different repos on one host that share a folder name share `-home` (the gh
token), `-tmp`, `-node_modules` and `-venv`, which merges two trust domains. #23 folded `-gh`
and `-claude` into `-home`, so one marker there detects a collision on every volume under
the unmodified template.

**Decision.**
- `images/base/files/owner-check.sh` keeps `org/repo` (lowercase) of the first origin it
  sees in `~/.devc-owner` on the home volume. Later starts compare it with the current
  origin. A mismatch prints a banner naming both repos and the fix and leaves the marker
  alone.
- It **warns and never blocks**, and always exits 0, like `git-identity.sh` and
  `gpg-check.sh`. When `postStartCommand` runs, the token is already mounted, so blocking
  would protect nothing and would break the legitimate rename and transfer cases.
- It is an image script, called first in the template's `postStartCommand` (every start,
  because a collision often first appears when a second checkout starts against existing
  volumes). A fix to the script reaches every consumer through its digest bump. The new
  `postStartCommand` line is in the template, which a repo copies once, so a repo that
  adopted the template earlier must re-copy it (none has: #10). The image change is
  additive, so the MAJOR is unchanged. A new template on an older image just skips the
  missing script, since the chain ends in `gpg-check.sh`, which exits 0.
- It reads the origin with **the same anchored grammar as `git-identity.sh`**, and prints
  only the parsed `org/repo`, never the URL (it can carry a token). A rejected or missing
  origin yields no owner and writes nothing. A marker that is unreadable, not a regular
  file or off-grammar counts as a mismatch, is never echoed (code in the volume wrote it),
  and is replaced so the banner fires once. `tests/smoke.sh` runs one URL table through
  both scripts, so the shared regex cannot drift apart unnoticed. (One fail-safe difference:
  owner-check drops a trailing `.git`, so a repo segment of exactly `.git` yields no owner.)
- Tests: `tests/smoke.sh` covers match, mismatch, the edge cases and grammar agreement.
  `tests/template-proof.sh` covers the match case and a real two-checkout collision on one
  `-home` volume.
- Rejected:
  - *A host-side `initializeCommand`.* It runs before anything mounts, so it is the only
    place that could prevent a collision. But it runs in the host's shell, so it needs
    separate PowerShell, cmd and POSIX versions, and it cannot read a volume without
    starting a container.
  - *Folding the check into `git-identity.sh`.* That script owns identity and has its own
    reviewed failure model; the two concerns should fail independently.

**Why DEVC-D and not IAC-D.** No repo has adopted the template yet (#10), so no other repo
has to change (the same test as DEVC-D2). IAC-D49's consumer obligation and the README's host
rule are unchanged: this check backs them up and doesn't replace them.

**Consequences.** It catches accidental collisions under the unmodified template, after the
fact. A hostile `.devcontainer/` can mount any volume and skip the check (threat model
boundary 5). The threat model's Known gap now reads "detected at start, not prevented".

#### DEVC-D7: The review gate trusts human writers; the bump App is not trusted

**Resolved** 2026-10-05 by the repo owner, on #93 and #122 (milestone 4, build-order item 4).

**Context.** `architect-review` is the only review control on `main`. Any writer can turn it
green without a review: a PR runs its own copy of the gate (#93), and a PR's own workflow can
post the status itself, because every `GITHUB_TOKEN` run posts as the same integration (F9b,
#122). Auto-merge is off, so a human reads and merges every PR. The writers are the owner's
two accounts, Dependabot, and, once #102 creates it, the bump-binaries App.

**Decision.**
- **Human writers are trusted by construction.** The gate does not defend against them. #93
  is accepted, not fixed, and stays a Known gap in the threat model.
- **The bump-binaries App is not a trusted writer.** It is an automated identity that parses
  untrusted upstream release data. Its permissions (`contents` and `pull-requests: write`,
  no `workflows` or `statuses`) already keep it from editing the gate or posting the status.
  Its remaining routes are #92 (a backdated commit passes against an older review) and #94
  (editing an owner's comment into a qualifying one). Both close by counting only formal
  reviews whose `commit_id` is the head SHA; comments stop counting. That fix ships in `v1.3`.
  *Amended 2026-10-05, when the fix was built:* #92 closes. #94 narrows rather than closes:
  a writer may be able to edit another user's formal review body into a qualifying one (needs
  an owner review already on the current head; unverified), so #94 stays open. A second gap,
  the review being bound to the head at the moment it is posted rather than the one the
  reviewer read, is tracked as #278. The threat model's Known gaps carry both.
  *Amended 2026-10-06, when #94 was verified and fixed:* a write-access account can edit another
  user's formal review body, leaving its author, state and `commit_id` unchanged (probed on a
  throwaway PR). The gate now also requires every editor in a matching review's edit history
  (GraphQL `userContentEdits`) to be an ID in `REVIEWER_IDS`; #94 closes. This ships in the next
  release, not `v1.3` (DEVC-D8: immutable). The App token's own ability to make the edit stays
  untested, and the gate does not re-run when a review is edited.
  *Amended 2026-10-06, #315 and #281:* the gate now also re-runs when a review is edited or dismissed
  (`pull_request_review` types `edited` and `dismissed`); the "does not re-run" clause above no longer holds
  for same-repo PRs. A fork PR's run still gets a read-only token (see the threat model's Known gaps).
  *Amended 2026-10-06, #278 (gate side):* a matching review must also carry the line
  `Reviewed against head <HEAD_SHA>` in its quote-stripped body, so a review stamped onto a head
  that moved during it fails closed. The skill side (posting with `commit_id` pinned) stays with the
  way-of-working plugin.
- **Auto-merge needs a reviewer App first.** Before `devc-automerge-on` is created (#139), the
  gate's result must come from a dedicated App's check run that the ruleset requires by
  integration id, with the key in a `main`-only Environment (#267). #126 and #132 (`disarm()`)
  move out of milestone 4 and stay #139 preconditions: that change re-copies the gate to every
  consumer anyway, so they ride along at no extra cost.
- Rejected:
  - *Moving the gate to `pull_request_target` now (#93's fix):* a writer can still post the
    status from another workflow (F9b), so it adds a dangerous trigger without closing the gap.
  - *A ruleset-required workflow (#122 option b):* needs GitHub Team, which glunk-works is not
    on, so the shared template could not use it.
  - *Trusting the App too:* #94's scenario is exactly an App with write access, and #92 lets it
    push a backdated commit after a review.

**Why DEVC-D and not IAC-D.** It decides what this repo's gate, and the template gate it
publishes, defends against. Consumers take the #92 fix in `v1.3` and the #94 fix in the next release, by re-copying
the gate, as they take any gate fix.

**Consequences.** Fork PRs on this repo and the orgs' other public repos need a collaborator
to open them and approval to run (set 2026-10-05), which narrows the fork gap #122 also
named. The threat model records the trust split, and #139 lists #267 among its
preconditions.

#### DEVC-D8: Each version ships as a signed tag with an immutable GitHub Release

**Resolved** 2026-10-06 by the repo owner, when cutting `v1.3`.

**Context.** `v1.0`-`v1.2` were bare tags (`v1.1` lightweight, `v1.2` signed and annotated),
with no release notes. Consumers copy the gate from a tag and pin the reusable workflows to its
SHA, so the upgrade steps for each version lived only in this roadmap. The `release-tags`
ruleset lets the Repository admin role bypass it, so an admin could still move or delete a tag
consumers had already pinned.

**Decision.**
- Each version is a signed, annotated `vX.Y` tag on a commit already on `main`, pushed by its
  full ref (`git push origin refs/tags/vX.Y`).
- Each tag is published as a GitHub Release, created with `gh release create vX.Y --verify-tag`
  so it never mints an unsigned tag. The notes lead with the consumer upgrade steps (re-copy,
  re-pin, re-lint), then the behaviour changes and the known gaps. A docs-consistency pass checks
  them against the code before they are published.
- Release immutability is on for the repo (set 2026-10-06). A published release's tag cannot be
  moved or deleted, admins included. A mistake ships as a new version, never as an edit.
- After each release, one PR re-points `template/`'s pins and this repo's own `decide` pin to
  the new SHA.
- Rejected: *staying with bare tags:* no place for upgrade steps that consumers see beside
  Dependabot's pin bump, and the admin bypass stays open.

**Why DEVC-D and not IAC-D.** It changes how this repo publishes. Consumers pin by SHA either
way, so no other repo has to change.

**Consequences.** `v1.3` is the first immutable release. `v1.0`-`v1.2` keep only the ruleset's
protection. The threat model's tag-ruleset entry records the change.

### Org-wide IAC-D decisions that bind this repo

Each of these is recorded in full in infrastructure-core's log. They are cited here only.

| Id | Summary | Where it shows up here |
|----|---------|------------------------|
| IAC-D14 | Work branches live on the org repo, not a personal fork, because fork PRs silently ran no CI. The same "absent-check trap" is why required-check names are read from each workflow's `name:` field and never typed from memory. | Branches on `603-Identity/devcontainers`; `ruleset.required_checks` |
| IAC-D48 | Each repo numbers its own decisions in a local series; shared and org-wide decisions stay `IAC-D`. Repos that plan sprints as milestones keep a README-only `sprints/`. | DEVC-D1; `decisions` and `sprints_dir` in `.ai/project.yml`; `sprints/` |
| IAC-D49 | Every repo in 603-Identity and glunk-works gets its devcontainer from shared, digest-pinned images that only this repo publishes, from `main`. Each container carries a per-repo, tiered fine-grained token. Consumers pin and verify every digest, keep checkout folder names unique, and on Linux run as uid 1000. Adds `DEVC-D` to IAC-D48's series. | DEVC-D2, DEVC-D3, DEVC-D5; README's *Credentials* section; `build.yml`'s `MAJOR`; #12 |
