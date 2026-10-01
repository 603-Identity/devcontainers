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
| Issue, PR and review text | `architect-review-gate.yml`'s `issue_comment` and `pull_request_review` triggers | Read as data by a substring match. Event values reach the shell through `env`, never inline expressions. The repo is **public**, so anyone can post a comment, but only one whose `author_association` is `OWNER`, `MEMBER` or `COLLABORATOR` counts toward the gate; any other value, or a missing one, is ignored. |
| Linter and scanner images | `lint.yml` and `build-and-test.sh` | Pinned by digest, the same rule the images follow. |
| Upstream release metadata and checksum files (GitHub releases, nodejs.org, the npm registry) | `bump-binaries.sh`, run by `bump-binaries.yml`, holding the write token below while it parses this | The sha256 (or npm's registry `integrity`) is read from that release's own published file, never computed from a first download, then checked against a strict shape (a plain `X.Y.Z` version; 64 lowercase hex, or `sha512-...` for npm) before it is ever written to a file, a branch name or a commit message -- closing the path a crafted tag or checksum line would otherwise have into the Dockerfile rewrite. A resolved version older than the current pin is rejected rather than opened as a downgrade PR. The resulting PR still goes through every ordinary gate, including `architect-review`, before merge (see Known gaps for what that gate does and does not check). |
| Other repos' and orgs' code, through the shared cache volume | `devc-tofu-plugins` at `~/.cache/tofu-plugins` | Only the tofu provider cache lives there: the volume is mounted at that one directory, not over `~/.cache`, so a tool that hard-codes `~/.cache` writes into the per-repo home volume. `tofu` verifies each cached provider against the consuming repo's lock when a command starts, but runs it from the shared, writable path (see Known gaps). npm's cache is per repo, because `npx` runs packages from it without a check; pre-commit, pip, uv and every other XDG-aware cache are per repo too, in the home volume (`XDG_CACHE_HOME=~/.local/cache`). A modified `.devcontainer/` is outside this control (boundary 5). |
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
| GitHub App installation token, `contents: write` + `pull-requests: write`, scoped to this repo only | `bump-binaries.yml` | **Can do more than the job uses it for**: push or delete any non-`main` branch, create tags and releases, and comment on or merge a PR -- `contents: write` is also what `PUT /pulls/{n}/merge` requires (a PR's own author cannot approve it, but this ruleset needs no approval at all; see Known gaps). The job only pushes a `bump/<tool>-<version>` branch and opens its PR; the rest is this credential's reach if ever leaked or (see Known gaps) if the write step's own untrusted input were ever to reach it. Needed at all because a PR opened with the ambient `GITHUB_TOKEN` never triggers the required-check workflows (GitHub's own anti-recursion rule) -- and on this repo a job-scoped `GITHUB_TOKEN` could not even open the PR in the first place ("Allow GitHub Actions to create and approve pull requests" is off; `can_approve_pull_request_reviews: false`), so a dedicated identity is the only way to get this PR opened at all, let alone checked. Revoked at job end (the token action's default). The app's private key is meant to be a repo secret held outside any container -- **not yet provisioned**: `bump-binaries.yml` cannot run for real until a human creates the App and sets `BUMP_BINARIES_APP_ID`/`BUMP_BINARIES_APP_PRIVATE_KEY`. |
| Per-repo fine-grained PAT | a consuming repo's container, in the `<repo>-home` volume | That repo only. The hub's token also covers the repos it coordinates. It expires after 90 days at most and is recorded in the owning org's credential ledger (603-Identity: infrastructure-core's; glunk-works: none yet, see Known gaps). Admin work (rulesets, repo settings) never uses a container token. |
| Owner's org login | the host, outside any container | Admin. It is the only identity that merges PRs or changes rulesets and package visibility, which must stay public for consumers in other orgs. |

## Boundaries meant to hold

1. **Nothing reaches the registry untested.** No image is published unless all of these
   pass first:

   | Check | Where | Fails the build when |
   |---|---|---|
   | Smoke test ([`tests/smoke.sh`](../tests/smoke.sh)) | before push | a tool version differs from its pin (a Dockerfile `ARG`, or `images/base/tools/uv.lock` for the Python tools); the user isn't uid 1000; any setuid/setgid binary exists; a volume mount point isn't app-owned; any credential helper other than gh's runs; the projected identity holds a non-allowlisted key; a token from the origin URL appears in output; an identity is left in place after a failed selection (no origin, a non-github or lookalike origin, an ambiguous, unreadable or missing identity file); the system Python isn't the expected major.minor; the tools venv or a cache path isn't where the image documents it; a mount point (`/home/app`, `~/.cache/tofu-plugins`, `/workspace/.venv`, `/workspace/node_modules`) or `~/.cache` isn't app-owned; any cache variable points into the shared `~/.cache/tofu-plugins` except tofu's; the image ships a `~/.gitconfig`; `git-identity.sh` fails to rewrite a stale, symlinked or directory `~/.gitconfig`, or to remove a planted `~/.config/git/config` |
   | Template proof ([`tests/template-proof.sh`](../tests/template-proof.sh)) | pull request | a container brought up from `template/.devcontainer/` with the pinned devcontainer CLI is not uid 1000, has a non-empty capability bounding set or `NoNewPrivs` 0, has no init as PID 1, has a writable root filesystem (a write to `/usr/local` succeeds instead of failing with `EROFS`), lacks any of the `<repo>-home`, `-tmp`, `-node_modules`, `-venv`, `devc-tofu-plugins` or read-only identity mounts, cannot write the home, `/tmp`, `.venv` or shared cache paths, has no `~/.gitconfig` or fixture identity after start, runs a credential helper other than gh's, has a `tofu` other than the image's pin, or skips `pre-commit install` |
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
   script that wants git isolated from the home volume's config sets
   `GIT_CONFIG_GLOBAL=/dev/null` (`/etc/gitconfig` still applies), not `HOME=<dir>`. A
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
   `code_paths`. `architect-review` counts only a comment or review from an `OWNER`,
   `MEMBER` or `COLLABORATOR`, so a stranger on this public repo cannot turn it green by
   pasting the header and attestation strings. It is still an existence gate: it never reads
   what the review concluded, and the human's merge is the approval.

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
- **`--cap-drop=ALL` is proven in force, not against every repo's workflow.** The template
  proof ([`tests/template-proof.sh`](../tests/template-proof.sh), run in CI) asserts an
  empty capability bounding set, `NoNewPrivs` and uid 1000 in a container brought up from
  the template. Whether a given repo's own tooling runs without any capability is still
  unverified: the first pilot repos check it (#10), and this line is updated with the
  result.
- **The app user is uid 1000 on every host, so a Linux host with another uid loses
  write access to `/workspace`.** The template sets `updateRemoteUserUID: false`: the
  CLI's rewrite to the host uid would chown only `/home/app` and leave the dependency
  volumes unwritable. A Linux developer whose uid is not 1000 can read the bind mount but
  not write it from the container. macOS and Windows hosts are unaffected. The template
  proof asserts uid 1000 and writes to the home, `/tmp`, `.venv` and shared-cache volumes; its CI
  fixture is made world-writable, so it does not exercise this trade-off.
- **The devcontainer CLI in the template proof is pinned by version, not by hash.** npm
  checks the registry's integrity value for the tarball it resolves, but nothing here pins
  that value, so a tarball the registry served differently for the same version would run.
  In CI that is the build job, which holds no write permission and no secret, but it does reach the runner's Docker socket and the checkout. The same
  script is in `gates.green`, so it also runs on a developer's machine as that user, with
  access to the Docker daemon. The CLI itself has no dependencies and no install scripts.
- **Verifying a new digest is manual** until #30: a Dependabot image bump merged without
  running the verify command takes whatever digest it proposes, including a branch-built one.
- **The shared tofu provider cache is checked at command start, not at exec.** tofu links a
  cached provider into the repo's data directory and runs it from the shared volume, so a
  hostile process in another container could swap the binary between the check and the
  exec. It needs code already running in any container that mounts `devc-tofu-plugins` (a hostile
  dependency in another repo or org, say). The `devc-tofu-plugins` volume is the one cross-container
  channel left. `plugin_cache_may_break_dependency_lock_file` must stay unset: the smoke test asserts its
  environment-variable form, and no image ships a tofu CLI config file.
- **The shared cache volume is readable and writable from every container that mounts it.**
  It holds only the tofu provider cache and is mounted at `~/.cache/tofu-plugins` alone, so
  a tool that hard-codes `~/.cache` (Puppeteer, say) or ignores `XDG_CACHE_HOME` stays in
  the per-repo home volume; a cache variable pointed into the shared directory is the only
  way in, and the smoke test asserts the variables. npm's cache is deliberately not shared
  (#23 first shared it; `npx` runs installed packages from `<cache>/_npx` with no integrity
  check, which would be cross-org code execution). Private tofu providers fetched with a
  registry credential are readable from every container that mounts the volume.
- **The read-only root is enforced by the template, not by the image.** A `.devcontainer/`
  that drops `--read-only` is a modified template (boundary 5). The template proof
  ([`tests/template-proof.sh`](../tests/template-proof.sh), #24) shows the mount is in
  force in a container brought up from the template with the pinned devcontainer CLI
  (`findmnt`, an `EROFS` write, init as PID 1, and the CLI's own setup succeeding under
  `--read-only`). It runs against a fixture, so a repo's own edited copy of the template
  is still unchecked; the live pilot check is open too.
- **Folder-name uniqueness is unenforced.** A collision between two checkouts' folder names
  merges two repos' trust domains (up to four per-repo volumes).
- **glunk-works has no credential ledger yet**, so its tokens have no recorded home.
- **The broad OAuth token** that containers used before this model can still be live
  until every repo has moved to the template (#6).
- **The `main` ruleset's `pull_request` rule requires 0 approvals**, and
  `architect-review-gate.yml` counts a comment or review from any `OWNER`, `MEMBER` or
  `COLLABORATOR`, never *which* one. Outside commenters can no longer satisfy the gate
  (#14), though `MEMBER` is any 603-Identity org member and `COLLABORATOR` includes
  read-only collaborators, not only people with write access here. The owner's login
  staying "the only identity that merges PRs" is still a practice, not something
  this ruleset enforces. The bump-binaries App token (above) can
  itself comment on and merge a PR it opened; whether GitHub reports that bot's comment
  as a qualifying `author_association` is **not yet verified** -- check it live when the
  App exists, and if it does qualify, that token can still satisfy its own gate if misused
  or if its write step's input validation is bypassed. Closing that needs an
  allowlisted-login check in the gate, or `required_approving_review_count` of at least 1
  (which costs the solo maintainer a second reviewer or an owner-bypass rule to merge
  anything); left to a human to decide.
- **The gate dates a review against the head commit's committer date**, which whoever
  creates the commit controls, not when it was pushed. A commit dated before an earlier
  trusted review -- backdated on purpose, or just made locally before that review and
  pushed after it -- passes against that old review. On a same-repo branch the push's own
  run posts `success`; from a fork, whose `pull_request` run has a read-only token, any
  comment triggers the default-branch workflow, which does. Binding a review to the head
  SHA would close it, but only formal reviews carry a `commit_id`: comments would have to
  stop counting or have to quote the SHA. A human still reads the PR and merges.
- **`bump-binaries.yml` cannot run for real yet**: the App it needs has not been created,
  and `BUMP_BINARIES_APP_ID`/`BUMP_BINARIES_APP_PRIVATE_KEY` are not set on this repo.
  When it is, put the private key in a GitHub Environment restricted to deploy from
  `main` (the workflow job would then need an `environment:` key, which it has not
  been given) -- a plain repo secret is readable by any workflow run on any branch a
  write-access user pushes.
- **Every container can read every account's identity file**, for example the other
  org's email and signing-key ID, because the whole `~/.gitconfig.d` is mounted
  read-only. A secret written inline in one of those files (a token in a URL, an
  `http.extraHeader`) would be readable too, so the README forbids it.
- **Identity selection is not authorization.** The forwarded GPG agent is the signing
  boundary, and a container could name another key that the agent holds.
- **`/workspace/.git` sits on the host bind mount** (pre-existing), so a container
  process can plant hooks, `core.hooksPath` or `core.fsmonitor` that the **host's** git
  then runs.
