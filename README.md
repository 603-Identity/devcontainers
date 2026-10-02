# 603-Identity devcontainers

These are the shared devcontainer images for 603-Identity and glunk-works repositories. Every repo gets its
**own container**, built from **shared, digest-pinned images**. Isolation between repos
costs almost no disk, because the image layers are stored once per machine.

| Image | Contents |
|---|---|
| `ghcr.io/603-identity/devcontainer-base` | Ubuntu, non-root `app` (uid 1000), git, gh, jq, yq, Python (system), uv, pre-commit, bc-detect-secrets, zizmor |
| `ghcr.io/603-identity/devcontainer-tofu` | base + OpenTofu + tflint |
| `ghcr.io/603-identity/devcontainer-node` | base + Node.js + npm |

Exact versions live in one place each, not here: the Dockerfile `ARG`s for the downloaded
binaries and [`images/base/tools/uv.lock`](images/base/tools/uv.lock) for the Python tools.

The images are **linux/amd64 only**: every downloaded binary is amd64, so the base
image's first build step fails with a clear message on any other architecture.

No repo has adopted the images yet. Adoption is tracked in #10 (pilots) and the wave
issues #26 to #28.

Local sizes measured on 2026-09-28: base 445 MB, tofu 664 MB, node 752 MB. Shared layers
are stored only once, so all three together take about 0.95 GB.

Work on these images is planned on this repo's issues and milestones. See
[`docs/roadmap.md`](docs/roadmap.md) for status, next action and decisions. This repo has
no devcontainer of its own and is worked on from the host: its local gate (`gates.green`
in [`.ai/project.yml`](.ai/project.yml)) runs `docker run` and `shellcheck`, and a
container built from the template has neither a Docker daemon nor shellcheck.

