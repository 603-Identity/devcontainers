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
  betterleaks, zizmor). A tampered tool could report a clean result that CI would not.

A compromised image reaches every repo that adopts it, in every consuming org, which is why the controls below sit
at build and publish time, before any consumer pulls.

## Untrusted inputs

| Input | Enters through | Control |
|---|---|---|
| Ubuntu base image | `FROM` in `images/base/Dockerfile` | Pinned by digest. Dependabot proposes new digests as reviewed PRs. |
| apt packages | `apt-get install` in the base image | **Not version-pinned** (see [Known gaps](#known-gaps)). Bounded by the base digest and the weekly rebuild. |
| Release binaries (gh, yq, uv, tofu, tflint, node, betterleaks) | `curl` in each Dockerfile | Pinned by version and sha256. Each sha256 comes from that release's own published checksum file, never from a first download. Neither the build nor the automated bump checks that file's signature or the binary's provenance. Only tofu 1.13.0's checksum file was checked, by hand (see Known gaps). The exception is betterleaks: `bump-binaries.sh` verifies its sigstore bundle before taking the checksum (see Org secret scanning). |
| uv-provisioned interpreters | `uv` at run time, when a repo's `.python-version` asks for an older Python | Not part of the image: uv downloads the interpreter from upstream on demand, into the per-repo home volume (`~/.local/share/uv`, kept across rebuilds, never the shared cache volume). uv checks it against a sha256 built into the pinned uv binary; the build's Trivy gate never scans it. Only a repo that cannot use the system 3.14 does this. |
| Python tools | `uv sync --locked` in the base image | Installed only from `images/base/tools/uv.lock`, which carries hashes; `--locked` fails on any drift from `pyproject.toml`. |
| npm, and the `brace-expansion` and `undici` copies replaced inside it | the node image | Each checked against the registry's sha512 `integrity` value, pinned as an `ARG`; the replaced versions are asserted after the swap. |
| Pull-request content | `pull_request` runs of `build.yml` and `lint.yml` | The PR job holds `contents: read` only, never a write token, and pushes nothing. |
| Issue, PR and review text | `architect-review-gate.yml`, on every trigger (`pull_request`, `issue_comment`, `pull_request_review`) | Read as data by a substring match. Event values reach the shell through `env`, never inline expressions. The repo is **public**, so anyone can post a comment, but no comment counts toward the gate: only a formal review on the head SHA whose author's numeric user ID is in the gate's `REVIEWER_IDS` allowlist does. A comment from an allowlisted author only re-runs the gate; any other author, or a missing ID, is ignored. |
| Linter and scanner images | `lint.yml` and `build-and-test.sh` | Pinned by digest, the same rule the images follow. |
| Upstream release metadata and checksum files (GitHub releases, nodejs.org, the npm registry) | `bump-binaries.sh`, run by `bump-binaries.yml`, holding the write token below while it parses this | The sha256 (or npm's registry `integrity`) is read from that release's own published file, never computed from a first download, then checked against a strict shape (a plain `X.Y.Z` version, or `X.Y.Z-rc.N` for betterleaks, which the resolver considers only while its pin is itself an rc (#208); 64 lowercase hex, or `sha512-...` for npm) before it is ever written to a file, a branch name or a commit message -- closing the path a crafted tag or checksum line would otherwise have into the Dockerfile rewrite. A resolved version older than the current pin is rejected rather than opened as a downgrade PR. The resulting PR still goes through every ordinary gate, including `architect-review`, before merge (see Known gaps for what that gate does and does not check). |
| Other repos' and orgs' code, through the shared cache volume | `devc-tofu-plugins` at `~/.cache/tofu-plugins` | Only the tofu provider cache lives there: the volume is mounted at that one directory, not over `~/.cache`, so a tool that hard-codes `~/.cache` writes into the per-repo home volume. `tofu` verifies each cached provider against the consuming repo's lock when a command starts, but runs it from the shared, writable path (see Known gaps). npm's cache is per repo, because `npx` runs packages from it without a check; pre-commit, pip, uv and every other XDG-aware cache are per repo too, in the home volume (`XDG_CACHE_HOME=~/.local/cache`). A modified `.devcontainer/` is outside this control (boundary 5). |
| Home-volume contents | `~/.vscode-server` and extensions, uv interpreters and cache, pre-commit and tflint plugins, `npm install -g` packages, dotfiles and `~/.local/bin`, all in `<repo>-home` | Installed at container create and first use, on the developer's machine, from their upstream sources, into a volume that outlives rebuilds. **Covered by no attestation, SBOM, Trivy scan or `.trivyignore.yaml` expiry, and never re-pinned by an image bump**: a rebuild does not refresh or remove them. What checks each one is the installer's own: uv checks an interpreter against a sha256 built into the pinned uv binary (the image sets no `UV_PYTHON_INSTALL_MIRROR`); a PyPI package a repo installs itself (checkov, say) is hash-checked only when the repo installs it from its own `--require-hashes` file; `npm install -g` checks the registry's `integrity` value for what it resolves, which nothing here pins. Wipe the volume to start clean. |
| Host identity directory | the host's `~/.gitconfig.d`, mounted read-only into **every** container | `git-identity.sh` copies an allowlist of five keys (`user.name`, `user.email`, `user.signingkey`, `commit.gpgsign`, `tag.gpgsign`) from the one file that claims the origin's org. It never includes or links the host file, so that file's credential, `gpg.*`, `url.*`, `core.*` and alias sections cannot reach the container's git config. |

## Sinks

| Sink | Written by | Control |
|---|---|---|
| `ghcr.io/603-identity/devcontainer-*` | `build.yml`'s publish job, on a push to `main` that changed an image-affecting path (`.github/scripts/image-scope.sh` decides), the weekly schedule, or manual dispatch on `main` | The image is built, smoke-tested and scanned before any push. The job never runs on a pull request. |
| Attestations (build provenance, CycloneDX SBOM) | `actions/attest`, per pushed digest | Signed with Sigstore through the job's OIDC token, and stored on GitHub and in the registry. |
| Code scanning (SARIF) | the publish job | Carries the full findings, including unfixed and allowlisted ones, so nothing the gate lets through is hidden. |
| Commit statuses (`architect-review`) | `architect-review-gate.yml`, here and in every consumer's copy | The gate is the rendered template (`tools/render-gate.sh --check-masked` fails when it drifts outside its `CONSUMER` regions), so its `post` job holds `statuses: write` plus `contents` and `pull-requests: write` here too, as in every consumer. The two extra scopes arm or disarm auto-merge, which is off (see below), and never fire here: with no candidate PR the job is always in plain mode, so arming is unreachable, and only its error row could disarm, which `resolve` succeeding rules out. A candidate needs a `.devcontainer/Dockerfile` and a Dependabot docker bump of it, and this repo has neither (held by convention, not by a check). Arming would also need the admin-only tag `devc-automerge-on` (ruleset `release-tags`), and the repo has `allow_auto_merge` off. The job runs on `issue_comment` events with `main`'s copy, and on `pull_request` and `pull_request_review` events with a same-repo PR's own copy (any writer can already add a workflow asking for these scopes, DEVC-D7). It has `run:` steps only and no checkout. `--check-masked` checks nothing inside the `CONSUMER` regions (their bodies are unconstrained code); `render-gate-test.sh` pins this repo's three regions to the expected shapes, and a human merge covers the rest. It fails closed when it cannot look. |
| Auto-merge armed on a consumer PR | a consumer gate's `post` job, only for a verified candidate while the tag `devc-automerge-on` exists in this repo | Not created, so never. The tag sits under a tag ruleset (admin-only). See [Consumer verification](#consumer-verification-and-the-bump-gate-30). |

## Credential holders

| Credential | Held by | Reach |
|---|---|---|
| `GITHUB_TOKEN` with `packages: write`, `id-token: write`, `attestations: write`, `artifact-metadata: write`, `security-events: write` | `build.yml`'s publish job only | Push to this org's GHCR packages, and sign attestations for this repo. Scoped per job; every workflow sets `permissions: {}` at the top. |
| `GITHUB_TOKEN` with `statuses`, `contents` and `pull-requests: write` for the gate's `post` job only, and reads | `architect-review-gate.yml` | Post commit statuses on this repo. The two other write scopes are unused here (see the commit-status row above). The job has no `uses:`, `container:` or `services:`. |
| A consuming repo's `GITHUB_TOKEN`: `contents: read` for `verify`; `statuses`, `contents` and `pull-requests: write` for the gate's `post` job only | the consumer's `devcontainer-image.yml` and gate, running this repo's reusable workflows | `verify` and `decide` hold no write token and read this repo's public attestations cross-org. `post` can post statuses and arm or disarm auto-merge on that consumer's own PRs, and holds the token in a job with no `uses:`, `container:` or `services:`, so no third-party action or image shares its GitHub-hosted runner (checked by `tools/check-consumer-workflows.sh` when it is run, not continuously). |
| GitHub App installation token, `contents: write` + `pull-requests: write`, scoped to this repo only | `bump-binaries.yml` | **Can do more than the job uses it for**: push or delete any non-`main` branch, create tags and releases, and comment on or merge a PR -- `contents: write` is also what `PUT /pulls/{n}/merge` requires (a PR's own author cannot approve it, but this ruleset needs no approval at all; see Known gaps). The job only pushes a `bump/<tool>-<version>` branch and opens its PR; the rest is this credential's reach if ever leaked or (see Known gaps) if the write step's own untrusted input were ever to reach it. Needed at all because a PR opened with the ambient `GITHUB_TOKEN` never triggers the required-check workflows (GitHub's own anti-recursion rule) -- and on this repo a job-scoped `GITHUB_TOKEN` could not even open the PR in the first place ("Allow GitHub Actions to create and approve pull requests" is off; `can_approve_pull_request_reviews: false`), so a dedicated identity is the only way to get this PR opened at all, let alone checked. Revoked at job end (the token action's default). The app's private key is a secret of the `bump-binaries` Environment, restricted to deployments from `main` (the job declares `environment: bump-binaries`), so a workflow run on any other branch cannot read it; it is held outside any container. The job runs only when the repo-level variable `BUMP_BINARIES_CLIENT_ID` (the App's Client ID) is set (#87). |
| Per-repo fine-grained PAT | a consuming repo's container, in the `<repo>-home` volume | That repo only. The hub's token also covers the repos it coordinates. It expires after 90 days at most and is recorded in the owning org's credential ledger (603-Identity: infrastructure-core's; glunk-works: none yet, see Known gaps). Admin work (rulesets, repo settings) never uses a container token. |
| Owner's org login | the host, outside any container | Admin. It is the only identity that merges PRs or changes rulesets and package visibility, which must stay public for consumers in other orgs. |

## Boundaries meant to hold

1. **Nothing reaches the registry untested.** No image is published unless all of these
   pass first:

   | Check | Where | Fails the build when |
   |---|---|---|
   | Smoke test ([`tests/smoke.sh`](../tests/smoke.sh)) | before push | a tool version differs from its pin (a Dockerfile `ARG`, or `images/base/tools/uv.lock` for the Python tools); the user isn't uid 1000; any setuid/setgid binary exists; a volume mount point isn't app-owned; any credential helper other than gh's runs; the projected identity holds a non-allowlisted key; a token from the origin URL appears in output; an identity is left in place after a failed selection (no origin, a non-github or lookalike origin, an ambiguous, unreadable or missing identity file); the system Python isn't the expected major.minor; the tools venv or a cache path isn't where the image documents it; a mount point (`/home/app`, `~/.cache/tofu-plugins`, `/workspace/.venv`, `/workspace/node_modules`) or `~/.cache` isn't app-owned; any cache variable points into the shared `~/.cache/tofu-plugins` except tofu's; the image ships a `~/.gitconfig`; `git-identity.sh` fails to rewrite a stale, symlinked or directory `~/.gitconfig`, or to remove a planted `~/.config/git/config`; `owner-check.sh` fails to write the lowercase owner marker, to warn on a different owner or leave that marker unchanged, to replace a symlinked, directory or junk marker without echoing its content or following a link; a token from the origin URL appears in its output; a `url.*.insteadOf` planted in the home volume's global git config changes the origin it reads, or one planted in `~/.gitconfig-identity` changes the origin `git-identity.sh` reads; or its origin grammar disagrees with `git-identity.sh`'s on a table of URLs |
   | Template proof ([`tests/template-proof.sh`](../tests/template-proof.sh)) | pull request | a container brought up from `template/.devcontainer/` with the pinned devcontainer CLI is not uid 1000, has a non-empty capability bounding set or `NoNewPrivs` 0, has no init as PID 1, has a writable root filesystem (a write to `/usr/local` succeeds instead of failing with `EROFS`), lacks any of the `<repo>-home`, `-tmp`, `-node_modules`, `-venv`, `devc-tofu-plugins` or read-only identity mounts, cannot write the home, `/tmp`, `.venv` or shared cache paths, has no `~/.gitconfig` or fixture identity after start, has no owner marker after start, prints the collision banner for a first checkout, prints no banner (or changes the marker) when a second checkout with the same folder name and another origin shares its `-home` volume, runs a credential helper other than gh's, has a `tofu` other than the image's pin, or skips `pre-commit install` |
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
   through Dependabot PRs. The verify command pins the exact signer workflow
   (`--cert-identity ...build.yml@refs/heads/main`), the OIDC issuer and `--source-ref
   refs/heads/main`, and it runs on every new digest, not only first use. **That consumer-side
   check is what enforces "built from reviewed `main`"**; the `if:` in `build.yml` is defense
   in depth, since anyone who can write a branch could dispatch an edited copy of the workflow.
   (`--signer-workflow` is a prefix match and not an exact pin, which is why the documented
   command no longer uses it.) The `verify / verify` check (#30) runs it on every consumer pull
   request, plus the provenance bindings (see
   [Consumer verification](#consumer-verification-and-the-bump-gate-30)). Nothing changes
   under a repo without a reviewed diff, bar the one gated exception listed there.

4. **The container cannot raise its own privileges, or change its own image.** It runs as
   non-root uid 1000 with `--cap-drop=ALL` and `--security-opt=no-new-privileges`. Every
   setuid/setgid bit is stripped from the image, and the smoke test asserts that none
   remain. **The root filesystem is read-only** (`--read-only` in the template's
   `runArgs`): code running as `app` cannot replace `/usr/local/bin/gh`, `git`, the
   tools venv or `/etc/gitconfig`, and a write to the image fails with `EROFS` (the
   template proof asserts that failure on `/usr/local`; see boundary 1). It
   can still write the mounts (the home volume, `/tmp`, the dependency volumes, the shared
   cache) and the tmpfs directories (`/var/tmp`, `/dev/shm`; `/run` is tmpfs too but root-owned), so this closes the image, not
   the volumes. In particular the home volume's `~/.local/bin` leads `PATH`, so a planted
   `gh` there, or a planted `git` or `tofu`, shadows the image's, and it now persists
   across rebuilds (see Known gaps). `GIT_CONFIG_GLOBAL` pins git's global file to `~/.gitconfig`,
   which `git-identity.sh` rewrites at every start, so a planted `~/.config/git/config` is
   ignored by git. pre-commit strips `GIT_*` variables from the git it runs, so that file
   would still apply there: `git-identity.sh` therefore also deletes it at every start,
   unless `~/.config` or `~/.config/git` is a symlink (see Known gaps). That bounds its
   persistence across restarts, not its use within one session. A
   script that wants git isolated from the home volume's config files sets
   `GIT_CONFIG_GLOBAL=/dev/null` (`/etc/gitconfig` still applies), not `HOME=<dir>`. A
   hostile `.devcontainer/` can simply drop the flag (boundary 5). The template's
   `init: true` gives the container a real PID 1. GitHub's SSH host key is pinned
   system-wide.

5. **Repos stay apart; identity files do not.** Repos stay apart under their own,
   unmodified template, and only while every checkout on the host has a unique folder
   name. Each repo gets its own container and up to four per-repo volumes: `-home`,
   `-tmp`, `-node_modules` and `-venv`. Only tofu's provider cache is shared (see Known gaps).
   A start-up check warns when two checkouts collide on a folder name (see Known gaps). A modified
   `.devcontainer/` (a PR branch opened in a container, say) can mount any volume on the
   host, and skip that check: Docker named volumes are not a boundary against a hostile config.
   The host's identity files are shared by design: every container mounts the whole
   `~/.gitconfig.d`, and identity is host-wide (see Known gaps).

6. **Changes to `main` are reviewed.** The `main-required-checks` ruleset requires a pull
   request, the lint, build and smoke-test checks, and `architect-review` on any change to
   `code_paths`. `architect-review` counts only a formal review, made against the PR's head SHA whose body also carries the line `Reviewed against head <that SHA>` (#278), from a
   user ID in the gate's `REVIEWER_IDS` allowlist (today, only the owner's user ID), so a stranger on
   this public repo cannot turn it green by pasting the header and attestation strings. It is still an existence gate: it never reads
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

## Consumer verification and the bump gate (#30)

A consuming repo's CI calls two reusable workflows from this repo, pinned by commit SHA:
`verify-devcontainer-image.yml` (the required check `verify / verify`, on every pull request)
and `devcontainer-bump-decision.yml` (`decide`, which fully verifies one candidate commit). Both
build the Go verifier in `tools/devc-verify` at the caller's pin before any pull-request content
is on disk, then read the consumer's files through the contents API at one exact SHA; there is
never a checkout of consumer content. Their write token is nil. The one place a status is
decided, and the one write token, is the consumer gate's `post` job
([`template/.github/workflows/architect-review-gate.yml`](../template/.github/workflows/architect-review-gate.yml)).
What each piece trusts, and what it leaves open:

- **Invariant 3, restated.** Nothing changes under a repo without a reviewed diff, *except* a
  verified, same-MAJOR, Dependabot-only `FROM` bump to `.devcontainer/Dockerfile`, **while the
  tag `devc-automerge-on` exists in this repo**. It does not exist, so today there is no
  exception.
- **The consumer bounds candidacy; `decide` is in the TCB for the verdict.** The consumer's own
  `resolve` job decides, from API facts that parse no PR content, which SHAs *can* be exempt:
  a single-file, Dependabot-authored, signature-verified Dockerfile bump. Within that set,
  `decide` is the only attestation check, so a lying `decide` release would widen the verdict
  (to unattested tags, say). Its pin therefore changes only through review: a pin bump edits
  `.github/`, `.github/` is always in review scope whatever the consumer's `case` block says,
  and a pin bump is never a candidate. `actions/checkout` and `actions/setup-go` inside the
  reusable workflows are in the TCB too, because they share the runner with the verifier;
  their bumps arrive as this repo's own reviewed Dependabot PRs.
- **Writers are trusted by construction.** A writer's own PR workflow can mint the
  `architect-review` status even when its ruleset pins the integration (F9b): this predates
  #30 and holds for every repo whose only review control is that status. "Writers" includes
  Dependabot's `github-actions` PRs, whose payload comes from upstream action maintainers.
  That is why `resolve` and `post` contain no `uses:`, `container:` or `services:`, and why no
  other consumer job may hold `statuses`, `contents`, `pull-requests`, `checks` or `actions:
  write` on a trigger Dependabot's own branch can run: a PR event, `create`, or a `push` whose filter is not `tags:` alone or a list of literal branch names; no `branches-ignore:` counts, since Dependabot's branch name is configurable (`pull-request-branch-name.separator`) (Dependabot's branch push runs its bumped workflow files;
  that a Dependabot push run can raise its token is assumed from the `pull_request` case, not
  observed). `tools/check-consumer-workflows.sh` checks both **when it is run**, at adoption
  and from the pilots; nothing re-runs it in the consuming repo's CI, so a later edit that
  breaks a rule is caught by review alone. The gate defends against Dependabot-shaped
  forgeries, outsiders and wrong images, and against forks only to the extent that auto-merge
  never acts on a fork PR. DEVC-D7 records this split: human writers are trusted, while the
  bump-binaries App is not and is bounded by its permissions plus the head-SHA binding (#92) plus the review-editor check (#94, see Known gaps). Before auto-merge goes on, the gate's result must come from a reviewer App's check run
  that a PR's own workflows cannot post (#267); a ruleset-required workflow was rejected
  because it needs GitHub Team.
- **Forks and same-named checks.** A fork PR from a returning contributor needs no approval to
  run. It can add a job named `architect-review`, or a `verify`/`verify` pair, whose check runs
  come from integration 15368 and so satisfy the pin: the fork PR can look fully green.
  Auto-merge never acts on it (only the candidate PR is armed), so the exposure is a human
  merging it. A fork can also block a bump by landing a *failing* same-named check at the
  Dependabot SHA (liveness only). This repo and the orgs' other public repos narrow the path:
  only collaborators can open a PR, and every outside contributor's run needs approval (set
  2026-10-05). A consumer that has not set both keeps the gap.
- **No soak.** A bad attested image can reach every opted-in consumer within minutes of
  Dependabot's run. The limits are the fail-closed kill switch, same-MAJOR only, the exact
  signer, issuer and repository-id pins, and attempt-1-only provenance.
- **Auto-merge is off and stays off until its preconditions are met.** The fail-closed kill
  switch makes "not created yet" the off state. When it is on, this repo's `main`, then the
  publish, then a consumer merge becomes an unattended chain whose only human control is this
  repo's own `architect-review`, an existence gate with known gaps (#93, and the skill half of #278). The owner
  creates `devc-automerge-on` only when #139's preconditions are met: among them a pilot that
  has taken real bumps through the review path, the reviewer App check (#267), and `disarm()`
  in every row (#126, #132). Docs-only pushes no longer publish: a push
  to `main` publishes only when it changed an image-affecting path (#124), so a docs-only
  merge ships no new tag set.
- **The kill-switch window.** Removing the tag stops later *arming*; `decide` still runs. It
  does **not** disarm open PRs: an armed PR merges whenever its remaining checks go green,
  possibly hours later. To close the window, post an allowlisted comment on each armed PR
  (that re-runs `post`, which disarms), or run `gh pr merge --disable-auto` on each.
- **The tag ruleset** (`release-tags`) restricts creating, updating, deleting and moving
  `refs/tags/v*` and `refs/tags/devc-automerge-*`, with the Repository admin role as its only
  bypass. On 603-Identity, org owners and any admin team also bypass it. It was read back
  through the API after creation. **The negative test is outstanding:** deleting a tag with the
  bump-binaries App token has not been tried (see Known gaps). Releases are signed `vX.Y` tags, each published as an immutable GitHub Release from
  `v1.3` on (DEVC-D8), with no release automation. Once a release is published, GitHub refuses
  to move or delete its tag, admins included, which closes the admin bypass above for that tag;
  `v1.0`-`v1.2` predate it and keep only the ruleset. The owner checks
  `git merge-base --is-ancestor <sha> origin/main` before pushing one, and every consumer pins
  the release's commit SHA, never the tag.
- **Liveness only.** Forks can block a bump with a failing same-named check; a fork's
  `pull_request` run can join the per-SHA concurrency group and cancel a pending `post` (the
  workflow name in the key narrows this); a `decide` error sends a bump to review; an image
  built by a re-run of `build.yml` (attempt 2) fails `verify / verify` as well as being
  non-exempt, because both run the attempt-1-only provenance check, so a consumer PR that
  pins one cannot merge (a hand-run `gh attestation verify` still passes it); repeated
  fork PRs can drain a repo's `GITHUB_TOKEN` API budget. A caller that fails to start reports
  no check at all, which fails closed (F8).
- **Parser residual.** Pure-Go parsers (BuildKit's Dockerfile parser, hujson) read pull-request
  bytes in a job with a read-only token, and at worst can flip the boolean. Our own packages
  import neither cgo nor `unsafe` (a test asserts it) and the build sets `CGO_ENABLED=0`;
  vendored and standard-library packages do use `unsafe`, so "no `unsafe` anywhere" is not
  claimed.
- **Private consumers.** A Dependabot-triggered `pull_request` run raising its token and
  arming auto-merge was observed on a public repo only. A private pilot has to confirm it
  before auto-merge is turned on; with the switch off, no pilot can show it.
- **Triggers the lint does not watch.** `workflow_run` and `merge_group` run files from the default
  branch or after approval. `deployment` and `deployment_status` run the file at the deployed commit,
  so a repo whose integrations create a deployment for every branch would let Dependabot's branch
  reach a write token that way; that is not checked.
- **Unchanged.** The image's MINOR is checked against the run number of the signed run, which is
  the one input read unauthenticated from the API; its MAJOR is not bound at all. The runner's
  `gh` and `setup-go`'s download are part of the TCB. No `on: push` run follows an auto-merge made with
  `GITHUB_TOKEN` (E12).

## Org secret scanning (#190)

`secret-scan.yml` is a reusable workflow, called by each repo as the job `secrets` (required
check `secrets / scan`). It runs Betterleaks over the full ancestry of the PR head. It is
separate from `verify-devcontainer-image.yml` on purpose: verify never checks out consumer
content, and this one must.

- **A new boundary: this repo's workflow checks out consumer content.** It does so as data
  only. The scanner, `images/base/files/secret-scan/org.toml`, `tools/secret-scan.sh` and the lint all come from
  this repo at the caller's pin (`job.workflow_sha`); nothing from the consumer is executed.
  The consumer is checked out at the PR's **base** commit and the head is fetched by SHA, so a PR
  cannot supply its own config, ignore file or `.gitattributes` (`-diff`) to hide a secret.
  The job has `contents: read`, no secrets and no `persist-credentials`. It runs on
  `pull_request` only; a branch or tag pin is refused, except this repo's own self-test caller
  at exactly `refs/pull/<n>/merge`.
- **A new untrusted input: the Betterleaks release.** The version and sha256 are the
  `BETTERLEAKS_*` ARGs in `images/base/Dockerfile`. The sha256 comes from the release's
  sigstore-signed `checksums.txt`. `bump-binaries.sh betterleaks` takes that checksum only after
  `cosign verify-blob` accepts the release's bundle for the exact tag's signer identity
  (`betterleaks/betterleaks` `release.yml` at `refs/tags/v<version>`, GitHub Actions OIDC), and
  fails closed otherwise. The cosign binary that does it is pinned by sha256 from its own
  release's checksum file, which is the same unsigned-checksum trust as the other binaries.
  The base image installs the same pinned release and ships the org rules from the same commit.
- **Fail closed.** v2 exits 1 for findings and for errors alike, so the wrapper requires the
  JSONL `scan` record to say `complete`. A missing or incomplete record is red (one retry on
  `incomplete`, never on findings). The env vars that change the config or contact credential
  providers are refused. Findings are always redacted and never uploaded.
- **Residual risks.**
  - Unlabeled high-entropy strings outside the entropy rule's file types and shape are not found.
  - Pre-commit hooks can be bypassed and web or host-side edits go unscanned until CI, so CI is
    the control.
  - A compromised commit here reaches consumers only through a human-merged SHA bump, which the
    new version itself scans; the impact is bounded by `contents: read` and no secrets.
  - A commit anywhere in the fork network can be named by SHA, so a consumer's pin could point at
    a commit that is not on `main`. When it is run, `check-consumer-workflows.sh` clones `main`
    and requires the verify, decide and secret-scan pins to be on its first-parent line, with the `# vX.Y` tag peeling to it
    (#234); an unreachable GitHub exits 3, never ok. Nothing re-runs the lint in a consumer's CI,
    so between runs this stays a residual that human review of each pin bump covers.
  - A PR that introduces its own false positive needs the ignore or rule change merged first,
    because the config is read from the base commit.

## Exceptions

Every repo in both orgs gets a container from these images unless one of these applies:

- **glunk-works/loop-orchestrator keeps its own container.** Its sandbox needs a Docker
  daemon (`--privileged`, docker-in-docker), which cannot coexist with `--cap-drop=ALL` and
  `no-new-privileges` (boundary 4). Docker-outside-of-docker was evaluated and **rejected**:
  a host Docker socket in the container would let anything running in it mount every other
  repo's `<repo>-home` volume, token included (a direct breach of boundary 5), and the
  sandbox resolves worktree paths inside the container that a host daemon cannot see. The
  rule for that container: it mounts no other repo's volumes.
- **603-Identity/devcontainers has no devcontainer.** Building and smoke-testing its images
  needs a Docker daemon, which in a container means docker-in-docker (`--privileged`, a
  breach of boundary 4) or the host socket (a breach of boundary 5): the same reasoning as
  the loop-orchestrator exception above. A devcontainer would cover only lint and the gate
  suites, and the repo would still need a host Linux shell for builds. That shell is the
  Ubuntu WSL2 distro (`tools/wsl-setup.sh`, README "Working on this repo from Windows"):
  host-side like PowerShell, so it adds no boundary to hold. It is not a sandbox either: with
  Docker Desktop's WSL integration on, the distro reaches the host Docker daemon exactly as
  PowerShell does, so code run there (a PR branch's test scripts, the npm-installed
  devcontainer CLI) can mount any repo's `-home` volume. Only run code from checkouts you trust there. Revisit if a
  second contributor or machine joins, or the WSL setup drifts from CI (a lint-and-test-only
  devcontainer would still exclude image builds).
- **No devcontainer** for org profile repos (`.github`), archived repos, or demo
  repositories.

## Known gaps

These are stated plainly so nobody trusts the setup for more than it does:

- **Checksum files are trusted without their signatures.** Each release binary's sha256
  comes from that release's own checksum file, which comes from the same release page as
  the binary, so whoever can replace one can replace the other. Every ARG-pinned upstream
  publishes a way to check this, and nothing here uses it routinely (the one exception is
  betterleaks, whose signed `checksums.txt` the bump verifies before taking the sha256):
  - OpenTofu signs `tofu_<version>_SHA256SUMS` with cosign (keyless, `.sig` and `.pem`)
    and with GPG (`.gpgsig`).
  - tflint signs `checksums.txt` with cosign (keyless, `.keyless.sig` and `.pem`).
  - yq signs `checksums` with cosign as a Sigstore bundle (`checksums.bundle`).
  - gh and uv do not sign their checksum files, but publish a GitHub artifact attestation
    (SLSA build provenance) for each binary, checked with `gh attestation verify`.
  - Node.js signs `SHASUMS256.txt` with GPG. Verifying it means pinning the Node release
    team's keyring here.

  The one exception is tofu 1.13.0's checksum file, verified by hand when it was pinned
  (#58). The verified signer identity is recorded beside `TOFU_SHA256` in
  `images/tofu/Dockerfile`. No build checks a signature, and `bump-binaries.sh` doesn't
  either (#29). An automated bump rewrites the pin and leaves the hand-written record
  untouched, so the record covers only the version it names. Nothing in a bump PR
  prompts the re-check: only README's bump checklist does, and the PR body does not
  link it. For the other pins, each
  mechanism above except Node's was confirmed to exist for the current pin on
  2026-10-02. That is not a verification of record: no signer identity is pinned for
  them.
- **`~/.local/bin` leads `PATH` by design**, and `app` can write it in the persistent home
  volume, where `uv tool install` and `npm install -g` put their entry points. Any bare
  tool name (`git`, `pre-commit`, `tofu`, `node`, ...) can be shadowed there, by accident
  or on purpose, and the shadow survives rebuilds. Only git's credential helper is pinned
  by absolute path (`/usr/local/bin/gh`, boundary 8). Hygiene, not a boundary against code
  running as `app` (#54).
- **A symlinked `~/.config` keeps a planted XDG git config.** `git-identity.sh` skips its
  delete of `~/.config/git/config` when `~/.config` or `~/.config/git` is a symlink, so a
  dotfiles tool's linked checkout is not touched. A process in the container can create
  that symlink itself, and the file then survives every restart and applies wherever
  `GIT_CONFIG_GLOBAL` is stripped, as it is under pre-commit. Low severity: `~/.local/bin`
  (above) is already a stronger persistence path (#69).
- **Home-volume contents are never scanned.** Interpreters, `npm install -g` packages,
  editor extensions and hook environments are installed at container create, outside the
  build, and persist across image bumps (see the input row above).
- **apt packages** aren't version-pinned. The base digest and the weekly rebuild bound
  them instead.
- **`--cap-drop=ALL` is proven in force, not against every repo's workflow.** The template
  proof ([`tests/template-proof.sh`](../tests/template-proof.sh), run in CI) asserts an
  empty capability bounding set, `NoNewPrivs` and uid 1000 in a container brought up from
  the template. Whether a given repo's own tooling runs without any capability is still
  unverified for each repo; the two pilots ran with it (#10), and each later adopter
  checks its own tooling ([docs/adopting.md](adopting.md), step 7).
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
- **Verifying a new digest is automatic only in a repo that has adopted #30's workflows.** A
  repo that has not copied `devcontainer-image.yml` and does not require `verify / verify`
  still takes whatever digest a Dependabot image bump proposes, including a branch-built
  one, unless a human runs the verify command. Only the two pilots have adopted them (#10).
- **The tag ruleset's App-token negative test has not been run.** Deleting a `v*` or
  `devc-automerge-*` tag with the `bump-binaries` App's token is the test; it can now be run, and
  nothing has run it yet. Org owners and any admin team bypass the
  ruleset by design.
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
  is still unchecked; the pilots ran the live checks (#10).
- **Folder-name uniqueness is detected at start, not prevented.** A collision between two
  checkouts' folder names merges two repos' trust domains (up to four per-repo volumes).
  `owner-check.sh` (DEVC-D6) runs first in the template's `postStartCommand`, keeps the
  `org/repo` of the first origin it saw in `~/.devc-owner` on the `-home` volume, and prints
  a banner when a later start's origin names another repo. It warns and never blocks. By
  then the second container already has the first repo's `-home` volume mounted, token
  included, so the fix stays the host rule: rename the folder and remove the shared
  volumes. It catches accidental collisions under the unmodified template only. A hostile
  `.devcontainer/` mounts any volume and skips any start-up step (boundary 5), and a repo
  renamed or transferred needs `rm ~/.devc-owner`. The marker is untrusted input: it is
  printed only when it matches the `org/repo` grammar.
- **glunk-works has no credential ledger yet**, so its tokens have no recorded home.
- **The broad OAuth token** that containers used before this model can still be live
  until every repo has moved to the template (#6).
- **The `main` ruleset's `pull_request` rule requires 0 approvals**, and
  `architect-review-gate.yml` counts a formal review only from a user ID in its
  `REVIEWER_IDS` allowlist (#14): today the owner's user ID alone. It is an ID list, not
  `author_association`, because the owner's 603-Identity membership is private and the
  workflow's token reads it as `CONTRIBUTOR` (seen live on #89); IDs rather than logins,
  because a released login can be re-registered. The bump-binaries App token (above)
  is not on the list, so a review it posts doesn't count. It can still merge a PR once the
  gate is green. Comments no longer count, so editing an owner comment into a qualifying one
  (#94) does nothing. A writer can edit someone else's formal review body (verified on #94),
  so a review with any editor not in `REVIEWER_IDS` does not count either (see below).
  Quoted lines (`> ...`) are ignored, so quote-replying someone else's pasted strings
  doesn't qualify. A second reviewer means a PR adding their ID, which that PR's own edited
  gate checks (see below), so the human's merge is the control on it. The owner's
  login staying "the only identity that merges PRs" is still a practice, not something
  this ruleset enforces.
- **A review is bound to the head SHA, not a date (#92 and #94 closed).** The gate used to
  date a review against the head commit's committer date, which whoever creates the commit
  controls, so a backdated commit passed against an older review. It now counts only a formal PR
  review (not dismissed) whose `commit_id` equals the head SHA and whose author is in
  `REVIEWER_IDS`; a comment never counts, whatever it says. A push moves the head SHA, so every
  earlier review stops counting until the reviewer posts a new one. Any writer can edit another
  user's formal review body (`PUT /pulls/{n}/reviews/{id}`; verified on #94 with a non-admin
  write account, which leaves author, state, `commit_id` and `submitted_at` unchanged), so a
  matching review also has to be unedited, or have only editors in `REVIEWER_IDS`. The gate
  reads the whole edit history from GraphQL (`userContentEdits`) for each otherwise-qualifying
  review; an unreadable editor, a history longer than one page, a deleted revision or a failed lookup fails closed. A matching review must also carry, as a line of its
  own in its quote-stripped body, the literal `Reviewed against head <HEAD_SHA>` (#278).
  `commit_id` is the head when the review is posted, not the commit the reviewer read, so a push
  during the review stamps it onto the new head; the line is the reviewer's own statement of the
  SHA they pinned, so a review that names an earlier head fails closed. The line may have
  surrounding whitespace, backticks around the SHA and one trailing period (the posting skill's
  own output); an abbreviated SHA, extra text or a `>`-quoted line does not match. A line inside
  a code fence or an HTML comment, or one that is a lazy continuation of a blockquote, still counts.
  It is a check on the reviewer's own text, not on GitHub: a writer's edit of the body is still
  caught only by the editor check above, and a reviewer (a model reading untrusted PR text) who
  writes the line without having read that head defeats it. Residuals, open: (1) the posting skill still does not pin
  `commit_id`, so the safeguard is the gate refusing, not the skill posting against the right
  commit (the way-of-working plugin's half of #278; posting with `POST
  repos/{repo}/pulls/N/reviews` and `commit_id=<pinned>` would make the review fail to post
  instead); (2) the gate re-runs when a review is edited or dismissed (`pull_request_review` types `edited` and
  `dismissed`; #315, #281), so a later edit by a stranger, or a dismissal, moves the status. An edit by a trusted reviewer
  still keeps it green while changing the text a human reads, and is not told apart from a typo fix. On a fork PR the
  `edited` and `dismissed` runs get the same read-only token as `submitted` (GitHub's rule for every
  `pull_request_review` activity type, not exercised live here), so they cannot post: there the status moves
  only on the reviewer's allowlisted re-run comment. A history with a deleted revision (a web-UI action; the public API cannot delete
  one, so this was not exercised live) fails closed, since the revision's text is hidden. The
  bump-binaries App's own ability to make the edit is the same call and was not tested; the fix does not depend on it. A human still reads the PR and merges. Consumers take the
  head-SHA binding (#92) in `v1.3` and the review-editor check (#94) in `v1.4`
  (DEVC-D7, DEVC-D8).
- **A same-repo PR runs its own copy of the gate.** `pull_request` and
  `pull_request_review` runs execute the PR's version of `architect-review-gate.yml`
  (only `issue_comment` uses `main`'s), so a branch that edits the gate, or its
  `REVIEWER_IDS`, is checked by the edited gate. Pushing a branch already takes write
  access, and the edit shows in the diff the human reads before merging (#93). Accepted under
  DEVC-D7: the gate does not defend against human writers. The reviewer App check (#267) closes
  it before auto-merge goes on.
- **`bump-binaries.yml` is skipped until `BUMP_BINARIES_CLIENT_ID` is set** (#87, #102): the job's
  `if:` on that variable skips it. The variable must stay a repo-level one, never an Environment
  one: a job-level `if:` cannot see Environment variables, so the job would skip forever. The App's
  private key is a secret of the `bump-binaries` Environment, restricted to deployments from
  `main`, and the job declares `environment: bump-binaries`; a plain repo secret would be readable
  by any workflow run on any branch a write-access user pushes. Once the variable is set, a manual dispatch from another
  branch gets past the `if:` and is then refused by the Environment's branch policy, so it fails
  rather than skips: that failure is the protection working. Install the App on this repo only (the
  installation's repository list is not visible to the workflow).
- **Every container can read every account's identity file**, for example the other
  org's email and signing-key ID, because the whole `~/.gitconfig.d` is mounted
  read-only. A secret written inline in one of those files (a token in a URL, an
  `http.extraHeader`) would be readable too, so the README forbids it.
- **Identity selection is not authorization.** Identity and the GPG agent are host-wide
  across both orgs: the editor forwards one agent to every container, so a glunk-works
  container whose `user.signingkey` were changed could sign with the 603-Identity key.
  Accepted: the agent is the signing boundary, and `git-identity.sh` only sets the key each
  org's identity file names. The host passphrase cache (README § Host signing policy, 8h if
  configured as recommended) widens the same boundary in time: once unlocked, any attached
  container signs without a prompt until the cache expires. The owner accepted the key
  exposure on purpose (#10): the forwarded agent offers the personal and the org keys alike.
- **`/workspace/.git` sits on the host bind mount** (pre-existing), so a container
  process can plant hooks, `core.hooksPath` or `core.fsmonitor` that the **host's** git
  then runs.
