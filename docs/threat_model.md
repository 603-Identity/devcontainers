# Threat model

This is the security record of reference for 603-Identity/devcontainers: what the images
take in, what they produce, who holds which credential, which boundaries are meant to hold,
and the controls that hold them. README.md summarizes it and links here.

## What is being protected

Every consuming repository, in 603-Identity and glunk-works, opens its development container
from one of these images, so an image is trusted with:

- **the repo's source**, bind-mounted read-write at `/workspace`;
- **the repo's GitHub credential**, a fine-grained PAT in the per-repo `<repo>-gh` volume;
- **commit signing**, through VS Code's forwarded GPG agent;
- **the toolchain that validates infrastructure** (OpenTofu, tflint, pre-commit,
  bc-detect-secrets). A tampered tool could report a clean result that CI would not.

A compromised image reaches every repo that adopts it, in every consuming org, which is why the controls below sit
at build and publish time, before any consumer pulls.

## Untrusted inputs

| Input | Enters through | Control |
|---|---|---|
| Ubuntu base image | `FROM` in `images/base/Dockerfile` | Pinned by digest. Dependabot proposes new digests as reviewed PRs. |
| apt packages | `apt-get install` in the base image | **Not version-pinned** (see [Known gaps](#known-gaps)). Bounded by the base digest and the weekly rebuild. |
| Release binaries (gh, yq, tofu, tflint, node) | `curl` in each Dockerfile | Pinned by version and sha256. Each sha256 comes from that release's own published checksum file, never from a first download. |
| Python tools | `pip install` in the base image | Installed only from `tools.lock.txt` with `--require-hashes`. |
| npm | the node image | Checked against the registry's sha512 `integrity` value. |
| Pull-request content | `pull_request` runs of `build.yml` and `lint.yml` | The PR job holds `contents: read` only, never a write token, and pushes nothing. |
| Issue, PR and review text | `architect-review-gate.yml`'s `issue_comment` and `pull_request_review` triggers | Read as data by a substring match. Event values reach the shell through `env`, never inline expressions. The repo is **public**, so anyone can post a comment. |
| Linter and scanner images | `lint.yml` and `build-and-test.sh` | Pinned by digest, the same rule the images follow. |
| Other repos' and orgs' code, through the shared cache volume | `devc-cache` at `~/.cache/shared` | Only the tofu provider cache lives there. `tofu` verifies each cached provider against the consuming repo's lock when a command starts, but runs it from the shared, writable path (see Known gaps). npm's cache is per container, because `npx` and unlocked installs trust cached metadata. pre-commit, pip and uv caches are per container too. A modified `.devcontainer/` is outside this control (boundary 5). |
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
| Per-repo fine-grained PAT | a consuming repo's container, in the `<repo>-gh` volume | That repo only. The hub's token also covers the repos it coordinates. It expires after 90 days at most and is recorded in the owning org's credential ledger (603-Identity: infrastructure-core's; glunk-works: none yet, see Known gaps). Admin work (rulesets, repo settings) never uses a container token. |
| Owner's org login | the host, outside any container | Admin. It is the only identity that merges PRs or changes rulesets and package visibility, which must stay public for consumers in other orgs. |

## Boundaries meant to hold

1. **Nothing reaches the registry untested.** No image is published unless all of these
   pass first:

   | Check | Where | Fails the build when |
   |---|---|---|
   | Smoke test ([`tests/smoke.sh`](../tests/smoke.sh)) | before push | a tool version differs from its Dockerfile pin; the user isn't uid 1000; any setuid/setgid binary exists; a volume mount point isn't app-owned; any credential helper other than gh's runs; the projected identity holds a non-allowlisted key; a token from the origin URL appears in output; an identity is left in place after a failed selection (no origin, a non-github or lookalike origin, an ambiguous, unreadable or missing identity file); the system Python isn't the expected major.minor; the tools venv or a shared-cache path isn't where the image documents it |
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

4. **The container cannot raise its own privileges.** It runs as non-root uid 1000 with
   `--cap-drop=ALL` and `--security-opt=no-new-privileges`. Every setuid/setgid bit is
   stripped from the image, and the smoke test asserts that none remain. GitHub's SSH host
   key is pinned system-wide.

5. **Repos stay apart; identity files do not.** Repos stay apart under their own,
   unmodified template, and only while every checkout on the host has a unique folder
   name. Each repo gets its own container and up to five per-repo volumes: `-gh`, `-claude`,
   `-tmp`, `-node_modules` and `-venv`. Only lock-verified caches are shared. A modified
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
   displace the image's `gh auth git-credential`. The smoke test proves it by behaviour.
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
  dependency in another repo or org, say), and it is the one cross-container
  channel left. `plugin_cache_may_break_dependency_lock_file` must stay unset: the smoke test asserts its
  environment-variable form, and no image ships a tofu CLI config file.
- **Folder-name uniqueness is unenforced.** A collision between two checkouts' folder names
  merges two repos' trust domains (up to five per-repo volumes).
- **glunk-works has no credential ledger yet**, so its tokens have no recorded home.
- **The VS Code server and extensions** download into the container on each rebuild.
  That costs time, not safety.
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
