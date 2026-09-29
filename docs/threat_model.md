# Threat model

This is the security record of reference for 603-Identity/devcontainers: what the images
take in, what they produce, who holds which credential, which boundaries are meant to hold,
and the controls that hold them. README.md summarizes it and links here.

## What is being protected

Every 603-Identity repository opens its development container from one of these images, so
an image is trusted with:

- **the repo's source**, bind-mounted read-write at `/workspace`;
- **the repo's GitHub credential**, a fine-grained PAT in the per-repo `<repo>-gh` volume;
- **commit signing**, through the editor's forwarded GPG agent;
- **the toolchain that validates infrastructure** (OpenTofu, tflint, pre-commit,
  bc-detect-secrets). A tampered tool could report a clean result that CI would not.

A compromised image reaches every repo that adopts it, which is why the controls below sit
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

## Sinks

| Sink | Written by | Control |
|---|---|---|
| `ghcr.io/603-identity/devcontainer-*` | `build.yml`'s publish job, on push to `main`, the weekly schedule, or manual dispatch | The image is built, smoke-tested and scanned before any push. The job never runs on a pull request. |
| Attestations (build provenance, CycloneDX SBOM) | `actions/attest`, per pushed digest | Signed with Sigstore through the job's OIDC token, and stored on GitHub and in the registry. |
| Code scanning (SARIF) | the publish job | Carries the full findings, including unfixed and allowlisted ones, so nothing the gate lets through is hidden. |
| Commit statuses (`architect-review`) | `architect-review-gate.yml` | `statuses: write` only. It fails closed when it cannot look. |

## Credential holders

| Credential | Held by | Reach |
|---|---|---|
| `GITHUB_TOKEN` with `packages: write`, `id-token: write`, `attestations: write`, `artifact-metadata: write`, `security-events: write` | `build.yml`'s publish job only | Push to this org's GHCR packages, and sign attestations for this repo. Scoped per job; every workflow sets `permissions: {}` at the top. |
| `GITHUB_TOKEN` with `statuses: write` and reads | `architect-review-gate.yml` | Post commit statuses on this repo. |
| Per-repo fine-grained PAT | a consuming repo's container, in the `<repo>-gh` volume | That repo only. The hub's token also covers the repos it coordinates. It expires after 90 days at most and is recorded in infrastructure-core's credential ledger. Admin work (rulesets, repo settings) never uses a container token. |
| Owner's org login | the host, outside any container | Admin. It is the only identity that merges PRs or changes rulesets and package visibility. |

## Boundaries meant to hold

1. **Nothing reaches the registry untested.** No image is published unless all of these
   pass first:

   | Check | Where | Fails the build when |
   |---|---|---|
   | Smoke test ([`tests/smoke.sh`](../tests/smoke.sh)) | before push | a tool version differs from its Dockerfile pin; the user isn't uid 1000; any setuid/setgid binary exists; a volume mount point isn't app-owned |
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
   provenance (which commit and workflow run produced it) and an SBOM. Consuming repos pin
   an image by tag **and** digest, verify it with `gh attestation verify` before first use,
   and take new digests only through Dependabot PRs. Nothing changes under a repo without
   a reviewed diff.

4. **The container cannot raise its own privileges.** It runs as non-root uid 1000 with
   `--cap-drop=ALL` and `--security-opt=no-new-privileges`. Every setuid/setgid bit is
   stripped from the image, and the smoke test asserts that none remain. GitHub's SSH host
   key is pinned system-wide.

5. **Repos stay apart.** Each repo gets its own container and its own credential, Claude
   Code, and scratch volumes. Only the download cache is shared, and every entry in it is
   verified against the consuming repo's own lock file before use.

6. **Changes to `main` are reviewed.** The `main-required-checks` ruleset requires a pull
   request, the lint, build and smoke-test checks, and `architect-review` on any change to
   `code_paths`.

7. **OS security fixes arrive on a schedule.** apt packages aren't version-pinned, so a
   weekly scheduled rebuild picks them up. Each rebuild publishes new digests under a new
   tag.

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
- **The VS Code server and extensions** download into the container on each rebuild.
  That costs time, not safety.
- **The broad OAuth token** that containers used before this model can still be live
  until every repo has moved to the template (#6).
