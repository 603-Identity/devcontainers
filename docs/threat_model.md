# Threat model

This is the security record of reference for 603-Identity/devcontainers: what the images
take in, what they produce, who holds which credential, which boundaries are meant to hold,
and the controls that hold them. README.md summarizes it and links here.

## What is being protected

Every consuming repository, in 603-Identity and glunk-works, opens its development container
from one of these images, so an image is trusted with:

- **the repo's source**, bind-mounted read-write at `/workspace`;
- **the repo's GitHub credential**, a fine-grained PAT in the per-repo `<repo>-home` volume;
- **commit signing**, through VS Code's forwarded GPG agent;
- **the toolchain that validates infrastructure** (OpenTofu, tflint, pre-commit,
  bc-detect-secrets, zizmor). A tampered tool could report a clean result that CI would not.

A compromised image reaches every repo that adopts it, in every consuming org, which is why the controls below sit
at build and publish time, before any consumer pulls.

## Untrusted inputs

| Input | Enters through | Control |
|---|---|---|
| Ubuntu base image | `FROM` in `images/base/Dockerfile` | Pinned by digest. Dependabot proposes new digests as reviewed PRs. |
| apt packages | `apt-get install` in the base image | **Not version-pinned** (see [Known gaps](#known-gaps)). Bounded by the base digest and the weekly rebuild. |
| Release binaries (gh, yq, uv, tofu, tflint, node) | `curl` in each Dockerfile | Pinned by version and sha256. Each sha256 comes from that release's own published checksum file, never from a first download. |
| uv-provisioned interpreters | `uv` at run time, when a repo's `.python-version` asks for an older Python | Not part of the image: uv downloads the interpreter from upstream on demand, into the per-repo home volume (`~/.local/share/uv`, kept across rebuilds, never the shared cache volume). uv checks it against a sha256 built into the pinned uv binary; the build's Trivy gate never scans it. Only a repo that cannot use the system 3.14 does this. |
| Python tools | `uv sync --locked` in the base image | Installed only from `images/base/tools/uv.lock`, which carries hashes; `--locked` fails on any drift from `pyproject.toml`. |
| npm, and the `brace-expansion` and `undici` copies replaced inside it | the node image | Each checked against the registry's sha512 `integrity` value, pinned as an `ARG`; the replaced versions are asserted after the swap. |
| Pull-request content | `pull_request` runs of `build.yml` and `lint.yml` | The PR job holds `contents: read` only, never a write token, and pushes nothing. |
| Issue, PR and review text | `architect-review-gate.yml`'s `issue_comment` and `pull_request_review` triggers | Read as data by a substring match. Event values reach the shell through `env`, never inline expressions. The repo is **public**, so anyone can post a comment. |
| Linter and scanner images | `lint.yml` and `build-and-test.sh` | Pinned by digest, the same rule the images follow. |
| Other repos' and orgs' code, through the shared cache volume | `devc-cache` at `~/.cache` | Only the tofu provider cache lives there. `tofu` verifies each cached provider against the consuming repo's lock when a command starts, but runs it from the shared, writable path (see Known gaps). npm's cache is per repo, because `npx` runs packages from it without a check; pre-commit, pip, uv and every other XDG-aware cache are per repo too, in the home volume (`XDG_CACHE_HOME=~/.local/cache`). A modified `.devcontainer/` is outside this control (boundary 5). |
| Home-volume contents | `~/.vscode-server` and extensions, uv interpreters and cache, pre-commit and tflint plugins, `npm install -g` packages, dotfiles and `~/.local/bin`, all in `<repo>-home` | Installed at container create and first use, from their upstream sources, into a volume that outlives rebuilds. **Never scanned by the build's Trivy gate and never re-pinned by an image bump**: a rebuild does not refresh or remove them. Wipe the volume to start clean. |
| Host identity directory | the host's `~/.gitconfig.d`, mounted read-only into **every** container | `git-identity.sh` copies an allowlist of five keys (`user.name`, `user.email`, `user.signingkey`, `commit.gpgsign`, `tag.gpgsign`) from the one file that claims the origin's org. It never includes or links the host file, so that file's credential, `gpg.*`, `url.*`, `core.*` and alias sections cannot reach the container's git config. |

## Sinks

| Sink | Written by | Control |
|---|---|---|
| `ghcr.io/603-identity/devcontainer-*` | `build.yml`'s publish job, on push to `main`, the weekly schedule, or manual dispatch on `main` | The image is built, smoke-tested and scanned before any push. The job never runs on a pull request. |
| Attestations (build provenance, CycloneDX SBOM) | `actions/attest`, per pushed digest | Signed with Sigstore through the job's OIDC token, and stored on GitHub and in the registry. |
| Code scanning (SARIF) | the publish job | Carries the full findings, including unfixed and allowlisted ones, so nothing the gate lets through is hidden. |
| Commit statuses (`architect-review`) | `architect-review-gate.yml` | `statuses: write` only. It fails closed when it cannot look. |

## Credential holders

| Credential | Held by | Reach |
|---|---|---|
| `GITHUB_TOKEN` with `packages: write`, `id-token: write`, `attestations: write`, `artifact-metadata: write`, `security-events: write` | `build.yml`'s publish job only | Push to this org's GHCR packages, and sign attestations for this repo. Scoped per job; every workflow sets `permissions: {}` at the top. |
| `GITHUB_TOKEN` with `statuses: write` and reads | `architect-review-gate.yml` | Post commit statuses on this repo. |
| Per-repo fine-grained PAT | a consuming repo's container, in the `<repo>-home` volume | That repo only. The hub's token also covers the repos it coordinates. It expires after 90 days at most and is recorded in the owning org's credential ledger (603-Identity: infrastructure-core's; glunk-works: none yet, see Known gaps). Admin work (rulesets, repo settings) never uses a container token. |
| Owner's org login | the host, outside any container | Admin. It is the only identity that merges PRs or changes rulesets and package visibility, which must stay public for consumers in other orgs. |

## Boundaries meant to hold

1. **Nothing reaches the registry untested.** No image is published unless all of these
   pass first:

   | Check | Where | Fails the build when |
   |---|---|---|
   | Smoke test ([`tests/smoke.sh`](../tests/smoke.sh)) | before push | a tool version differs from its pin (a Dockerfile `ARG`, or `images/base/tools/uv.lock` for the Python tools); the user isn't uid 1000; any setuid/setgid binary exists; a volume mount point isn't app-owned; any credential helper other than gh's runs; the projected identity holds a non-allowlisted key; a token from the origin URL appears in output; an identity is left in place after a failed selection (no origin, a non-github or lookalike origin, an ambiguous, unreadable or missing identity file); the system Python isn't the expected major.minor; the tools venv or a cache path isn't where the image documents it; a mount point (`/home/app`, `~/.cache`, `/workspace/.venv`, `/workspace/node_modules`) isn't app-owned; any cache variable points into the shared `~/.cache` except tofu's; the image ships a `~/.gitconfig`; `git-identity.sh` fails to rewrite a stale or symlinked `~/.gitconfig` |
   | Trivy image scan | before push | there's a HIGH/CRITICAL vulnerability **with a fix available**, or a secret is baked into a layer |
   | hadolint and Trivy config | lint | there's a Dockerfile anti-pattern |
   | shellcheck | lint | a script has a shell bug |
   | zizmor | lint | a workflow has a security problem (template injection, excessive permissions, unpinned action) |

2. **Exceptions expire.** The only way past the vulnerability gate is an entry in
   [`.trivyignore.yaml`](../.trivyignore.yaml). Each entry is scoped to one binary's path,
   carries a written reason, and expires within 30 days. After that date the weekly
   rebuild fails until someone re-reviews the entry. That file is in `code_paths`, so any
   edit to it needs the architect review.

3. **Consumers can check what they run.** Every published digest carries signed build
   provenance (which commit and workflow run produced it) and an SBOM, and `build.yml` publishes only from `main`. Consuming repos pin an image by tag **and** digest and take new digests only
   through Dependabot PRs. The verify command pins the signer workflow and
   `refs/heads/main`, and it runs on every new digest, not only first use. **That consumer-side
   check is what enforces "built from reviewed `main`"**; the `if:` in `build.yml` is defense
   in depth, since anyone who can write a branch could dispatch an edited copy of the workflow.
   `--signer-workflow` is a prefix match, so it is not an exact pin; `--source-ref` carries
   the ref. The check is a manual step when a Dependabot bump is reviewed, until #30
   automates it in consumer CI (see Known gaps). Nothing changes under a repo without a reviewed diff.

4. **The container cannot raise its own privileges, or change its own image.** It runs as
   non-root uid 1000 with `--cap-drop=ALL` and `--security-opt=no-new-privileges`. Every
   setuid/setgid bit is stripped from the image, and the smoke test asserts that none
   remain. **The root filesystem is read-only** (`--read-only` in the template's
   `runArgs`): code running as `app` cannot replace `/usr/local/bin/gh`, `git`, the
   tools venv or `/etc/gitconfig`, and a write to the image fails with `EROFS`. It
   can still write the mounts (the home volume, `/tmp`, the dependency volumes, the shared
   cache) and the tmpfs directories (`/var/tmp`, `/dev/shm`; `/run` is tmpfs too but root-owned), so this closes the image, not
   the volumes. In particular the home volume's `~/.local/bin` leads `PATH`, so a planted
   `gh` there shadows the image's (boundary 8: hygiene, not a boundary), and it now
   persists across rebuilds. `GIT_CONFIG_GLOBAL` pins git's global file to `~/.gitconfig`,
   which `git-identity.sh` rewrites at every start, so a planted `~/.config/git/config` is
   ignored by git. pre-commit strips `GIT_*` variables from the git it runs, so that file
   would still apply there: `git-identity.sh` therefore also deletes it at every start,
   which bounds its persistence across restarts but not its use within one session. A
   script that wants git isolated from the container's config sets
   `GIT_CONFIG_GLOBAL=/dev/null`, not `HOME=<dir>`. A
   hostile `.devcontainer/` can simply drop the flag (boundary 5). The template's
   `init: true` gives the container a real PID 1. GitHub's SSH host key is pinned
   system-wide.

5. **Repos stay apart; identity files do not.** Repos stay apart under their own,
   unmodified template, and only while every checkout on the host has a unique folder
   name. Each repo gets its own container and up to four per-repo volumes: `-home`,
   `-tmp`, `-node_modules` and `-venv`. Only tofu's provider cache is shared (see Known gaps). A modified
   `.devcontainer/` (a PR branch opened in a container, say) can mount any volume on the
   host: Docker named volumes are not a boundary against a hostile config.
   The host's identity files are shared by design: every container mounts the whole
   `~/.gitconfig.d`, and identity is host-wide (see Known gaps).

6. **Changes to `main` are reviewed.** The `main-required-checks` ruleset requires a pull
   request, the lint, build and smoke-test checks, and `architect-review` on any change to
   `code_paths`.

7. **OS security fixes arrive on a schedule.** apt packages aren't version-pinned, so a
   weekly scheduled rebuild picks them up. Each rebuild publishes new digests under a new
   tag.

8. **Host identity files cannot reach the container's effective credential helper.** The
   identity file is generated from an allowlist of five keys, never included or linked, so
   a host `[credential]` section (whose helper is a host path such as `gh.exe`) cannot
   displace the image's `gh auth git-credential`. The helper is configured by absolute
   path (`/usr/local/bin/gh`), because `~/.local/bin`, which `app` can write, leads `PATH`
   and a bare `gh` could be shadowed there by accident. That is hygiene, not a boundary
   against code running as `app` (see the qualification below). The smoke test proves
   both by behaviour.
   This is narrower than "nothing can change the helper": code running in the container
   can still edit `~/.gitconfig`, and `/workspace/.git/config` is host-checkout config that
   the projection doesn't touch.

## Known gaps

These are stated plainly so nobody trusts the setup for more than it does:

- **Node.js**: the tarball's sha256 is checked against `SHASUMS256.txt`, but that file's
  GPG signature isn't verified yet. Doing so means pinning the Node release team's
  keyring here.
- **apt packages** aren't version-pinned. The base digest and the weekly rebuild bound
  them instead.
- **`--cap-drop=ALL`** in the template hasn't yet been proven against every repo's
  workflow. The first pilot repos verify it (#10), and this line is updated with the
  result.
- **Verifying a new digest is manual** until #30: a Dependabot image bump merged without
  running the verify command takes whatever digest it proposes, including a branch-built one.
- **The shared tofu provider cache is checked at command start, not at exec.** tofu links a
  cached provider into the repo's data directory and runs it from the shared volume, so a
  hostile process in another container could swap the binary between the check and the
  exec. It needs code already running in any container that mounts `devc-cache` (a hostile
  dependency in another repo or org, say). The `devc-cache` volume is the one cross-container
  channel left. `plugin_cache_may_break_dependency_lock_file` must stay unset: the smoke test asserts its
  environment-variable form, and no image ships a tofu CLI config file.
- **The shared cache volume is only as narrow as the variables that direct into it.** Only
  `TF_PLUGIN_CACHE_DIR` points at `~/.cache`; `XDG_CACHE_HOME` moves XDG-aware tools out, and
  the smoke test asserts the variables. A tool with a hard-coded `~/.cache` path that ignores
  `XDG_CACHE_HOME`, or a process started with a cleared environment, still lands in it, and
  where that cache holds executables (a downloaded browser) another org's container can
  swap one, which is execution, not only disclosure. The node image redirects Puppeteer's
  (`PUPPETEER_CACHE_DIR`); others are unknown. npm's
  cache is deliberately not shared (#23 first shared it; `npx` runs installed packages from
  `<cache>/_npx` with no integrity check, which would be cross-org code execution). Anything
  cached in the volume is readable from every container that mounts it, private tofu
  providers fetched with a registry credential included.
- **The read-only root is enforced by the template, not by the image.** A `.devcontainer/`
  that drops `--read-only` is a modified template (boundary 5). The template's proof that
  the mount is in force (`findmnt`, an `EROFS` write, PID 1) is the template CI issue
  (#24), not yet built; the live pilot check is open too.
- **Folder-name uniqueness is unenforced.** A collision between two checkouts' folder names
  merges two repos' trust domains (up to four per-repo volumes).
- **glunk-works has no credential ledger yet**, so its tokens have no recorded home.
- **The broad OAuth token** that containers used before this model can still be live
  until every repo has moved to the template (#6).
- **Every container can read every account's identity file**, for example the other
  org's email and signing-key ID, because the whole `~/.gitconfig.d` is mounted
  read-only. A secret written inline in one of those files (a token in a URL, an
  `http.extraHeader`) would be readable too, so the README forbids it.
- **Identity selection is not authorization.** The forwarded GPG agent is the signing
  boundary, and a container could name another key that the agent holds.
- **`/workspace/.git` sits on the host bind mount** (pre-existing), so a container
  process can plant hooks, `core.hooksPath` or `core.fsmonitor` that the **host's** git
  then runs.
