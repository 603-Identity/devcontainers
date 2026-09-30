# 603-Identity devcontainers

These are the shared devcontainer images for 603-Identity and glunk-works repositories. Every repo gets its
**own container**, built from **shared, digest-pinned images**. Isolation between repos
costs almost no disk, because the image layers are stored once per machine.

| Image | Contents |
|---|---|
| `ghcr.io/603-identity/devcontainer-base` | Ubuntu 26.04, non-root `app` (uid 1000), git, gh 2.102.0, jq, yq, Python 3.14 (system), uv 0.12.21, pre-commit, bc-detect-secrets 1.5.51, zizmor 1.30.1 |
| `ghcr.io/603-identity/devcontainer-tofu` | base + OpenTofu 1.11.14 + tflint |
| `ghcr.io/603-identity/devcontainer-node` | base + Node.js 24 + npm 11 |

The images are **linux/amd64 only**: every downloaded binary is amd64, so the base
image's first build step fails with a clear message on any other architecture.

No repo has adopted the images yet. Adoption is tracked in #10 (pilots) and the wave
issues #26 to #28.

Local sizes measured on 2026-09-28: base 445 MB, tofu 664 MB, node 752 MB. Shared layers
are stored only once, so all three together take about 0.95 GB.

Work on these images is planned on this repo's issues and milestones. See
[`docs/roadmap.md`](docs/roadmap.md) for status, next action and decisions.

## Using an image in a repo

Open the repo with VS Code and its Dev Containers extension. Commit signing depends on its
GPG agent forwarding, and no other editor is supported.

1. Copy [`template/.devcontainer/`](template/.devcontainer/) into the repo unchanged.
2. In its `Dockerfile`, set `FROM` to one image, by tag **and** digest. Take both from the
   latest *Build images* run summary. Verify the image before its first use, and every new
   digest after it (see step 3):
   ```sh
   gh attestation verify oci://ghcr.io/603-identity/devcontainer-tofu@sha256:<digest> \
     --repo 603-Identity/devcontainers \
     --signer-workflow 603-Identity/devcontainers/.github/workflows/build.yml \
     --source-ref refs/heads/main --deny-self-hosted-runners
   ```
3. Add `.devcontainer` to the repo's `.github/dependabot.yml` under the `docker`
   ecosystem. Image bumps then arrive as reviewed PRs. Verify each bump's digest with the
   command above before merging it.
4. Delete the dependency-volume lines the repo doesn't use (`node_modules`, `.venv`).
5. Open the repo in the container, then store its GitHub credential once:
   `gh auth login --with-token` (see [Credentials](#credentials)).

### Toolchain versions must match CI

A container that validates with a different tool version than CI reports a result CI
doesn't share. The OpenTofu and Node versions here are the ones every consuming repo's
workflows pin, in every org. **Bump the image and every repo's workflow pin together**, never one
without the other.

### Consuming from another org

1. Every org pulls `ghcr.io/603-identity/devcontainer-*` and verifies it against this
   repo's `build.yml` on `main`, with the command in step 2 above. There is no per-org
   image or fork: this repo is the single publisher.
2. **The GHCR packages must stay public.** Package visibility is set per package, separately
   from the repo's visibility. A private package fails the next pull or rebuild of every
   container outside 603-Identity, and every Dependabot bump there. It changes
   availability, not security.
3. **Checkout folder names must be unique across every checkout on the host, in every
   org**, including forks, reference clones of third-party repos, and a second clone of the
   same repo. Each per-repo volume is named `<folder>-<suffix>`. Two checkouts with one
   folder name share every one they both mount, up to all five: `-gh` (the token, usable from both), `-claude` (sessions
   and, on Linux, Claude Code's own login and settings hooks), `-tmp`, `-node_modules` and
   `-venv` (each repo runs the other's dependency trees). **A collision merges two repos
   into one trust domain.** Rename the second folder. Docker volume names are
   case-sensitive and Windows folders are not, so `Foo` and `foo` get separate volumes.
   That fails safe, but it orphans a credential volume.
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
- The container runs as non-root, with no Linux capabilities and no way to gain privileges.

## Disk, speed and volumes

Code stays in the Windows checkout, bind-mounted at `/workspace`. Everything heavy or
growing lives in **named volumes**, except the rest of `~/.cache` (pre-commit, pip, uv and npm
caches), which stays in the container's own filesystem until #23 moves the home directory
onto a per-repo volume, and which a rebuild clears:

| Volume | Scope | Why |
|---|---|---|
| `<repo>-tmp` → `/tmp` | per repo | Session scratch and task output. Wipe it with `docker volume rm <repo>-tmp`. |
| `<repo>-node_modules`, `<repo>-venv` | per repo | Many small files are the slowest thing across the Windows bind mount. |
| `<repo>-claude` → `~/.claude` | per repo | Claude Code sessions and memory. Every repo mounts at `/workspace`, and Claude keys projects by path, so sharing this volume would mix repos' histories. |
| `<repo>-gh` → `~/.config/gh` | per repo | That repo's GitHub credential. |
| `devc-cache` → `~/.cache/shared` | shared, every repo on the host | tofu providers only, each verified against the consuming repo's `.terraform.lock.hcl` before use. The rest of `~/.cache` is per container. |

**Why this matters:** the previous single devcontainer grew to **331 GB**. Claude Code
sessions installed dependencies into `/tmp`, which sat in the container's own filesystem
where nothing ever cleaned it up, and several repos had been cloned into one container.
The volume layout above makes that growth visible (`docker system df -v`) and
disposable, for everything in a volume. The one-container-per-repo rule keeps each repo's credentials and data apart.
Only the tofu provider cache and the host's git identity files (see
[Git identity](#git-identity)) are shared by all containers.

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

## Updating a pinned tool

1. Read the upstream release notes and the diff since the current tag.
2. Take the new sha256 from **that release's published checksum file**. Never
   `sha256sum` a download and paste the result.
3. Change the `ARG`s in the Dockerfile. `tests/smoke.sh` reads the expected version from
   those same lines, so there is nothing else to edit. (The Python tools are not `ARG`s:
   they live in `images/base/tools/pyproject.toml` and `uv.lock`, and smoke reads their
   versions from the lock.)
4. For OpenTofu or Node, also open the matching CI-pin PRs in every consuming repo.
5. If the Trivy scan now passes without an entry in `.trivyignore.yaml`, delete that
   entry in the same PR.

The `# syntax=docker/dockerfile:...@sha256:...` line on line 1 of all four Dockerfiles is
pinned by digest but no bot bumps it (Dependabot's docker updater reads only `FROM`
lines). Move the four together, taking the digest from `docker buildx imagetools inspect
docker/dockerfile:<tag>`.

Dependabot handles the base image digest, the GitHub Actions pins, and the Python tool lock (`uv` ecosystem on `images/base/tools`). Dependabot
may propose a `bc-detect-secrets` bump in the grouped `uv` PR (#22 removed the old ignore
on purpose). Do not merge one until every 603 repo is ready to regenerate its
`.secrets.baseline` and bump its CI pin in the same change.
