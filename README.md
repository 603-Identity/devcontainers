# 603-Identity devcontainers

These are the shared devcontainer images for 603-Identity repositories. Every repo gets its
**own container**, built from **shared, digest-pinned images**. Isolation between repos
costs almost no disk, because the image layers are stored once per machine.

| Image | Contents | Used by |
|---|---|---|
| `ghcr.io/603-identity/devcontainer-base` | Ubuntu 24.04, non-root `app` (uid 1000), git, gh, jq, yq, Python 3.12, pre-commit, bc-detect-secrets 1.5.47 | tenant-posture-assessment, checkov-ledger-action |
| `ghcr.io/603-identity/devcontainer-tofu` | base + OpenTofu 1.11.14 + tflint | infrastructure-core, terraform-cloudflare-dns, terraform-microsoft365-entra |
| `ghcr.io/603-identity/devcontainer-node` | base + Node.js 24 + npm 11 | trust-anchors, jrg-consulting-site |

Local sizes measured on 2026-09-28: base 445 MB, tofu 664 MB, node 752 MB. Shared layers
are stored only once, so all three together take about 0.95 GB.

## Using an image in a repo

1. Copy [`template/.devcontainer/`](template/.devcontainer/) into the repo unchanged.
2. In its `Dockerfile`, set `FROM` to one image, by tag **and** digest. Take both from the
   latest *Build images* run summary. Verify the image before its first use:
   ```sh
   gh attestation verify oci://ghcr.io/603-identity/devcontainer-tofu@sha256:<digest> \
     --repo 603-Identity/devcontainers
   ```
3. Add `.devcontainer` to the repo's `.github/dependabot.yml` under the `docker`
   ecosystem. Image bumps then arrive as reviewed PRs.