Repos that get no container from these images (glunk-works/loop-orchestrator, this repo,
org profile, archived and demo repos) are listed under
[Exceptions](docs/threat_model.md#exceptions) in the threat model.

## Using an image in a repo

Open the repo with VS Code and its Dev Containers extension. Commit signing depends on its
GPG agent forwarding, and no other editor is supported. On a Linux host your uid must be
1000, or the container can't write `/workspace` (DEVC-D5). macOS and Windows hosts are
unaffected.

1. Copy [`template/.devcontainer/`](template/.devcontainer/) into the repo unchanged.
2. In its `Dockerfile`, set `FROM` to one image, by tag **and** digest. Take both from the
   latest *Build images* run summary. CI verifies every digest on every pull request (step 3),
   so a bad one fails the PR. To check one by hand first:
   ```sh
   gh attestation verify oci://ghcr.io/603-identity/devcontainer-tofu@sha256:<digest> \
     --repo 603-Identity/devcontainers \
     --cert-identity https://github.com/603-Identity/devcontainers/.github/workflows/build.yml@refs/heads/main \
     --cert-oidc-issuer https://token.actions.githubusercontent.com \
     --source-ref refs/heads/main --deny-self-hosted-runners
   ```
3. Wire up CI (the full list is in [What the consuming repo needs](#what-the-consuming-repo-needs)):
   - Copy [`template/.github/workflows/devcontainer-image.yml`](template/.github/workflows/devcontainer-image.yml)
     and [`architect-review-gate.yml`](template/.github/workflows/architect-review-gate.yml)
     into `.github/workflows/`. The first runs this repo's verifier as the check
     `verify / verify` on every pull request. Copy it unchanged.
   - Edit only the marked per-consumer values in the gate.
   - Add `.devcontainer` to `.github/dependabot.yml` under the `docker` ecosystem, and
     configure the `github-actions` ecosystem too. Image bumps and verify-pin bumps then
     arrive as pull requests. **Dependabot's image bump is not exempt from review**: a human
     merges it (auto-merge is off, see below).
   - Run `tools/check-consumer-workflows.sh` from a checkout of this repo, against the
     consuming repo's `.github/workflows`, before opening the adoption PR.
4. Delete the dependency-volume lines the repo doesn't use (`node_modules`, `.venv`).
   Leave the `--read-only` and tmpfs `runArgs`, the `init` line and the home volume alone.
5. Open the repo in the container, then store its GitHub credential once:
   `gh auth login --with-token` (see [Credentials](#credentials)).

### What the consuming repo needs

[`devcontainer-image.yml`](template/.github/workflows/devcontainer-image.yml) and the
[gate](template/.github/workflows/architect-review-gate.yml) only mean something with these
in place. `tools/check-consumer-workflows.sh` lints the workflow shapes named below (the caller, write
permissions, `uses:` in the gate's `resolve` and `post`, the `.github/` rule, the pin shapes). It runs
when you run it, at adoption and from the pilots; nothing re-runs it in the repo's CI. The rest is
settings the adoption PR records, and review.

- **Required checks, pinned.** The ruleset requires `architect-review` and `verify / verify`,
  each with `integration_id: 15368` (GitHub Actions). Unpinned, a status posted by a user
  with push access satisfies the requirement. Read the ruleset back through the API after
  creating it, and attach the result to the adoption PR. The pin on `verify / verify` is
  untested until the first pilot (#10).
- **What `verify / verify` rejects.** It fails the PR unless `.devcontainer/Dockerfile` is the template's shape (the
  header comment in the template Dockerfile lists the rules: one plain `FROM`, ASCII with LF endings, the
  `# syntax=` line, no `COPY --from` or `ONBUILD`) and `devcontainer.json` has no top-level `image`,
  `features`, `dockerComposeFile`, `dockerfile` or `context` key (any letter case), a `build` holding only
  `dockerfile: "Dockerfile"` and, optionally, `context: "."`, and no second `devcontainer.json` anywhere in the
  repo (a symlink or a case-variant path also fails). A
  repo that needs Dev Container Features, or keeps a fixture `devcontainer.json`, cannot adopt the
  template as it stands. An image built by a re-run of `build.yml` (attempt 2) fails too: use a digest from
  a first-attempt run.
- **The caller stays unfiltered.** `pull_request` with no `paths:` or `branches:` filter, one
  job `verify` with no `name:` or `if:`. A filtered required check never reports and blocks
  every other PR.
- **Both pins are `@<sha> # vX.Y`.** A full commit SHA plus a version comment, never a bare tag:
  the verifier fails unless its own pin is a SHA. The caller's pin and the gate's `decide` pin
  name the same release (the lint only warns when they differ). Dependabot's `github-actions` ecosystem bumps them. A bump edits only
  `.github/`, which is always in the gate's review scope whatever its `case` block says, so it
  always needs a review.
- **The gate's per-consumer values**, marked in the file, and nothing else: the `case` block
  (this repo's `code_paths`; the `.github/` rule above it is not editable), `REVIEWER_IDS`,
  `HEADER` and `ATTESTATION`, and the `decide` pin.
- **Write tokens only where the gate needs them.** No job other than the gate's `post` holds
  `statuses`, `contents`, `pull-requests`, `checks` or `actions: write` on a trigger that
  Dependabot's own branch can run (a PR event, including `issue_comment` and `pull_request_target`, which the lint treats alike; `create`; and a `push` whose
  filter is not `tags:` alone or a list of literal branch names; no `branches-ignore:` counts, because Dependabot's branch name is configurable (`pull-request-branch-name.separator`)). A job on such a trigger with no
  `permissions:` block (the repo default token applies) or `write-all` counts too, so give every job
  on those triggers an explicit block. `resolve` and `post` contain no `uses:`, `container:` or
  `services:`, run on a GitHub-hosted runner, and `post` holds only `statuses`, `contents` and `pull-requests: write` and `issues: read`. That keeps upstream action code, which
  Dependabot bumps, off the runner that holds the status token.
- **Settings.** "Allow auto-merge" on, and an approval count of 0 in the ruleset. The `docker`
  and `github-actions` Dependabot ecosystems both configured. **Private repos:** "Send write
  tokens to workflows from fork pull requests" stays **off**.
- **A caller that fails to start fails closed.** No `verify / verify` check is reported, so the
  required check blocks the PR.

**Auto-merge is off.** The gate can merge a verified, same-MAJOR Dependabot image bump on its
own, but only while the tag `devc-automerge-on` exists in *this* repo, and nobody has created
it. Until the owner does (a separate decision with preconditions, tracked in #30), every bump
takes the review path and a human merges it. The tags `v*` and `devc-automerge-*` are
protected by a tag ruleset here: creating, moving or deleting one needs the Repository admin
role.

**If the tag ever exists, and is then removed,** that stops later *arming* only. It does not
disarm a pull request that is already armed: that merges whenever its remaining checks go
green, possibly hours later. To close the window, post a comment as an allowlisted reviewer on
each armed PR (that re-runs the gate's `post` job, which disarms it), or run
`gh pr merge --disable-auto` on each.

### Toolchain versions must match CI

A container that validates with a different tool version than CI reports a result CI
doesn't share. The OpenTofu and Node versions here are the ones every consuming repo's
workflows pin, in every org. **Bump the image and every repo's workflow pin together**, never one
without the other. The one known exception is npm: the image ships npm 12 ahead of CI's
bundled npm 11 until each repo takes it (#27).

### Consuming from another org

1. Every org pulls `ghcr.io/603-identity/devcontainer-*` and verifies it against this
   repo's `build.yml` on `main`: the `verify / verify` check does it on every PR, and step 2 has the
   command to run by hand. There is no per-org
   image or fork: this repo is the single publisher.
2. **The GHCR packages must stay public.** Package visibility is set per package, separately
   from the repo's visibility. A private package fails the next pull or rebuild of every
   container outside 603-Identity, and every Dependabot bump there. It changes
   availability, not security.
3. **Checkout folder names must be unique across every checkout on the host, in every
   org**, including forks, reference clones of third-party repos, and a second clone of the
   same repo. Each per-repo volume is named `<folder>-<suffix>`. Two checkouts with one
   folder name share every one they both mount, up to all four: `-home` (the token, usable
   from both, plus Claude sessions and, on Linux, Claude Code's own login and settings
   hooks), `-tmp`, `-node_modules` and `-venv` (each repo runs the other's dependency
   trees). **A collision merges two repos
   into one trust domain.** Rename the second folder. Docker volume names are
   case-sensitive and Windows folders are not, so `Foo` and `foo` get separate volumes.
   That fails safe, but it orphans a credential volume. A start-up check warns, after the
   fact, when a container starts against a home volume first used by another repo: it
   prints a banner naming both repos and the fix (rename the folder, then
   `docker volume rm <folder>-home <folder>-tmp <folder>-node_modules <folder>-venv`; for a
   repo that was only renamed or transferred, `rm ~/.devc-owner`). It detects and never
   blocks, so the rule stands.
4. Tokens stay per repo, tiered as in [Credentials](#credentials), inside the repo's own
   org. A token never covers another org's repos.
5. Identity takes one `~/.gitconfig.d` file per account, listing every org it serves; see
   [Git identity](#git-identity).

## Security model

[`docs/threat_model.md`](docs/threat_model.md) is the record of reference: what the images
take in, what they publish, who holds which credential, the boundaries meant to hold, and
the known gaps. In short:

- Everything is pinned and verified: the base image by digest, each binary by version and
  a sha256 from its release's own checksum file, and the Python tools by hash lock.
- Nothing is published until the smoke test and a Trivy scan pass. The only way past the
  scan is an entry in [`.trivyignore.yaml`](.trivyignore.yaml), and every entry expires
  within 30 days.
- Every published digest carries signed build provenance and an SBOM.
- Consumer CI re-verifies every image digest on every pull request, and a verified Dependabot image
  bump can be auto-merged only while a kill-switch tag exists that nobody has created (see
  [What the consuming repo needs](#what-the-consuming-repo-needs)).
- The container runs as non-root, with no Linux capabilities and no way to gain privileges.

## Disk, speed and volumes

Code stays in the Windows checkout, bind-mounted at `/workspace`. **Nothing grows in the
container's own filesystem**, and that is enforced rather than left to convention: the root
filesystem is **read-only** (`--read-only` in `runArgs`), so every write outside the mounts
below fails with `EROFS` and names the next disk hog instead of hiding it.

| Mount | Kind | Holds |
|---|---|---|
| `/workspace` | bind (host checkout) | the repo |
| `/workspace/.venv`, `/workspace/node_modules` | per-repo volumes `<repo>-venv`, `<repo>-node_modules` | the uv project environment and npm dependencies (many small files are the slowest thing across the Windows bind mount) |
| `/home/app` | per-repo volume `<repo>-home` | everything user-scoped: the gh credential, Claude Code sessions and memory, the VS Code server and extensions, uv's managed interpreters and cache (`UV_CACHE_DIR=~/.local/uv-cache`), `PRE_COMMIT_HOME=~/.local/pre-commit`, `TFLINT_PLUGIN_DIR=~/.local/tflint-plugins` (tofu image), `NPM_CONFIG_CACHE=~/.local/npm-cache` and `NPM_CONFIG_PREFIX=~/.local` (node image), the forwarded GPG agent socket in `~/.gnupg`. `XDG_CACHE_HOME=~/.local/cache` moves every other XDG-aware cache here too. |
| `/home/app/.cache/tofu-plugins` | shared volume `devc-tofu-plugins`, nested in the home volume | **only** `TF_PLUGIN_CACHE_DIR`, the tofu provider cache, which `tofu init` checks against the consuming repo's `.terraform.lock.hcl`. It is mounted at that one directory, not over `~/.cache`, so a tool that hard-codes `~/.cache` stays in the per-repo home volume. npm's cache is per repo too, because `npx` runs packages from it without a check |
| `/tmp` | per-repo volume `<repo>-tmp` | scratch and task output |
| `/var/tmp`, `/dev/shm` | tmpfs | scratch that is gone when the container stops. `/run` is tmpfs too, but root-owned, so only root-run tooling writes there |
| everything else | **read-only** | the image |

`"init": true` gives the container a real PID 1 that reaps the zombies VS Code and Claude
Code leave behind. The base image sets `UV_LINK_MODE=copy`, because uv's cache and the
project environment are separate mounts and hardlinks between them fail with `EXDEV`.
`postCreateCommand`'s `pre-commit install` writes `/workspace/.git/hooks`, which is the
bind mount, so it still works.

**Wiping a repo's state:** `docker volume rm <repo>-home <repo>-tmp <repo>-venv <repo>-node_modules`.
That also removes the repo's GitHub credential, so run `gh auth login --with-token` again.

**The home volume is frozen at first mount.** Docker copies the image's `/home/app` into an
empty volume once and never again, so image-owned configuration must not live in the home
directory. The `~/.gitconfig` include stub is therefore written by `git-identity.sh` at
every start, not shipped in the image; system git settings stay in `/etc/gitconfig`, and
scripts in `/usr/local/share`. Each home, cache and dependency volume mount point above is pre-created app-owned in the
image (`tests/smoke.sh` asserts it), because Docker copies the image path's ownership into
an empty volume and a missing path comes up root-owned and unwritable as uid 1000.

**Migrating from the old layout.** Needed only by a container that already holds the
template's earlier `<repo>-gh` and `<repo>-claude` volumes; no repo has adopted the images
yet (adoption starts with milestone 2), so this is the procedure for the first ones that
have. With the container stopped and before rebuilding it, copy the credential and sessions
once into the new home volume (substitute the old volumes' actual names):

```sh
docker run --rm --user 0 --network none \
  --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
  -v <repo>-gh:/from-gh:ro \
  -v <repo>-claude:/from-claude:ro \
  -v <repo>-home:/to \
  ghcr.io/603-identity/devcontainer-base:<tag>@sha256:<digest> \
  sh -c 'mkdir -p /to/.config/gh /to/.claude && cp -a /from-gh/. /to/.config/gh/ && cp -a /from-claude/. /to/.claude/ \
    && cp -a /home/app/. /to/ && chown -R 1000:1000 /to'
```

Check `gh auth status` in the rebuilt container, then remove the old volumes with
`docker volume rm`. The old shared `devc-cache` volume is unused on the new layout (the
tofu cache is now `devc-tofu-plugins`) and can be removed once no container on the host
still runs the old template. The copy runs as root and ends with a `chown`, because a home volume
that is not empty at first mount is not seeded from the image: its root directory would
otherwise stay root-owned and unwritable as uid 1000. Run it before the first container
start on the new layout, never after.

**Why this matters:** the previous single devcontainer grew to **331 GB**. Claude Code
sessions installed dependencies into `/tmp`, which sat in the container's own filesystem
where nothing ever cleaned it up, and several repos had been cloned into one container.
The layout above makes growth visible (`docker system df -v`) and disposable, for everything
in a volume, and the read-only root stops anything else from accumulating. The
one-container-per-repo rule keeps each repo's credentials and data apart. Only the tofu
provider cache and the host's git identity files (see [Git identity](#git-identity)) are shared
by all containers.

**Getting disk space back on Windows:** Docker Desktop keeps everything in
`%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`. Deleting data frees space inside that
file, but Windows gets it back only when the file is compacted, or automatically if the
file is marked sparse (`fsutil sparse setflag`, run with Docker stopped). Check that it
still works after Docker Desktop updates.

Microsoft's WSL docs describe `sparseVhd` under `[experimental]` in `.wslconfig` as: "When
set to `true`, any newly created VHD will be set to sparse automatically." It applies to
newly created VHDs, so it does not by itself keep an existing `docker_data.vhdx` sparse.
To have new VHDs sparse from the start, add to `%USERPROFILE%\.wslconfig`:

```ini
[experimental]
sparseVhd=true
```

The monthly prune routine is tracked in #31.

## Credentials

Each container carries a **fine-grained personal access token**, tiered by what that repo
needs:

- **Satellite repos:** a token covering **only that repo**.
- **infrastructure-core (the hub):** a token covering infrastructure-core **and** the repos
  it coordinates. Its wider reach is deliberate, because coordinating is its job.
- **Admin work** (rulesets, repo settings, applying `tenants/*/github*`): **never** done
  with a container token. It happens from the host's org login, or in CI, when needed.

Tokens expire after 90 days at most. Record each one in the owning org's credential
ledger (603-Identity: infrastructure-core's).

## Git identity

Identity (who commits) is **host-wide**. The GitHub credential (what may push) is **per
repo**, see [Credentials](#credentials). Every container mounts the same host directory
`~/.gitconfig.d/` (on Windows, `%USERPROFILE%\.gitconfig.d\`) read-only. It holds one
git-config file per GitHub account, named `<anything>.gitconfig`, and each file lists the
orgs it serves in a key host git ignores:

```ini
[user]
	name = Jane Doe
	email = jane@example.com
	signingkey = ABCDEF0123456789
[commit]
	gpgsign = true
[devcontainer]
	org = 603-identity
	org = jrg-consulting
```

At every container start `git-identity.sh` reads `/workspace`'s `origin`, takes the org from
a `github.com` URL (case-insensitive, https or ssh), finds the **one** file that claims it,
and copies only `user.name`, `user.email`, `user.signingkey`, `commit.gpgsign` and
`tag.gpgsign` into `~/.gitconfig-identity`. Nothing else is copied: no `[credential]`
section, no `include`, no `gpg.*`. A host credential helper in an identity file that points at `gh.exe` can
therefore never reach the container's effective credential helper. When nothing matches (no origin, a non-GitHub or
lookalike URL, no file or several files claiming the org, an unreadable file, an empty
directory), the script prints a loud banner naming the reason, commits have no identity,
and the container still starts.

- The directory is mounted into **every** container, so it holds these files and nothing
  else: no backups, no credential stores, and no secret of any kind inside the files (no
  token in a URL, no `http.extraHeader`), because any container can read them.
- **Prerequisite:** `~/.gitconfig.d` must exist on the host. The devcontainer CLI's
  `--mount` fails on a missing source with `bind source path does not exist`.
- **Windows:** start VS Code or the CLI from PowerShell or cmd. Git Bash also exports
  `HOME`, so the template's source path doubles (`C:\Users\x` + `C:\Users\x/.gitconfig.d`)
  and the same error appears. Run `unset HOME` in that shell first if you must use it.
- Edits to the host files apply on the **next container start**.
- Signing goes through VS Code's forwarded GPG agent. SSH signing is out of scope.

## Repairing Claude Code plugin state

No image ships the `claude` CLI (DEVC-D4). When a container keeps loading an old plugin
version, the documented fix (refresh the marketplace, then reinstall the plugin) still
works: the Claude Code extension the template installs carries its own native `claude`
binary, the same release as the extension, with no node or npm needed. Close the Claude
panel first, so the extension isn't writing plugin state at the same time, then run it from
a terminal in the container:

```sh
claude=$(ls -d ~/.vscode-server/extensions/anthropic.claude-code-*-linux-x64/resources/native-binary/claude | sort -V | tail -1)
"$claude" plugin marketplace update <marketplace>
"$claude" plugin uninstall <plugin>@<marketplace>
"$claude" plugin install <plugin>@<marketplace>
```

Reload the window afterwards. Don't hand-edit the files under `~/.claude/plugins/`: their
format is internal and changes between releases. The `resources/native-binary/` path is
internal to the extension too (checked against 2.1.286). If `ls` finds nothing, the
extension has moved it; look for the binary under the extension directory before reaching
for the state files.

## Working on this repo from Windows (WSL)

This repo has no devcontainer of its own (docs/threat_model.md, Exceptions): building and
smoke-testing the images needs a Docker daemon, and giving a container one would break the
boundaries the images exist to enforce. The local Linux environment is the Ubuntu WSL2
distro instead, working on the same `/mnt/c/...` checkout.

Set it up once (and again after changing a pin) from inside the distro:

```
bash tools/wsl-setup.sh
```

It installs the mikefarah yq release binary at the version `images/base/Dockerfile` pins,
the Node release `images/node/Dockerfile` pins (for `tests/template-proof.sh`'s devcontainer
CLI), the Go release that `.github/workflows` pins, and jq and shellcheck from apt. It reads
each pin from the repo rather than repeating it, but only Go follows what CI runs: CI uses
the runner's own jq, yq, node and shellcheck, and apt's versions are whatever the distro
ships. apt's `yq` is the Python wrapper and fails the gate suites. The script runs as root:
start it as root (`wsl -u root`) or let it re-run itself under `sudo`. It checks the shape of
each pin before use, but the pins come from your checkout, so run it on one you trust.

| Runs in WSL | Stays on Windows |
| --- | --- |
| `bash tools/tests/run-gate-tests.sh` (the gate suites; Git Bash on Windows is flaky: a test can exit 127 with no output) | `git` (commits, branches, signing) and `gh` |
| `shellcheck`, `go test` / `go vet` for `tools/devc-verify` | the editor and Claude Code |
| `bash .github/scripts/build-and-test.sh local` (builds the images and runs `tests/smoke.sh` in each), `tests/template-proof.sh` | |

Image builds and the smoke tests need `docker` inside the distro: turn on Docker Desktop's
WSL integration for it (Settings, Resources, WSL integration).

- **Don't run git from both sides on the same checkout.** WSL on `/mnt/c` reports file mode
  changes; if it ever has to run git, `git config core.fileMode false` there.
  `tests/template-proof.sh` does run `git init` in WSL, but on a throwaway fixture, not the
  checkout. The setup script doesn't install git; the Ubuntu distro ships it.
- **WSL has its own home directory**, so the per-account gitconfig and the `gh` logins do
  not carry over. The gate suites don't need them: they are offline and use a fake `gh`.

## Updating a pinned tool

`bump-binaries.yml` runs weekly, and on manual dispatch, for gh, yq, uv, tofu, tflint,
node and npm. **It cannot run for real yet**: it needs a GitHub App that hasn't been
created (docs/threat_model.md's Known gaps). Until that App exists and its secrets are
set, every run fails at the token step, and the fallback below is how to bump a tool.
The workflow resolves each tool's newest release (node: the current LTS line; npm:
the newest release the current node pin supports), takes the sha256 from that release's
own published checksum file (npm: the registry's `integrity` field) -- never from
hashing the download -- and opens one PR per tool that is behind, with the release page
linked in the body (not a diff -- see step 1 below). `tests/smoke.sh` reads the expected
version from the same `ARG` lines the workflow rewrites, so there is nothing else to
edit there. (The Python tools are not `ARG`s: they live in
`images/base/tools/pyproject.toml` and `uv.lock`, and Dependabot bumps those on its own
schedule.)

A human still has to:

1. Read the linked release notes and the diff since the current tag (not linked -- open
   it yourself from the release page or the tags comparison on GitHub).
2. Check the Dockerfile's own prose for anything tied to the specific version being
   replaced -- the node image's npm-bundled-CVE override block and its "Node X bundles
   npm Y" comments, the tofu image's per-bump CVE/Trivy-count notes -- and update or
   remove what the new version makes stale. The workflow only ever touches the `ARG`
   lines themselves.
3. For OpenTofu or Node, open the matching CI-pin PRs in every consuming repo.
4. If the Trivy scan now passes without an entry in `.trivyignore.yaml`, delete that
   entry in the same PR.
5. Merge -- the workflow never does.

To bump a tool the workflow doesn't cover, or while it's down, do the same by hand: read
the release notes, take the sha256 from the release's own checksum file (never
`sha256sum` a download and paste the result), and change the Dockerfile's `ARG`s.

The `# syntax=docker/dockerfile:...@sha256:...` line on line 1 of all four Dockerfiles is
pinned by digest but no bot bumps it (Dependabot's docker updater reads only `FROM`
lines). Move the four together, taking the digest from `docker buildx imagetools inspect
docker/dockerfile:<tag>`.

Dependabot handles the base image digest, the GitHub Actions pins, and the Python tool lock (`uv` ecosystem on `images/base/tools`). Dependabot
proposes a `bc-detect-secrets` bump as a PR of its own: it is excluded from the grouped `uv`
PR, not ignored (#22 removed the old ignore on purpose). Do not merge one until every 603 repo is ready to regenerate its
`.secrets.baseline` and bump its CI pin in the same change.