4. Delete the dependency-volume lines the repo doesn't use (`node_modules`, `.venv`).
5. Open the repo in the container, then store its GitHub credential once:
   `gh auth login --with-token` (see [Credentials](#credentials)).

### Toolchain versions must match CI

A container that validates with a different tool version than CI reports a result CI
doesn't share. The OpenTofu and Node versions here are the ones every consuming repo's
workflows pin. **Bump the image and every repo's workflow pin together**, never one
without the other.

## Security model

**Everything is pinned and verified.** The base image is pinned by digest. Each binary is
pinned by version and sha256, and each sha256 comes from that release's own published
checksum file, never from a first download. Python tools install only from a hash lock
(`--require-hashes`). npm is checked against the registry's sha512 `integrity` value. The
CI linters also run from digest-pinned images.

**Nothing is published without these checks:**

| Check | Where | Fails the build when |
|---|---|---|
| Smoke test ([`tests/smoke.sh`](tests/smoke.sh)) | before push | a tool version differs from its Dockerfile pin; the user isn't uid 1000; any setuid/setgid binary exists; a volume mount point isn't app-owned |
| Trivy image scan | before push | there's a HIGH/CRITICAL vulnerability **with a fix available**, or a secret is baked into a layer |
| hadolint and Trivy config | lint | there's a Dockerfile anti-pattern |
| shellcheck | lint | a script has a shell bug |
| zizmor | lint | a workflow has a security problem (template injection, excessive permissions, unpinned action) |

**Exceptions expire.** The only way past the vulnerability gate is an entry in
[`.trivyignore.yaml`](.trivyignore.yaml). Each entry is scoped to one binary's path,
carries a written reason, and expires within 30 days. After the expiry date the weekly
rebuild fails until someone re-reviews the entry. Today the only entries cover Go
libraries compiled into the upstream `tofu` and `tflint` binaries, where no fixed
upstream release exists at the pinned version. The base and node images pass with **zero**
exceptions.

**Findings the gate doesn't block** (unfixed or allowlisted) are still uploaded to this
repo's *Security → Code scanning* page on every publish, so nothing is hidden.

**Every published digest carries two signed attestations** (Sigstore, stored on GitHub
and in the registry): build provenance, meaning which commit and workflow run produced it,
and a CycloneDX SBOM of what's inside it.

**Runtime hardening, from the template:** the container runs as non-root uid 1000 with
`--cap-drop=ALL` and `--security-opt=no-new-privileges`, and every setuid/setgid bit is
stripped from the image. GitHub's SSH host key is pinned system-wide.

**Rebuilds:** there's a weekly scheduled rebuild. apt packages aren't version-pinned
(Ubuntu's archive drops superseded versions), so this is how OS security fixes arrive.
Each rebuild publishes new digests under a new tag, and consuming repos pick them up
through Dependabot PRs. Nothing changes under a repo without a reviewed diff.

## Disk, speed and volumes

Code stays in the Windows checkout, bind-mounted at `/workspace`. Everything heavy or
growing lives in **named volumes**, never in the container's own filesystem:

| Volume | Scope | Why |
|---|---|---|
| `<repo>-tmp` → `/tmp` | per repo | Session scratch and task output. Wipe it with `docker volume rm <repo>-tmp`. |
| `<repo>-node_modules`, `<repo>-venv` | per repo | Many small files are the slowest thing across the Windows bind mount. |
| `<repo>-claude` → `~/.claude` | per repo | Claude Code sessions and memory. Every repo mounts at `/workspace`, and Claude keys projects by path, so sharing this volume would mix repos' histories. |
| `<repo>-gh` → `~/.config/gh` | per repo | That repo's GitHub credential. |
| `603identity-cache` → `~/.cache` | shared | tofu providers and npm tarballs, each verified against the consuming repo's lock file before use. |

**Why this matters:** the previous single devcontainer grew to **331 GB**. Claude Code
sessions installed dependencies into `/tmp`, which sat in the container's own filesystem
where nothing ever cleaned it up, and several repos had been cloned into one container.
The volume layout above makes that growth visible (`docker system df -v`) and
disposable. The one-container-per-repo rule keeps each repo's credentials and data apart.

**Getting disk space back on Windows:** Docker Desktop keeps everything in
`%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`. Deleting data frees space inside that
file, but Windows gets it back only when the file is compacted, or automatically if the
file is marked sparse (`fsutil sparse setflag`, run with Docker stopped). Check that it
still works after Docker Desktop updates.

## Credentials

Each container carries a **fine-grained personal access token**, tiered by what that repo
needs:

- **Satellite repos:** a token covering **only that repo**.
- **infrastructure-core (the hub):** a token covering infrastructure-core **and** the repos
  it coordinates. Its wider reach is deliberate, because coordinating is its job.
- **Admin work** (rulesets, repo settings, applying `tenants/*/github*`): **never** done
  with a container token. It happens from the host's org login, or in CI, when needed.

Tokens expire after 90 days at most. Record each one in infrastructure-core's credential
ledger.

## Updating a pinned tool

1. Read the upstream release notes and the diff since the current tag.
2. Take the new sha256 from **that release's published checksum file**. Never
   `sha256sum` a download and paste the result.
3. Change the `ARG`s in the Dockerfile. `tests/smoke.sh` reads the expected version from
   those same lines, so there is nothing else to edit.
4. For OpenTofu or Node, also open the matching CI-pin PRs in every consuming repo.
5. If the Trivy scan now passes without an entry in `.trivyignore.yaml`, delete that
   entry in the same PR.

Dependabot handles the base image digest, the GitHub Actions pins, and the Python tool
lock (except `bc-detect-secrets`, which is held at 1.5.47 org-wide on purpose).

## Known gaps

These are stated plainly so nobody trusts the setup for more than it does:

- **Node.js**: the tarball's sha256 is checked against `SHASUMS256.txt`, but that file's
  GPG signature isn't verified yet. Doing so means pinning the Node release team's
  keyring here.
- **apt packages** aren't version-pinned. The base digest and the weekly rebuild bound
  them instead.
- **`--cap-drop=ALL`** in the template hasn't yet been proven against every repo's
  workflow. The first pilot repos verify it, and this line is updated with the result.
- **The VS Code server and extensions** download into the container on each rebuild.
  That costs time, not safety.
