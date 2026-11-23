# Threat model

This is the security record of reference for 603-Identity/devcontainers: what the images
take in, what they produce, who holds which credential, which boundaries are meant to hold,
and the controls that hold them. README.md summarizes it and links here.

## What is being protected

Every consuming repository, in 603-Identity and glunk-works, opens its development container
from one of these images, so an image is trusted with:

- **the repo's source**, bind-mounted read-write at `/workspace`;
- **the repo's GitHub credential**, a fine-grained PAT in the per-repo `<repo>-home` volume;
- **commit signing**, through VS Code's forwarded GPG agent. (The dev-App flavour, below, has
  none: no key, no agent, no gpg.)
- **in the dev-App flavour, the repo's dev token** (`/run/wow/dev-token`, a GitHub App
  installation token the host's broker mints for that one repository and mounts read-only) and
  the verified `claude` binary. These replace the PAT and the signing agent for repos on that
  flavour (DEVC-D9, #418);
- **the toolchain that validates infrastructure** (OpenTofu, tflint, pre-commit,
  betterleaks, zizmor). A tampered tool could report a clean result that CI would not.

The dev-App flavour (`images/devapp`, published as `devcontainer-devapp` and
`devcontainer-devapp-tofu`) is a layer on base or tofu; everything below holds for it unless
a row says otherwise. A compromised image reaches every repo that adopts it, in every consuming org, which is why the controls below sit
at build and publish time, before any consumer pulls.

## Untrusted inputs

| Input | Enters through | Control |
|---|---|---|
| Ubuntu base image | `FROM` in `images/base/Dockerfile` | Pinned by digest. Dependabot proposes new digests as reviewed PRs. |
| apt packages | `apt-get install` in the base, node and dev-App images | **Not version-pinned** (see [Known gaps](#known-gaps)). Bounded by the base digest and the weekly rebuild. |
| Release binaries and the Python interpreter (gh, yq, uv, tofu, tflint, node, betterleaks, and the base image's CPython from python-build-standalone) | `curl` in each Dockerfile | Pinned by version and sha256. Each sha256 comes from that release's own published checksum file, never from a first download. Neither the build nor the automated bump checks that file's signature or the binary's provenance. Only tofu's checksum file was checked, by hand, for 1.13.0, 1.13.2 and 1.13.9 (see Known gaps). The exception is betterleaks: `bump-binaries.sh` verifies its sigstore bundle before taking the checksum (see Org secret scanning). The interpreter's sha256 comes from python-build-standalone's own `SHA256SUMS`. `bump-binaries.sh` re-pins it weekly within its pinned minor (#561); a change of minor is a hand re-pin (DEVC-D11). |
| uv-provisioned interpreters | `uv` at run time, when neither the image's pinned 3.15 nor Ubuntu's 3.14 satisfies a request (another minor, or an exact patch other than the pinned one) | Not part of the image: uv downloads the interpreter from upstream on demand, into the per-repo home volume (`~/.local/share/uv`, kept across rebuilds, never the shared cache volume). uv checks it against a sha256 built into the pinned uv binary; the build's Trivy gate never scans it. uv prefers an interpreter it already installed in the home volume to the image's, and an explicit `uv python install` puts a `python3.X` entry in `~/.local/bin`, which leads `PATH` and so shadows the image's, until it is uninstalled or the volume is wiped. |
| Python tools | `uv sync --locked` in the base image | Installed only from `images/base/tools/uv.lock`, which carries hashes; `--locked` fails on any drift from `pyproject.toml`. |
| The run, jobs, job-log and release API responses read by `tools/trivy-except.sh` | `gh api` in the exception lane's container, with the dev token (`docs/trivy-renewal.md`, "Adding an exception") | A `main` run's head commit must be reachable from `main`: checked against the main ref's commit (`origin/main` unless the test override `TRIVY_EXCEPT_MAIN_REF` names another; never fetched by the script), which the script prints for the code owner to confirm. Controls: that check, which relies on squash-only merges as the `GITHUB_TOKEN` row says (with merge commits a PR branch's unreviewed commits would be ancestors too); only a `main` run is admitted (a pull-request run is refused), the event and branch check being only a filter, since a run on a tag named `main` also reports `head_branch` `main`; the main ref is a local ref the caller can set (its override exists for tests), so the script prints its name and resolved commit; the git hygiene as defence in depth (the redirecting git variables unset, no replace objects, no commit-graph, no lazy fetch, no shallow, grafted or partial-clone root); the pin check at the head commit and against the latest upstream release; the field shapes (a library, version, run id, head commit and job id are cut to a fixed shape before they are used, and a response that is not JSON or lacks a checked field is refused); the table parse's refusal of a matched row whose Library cell (its own or the one it inherits) continues on a wrapped row, which would otherwise cut the name to its first fragment; and the write check (a copy is parsed and compared field for field before it replaces the file). These checks are self-attested by the lane, whose container runs the script and pastes its output; the controls of record are the code owner's check of the run on GitHub, which the section lists, and the `main-approval` approval. |
| npm | the node image | Checked against the registry's sha512 `integrity` value, pinned as an `ARG`. |
| Pull-request content | `pull_request` runs of `build.yml` and `lint.yml` | The PR job holds `contents: read` only, never a write token, and pushes nothing. |
| Issue, PR and review text | `review-gate.yml`, this repo's gate (the way-of-working plugin's), on `pull_request` (to `main`; its types include `edited`) and `pull_request_review` of type `submitted`, never on `issue_comment`; in every legacy-route consumer, the template's `architect-review-gate.yml` on every trigger | Read as data. Event values reach the shell through `env`, never inline expressions. The repo is **public**, so anyone can post a comment or a review, but no comment counts. `review-gate.yml` reads from review text only: it counts a review in state `COMMENTED` on the head SHA by the declared reviewer App's numeric id (`identities.reviewer_app.id`, read from the default branch's `.ai/project.yml`, in place of the template gate's `REVIEWER_IDS` allowlist) whose body's first and third lines equal the configured header and attestation, by exact line match; of the latest such review it reads the fifth line, and only exactly `Review verdict: pass` gives `success`. Besides review text it reads the changed-file names from the compare API, to match them against the trigger paths. The template gate (legacy route) matches review text by substring, counts a formal review on the head SHA from an allowlisted user ID, and re-runs on an allowlisted author's comment; any other author, or a missing ID, is ignored. |
| Anthropic's `claude` release, and the release signing key | `images/devapp/Dockerfile`, build time, in the `claude-fetch` stage (`images/devapp/files/claude-fetch.sh`) | The binary, its version and its sha256 are pinned (`CLAUDE_VERSION`, `CLAUDE_SHA256`), and before ANYTHING is pushed `gpgv` must report exactly one good signature on Anthropic's `manifest.json`, by the committed key (`images/devapp/files/claude-release.asc`, one primary key, fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE` as published in Anthropic's setup docs), with the status stream parsed and none of BADSIG, ERRSIG, EXPKEYSIG, REVKEYSIG or NO_PUBKEY; the manifest's version and linux-x64 checksum must equal the pins and the downloaded file's sha256. A download or signature failure stops `build-and-test.sh` before the first push. Stated limits: a committed key cannot learn that Anthropic revoked it; a session can always fetch its own binary (a copy in `~/.local/bin` leads `PATH`, which `devapp-check.sh` warns about but cannot prevent); and the organisation settings Anthropic's servers push to a logged-in `claude` are not verified here. |
| Claude Code marketplace and plugins named by the repo's `.claude/settings.json` | `plugin-install.sh`, at the end of every start of a dev-App container (`images/devapp/files/plugin-install.sh`, DEVC-D10) | **Trust root:** the tree checked out at container start, not reviewed `main`; trust is granted at start, with no folder-trust prompt. **Persistence:** the install lives in `<repo>-home` and outlives branch switches and rebuilds. A plugin enabled on a branch stays installed after the switch back to `main`, and is reported (a warning banner), never removed; remove it with `claude plugin uninstall <P@M> --scope user` and `claude plugin marketplace remove <M> --scope user`, or wipe `<repo>-home`. A branch that declares a familiar marketplace name with another `repo` makes the next start re-point it (the success line prints `repo#ref`; the extras warning, which also prints `repo#ref`, covers only marketplaces this tree does not pin); the check compares ids and scope, not installed content, so after reviewing such a branch wipe `<repo>-home`. **The ref** pins only the marketplace catalogue, and it is a tag (mutable upstream) unless the repo pins a SHA; a plugin entry in `marketplace.json` can point at another repo or ref. **What runs:** installing runs no plugin code, and marketplace-declared install commands are refused (the script never passes `-y`, `--yes` or `--accept-command`, and has no TTY), but the installed plugin's hooks and MCP servers run in every later session. **Fetches** go over HTTPS through system git with no global git config (`GIT_CONFIG_GLOBAL=/dev/null`); `dev-token` offers the per-repo token only on an auth challenge from github.com, and that token reads only this repo. **Isolation:** no `claude` call runs in the workspace or from a `PATH` the home volume controls; the script fixes `PATH` and `TMPDIR`, unsets `CLAUDE_CONFIG_DIR`, removes `GIT_CONFIG`, `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`, `GIT_CONFIG_SYSTEM`, `GIT_CONFIG_NOSYSTEM`, `GIT_DIR`, `GIT_WORK_TREE`, `GIT_EXEC_PATH`, `GIT_ASKPASS`, `GIT_SSH_COMMAND`, `LD_PRELOAD`, `LD_LIBRARY_PATH`, `LD_AUDIT`, `BASH_ENV` and `ENV` from the calls' environment (other variables still pass: the proxy ones, `NODE_OPTIONS`, `NODE_PATH`, `GIT_SSL_*` and `SSL_CERT_FILE`), sets a git ceiling at `TMPDIR` and refuses to run when `TMPDIR` holds a `.git` or `.claude`, so neither a Dockerfile extra nor the repo can move the scratch space or `CLAUDE_CONFIG_DIR`. `HOME` and the rest of the environment the start was launched with are not fixed (the verifier's env filter catches accidents, not attacks), so the user scope follows `HOME`. The user-scope `~/.claude/settings.json` in the home volume still reaches these calls, as it reaches any session. The tracked file is checked (not a symlink, a regular file, at most 64 KiB) and hashed before and after, never written. |
| A checkout's own `CLAUDE.md` (root and nested), `.claude/` settings and hooks, and root `.mcp.json` | every `claude` session started in that checkout (a lane, the critic subagents it spawns, a driver session on a branch). It loads at session start, or, for a nested `CLAUDE.md`, when the session reads files in that directory (#607) | **None before review.** The session loads the branch's copy as instructions, and runs its hooks, before the review gate has read it. `code_paths` gates the merge to `main`, not this loading. A host session loads no PR branch's project-level files: it starts in a new, empty directory, its anonymous clone stays at `origin/main`, and among the project-level files a folder supplies, a `CLAUDE.md` from that clone is the one that may be in force there (`docs/host-steps.md`, the start text and Rule 1). A host session's user scope (the owner's user-level Claude folder and config file, the claude.ai account's connectors, managed settings, launch options and environment) is outside those stops (the user-scope *Known gaps* bullet below). No container this repo defines mounts the host's user-level Claude folder or config file; each container keeps its own `~/.claude` in its `-home` volume. Container code can still reach the host's through the host-execution gaps *Known gaps* records (a planted `initializeCommand` or an added host bind in the local `.devcontainer/`, git hooks or `core.fsmonitor`, a VS Code task, a host run of a branch's code) and through the paths *Exceptions* names (an ad hoc host run of a branch's scripts, and a privileged container, one with the Docker socket, or one with a bind of `%USERPROFILE%`). |
| The token directory `/run/wow` | the host's broker, mounted read-only into a dev-App container | `dev-token` reads the one file `/run/wow/dev-token` (two lines, LF, at most 2048 bytes, an installation token -- `ghs_` then 36 or more of `[A-Za-z0-9._-]`, the classic and the stateless format (#492) -- then UTC `expires_at`, replaced by atomic rename; refused from 60 s before `expires_at`, so the broker must replace it earlier), refuses a symlink, a malformed or oversized file, a wrong kind of token and an expired one, and answers `quit=1` to every host and protocol except https github.com. Nothing else in the directory is read. An older `wow-admin` wrote the elevated token there as `admin-token`; it now writes it outside every container (Known gaps, "The elevated token used to share the mount"), and the flavour never opens it either way. A missing or empty directory fails closed. |
| The release dispatch inputs `bump` and `dry_run` | `workflow_dispatch` of `release.yml` | `bump` is an enum (`minor` or `major`) and `dry_run` a boolean. `release-plan.sh` validates both again, as exactly `minor` or `major` and exactly `true` or `false`, with bash `[[ =~ ]]` or `case`. Neither reaches a shell except through a step `env:` entry, and no `if:` compares an input with a quoted string. There is no input for a tag name. |
| The dispatcher | any account with write access | A dispatch alone creates nothing: the `release` job waits for the `release` environment's required reviewer, dry runs included. That approval is the only control on who can release. |
| Commit subjects (PR titles) and `docs/releases/vX.Y.md` | `release-plan.sh notes`, into a public Release body | Generated notes are the first-parent commit subjects, verbatim. `docs/releases/` is outside `code_paths`, so a curated file is gated only by review and the approval. It is read from the commit as a regular file (mode `100644`), never through the working tree, so a symlink is refused. The approver reads the exact bytes in `verify`'s step summary, inside a code fence longer than any backtick run in them, so no note text can imitate the plan lines. The notes are never echoed to the job log, so a workflow-command line in them is not acted on. |
| API responses | `release-verify.sh`, through `gh api` (the producing PR, the check runs, the commit statuses and `main`'s push runs) | Parsed with `jq` into tab-separated rows and compared as strings; the SHA and `REPO` are validated first, and a check name is bound as a value, never spliced into an expression. An API error, an unexpected shape or a missing field is a refusal, never a pass. |
| Linter and scanner images | `lint.yml`, `build-and-test.sh`, `.github/scripts/trivy-evidence.sh` and `.github/scripts/trivy-daily.sh` | Pinned by digest, the same rule the images follow. |
| GHCR tag list, `Link` header and manifest responses | `trivy-daily.sh resolve`, run by `trivy-daily.yml` and by `build-and-test.sh`'s `local` mode, anonymously (the five packages are public) | Parsed with `jq` and compared as strings. The newest tag must match `^[0-9]+\.[0-9]+$` and the digest `^sha256:[0-9a-f]{64}$`. A `Link` next-page value is followed only when it matches the fixed `/v2/603-identity/devcontainer-.../tags/list?...` path pattern and is then prefixed with `https://ghcr.io`, so the pull token never goes to another host; anything else fails the run. `scan` re-checks every reference against the full reference pattern before any `docker` call. `build-and-test.sh`'s `local` mode also calls `resolve`, on a pull request, and re-checks every line of the reference file (five lines, one per flavour, each reference matching the full reference pattern with the flavour of its line) before any `docker` call, falling back to the full gate otherwise. |
| Trivy JSON of a pull request's images and of the published images | `trivy-diff.sh`, run by `build-and-test.sh local` on a pull request | Checked for shape first (an object whose results, vulnerabilities and secrets are null, absent or arrays of objects with the required string fields); anything else exits 2 and fails the flavour. Keys (id, package, location) are compared on the raw strings, byte for byte; only printed fields are cut to 256 characters and have every character outside the keep set replaced by `?`, so none holds a newline, a carriage return or a percent sign. Every output line starts with fixed text, no field goes into the properties part of a workflow command, and a secret line carries the rule id and target only. The base commit comes from the event payload and must be 40 lowercase hex before it reaches `git`. |
| Trivy's output for the published images | `trivy-daily.sh parse`, then `file` | Checked the way `trivy-evidence.sh` checks its own (record type, field count, no empty field, a length cap, no structure character, every other character outside the keep set written as `?`), plus a vulnerability-id shape check (`^[A-Z][A-Z0-9]{1,9}(-[A-Za-z0-9]{1,24}){1,4}$`, at most 64 characters) before any substitution. A record failing any check fails the run, so nothing is filed from a scan that did not parse whole. `file` re-validates every line before its first `gh` call, in the step that holds the token. A secret record's path never leaves `parse`: only its rule id reaches the step summary, and the run fails. The script writes no scan-derived or API-derived value to stdout, stderr, `GITHUB_ENV`, `GITHUB_PATH` or `GITHUB_OUTPUT`, and sends every child process's output to a file, so none can form a workflow command. |
| The upstream latest-release tag of gh, yq, uv, tofu, tflint (and betterleaks, once its pin leaves the release-candidate line) | `trivy-daily.sh file`, through `gh api repos/<owner>/<repo>/releases/latest` | Accepted only when it matches `^v?[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$` and is at most 64 characters, and only compared with the pin and written inside a code span. A failed lookup or a tag outside the pattern reads `unknown` and does not fail the run. |
| Issue and comment text of this repo | `trivy-daily.sh file`, which reads the open issues, one matching issue's body and its comments to decide whether to open, comment or do nothing | Only text whose author login is `github-actions[bot]` with user type `Bot` is read for matching, on an issue whose title is exactly `Trivy daily scan: ID in the published images`; text by any other author is never matched, and no text read from any issue or comment is copied into anything the workflow writes. A bot text matches only when it has the fixed line shape and a findings block byte-identical to the current one. **Residual:** every workflow in this repo, a branch's own included, writes as `github-actions[bot]`, and an account with Issues write can edit a bot-authored body or comment without changing its author. Such an edit suppresses a comment only when the edited text still has the fixed line shape and a findings block byte-identical to the current one; the lines outside the block (an image reference, the run line) can be changed to other well-formed values without a re-post, and the de-duplication cannot stop that. |
| Upstream release metadata and checksum files (GitHub releases, nodejs.org, the npm registry) | `bump-binaries.sh`, run by `bump-binaries.yml`, holding the write token below while it parses this | The sha256 (or npm's registry `integrity`) is read from that release's own published file, never computed from a first download, then checked against a strict shape (a plain `X.Y.Z` version, or `X.Y.Z-rc.N` for betterleaks, which the resolver considers only while its pin is itself an rc (#208); 64 lowercase hex, or `sha512-...` for npm) before it is ever written to a file, a branch name or a commit message -- closing the path a crafted tag or checksum line would otherwise have into the Dockerfile rewrite. A resolved version older than the current pin is rejected rather than opened as a downgrade PR. For python (#561) the build tag is a further upstream value: it must be exactly eight digits at listing time, before it reaches any URL, and again before any write; the resolved version's major.minor must equal the pin's; the release is chosen by its exact asset name (`cpython-X.Y.N+TAG-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz`) among the non-draft, non-prerelease releases of the five most recent the API lists (one `per_page=5` call, so possibly fewer than five candidates), highest tag first; and a build tag lower than the pinned one is refused like an older version. A candidate whose `SHA256SUMS` cannot be read is skipped with a warning that names no upstream tag, and once one has been skipped no candidate at or below the pin is fetched, so a run with no readable release above the pin fails with a count rather than taking the pin's own release or an older one. The upstream build tag and version also decide which older python bump PRs the write token closes (see the next row and the credentials table): a crafted or out-of-order upstream tag can close a pending python PR, an approved one included, and a bogus high build left open makes every later real build read as not older until a human closes it; the bounds are the author, same-repo and head-shape filter in the next row, the kept branch (a closed PR can be reopened) and the human review every bump PR goes through. The resulting PR still goes through every ordinary gate, including `architect-review`, before merge (see Known gaps for what that gate does and does not check). |
| This repo's open pull requests (number, head branch, author, cross-repo flag), as the python leg's supersede listing reads them | `bump-binaries.sh` (python only), holding the write token while it parses them | One `gh pr list --state open --limit 500` call. The run fails unless the listing has fewer records than its 500-record limit, and only records authored by this repo's bump App (`app/<APP_SLUG>`, a bot), from this repo (not a fork), with a head that is exactly `bump/python-<pinned minor>.<digits>-<eight digits>` (the minor compared as a literal string) and a plain positive PR number are used; nothing else from that listing is used or printed. A used record is closed, with a comment naming the new branch, only when its build is lower than the new one and its version not higher, and only after the new PR is created; any used record that is not older stops the run before a branch is cut. The script's existing open-PR check, which every tool runs, and its leftover-branch check, which runs only when the bump branch already exists on origin, count PRs by head branch name alone, with no author or same-repo filter. |
| Other repos' and orgs' code, through the shared cache volume (legacy template only; the dev-App template mounts none) | `devc-tofu-plugins` at `~/.cache/tofu-plugins` | Only the tofu provider cache lives there: the volume is mounted at that one directory, not over `~/.cache`, so a tool that hard-codes `~/.cache` writes into the per-repo home volume. `tofu` verifies each cached provider against the consuming repo's lock when a command starts, but runs it from the shared, writable path (see Known gaps). npm's cache is per repo, because `npx` runs packages from it without a check; pre-commit, pip, uv and every other XDG-aware cache are per repo too, in the home volume (`XDG_CACHE_HOME=~/.local/cache`). A modified `.devcontainer/` is outside this control (boundary 5). |
| Home-volume contents | `~/.vscode-server` and extensions, uv interpreters and cache, pre-commit and tflint plugins, `npm install -g` packages, `~/.claude/plugins` (marketplace clones and installed plugins), dotfiles and `~/.local/bin`, all in `<repo>-home` | Installed at container create, at every start, and on first use, on the developer's machine, from their upstream sources, into a volume that outlives rebuilds. **Covered by no attestation, SBOM, Trivy scan or `.trivyignore.yaml` expiry, and never re-pinned by an image bump**: a rebuild does not refresh or remove them. What checks each one is the installer's own: uv checks an interpreter against a sha256 built into the pinned uv binary (the image sets no `UV_PYTHON_INSTALL_MIRROR`); a PyPI package a repo installs itself (checkov, say) is hash-checked only when the repo installs it from its own `--require-hashes` file; `npm install -g` checks the registry's `integrity` value for what it resolves, which nothing here pins. Wipe the volume to start clean. |
| Host identity directory | the host's `~/.gitconfig.d`, mounted read-only into **every** container | `git-identity.sh` copies an allowlist of five keys (`user.name`, `user.email`, `user.signingkey`, `commit.gpgsign`, `tag.gpgsign`) from the one file that claims the origin's org. It never includes or links the host file, so that file's credential, `gpg.*`, `url.*`, `core.*` and alias sections cannot reach the container's git config. |

## Sinks

| Sink | Written by | Control |
|---|---|---|
| `ghcr.io/603-identity/devcontainer-*` | `build.yml`'s publish job, on a push to `main` that changed an image-affecting path since the last successful publish (`.github/scripts/last-publish-sha.sh` finds that commit, `.github/scripts/image-scope.sh` diffs against it; a failed or empty lookup builds), the weekly schedule, or manual dispatch on `main` | The image is built, smoke-tested and scanned before any push. The job never runs on a pull request. |
| Attestations (build provenance, CycloneDX SBOM) | `actions/attest`, per pushed digest | Signed with Sigstore through the job's OIDC token, and stored on GitHub and in the registry. |
| The `trivy-evidence` workflow artifact | the `publish` job, on schedule and dispatch runs on `main` only (`trivy-evidence.sh`, then `actions/upload-artifact`, after `docker logout ghcr.io`) | Readable by anyone who can read this repo's runs, and the repo is public. The file holds fields from Trivy's template and `--version` output, the Dockerfile pins, image ids, the registry digests of the pushed images (checked against the local images' RepoDigests, passed in from the push step's outputs, each shape-checked as `sha256:` and 64 lowercase hex) and binary hashes; every scan-derived field is checked for shape and length, structure characters are refused and the rest are cut to a safe set; a secret finding records its rule id and path, never its matched text; the file is capped at 1 MiB. A failed evidence pass leaves no file. |
| Code scanning (SARIF) | the publish job | Carries the full findings, including unfixed and allowlisted ones, so nothing the gate lets through is hidden. |
| Commit statuses (`architect-review`) | `review-gate.yml`, this repo's own gate: the way-of-working plugin's, one job with `statuses: write`, `contents: read` and `pull-requests: read`. A legacy-route consumer writes it from its copy of the template's `architect-review-gate.yml` instead (a dev-App repo runs the plugin's gate, #418 owner decision 6, and `tools/check-consumer-workflows.sh` fails if the template gate appears there). `.github/workflows/` here has no `architect-review-gate.yml`: it exists only as `template/.github/workflows/architect-review-gate.yml`, for the legacy route | `review-gate.yml` holds no `contents` or `pull-requests` write, so main's copy cannot arm or disarm auto-merge. No convention is needed to keep the template gate's arming scopes from mattering here: this repo now has a `.devcontainer/Dockerfile`, but `.github/dependabot.yml` has no `docker` entry for `.devcontainer`, and although the repo setting `allow_auto_merge` is on (see Boundary 6), arming needs `pull-requests: write`, which main's copy of the gate does not hold. Arming the template gate's chain would also need the tag `devc-automerge-on`, which does not exist (it sits under the `release-tags` ruleset: it is created or removed only through the recorded ruleset edit, and the release credential's reach to it is named in its row under Credential holders). Every run of the gate, on `pull_request` (to `main`) and on `pull_request_review` (type `submitted` only; never `issue_comment`), executes the PR's own copy of the workflow file, with only its config read from the default branch's `.ai/project.yml`, so a same-repo PR can still add a workflow asking for write scopes on its own run (any human writer can already do that, DEVC-D7; on this repo the workflow pusher is the elevated window, which DEVC-D7's split does not yet place, see the elevated-token row; the dev token cannot, and neither can the authoring container except through `docs/host-steps.md`'s Procedure B, where `603id-admin[bot]` pushes the bytes it hands over and the owner's read of the block's snapshot before minting is the control on the bytes the block pushes only, not on commits the dev App pushes to the branch afterwards, see `docs/host-steps.md`'s Known limits bullet on later dev-App pushes, or through the host-execution paths Known gaps records (a planted `initializeCommand` or an added host bind in the local `.devcontainer/`, git hooks or `core.fsmonitor`, a VS Code task, and a host run of a branch's code)). It has `run:` steps only and no checkout. A config or API error posts nothing and fails the job, so any earlier status on that head stands, and with none the check stays unset and the PR stays blocked. For the template gate, `tools/render-gate.sh --check-masked` fails when it drifts outside its `CONSUMER` regions and checks nothing inside them; `render-gate-test.sh` pins its three regions to the expected shapes, and a human merge covers the rest. |
| Auto-merge armed on a consumer PR | a consumer gate's `post` job, only for a verified candidate while the tag `devc-automerge-on` exists in this repo | Not created, so never. The tag sits under the `release-tags` tag ruleset: it is created or removed only through the recorded ruleset edit (the release App's credential could also create it, see its row under Credential holders). See [Consumer verification](#consumer-verification-and-the-bump-gate-30). |
| Issues and issue comments on this public repo | `trivy-daily.yml`, on schedule and dispatch runs on `main` only (`trivy-daily.sh file`, with `issues: write`) | They list fixable HIGH and CRITICAL library-package vulnerabilities per published image: image reference with tag and digest, in-image path, package, installed and fixed versions, the pinned version of the binary and whether upstream has a newer release, and the run id. That is what the images already publish through Trivy-visible metadata, and the repo is public. Every scan-derived field is checked before it is written and sits in a code span; one issue per vulnerability id, found again by author, exact title and the fixed shape of the newest bot text. A secret finding is never filed: it fails the run and the step summary names only the flavor and the rule id. |
| `v*` tags and GitHub Releases | `release.yml`'s `release` job, with the release App's token, in one `gh release create --target` call, only on a `real` dispatch after the `release` environment's approval | The tag is computed, never typed: `release-plan.sh` counts from the newest `vX.Y` tag reachable from the commit and refuses an existing tag, a tag not newer than every `vX.Y` tag in the repo, and a commit that already carries any `v*` tag. `release-verify.sh` first proves the commit came from one merged PR with every required check green and `main`'s push runs successful. The tag lands on the dispatched commit of `main` (`release.yml` asserts the default branch before and after approval), and release immutability stops a published tag from moving. The Release body is public and unreviewed beyond the approver's read of `verify`'s step summary (see the Inputs rows on notes). |

## Credential holders

| Credential | Held by | Reach |
|---|---|---|
| `GITHUB_TOKEN` with `packages: write`, `id-token: write`, `attestations: write`, `artifact-metadata: write`, `security-events: write` | `build.yml`'s publish job only | Push to this org's GHCR packages, and sign attestations for this repo. Scoped per job; every workflow sets `permissions: {}` at the top. `actions/upload-artifact` now runs in this job too, after `docker logout ghcr.io` and only when that step succeeded, so the registry login is not on the runner while it runs. Residual: like every step in this job, it can request the job's OIDC token. |
| `GITHUB_TOKEN` with `actions: read` | `build.yml`'s scope job (`verify-selftest.yml`'s `live` job holds the same read for its own purpose) and `release.yml`'s `verify` job, which also holds `checks`, `statuses` and `pull-requests: read` | List `build.yml`'s runs on `main` and their jobs, to find the last run whose publish job succeeded (#159). Read-only, and it names no secret. The result only picks the commit `image-scope.sh` diffs against, so a wrong or forged answer can at worst make a publish run that was not needed or skip one that was; the lookup fails toward building, and the weekly schedule and manual dispatch always build. The commit id is checked as 40 hex, must be an ancestor of HEAD (a run on a tag named `main`, which `release-tags` does not cover, runs that tag's own workflow file and could fake a successful publish job; as an ancestor it can only carry a historical `build.yml` of main, which has guarded publish with `github.ref == 'refs/heads/main'` since b4a490b, so the tag run skips it. This relies on squash-only merges: with merge commits a PR branch's unreviewed commits would be ancestors too. A tag run at a commit older than that guard really publishes, which only widens the next diff and so builds), and is fetched before use. `release.yml`'s `verify` job uses the same read to list `main`'s push runs on the commit to release, and its other three reads (check runs, commit statuses, the producing PR) change nothing. It holds no write scope, and `release-verify.sh` validates the SHA and `REPO` and treats an API error as a refusal. |
| `GITHUB_TOKEN` with `statuses: write`, and `contents: read` and `pull-requests: read` | `review-gate.yml`'s single job | Post commit statuses on this repo, and nothing else: no write to contents or pull requests. The job has no `uses:`, `container:` or `services:`. The template gate's `post` job, in a legacy-route consumer, holds more (next row). |
| `GITHUB_TOKEN` with `contents: read` and `issues: write` | `trivy-daily.yml`'s one job (workflow-level `permissions: {}`; no `packages`, `actions` or other scope: the five packages are public and read anonymously) | Create, edit, close and lock issues, and comment on any issue or PR in this repo; it cannot turn `architect-review` green, because `review-gate.yml` counts no comment. Only the file step's `env` exposes it to a script (`GH_TOKEN`); `actions/checkout` receives it as its default input without persisting it, and the scan step, which pulls images and runs Trivy, has no token in its `env`. |
| A consuming repo's `GITHUB_TOKEN`: `contents: read` for `verify`; `statuses`, `contents` and `pull-requests: write` for the gate's `post` job only (legacy route: a dev-App repo has no `post` job, its status writer is the plugin gate's job, whose only write is `statuses`) | the consumer's `devcontainer-image.yml` and gate, running this repo's reusable workflows | `verify` and `decide` hold no write token and read this repo's public attestations cross-org. In dev-App mode `verify` also reads the default branch's rules with it (repository metadata, which every token can read). `post` can post statuses and arm or disarm auto-merge on that consumer's own PRs, and holds the token in a job with no `uses:`, `container:` or `services:`, so no third-party action or image shares its GitHub-hosted runner (checked by `tools/check-consumer-workflows.sh` when it is run, not continuously). |
| GitHub App installation token, `contents: write` + `pull-requests: write`, scoped to this repo only | `bump-binaries.yml` | **Can do more than the job uses it for**: push or delete any non-`main` branch, create tags outside `v*` and `devc-automerge-*`, create releases, and close or comment on any PR in this repo other than the python bump PRs the job itself supersedes (the job closes, with a comment, the older open python bump PRs its own App opened in this repo, when a newer python build is proposed). In the owner's live test (2026-10-07, #327) the token was refused when it tried to merge a PR into `main` (`405`), to update the `main` ref (`422`), and to delete a `v*` tag (`422`); those refusals were observed under the rulesets live on that date and are no evidence for today's control on `main`. Today `main-approval` stops a push to `main`, the merge of a PR without a current code-owner approval of its last push, and deletion or non-fast-forward of `main`, and `release-tags` covers the protected tags (its only bypass actor is the release App, and this App is not on it). What it does not stop is this App, or any account with write access, merging a PR that already has a current code-owner approval and green required checks: no live branch ruleset has an `update` rule (deduced from the rule types, not re-tested). The dated 2026-11-15 owner read-back that `.ai/project.yml`'s branch-protection comment records shows no bypass actors on `main-approval` or `main-required-checks`. Only deleting a `v*` tag was tried live; the other tag operations rest on the ruleset read-back. The real residuals are non-`main` branches, tags outside the protected patterns, releases, closing and commenting on other PRs (the script's author, same-repo and branch-shape filter is the only limit on which PRs it closes), and the merge of an approved, green PR. The job only pushes a `bump/<tool>-<version>` branch (python's is `bump/python-<version>-<build>`) and opens its PR (for python it also closes, with a comment, the older open python bump PRs its own App opened); the rest is this credential's reach if ever leaked or (see Known gaps) if the write step's own untrusted input were ever to reach it. Needed at all because a PR opened with the ambient `GITHUB_TOKEN` never triggers the required-check workflows (GitHub's own anti-recursion rule) -- and on this repo a job-scoped `GITHUB_TOKEN` could not even open the PR in the first place ("Allow GitHub Actions to create and approve pull requests" is off; `can_approve_pull_request_reviews: false`), so a dedicated identity is the only way to get this PR opened at all, let alone checked. Revoked at job end (the token action's default). The app's private key is a secret of the `bump-binaries` Environment, restricted to deployments from `main` (the job declares `environment: bump-binaries`), so a workflow run on any other branch cannot read it; it is held outside any container. The job runs only when the repo-level variable `BUMP_BINARIES_CLIENT_ID` (the App's Client ID) is set (#87). |
| GitHub App installation token, `contents: write` (and metadata read), scoped to this repo only: the release App `603id-devcontainers-release` | `release.yml`'s `release` job, behind the `release` environment (deployments from `main` only, a required reviewer, admin bypass off). Minted per run in the step right before the create step, on dry runs too. The App's key is a secret of that environment; its Client ID is the repository variable `RELEASE_CLIENT_ID` | **Can do more than the job uses it for**, as the `bump-binaries` row says: it bypasses `release-tags`, so it can create `v*` and `devc-automerge-*` tags, `devc-automerge-on` included, which would arm auto-merge for every legacy-route consumer. It can delete a Release and then its tag, and edit any Release's notes. It can move `v1.0`-`v1.2`, which have no immutable Release. It can push to unprotected branches. **What bounds it:** the environment and its reviewer, as configured; release immutability, which stops a published tag from moving or its name from being reused but not its deletion (an availability loss only, since consumers pin SHAs); and the workflow taking no tag name as input. **The residual on that bound:** the environment's configuration, `release-tags` and `release.yml` can be changed by the owner's admin login and by `603id-admin[bot]` (Administration, Environments, Actions and Workflows write, per `docs/host-steps.md`, whose token the elevated-token row describes). Either could drop the reviewer, widen the branch policy and dispatch, reaching the key with no approval. The plugin's readback of the declared `release` environment and of `release-tags` is the detective control, not a preventive one. |
| Per-repo fine-grained PAT | a consuming repo's container, in the `<repo>-home` volume | That repo only. The hub's token also covers the repos it coordinates. It expires after 90 days at most and is recorded in the owning org's credential ledger (603-Identity: infrastructure-core's; glunk-works: none yet, see Known gaps). Admin work (rulesets, repo settings) never uses a container token. |
| The dev token, `/run/wow/dev-token` (dev-App flavour) | the host's broker mints it per repository; the container reads it | A GitHub App installation token for that one repository, short-lived (the `expires_at` on line 2). It lives on a host-side read-only mount, never in a volume, so it is not in `<repo>-home`. Only `/usr/local/libexec/dev-token` reads it, for `git` and the `gh` wrapper; code running as `app` can read the file too (it is the same uid), so this is scoping and expiry, not secrecy from the container. **On this repo** the broker serves this repo's own token to its devcontainer (`tokens/603-Identity/devcontainers`), so git and gh for this checkout act as the dev App, with `identities.dev_app.commit_route: api` replaying its commits through the API so that GitHub signs them. Its reach here: push any non-`main` branch and open PRs; edit a review body, so the reviewer App's verdict line (assumed from the same API call as the bump-binaries App's, not tested); arm auto-merge on its own PRs, which the repo setting `allow_auto_merge` allows; and merge a PR that already has a current code-owner approval and green required checks (Boundary 6). It also reads this repo's Actions runs, jobs and job logs, as observed (the driver, 2026-11-19: listing the Actions runs and reading a job's log through the API returned 200, and `gh run view` with a job's log returned the full log), which `tools/trivy-except.sh` uses; this is recorded as observed, not as a permission granted to the App. The dev App lacks the Workflows permission, so the dev token cannot push a change under `.github/workflows/`: a dev-App-authored branch cannot edit `review-gate.yml`, and such changes come from the elevated window (next row). Under `docs/host-steps.md`'s Procedure B the dev App also opens the PRs whose commits `603id-admin[bot]` pushed, workflow changes included; it still cannot change those files itself. The dev App is a new non-human writer driven by a model that reads untrusted text, and DEVC-D7's split of trusted human writers and the untrusted bump-binaries App does not yet place it; that is a follow-up for the maintainer. |
| The elevated token (`603id-admin[bot]`) | `wow-admin` on the host, for an elevated window (it writes the token under the `admin/` folder of its identity home, `.config/603id-identity`, which no container mounts, glunk-works/claude-workbench#1611; before that fix it wrote it into the repo's token directory, the container's `/run/wow`; by default with Contents and Pull requests write, and with Administration and Workflows write only when `--perms` names them; `wow-admin <repo> --revoke` revokes it and removes the file) | Never read by anything in the image, and outside every container's mounts (this repo's container binds the clone, `.gitconfig.d` and the dev token's folder only), which holds under the Exception for a host that holds a token directory. `docs/host-steps.md`'s Procedure B block checks that with its reader search before it prints the plan and again before it reads the token, for running containers on the default context's engine and within the limits that file's Known limits name; a hit stops the procedure (deleting the snapshot folder and the revoke per step 2.5, when one is due, are the only steps that follow) and nothing more, the host's trust being left to the owner outside the procedure. The residual: the revoke after a second-run search throw runs `wow-admin` from a folder a container could reach, step 2.5 counts it as a failed revoke, so its hour applies to the tokens this run minted, and the mint's `granted:` line is untrusted in that case: such a `wow-admin` may have minted a token with any of the App's permissions or taken what the mint uses, and it ran as the owner on the host with everything the owner's user can reach; the hour bounds none of that, nor any change such a token made within the hour, and the host's trust is the owner's decision outside the procedure. Only `docs/host-steps.md`'s Procedure B block, in a plain `pwsh` window, and `wow-admin` itself (to mint and to revoke it) read it, never a Claude session. The flavour still keeps its own tools from reading a file of that name in `/run/wow` and tests that they do not (decoy files in `tests/smoke-devapp.sh`), and anything an earlier elevated window left in the home volume persists: nothing in this image clears it. **On this repo** the elevated window, acting as `603id-admin[bot]`, is the route for changes under `.github/workflows/` (it opened #530 and #532; under Procedure B it only pushes, and the dev App opens the PR): its reach here includes pushing a branch that edits any workflow, `review-gate.yml` included. `603id-admin[bot]` holds Administration, Environments, Actions and Workflows write as well as Contents and Pull requests write (its App settings, `gh api apps/603id-admin`, read 2026-11-17), so `main-approval` does not bound it: it can edit or disable any ruleset, add a bypass actor, and change an environment's protection rules, a required reviewer included. What bounds the elevated window is that the owner mints it on the host for a single task and revokes it afterwards (after a failed revoke every admin token is treated as live for an hour, `docs/host-steps.md` step 2.5); where its key is held is outside this repo's record. The branch's workflow also runs on its own events before any approval, with the `GITHUB_TOKEN` scopes it requests (never Workflows): it can post every required check, `architect-review` included, as GitHub Actions, the integration they are all pinned to, on any commit and not only its own head, push a package or a non-protected ref, and, with `contents: write` or `pull-requests: write`, merge or arm auto-merge on any PR that already has a current code-owner approval (the reach the dev-token row lists for the dev token). Neither `main-approval` nor the diff review holds that. DEVC-D7's split does not yet place `603id-admin[bot]` either; that is part of the same follow-up. |
| The Claude login (dev-App flavour) | `claude`, in the home volume | The user's own login, kept in `~/.claude`. It is not scanned and not covered by the dev token's expiry. |
| A leftover PAT or `gh` login (dev-App flavour) | `~/.config/gh/hosts.yml`, `~/.git-credentials` in a home volume that outlived the image | From an earlier non-dev-App run of the same repo. The `gh` wrapper ignores it (`GH_TOKEN` wins) and `devapp-check.sh` deletes both files at every start. |
| Owner's org login | the host, outside any container | Admin: rulesets, repo settings and package visibility (which must stay public for consumers in other orgs). It has no standing bypass of `release-tags` and reaches the protected tags only through the recorded ruleset edit (break-glass, and setting or clearing `devc-automerge-on`). It approves the `release` environment's deployments and keeps ruleset changes, the break-glass edit included, while the tag and the Release come from `release.yml`. It is the one code owner (`.github/CODEOWNERS`), so its approval of the last push is required on every PR, including the workflow-file PRs the elevated window pushes (`main-approval` does not bound the elevated window itself, see the elevated-token row); on dev-App PRs with auto-merge armed that approval is the merge. Who merges is not an enforced control: no live branch ruleset restricts it (Boundary 6). |
| The declared reviewer App (`identities.reviewer_app`) | the way-of-working plugin's review step; where its key is held is outside this repo's record | A review it posts on a PR head, with the configured header, attestation and a `Review verdict: pass` line, turns `architect-review` green for that head. What still bounds it is `main-approval`'s code-owner approval of the last push; who merges is a practice (Boundary 6). |

## Boundaries meant to hold

1. **Nothing reaches the registry untested.** No image is published unless all of these
   pass first:

   | Check | Where | Fails the build when |
   |---|---|---|
   | Smoke test ([`tests/smoke.sh`](../tests/smoke.sh)) | before push | a tool version differs from its pin (a Dockerfile `ARG`, or `images/base/tools/uv.lock` for the Python tools); the user isn't uid 1000; any setuid/setgid binary exists; a volume mount point isn't app-owned; any credential helper other than gh's runs; the projected identity holds a non-allowlisted key; a token from the origin URL appears in output; an identity is left in place after a failed selection (no origin, a non-github or lookalike origin, an ambiguous, unreadable or missing identity file); the image's `python3` isn't the pinned version, the names `python`, `python3` and `python3.15` don't resolve to it, `/usr/bin/python3` isn't Ubuntu's 3.14, a file under it is owned by or writable by anyone but root, it has a pip module or lacks its `EXTERNALLY-MANAGED` marker, `python3 -m venv`, run as `app`, fails, or the venv it makes has no pip that runs and reports a version (checked with pip's package index and version check turned off), its TLS context loads no CA certificates, or uv's lookup of 3.15 doesn't resolve to it; the tools venv or a cache path isn't where the image documents it; a mount point (`/home/app`, `~/.cache/tofu-plugins`, `/workspace/.venv`, `/workspace/node_modules`) or `~/.cache` isn't app-owned; any cache variable points into the shared `~/.cache/tofu-plugins` except tofu's; the image ships a `~/.gitconfig`; `git-identity.sh` fails to rewrite a stale, symlinked or directory `~/.gitconfig`, or to remove a planted `~/.config/git/config`; `owner-check.sh` fails to write the lowercase owner marker, to warn on a different owner or leave that marker unchanged, to replace a symlinked, directory or junk marker without echoing its content or following a link; a token from the origin URL appears in its output; a `url.*.insteadOf` planted in the home volume's global git config changes the origin it reads, or one planted in `~/.gitconfig-identity` changes the origin `git-identity.sh` reads; or its origin grammar disagrees with `git-identity.sh`'s on a table of URLs. For the dev-App flavours the file asserts dev-token (not gh) as the one helper that runs and the only one configured, and the served and fail-closed cases are [`tests/smoke-devapp.sh`](../tests/smoke-devapp.sh) |
   | Dev-App smoke ([`tests/smoke-devapp.sh`](../tests/smoke-devapp.sh)) | before push, once per `/run/wow` | with a valid token (decoys beside it): `dev-token get` does not serve the dev token for `http`, `github.com:443`, an upper-case or lookalike host, a second host or protocol line or any other host; `git credential fill` does not run exactly one helper, `dev-token`; the `gh` wrapper or `gh auth token` yields anything but the dev token (including with `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN` or a `hosts.yml` set to the decoy); a decoy token appears in any output; an ssh remote form is not rewritten to https; a gpg program, `gpg-check.sh`, or the `unsigned` marker's absence; the projected identity carries a signing key or `gpgsign` other than false; `claude` is not root-owned, mode 0755, the pinned version and sha256, or its managed settings are not root-owned, 0444 and carry the pins and the updater switches; `timeout`, `date`, or the package is not GNU's; a setuid binary. The credential-helper, git and `gh` wrapper checks run again on a token in GitHub's stateless format (dots, dashes, 520 characters, a file over 512 bytes). With no `/run/wow`, an empty one, an expired token, CRLF line endings, a token of the wrong kind, a file over 2048 bytes, a token with a character outside `[A-Za-z0-9._-]` or one under 36 characters after `ghs_`: `dev-token` answers anything but `quit=1` (or the oversize and bad-shape files are refused for another reason than their own), the `gh` wrapper runs, or a credential fill succeeds. `devapp-check.sh` fails to remove `hosts.yml` or `.git-credentials`, follows a symlink out of the volume, or misses an agent or a shadowing `claude`. The `with` run has no network: `plugin-install.sh` is not root-owned, mode 0755 and unwritable by `app`, does not exit 0 with no settings file, does not exit 1 (leaving the file byte-identical, within 150 s) for a pinned plugin it cannot fetch, or runs a `claude` placed first on the caller's `PATH` |
   | `claude` signature ([`images/devapp/files/claude-fetch.sh`](../images/devapp/files/claude-fetch.sh)) | before any push (the `claude-verify` stage, built right after base) | the committed key file is not one primary key with the pinned fingerprint; `gpgv` does not report exactly one GOODSIG and one VALIDSIG on the manifest, or reports BADSIG, ERRSIG, EXPKEYSIG, REVKEYSIG or NO_PUBKEY; VALIDSIG's primary-key fingerprint is not the pinned one; the manifest's version is not `CLAUDE_VERSION`; the manifest's linux-x64 checksum, `CLAUDE_SHA256` and the downloaded file's sha256 are not all equal |
   | Template proof ([`tests/template-proof.sh`](../tests/template-proof.sh)) | pull request | a container brought up from `template/.devcontainer/` (the dev-App template) on `devcontainer-devapp-tofu:local`, with the pinned devcontainer CLI and a fixture `USERPROFILE` holding a token directory, is not uid 1000, has a non-empty capability bounding set or `NoNewPrivs` 0, has no init as PID 1, has a writable root filesystem (a write to `/usr/local` succeeds instead of failing with `EROFS`), lacks any of the `<repo>-home`, `-tmp`, `-node_modules`, `-venv` or read-only `.gitconfig.d` and `/run/wow` mounts, mounts a shared tofu cache or `~/.aws`, cannot write the home, `/tmp` or `.venv` paths, has a writable `/run/wow`, a gpg binary or a `commit.gpgsign` other than false, does not return the fixture token from `git credential fill` through `dev-token` as the one helper that runs, has no `~/.gitconfig` or fixture identity after start, has no owner marker after start, prints the collision banner for a first checkout, prints no banner (or changes the marker) when a second checkout with the same folder name and another origin shares its `-home` volume, has a `tofu` other than the image's pin, skips `pre-commit install`, or `plugin-install.sh` does not report `nothing pinned`. A start with no token directory must either fail or come up with an empty `/run/wow` where `dev-token` answers only `quit=1`, git has no password and `gh` refuses (the daemon decides which). An `appPort` string and a list must publish on `127.0.0.1` only |
   | Trivy image scan | before push (the push, schedule and dispatch runs keep the full gate); on a pull request, `local` mode | before push: there's a HIGH/CRITICAL vulnerability **with a fix available**, or a secret is baked into a layer. On a pull request the gate is differential: it fails only on a finding the published image of that flavour lacks, and on any secret (it falls back to the full gate when the published image cannot be had), so a passing PR can still turn `main` red (see Known gaps) |
   | hadolint and Trivy config | lint | there's a Dockerfile anti-pattern |
   | shellcheck | lint | a script has a shell bug |
   | zizmor | lint | a workflow has a security problem (template injection, excessive permissions, unpinned action) |

2. **Exceptions expire.** The only way past the vulnerability gate that publishes is an entry in
   [`.trivyignore.yaml`](../.trivyignore.yaml) (the pull-request gate also passes a finding the
   published image already has). Each entry is scoped by path to one binary,
   carries a written reason, and expires within 30 days. After that date the weekly
   rebuild fails until someone re-reviews the entry. That file is in `code_paths`, so any
   edit to it needs the architect review. The not-required `trivy-expiry.yml` check turns red
   within 10 days of an expiry, and the renewal evidence comes from the `trivy-evidence` CI
   artifact (`docs/trivy-renewal.md`), with a host re-scan as the fallback. An entry is added by
   the same file's "Adding an exception" section.

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
   can still write the mounts (the home volume, `/tmp`, the dependency volumes, and on the legacy template the shared
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
   In the dev-App flavour the identity layer sits in the same read-only image: the `gh`
   wrapper (`/usr/local/bin/gh`), `gh-real` and `dev-token` (`/usr/local/libexec`), the
   verified `claude` (`/usr/local/bin/claude`) and its managed settings
   (`/etc/claude-code/managed-settings.json`, root-owned, 0444), so `app` cannot replace
   them. `~/.local/bin` still leads `PATH`: a `claude` or `gh` planted there shadows the
   image's, which `devapp-check.sh` warns about for `claude` and the wrapper avoids for
   everything it runs by fixing its own `PATH`.

5. **Repos stay apart; identity files do not.** Repos stay apart under their own,
   unmodified template, and only while every checkout on the host has a unique folder
   name. Each repo gets its own container and up to four per-repo volumes: `-home`,
   `-tmp`, `-node_modules` and `-venv`, and (dev-App template) its own token directory,
   `tokens/<owner>/<repo>`, mounted read-only at `/run/wow`. The dev-App template shares no volume;
   the legacy template shared tofu's provider cache (see Known gaps).
   A start-up check warns when two checkouts collide on a folder name (see Known gaps). A modified
   `.devcontainer/` (a PR branch opened in a container, say) can mount any volume on the
   host, and skip that check: Docker named volumes are not a boundary against a hostile config.
   The host's identity files are shared by design: every container mounts the whole
   `~/.gitconfig.d`, and identity is host-wide (see Known gaps).

6. **Changes to `main` are reviewed.** Two live branch rulesets cover `main`. `main-approval`
   requires a pull request with one approving review, a code-owner review (`.github/CODEOWNERS`
   names the one human owner) and approval of the last push, dismisses stale approvals on push,
   and refuses deletion and non-fast-forward. `main-required-checks` (read live 2026-11-17: it carries only its `required_status_checks` rule) requires the lint,
   build-and-smoke-test and `selftest` checks and `architect-review` (every check from GitHub
   Actions, integration 15368). The dated 2026-11-15 owner read-back that `.ai/project.yml`'s
   branch-protection comment records shows no bypass actors on either; the dev App's token reads
   none. `.ai/project.yml`'s `rulesets` block declares `main-approval`, `main-required-checks` and
   `release-tags` (its legacy `ruleset:` alias still names only `main-required-checks`). `architect-review` is posted by `review-gate.yml`: it is green for a PR that
   changes nothing under the trigger paths (by default `code_paths`), and otherwise only when the
   declared reviewer App has reviewed the head SHA with a passing verdict line (see Untrusted
   inputs), so a stranger on this public repo cannot turn it green by pasting the header and
   attestation strings. That is a fresh-session review, not the approval: the enforced approval
   is `main-approval`'s code-owner approval of the last push. **Who merges is a practice, not a
   control.** No live branch ruleset has an `update` rule, so nothing restricts who merges to
   `main`: `main-approval` does not stop any account with write access (the bump-binaries App, the
   dev App) from merging a PR that already has a current code-owner approval and green required
   checks. This is deduced from the rule types, not re-tested. The repo setting `allow_auto_merge`
   is on, and the dev App arms auto-merge on its own PRs through the way-of-working ship skill, so
   on those PRs GitHub merges as soon as a current code-owner approval and green required checks
   are in: the code owner's approval is then the merge.

7. **OS security fixes arrive on a schedule.** apt packages aren't version-pinned, so a
   weekly scheduled rebuild picks them up. Each rebuild publishes new digests under a new
   tag. Base's apt layer runs `apt-get upgrade`, so this covers the packages the Ubuntu
   image itself ships (apt, libc and so on), not only the ones the Dockerfiles install
   (#494). The exception is the image's default `python3`: it is no longer an apt package,
   so the weekly rebuild does not refresh it (see Known gaps).

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
   **In the dev-App flavour the helper is `dev-token`**, by absolute path
   (`/usr/local/libexec/dev-token`), after the helper list is reset and base's gh helper
   removed from `/etc/gitconfig`. It reads only `/run/wow/dev-token`, serves https github.com
   and nothing else (`quit=1` otherwise, so git neither tries another helper nor prompts at a
   terminal: `GIT_TERMINAL_PROMPT=0`; an askpass program is a separate path, see Known gaps), and the listed ssh forms of a github.com remote are rewritten to https so
   an ssh clone lands on it (other spellings, such as another case of the host, are not). The same local-config qualification applies: code running
   as `app` can add a helper to `~/.gitconfig` or a repo's `.git/config`, and nothing in the
   image can stop that; `git-identity.sh` rewrites `~/.gitconfig` at every start.
   **VS Code attach to a dev-App container is unsupported, and the template sets no VS Code
   settings.** (It carried four `customizations.vscode.settings` keys until #456; none was verified, and
   a setting nobody tests would be copied into every adopter as if it were a control.) An attach brings
   back what the template keeps out: the host's git config and credential helper, an askpass program
   for the terminal's git, and the host's VS Code GitHub session. The supported entry is the launcher
   (planned, glunk-works/claude-workbench#1339); until it ships, the devcontainer CLI from PowerShell.
   `tests/template-proof.sh` runs that CLI, which injects no VS Code helper. The `postStartCommand`
   `rm` removes only the helper scripts already in `/tmp` at start (a cutover repo's legacy `<folder>-tmp`
   volume can hold them), and the `postAttachCommand` warning is a notice of an attach (a log line nobody watches): the devcontainer CLI's `up` runs
   it too, so the documented interim entry passes `--skip-post-attach`. The template lists no
   extension, `containerEnv` or `remoteEnv`. `verify / verify` holds the file to the template
   exactly, so a repo cannot add to it beyond an optional loopback `appPort` (see the consumer-verification section).

## Consumer verification and the bump gate (#30)

A consuming repo's CI calls two reusable workflows from this repo, pinned by commit SHA:
`verify-devcontainer-image.yml` (the required check `verify / verify`, on every pull request)
and `devcontainer-bump-decision.yml` (`decide`, which fully verifies one candidate commit). Both
build the Go verifier in `tools/devc-verify` at the caller's pin before any pull-request content
is on disk, then read the consumer's files through the contents API at exact SHAs (the head;
from v1.6 `verify` also reads the PR base and the default branch's tip leniently, for the mode and the base's `FROM`,
below); there is never a checkout of consumer content. Their write token is nil. On the legacy
route, the one place a status is decided, and the one write token, is the consumer gate's `post`
job ([`template/.github/workflows/architect-review-gate.yml`](../template/.github/workflows/architect-review-gate.yml));
a dev-App repo's is the way-of-working plugin gate's single status-writing job instead (below).
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
  That is why `resolve` and `post` (in a dev-App repo, the plugin gate's status writer, held to
  the same shape, with no `needs:`, and to `pull_request` and `pull_request_review` triggers) contain no `uses:`,
  `container:` or `services:`, and why no other consumer job may hold `statuses`, `contents`, `pull-requests`, `checks` or `actions:
  write` on a trigger Dependabot's own branch can run: a PR event, `create`, or a `push` whose filter is not `tags:` alone or a list of literal branch names; no `branches-ignore:` counts, since Dependabot's branch name is configurable (`pull-request-branch-name.separator`) (Dependabot's branch push runs its bumped workflow files;
  that a Dependabot push run can raise its token is assumed from the `pull_request` case, not
  observed). `tools/check-consumer-workflows.sh` checks both **when it is run**, at adoption
  and from the pilots; nothing re-runs it in the consuming repo's CI, so a later edit that
  breaks a rule is caught by review alone. The gate defends against Dependabot-shaped
  forgeries, outsiders and wrong images, and against forks only to the extent that auto-merge
  never acts on a fork PR. DEVC-D7 records this split: human writers are trusted, while the
  bump-binaries App is not and is bounded by its permissions and by `main-approval`, which refuses a
  push to `main` and the merge of a PR without a current code-owner approval of its last push, but
  not the merge of a PR that already has one and green checks (deduced, not re-tested; invariant 6;
  its 2026-10-07 `405`, #327, was observed under the rulesets live then). On the legacy template
  gate it is bounded further by the head-SHA binding (#92) and the review-editor check (#94, see
  Known gaps); this repo's own gate has the head-SHA binding but not the review-editor check. The reviewer-App check run that was to be required
  before auto-merge went on (#267) is superseded; for this repo's own gate what stands in its place
  against a forged status is the declared reviewer App's review, counted by `review-gate.yml` (see the auto-merge bullet
  below). Dev-App repos run the way-of-working plugin's gate.
  The other route to a non-forgeable status, a ruleset-required workflow, was rejected
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
- **Auto-merge is off and stays off until its preconditions are met.** This is the
  `devc-automerge-on` kill switch for the Dependabot image-bump chain, not the repo setting
  `allow_auto_merge`, which is on (the dev App arms auto-merge on its own PRs, Boundary 6). The
  fail-closed kill switch makes "not created yet" the off state. When it is on, this repo's `main`, then the
  publish, then a consumer merge becomes an unattended chain whose only human control is this
  repo's own `architect-review` (`review-gate.yml`, which reads the verdict line but has known gaps: the review-edit and #278 residuals below, and #93). The owner
  creates `devc-automerge-on` only when #396's preconditions are met (#396 absorbs #139; #267 is
  superseded): among them a pilot that has taken real bumps through the review path, a private
  repo that confirms the arming, and `disarm()` in every row (#126, #132). Nothing in #396 closes
  #93 or F9b, which #267 was to close: turning the switch on accepts them at the root of the chain,
  and what stands behind a forgeable `architect-review` is `main-approval`'s code-owner approval of
  the last push; who merges is still a practice, which the rulesets do not enforce. No dev-App bump is
  ever armed, because `decide` refuses those images. Docs-only pushes no longer publish: a push
  to `main` publishes only when an image-affecting path changed since the last successful
  publish (#124, #159), so a docs-only merge ships no new tag set. The base is the commit of the
  newest `main` run whose publish *job* succeeded, not the push's own `before`: a pending run
  that a newer push cancels, or a publish that failed, would otherwise lose its change to the
  next docs-only push. A lookup that fails or finds nothing (none among the newest 100
  successful runs, or the runs have aged out) builds.
- **The kill-switch window.** Removing the tag stops later *arming*; `decide` still runs. It
  does **not** disarm open PRs: an armed PR merges whenever its remaining checks go green,
  possibly hours later. To close the window, post an allowlisted comment on each armed PR
  (that re-runs `post`, which disarms), or run `gh pr merge --disable-auto` on each. Removing
  `devc-automerge-on` now needs the recorded ruleset edit first: the deletion rule of
  `release-tags` is disabled for the deletion and restored after it.
- **The tag ruleset** (`release-tags`) restricts creating, updating, deleting and moving
  `refs/tags/v*` and `refs/tags/devc-automerge-*`. The release App `603id-devcontainers-release`
  is its single bypass actor (DEVC-D12). There is no admin-role bypass: the owner's login, an org
  owner and any admin team reach these tags only through the break-glass edit below. It was read
  back through the API after creation. **One negative test was run live:** deleting a `v*` tag
  with the bump-binaries App token was refused (`422`, 2026-10-07, #327). Creating or updating a
  `v*` tag, and any operation on the `devc-automerge-*` pattern, were not tried; they rest on the
  ruleset read-back. Releases are `vX.Y` tags, each published as an immutable GitHub Release from
  `v1.3` on (DEVC-D8). From DEVC-D12 they are made by `release.yml`, a dispatched workflow behind
  the `release` environment, and the tags are **unsigned**: the provenance is the reviewed
  environment run on `main`, not an admin's key. That is safe because every consumer pins the
  release's commit SHA, never the tag, and `tools/check-self-pins.sh` checks that a tag peels to
  its commit, lightweight or annotated. The owner's manual `git merge-base --is-ancestor` check
  is replaced by `release-verify.sh` (the commit came from one merged PR into `main`, with every
  required check green and `main`'s push runs successful) and the default-branch assert, which
  both `release.yml` jobs run first. Once a release is published, its tag cannot be moved, and
  can be deleted only after deleting its release (the name can never be reused), which closes the
  App's bypass, not an admin's, against re-pointing that tag; `immutable-releases` is
  `enforced_by_owner: false`, so a repo admin can turn the setting off before a future release
  (existing releases stay immutable); `v1.0`-`v1.2` predate it and keep only the ruleset.
  **Break-glass is a recorded ruleset edit:** the owner disables the one rule the operation needs
  (creation to create a tag, deletion to delete one), does it, restores the rule and records the
  edit. While a rule is disabled, every writer can perform that operation on both patterns: any
  account with write access, the bump-binaries App token, the dev App, `603id-admin[bot]` while
  an elevated window is open, and any workflow's `GITHUB_TOKEN` with `contents: write`.
  The window is kept as short as the operation, and it is never a standing bypass.
- **Dev-App mode (#418, from v1.6).** `verify` reads two more commits, the PR base and the
  default branch's tip, through the API only and leniently: the raw bytes of their two
  `.devcontainer/` files, matched for the mode markers and, for the base, its `FROM`
  MAJOR.MINOR by a regex; neither file is otherwise parsed, and a tree whose listing did not
  complete is an error, never "absent" (a canonical path there that is not a regular file does
  count as absent, on purpose: failing closed would wedge the PR that repairs it, and the
  default branch's tip, read too, is what marks a dev-App repo). A repo is dev-App when any of the three is, and then the
  head must be too: a PR cannot step a dev-App repo back to plain mode, where the allowlist is
  wider. A plain head is read for the markers the same way, so a head that passes as plain can
  never turn a later base dev-App. The head is compared exactly with the template at the
  caller's pin, or the previous release's snapshot that the verifier embeds, outside four
  per-repo surfaces, so an added `initializeCommand`, an added mount, and a changed `runArgs`,
  `workspaceMount` or `${localEnv:` string are refused. Plain mode's allowlist refuses the same
  ones except added mounts, where it still takes a per-repo named volume (never a host bind). The
  token mount must name `github.repository` (from the workflow, never an input), so a repo
  cannot mount another repo's token directory. `verify` reads the default branch's rules and
  fails unless a `pull_request` rule requires an approval and code-owner review (owner decision
  8); an API error is red. **What it does not hold:** the extras filter catches accidents, not
  attacks (extras can run as root at build time, after a `USER 0` of their own, and undo the identity layer; the approval and
  the human review hold that); the approval rule check does not see bypass actors (a host
  procedure), whether a `CODEOWNERS` file covers the repo (without one, code-owner review
  requires nothing), or whether stale approvals are dismissed on push; a PR can downgrade its own verifier pin below v1.6, which has no mode and no
  dev-App images, and turn the repo's `.devcontainer/` back to plain in the same PR (the dev
  App's missing Workflows permission and the approval hold that, not a rule here); and
  `decide` refuses every dev-App image bump, so no dev-App repo is ever exempt from review.
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
  arming auto-merge was observed on a public repo only. A private throwaway repo has to confirm it
  before auto-merge is turned on (#396).
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
  `incomplete`, never on findings). The env vars that change the config or fingerprints, or contact
  credential providers, are refused. Findings are always redacted and never uploaded.
- **The git half is ours (rc.3 onward).** Betterleaks 2.0.0-rc.3 dropped `git --log-opts` and no longer runs git, so this wrapper
  runs `git log -p` over the head's whole ancestry and pipes it to `betterleaks stdin --git-diff`,
  so coverage is whatever that command prints. Every option that can drop coverage from the output is named
  (`--root`, `--diff-merges=separate`, `--text`, no renames, no external diff or textconv, full
  commit ids, the default date format, UTF-8 output, `--pretty=medium`, `--no-replace-objects`), so runner or repo git config cannot drop the root commit,
  merge-resolution content or a commit's header. A git failure, or git cut off because the scanner
  stopped reading, is red. The scanner itself treats input it cannot parse as an `incomplete` scan
  in most cases, but a stream with no `diff --git` file header is "nothing to scan", so the stream assertions
  in `tools/tests/secret-scan-test.sh` and the real-scanner cases in `tests/smoke.sh` are what
  keep coverage honest.
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
  repo's `<repo>-home` volume, token included on the legacy route (a direct breach of boundary 5), and the
  sandbox resolves worktree paths inside the container that a host daemon cannot see. The
  rule for that container: it mounts no other repo's volumes.
- **603-Identity/devcontainers has a dev-App devcontainer, and some of its local gate's
  steps run outside it (a partial exception to "every repo gets a container").** `.devcontainer/` is the dev-App template with this repo's token mount
  (`tokens/603-Identity/devcontainers`, read-only at `/run/wow`); its Dockerfile adds shellcheck
  and the pinned Go release to `devcontainer-devapp`. All authoring happens in it: editing, Claude
  Code, git and gh for this checkout (through the dev token: the broker serves this repo's token,
  and `identities.dev_app.commit_route` is `api`, so GitHub signs the dev App's commits),
  shellcheck, `go test` for `tools/devc-verify`, and every gate suite except the claude-fetch
  suite and the reader-search suite. The other steps run in CI's required checks, each for its own reason. The Docker steps
  (the hadolint and Trivy config scans, the digest-pinned zizmor image step, the image builds and
  smoke tests, the template proof) would need docker-in-docker in the container (`--privileged`, a
  breach of boundary 4) or the host socket (a breach of boundary 5): the same reasoning as the
  loop-orchestrator exception above. The claude-fetch suite of `tools/tests/run-gate-tests.sh`
  needs gpg, which the dev-App flavour removes on purpose (`gpgv` stays), and the reader-search
  suite needs `pwsh`, which the dev-App image does not ship, so `bash
  tools/tests/run-gate-tests.sh` as a whole exits 1 in the container. CI runs them in `lint.yml`'s
  jobs, the `gate-tests` job of `verify-selftest.yml` (aggregated by `selftest`), and `build.yml`'s
  `Build and smoke-test (no push)`, which builds the images and runs the template proof when the PR
  changes an image, the template or another path `.github/scripts/image-scope.sh` scopes in; a change made in the container ships with those steps named as
  pending in its PR. `lint.yml`'s hadolint and Trivy config scans now read this repo's own
  `.devcontainer/Dockerfile`, and `verify-selftest.yml` ties its `ARG GO_VERSION` to go.mod's `go`
  line; beyond those only review holds the directory: `.github/dependabot.yml` has no `docker`
  entry for it and no workflow here calls `verify-devcontainer-image.yml` on this repo's own pull
  requests, so its `FROM` line and its Go download change only by a hand-made PR under the
  `code_paths` review and `main-approval`. **Residual:** an ad hoc host run of one of those steps
  (for example a host Trivy scan) must use a checkout no container mounts, since code in the
  container can plant hooks or `.git/config` entries in the checkout it mounts; and because such a
  run executes the branch's own tracked scripts (for example `.github/scripts/build-and-test.sh` or
  `tests/template-proof.sh`) with the host Docker daemon's reach, which can mount any repo's
  volumes and read the token directories, it runs only at a commit whose diff has been reviewed.
  Revisit if a second contributor or machine joins, or the Docker-dependent steps need to run
  locally often enough that CI alone is too slow.
- **A host that holds the token directory runs no privileged container.** Every dev-App
  container mounts only its own repo's `tokens/<owner>/<repo>`, but a container with `--privileged`,
  the Docker socket or a bind of `%USERPROFILE%` can read every repo's directory, and the
  broker's own files beside them. That is the loop-orchestrator exception's rule (it mounts no
  other repo's volumes) applied to the host: such a container belongs on a host or account that
  holds no token directory.
  For `docs/host-steps.md`'s Procedure B the same ban reaches what such a container could read or
  rewrite there: the identity home `.config/603id-identity` in the user profile (the admin token
  folder, and the `wow-admin` the owner runs), and Procedure B's snapshot folder under `%TEMP%`,
  which it could read or rewrite between the block's write and the owner's read. So on such a host
  Procedure B also bans any container with a bind of the identity home, of any folder inside it, of
  `%TEMP%`, or of any folder that contains either (`%USERPROFILE%` itself, the folder that holds the
  user profiles, or a drive root), not only a bind of `%USERPROFILE%`. Procedure B's block checks
  that ban with its reader search at two points (before it prints the plan, and after `yes` before it
  reads the token), within the limits `docs/host-steps.md` names.
- **No devcontainer** for org profile repos (`.github`), archived repos, or demo
  repositories.
- **zizmor's `dangerous-triggers` rule is ignored for one line of the template gate.** zizmor
  1.32.0 flags the `issue_comment` trigger of `template/.github/workflows/architect-review-gate.yml`
  (1.30.1 did not). The trigger is deliberate (the template's header explains it, and the *Issue,
  PR and review text* and *Commit statuses* rows above describe what it reads and writes): an
  `issue_comment` run uses the default branch's copy of the file, a comment only re-triggers the
  gate and never counts toward the status, the early stop compares the actor's numeric id with
  `REVIEWER_IDS`, and `resolve` and `post` run `run:` steps only. `.github/zizmor.yml` carries
  the ignore, keyed to the file name and line (`architect-review-gate.yml:65`; zizmor matches the
  bare name, in either scanned directory), so the rule still reports any other trigger on another
  line of the file, `pull_request_target` and `workflow_run` included: an
  inline `# zizmor: ignore[dangerous-triggers]` comment on the trigger was tried and rejected,
  because it also hid a renamed `pull_request_target` in the same `on:` block. The residual: the
  ignore is keyed to a line number, so a change that moves the trigger makes the finding return
  until the number is updated (a loud failure, not a silent one). Two silent cases are pinned by
  `tools/tests/zizmor-pin-test.sh` instead: the template's line 65 must be exactly
  `  issue_comment:` (so another trigger put there is not hidden), and `.github/workflows/` must
  hold no file named `architect-review-gate.yml` (whose line 65 the same ignore would hide). A
  change to `issue_comment`'s `types:` is not pinned: review reads it. A consuming repo that copies the
  template and runs zizmor 1.32 or later needs its own ignore for that trigger; this repo's file
  does not reach it.

## Known gaps

These are stated plainly so nobody trusts the setup for more than it does:

- **A failed dev-App step leaves earlier images published, and publishing needs Anthropic's CDN.**
  `build-and-test.sh` pushes base, tofu and node before it builds, smoke-tests and scans the
  devapp images (each image is checked before its own push, not before every push). If a devapp
  step fails, every image pushed before it is already on GHCR (devapp is pushed before
  devapp-tofu is built), and `build.yml` still attests each of them (an image's attest steps run
  whenever the push step produced its digest); the images after the failure are simply not
  published until the next run. And because `claude` is verified before the first
  push, every run, the Monday security rebuild of the plain images included, fails if
  `downloads.claude.ai` is unreachable or stops serving the pinned release; the fix is a
  deliberate bump of `CLAUDE_VERSION` and `CLAUDE_SHA256`.
- **A finding carried only by an unpublished change fails every pull request whose image has it.**
  A pull request's Trivy gate (`build-and-test.sh local`) compares against the published image of
  each flavour, not a build of the base commit. A finding carried only by a change merged to
  `main` but not yet published is therefore not in the before set, so it fails every PR whose
  image has it until the change is fixed or excepted.
- **A pull request can pass with a finding the published image still carries.** The same
  comparison lets a PR through when it brings in a finding the published image still carries (a
  revert of a merged but unpublished fix, or a downgrade to the published pin), when an exception
  has expired (the finding is in both scans), or when an exception PR covers only some of the
  flavour groups a CVE reaches. In each case only the full gate of the `push` run on `main` stops
  it, which turns `main` red and holds back the failing flavour and every flavour built after it.
- **The dev-App flavour's credential path can be bypassed by code running as `app`.** `dev-token`
  is a helper in system git config, so `git -c credential.helper= ...`, `GIT_CONFIG_NOSYSTEM=1`,
  runs without it; git then asks `GIT_ASKPASS` if one is set. (Git started by `gh` also resets the
  helper list, but `gh` adds its own helper, which uses the wrapper's `GH_TOKEN`: the dev token
  for github.com, not askpass.) VS Code sets one in its terminals and tasks, and its GitHub
  authentication can answer for github.com with the host's VS Code GitHub session, a token that
  reaches every repo its owner can. `GIT_TERMINAL_PROMPT=0` does not stop askpass, and the image
  cannot override an environment `GIT_ASKPASS`. The template sets no VS Code settings against it:
  VS Code attach is unsupported (boundary 8), and the launcher (interim: the devcontainer CLI) is the only supported entry.
  Anything that does attach, including a VS Code window opened outside the launcher, gets whatever settings
  apply, and both askpass keys (`git.terminalAuthentication`, `github.gitAuthentication`) default to
  on: an askpass program and the host's GitHub session are in reach with no settings write at all. Code in
  the container can also write `/workspace/.vscode/settings.json` (the bind mount); a repo can commit the
  same file, and `verify / verify` reads only `.devcontainer/`, so the PR stays green. A verifier rule rejecting those keys, and a start-up warning, are not built (#458 declined: both keys
  default to on, so a rule rejecting `true` closes nothing, and a rule requiring `false` would be
  undone by container code rewriting `/workspace/.vscode/settings.json` after the check, or by a
  window that never opens that workspace). The same uid can also use an
  ssh key left in `~/.ssh`, or a forwarded agent (`devapp-check.sh` only warns about the latter, and only about an agent already present when it runs at start, which an attach that follows may not be).
- **The dev-App flavour's `claude` trust is a committed key, a pin and a build-time check.**
  The check proves the binary is the one Anthropic signed for exactly `CLAUDE_VERSION`
  (`images/devapp/files/claude-fetch.sh`), but: a committed key cannot learn of a revocation
  (if Anthropic revokes it, builds keep trusting it until a human changes the file); a
  session can fetch its own `claude` (the stock installer writes to `~/.local/bin`, which leads
  `PATH`), and `devapp-check.sh` only warns; the organisation settings Anthropic's servers push
  to a logged-in `claude` are not verified, so a managed-settings file here pins the version but
  cannot stop what the server adds; and the version is bumped by hand (a replayed older manifest is
  refused, because the signed version must equal the pin; a deliberate bump of the pin to an older
  release is not checked).

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
  - python-build-standalone publishes a GitHub artifact attestation for each release asset
    (including the pinned tarball), checked with `gh attestation verify --repo
    astral-sh/python-build-standalone`; its release carries a `SHA256SUMS` asset but no
    signature file for it.

  The one exception is tofu's checksum file, verified by hand for 1.13.0 when it was
  pinned (#58) and again for 1.13.2 and 1.13.9 (#511). The verified signer identity is recorded beside `TOFU_SHA256` in
  `images/tofu/Dockerfile`. No build checks a signature, and `bump-binaries.sh` doesn't
  either (#29). An automated bump rewrites the pin and leaves the hand-written record
  untouched, so the record covers only the version it names. Nothing in a bump PR
  prompts the re-check: only README's bump checklist does, and the PR body does not
  link it. For the other pins, each
  mechanism above except Node's was confirmed to exist for the current pin on
  2026-10-02 (python-build-standalone's attestation was confirmed later, when it was pinned).
  That is not a verification of record: no signer identity is pinned for them.
- **The default Python interpreter is bumped only within its minor, and not scanned.** The image's `python3` is
  a python-build-standalone CPython under `/opt/devc/python`, with the libraries that build
  links into it (OpenSSL among them). The weekly apt rebuild does not refresh it. `bump-binaries.sh`
  proposes a newer build of the pinned minor every week (#561), so a security fix in CPython or those
  libraries reaches the image through that PR; a change of minor is a hand re-pin (DEVC-D11). The build's
  Trivy gate does not see it: Trivy identifies no component under `/opt/devc/python` (recorded
  on #557), neither CPython nor the libraries linked into it, so a vulnerability in them fails no
  gate and is missing from the image's SBOM. The OpenSSL and Python packages the scan does list
  are Ubuntu's apt copies, which this interpreter does not load.
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
- **The removed pebble binary's bytes still ship in the base image's lower layer.**
  `images/base/Dockerfile` removes `usr/bin/pebble` and its state directory in its apt layer
  (#625), because that service manager carries CVE-2026-97054 and nothing in these images
  starts it. The merged filesystem, which the build gate and the daily scan read, no longer
  has the binary, so neither reports it. Its bytes still sit in the pinned `ubuntu:26.04`
  layer under that removal, which every published image carries, since all five flavours
  build on base. Anyone who inspects or extracts that layer without applying the later
  deletion can still find it. It is not on any container's filesystem. Removing the bytes
  would need the image built from a layer that never holds them (for example a flattened
  copy of the base image's filesystem), which is its own task.
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
  proof asserts uid 1000 and writes to the home, `/tmp`, `.venv` and `/var/tmp`; its CI
  fixture is made world-writable, so it does not exercise this trade-off.
- **The devcontainer CLI in the template proof is pinned by version, not by hash.** npm
  checks the registry's integrity value for the tarball it resolves, but nothing here pins
  that value, so a tarball the registry served differently for the same version would run.
  In CI that is the build job, which holds no write permission and no secret, but it does reach the runner's Docker socket and the checkout. The same
  script is in `gates.green`, so an ad hoc host run executes it as that user, with access to the
  Docker daemon (the Exceptions residual applies); the devcontainer has no Docker. The CLI itself has no dependencies and no install scripts.
- **Verifying a new digest is automatic only in a repo that has adopted #30's workflows.** A
  repo that has not copied `devcontainer-image.yml` and does not require `verify / verify`
  still takes whatever digest a Dependabot image bump proposes, including a branch-built
  one, unless a human runs the verify command. Only the two pilots have adopted them (#10).
- **Legacy template only: the shared tofu provider cache is checked at command start, not at exec.** tofu links a
  cached provider into the repo's data directory and runs it from the shared volume, so a
  hostile process in another container could swap the binary between the check and the
  exec. It needs code already running in any container that mounts `devc-tofu-plugins` (a hostile
  dependency in another repo or org, say). The `devc-tofu-plugins` volume is the one cross-container
  channel left. `plugin_cache_may_break_dependency_lock_file` must stay unset: the smoke test asserts its
  environment-variable form, and no image ships a tofu CLI config file.
- **Legacy template only: the shared cache volume is readable and writable from every container that mounts it.** The dev-App template mounts no `devc-tofu-plugins`, but a legacy container on the same host still does.
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
  included on the legacy route, so the fix stays the host rule: rename the folder and remove the shared
  volumes. It catches accidental collisions under the unmodified template only. A hostile
  `.devcontainer/` mounts any volume and skips any start-up step (boundary 5), and a repo
  renamed or transferred needs `rm ~/.devc-owner`. The marker is untrusted input: it is
  printed only when it matches the `org/repo` grammar.
- **glunk-works has no credential ledger yet**, so its tokens have no recorded home.
- **The broad OAuth token** that containers used before this model can still be live
  until it is revoked (#439), which waits for every container that used it to be rebuilt on a shared image or retired.
- **Approval is enforced by `main-approval`; who merges is a practice (Boundary 6).**
  `main-approval` requires one approving review, a code-owner review and approval of the last push,
  and dismisses stale approvals on push; the one human owner is in `.github/CODEOWNERS`. A PR that
  changes the reviewer App's id in `.ai/project.yml` is held by that approval of its last push, and
  the config is read from the default branch, so the change takes effect only once merged.
  `review-gate.yml` counts a review only from the declared reviewer App's numeric id
  (`identities.reviewer_app.id`, from the default branch's `.ai/project.yml`). The template gate's
  counterpart, for the legacy route, is its `REVIEWER_IDS` allowlist (#14): an ID list, not
  `author_association`, because the owner's 603-Identity membership is private and the workflow's
  token reads it as `CONTRIBUTOR` (seen live on #89); IDs rather than logins, because a released
  login can be re-registered. The bump-binaries App token (above) is not the reviewer App, so a
  review it posts doesn't count. It was refused when it tried to merge a PR to `main` (`405`, #327,
  observed 2026-10-07 under the rulesets live on that date); today there is no control on who
  merges an approved, green PR. Comments never count, so editing an owner comment into a
  qualifying one (#94) does nothing. On the template gate, a writer can edit someone else's
  formal review body (verified on #94), so a review with any editor not in `REVIEWER_IDS` does not
  count either (see below); and quoted lines (`> ...`) are ignored there, so quote-replying
  someone else's pasted strings doesn't qualify. `review-gate.yml` has no editor check (see the
  bullet after next). Nothing enforces that only the owner's login merges PRs: merges by the dev App's armed auto-merge
  and by other accounts have happened, and no ruleset restricts who merges.
- **Legacy route (the template gate): a review is bound to the head SHA, not a date (#92 and #94
  closed).** This bullet describes `architect-review-gate.yml`, the template gate; this repo runs
  `review-gate.yml`, which has no editor, `Reviewed against head` or review-edit check (next
  bullet). The template gate used to
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
- **This repo's gate, `review-gate.yml`: the head-SHA binding without the template gate's extra
  checks (the review-edit residual and the #278 skill half).** It counts a review in state
  `COMMENTED` whose `commit_id` equals the head SHA, by the declared reviewer App's id, with the
  configured header and attestation lines, and reads the verdict line of the latest such review; a
  push moves the head SHA, so every earlier review stops counting. It has no review-editor
  (edit-history) check, no `Reviewed against head` line check, and no trigger on a review edit or
  dismissal (`pull_request_review` runs on `submitted` only; `pull_request` includes `edited`, a PR
  title or body edit). Two residuals follow, each held only by `main-approval`'s code-owner approval
  of the last push (who merges is a practice). First, a review edit: a write account can edit the
  reviewer App's review body (verified for a non-admin human write account on #94; for the
  bump-binaries App's token, which holds `pull-requests: write`, and for the dev token, which the
  authoring session holds, assumed from the same API call and not tested), for example turning a
  blocking verdict line into `Review verdict: pass` with the header and attestation lines kept; the
  gate reads no edit history and does not re-run on the edit, but its next `pull_request` run on the
  same head (a PR title or body edit is enough) counts the edited review. Second, the #278 skill
  half, wider here: `commit_id` is the head when the review is posted, not the commit the reviewer
  read, and this gate matches only `commit_id` with no `Reviewed against head` line check, so a
  review written against an earlier head and posted after a push counts for the new, unread head.
  That residual is dropped only if the way-of-working plugin version this repo pins (the `ref` of
  the `claude-workbench` marketplace entry in `.claude/settings.json`) has a posting skill that pins
  `commit_id`; the condition names that pinned version, not this repo's tree.
- **A same-repo PR runs its own copy of the gate.** Every run of `review-gate.yml`,
  `pull_request` and `pull_request_review` alike, executes the PR's own version of the workflow
  file, while its config (the `review.ci_gate` strings, the trigger list, `identities.reviewer_app.id`)
  comes from the default branch's `.ai/project.yml`. So a branch that edits the gate is checked by
  the edited gate. Pushing a branch already takes write access, and the edit shows in the diff the
  human reads before approving (#93), though the edited workflow runs, with the scopes it requests, before that read (elevated-token row); a change to the workflow file itself is pushed from the elevated window
  on this repo (the dev token lacks the Workflows permission),
  and `main-approval` does not bound that window (elevated-token row, Credential holders). Accepted under DEVC-D7 for human writers: the gate does not defend against them. For `603id-admin[bot]`, the acceptance waits on the DEVC-D7 placement follow-up. The
  reviewer-App check (#267) that was to close this gap is superseded, and nothing else closes it (the
  reviewer App's review does not, since the edited gate decides whether it counts); the gap stays
  accepted for human writers on this repo and on the legacy route, including if the `devc-automerge-on` chain is ever turned on. #396 holds
  that switch's preconditions. The template gate, on the legacy route, has the same shape, except
  that its `issue_comment` runs use `main`'s copy.
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
- **Legacy route: identity selection is not authorization.** A dev-App container has no gpg and signs nothing (`devapp-check.sh` warns when an agent is present), so only the legacy template forwards one. Identity and the GPG agent are host-wide
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
- **A session can run code on the host through the checkout, not only `.devcontainer/`.**
  `/workspace/.vscode/tasks.json` with a `folderOpen` task, a root `.devcontainer.json`, `.git/config`
  (`core.fsmonitor`), `.git/hooks`, and the same in any nested `.git` directory or `.git/modules/*`, are all writable through the bind mount, and run on the host
  when the folder is opened in host VS Code (the git extension, a trusted workspace's tasks) before
  any prompt can be declined. The same holds for the machine settings file in the home volume
  (`~/.vscode-server/data/Machine/settings.json`), which can change VS Code's behaviour in an attach and
  is invisible to git and to `verify / verify`.
- **A session can run code on the host through the local `.devcontainer/`.** The checkout is a
  bind mount, so a session can edit `.devcontainer/devcontainer.json` (an `initializeCommand`, a
  host bind) and the host runs it on the next `up` or rebuild: the devcontainer CLI runs
  `initializeCommand` from the local file, as VS Code's "Reopen/Rebuild in Container" does.
  `devcontainer exec --workspace-folder <path>`, the per-session interim entry, re-reads the same file on
  every run (a running container can rewrite it between inspection and use), substitutes `${localEnv:...}` from the host's environment into `remoteEnv`, and takes
  `remoteUser` from it, so an edited file can carry a host secret into the next `claude` process or
  run it as another user. A checkout a container has written to is no longer "a clone you reviewed"
  after the first `up`.
  `verify / verify` sees only what is pushed. Until the
  launcher ships and is the only way in (planned, tracked at glunk-works/claude-workbench#1339),
  only the convention "enter through the launcher (interim: the devcontainer CLI; stop the container and
  inspect the config before any `up`, from a PowerShell outside the checkout with no secrets in its environment); never run the host's Dev Containers extension or git on a mounted checkout" holds this.
- **"No extensions" holds for a fresh home volume only.** The VS Code server loads every
  extension in `~/.vscode-server/extensions`, and a cutover repo reuses its legacy `<folder>-home`
  volume, which holds the GitHub and Claude Code extensions; a host user setting
  `dev.containers.defaultExtensions` also installs into every container. `docs/adopting.md` step 6
  has the cleanup. Nothing enforces it.
- **Extras can undo the identity layer.** The Dockerfile's extras run as root at build time if they
  say `USER 0`. The verifier's filter catches accidents (writes to the identity paths, `ENV` of
  `GIT_*`, a proxy or `ANTHROPIC_BASE_URL`, a local `ADD`), not attacks; the approval rule and the
  human review hold the rest.
- **The elevated token used to share the mount.** Until glunk-works/claude-workbench#1611, the
  elevated-token file `wow-admin` writes sat in the same directory as `dev-token`, a live bind mount,
  so while it existed any process in a running container of that repo could read it. It now sits
  under the `admin/` folder of its identity home, which no container mounts, and `docs/host-steps.md`'s
  Procedure B no longer stops the containers. What remains: residue in the home volume from an
  earlier elevated window (a copied token, a cached login) persists into every later window of the
  repo; and that no container reaches `admin/` rests on the Exception for a host that holds a token
  directory, which Procedure B's two search runs check, within the limits `docs/host-steps.md` names
  (among them a bind through a symbolic link, junction or other reparse point, an engine reached over
  TCP with no mounted socket or pipe, and containers Docker Desktop hides from `docker ps`), and which
  nothing checks between or after those runs or outside Procedure B. A further residual: the revoke
  after a second-run search throw runs `wow-admin` from a folder a container could reach, and counts
  as a failed revoke, whose hour bounds only how long the tokens this run minted live, not what the
  mint uses, any change such a token made within the hour, or anything such a `wow-admin`, run as
  the owner on the host, did with what the owner's user can reach.
- **A loopback `appPort` is reachable from other containers and from WSL.** The template proof
  shows a port is published on `127.0.0.1` and nowhere else, and that keeps it off the network.
  It does not keep it away from other containers on the same host. On the owner's Windows host
  (2026-11-03, #457), a port published as `127.0.0.1:<p>:<c>` from the dev-App image was reached:
  - **from a second container through `host.docker.internal:<p>`**, on the default bridge and on
    a user-defined network;
  - **from the Ubuntu WSL distro on its own `127.0.0.1:<p>`**, because Docker Desktop's WSL
    integration puts the published port inside the distro.

  The host's non-loopback address refused it. The host was Docker Desktop 4.95.0 (Engine 29.8.2)
  and WSL 2.7.8.0 in `nat` mode, with WSL integration on. So treat a dev-App `appPort` as open to
  every container on that Docker Desktop and every integrated distro. Whatever listens on it must
  authenticate its callers, or serve nothing that a co-tenant container should not see. Not
  measured: Enhanced Container Isolation, WSL `mirrored` networking, and a distro with WSL
  integration turned off.
- **A PR can downgrade its own verifier pin.** `verify / verify` runs the verifier the PR's own
  caller names, so a PR may pin an older release, or one that predates dev-App mode and reads the
  repo as plain. In a dev-App repo what holds it is the approval rule and the dev App's lack of the
  Workflows permission, not a gate rule. Plain pins below v1.6 also have no mount rules.
- **A host run of a branch's code reaches the token directories.** WSL is not a working
  environment for this repo (see Exceptions), but any host-side run, in a Windows shell or a WSL
  distro, of a branch's code (test scripts, the npm-installed devcontainer CLI) reaches the host
  Docker daemon and `%USERPROFILE%` (`/mnt/c/Users/...` from WSL), so it can read every repo's
  `dev-token` and mount any repo's `-home` volume. The Exceptions residual applies: use a checkout
  no container mounts, at a commit whose diff has been reviewed.
- **A `CLAUDE.md` whose path starts with no `code_paths` entry is not gated (#607).** `code_paths`
  entries are plain path prefixes: the gate in `.github/workflows/review-gate.yml` matches with
  `startswith` and rejects an entry with a glob character. So an entry can name one exact file or a
  directory, but cannot match the file name `CLAUDE.md` in every directory, including one that does not
  exist yet. A `CLAUDE.md` added at a path that starts with no entry merges without the architect
  review. It then loads into a session started above it when the session reads files in that directory.
  A `CLAUDE.md` can also import other files with `@` paths, and an imported file is instruction text
  even when the importing file is gated. The owner's approval under `main-approval` is still required
  on every PR. A `CLAUDE.md` under a listed directory (under `images/` or `tools/`, say) is gated like
  any other file there.
- **Host sessions do not check the owner's user scope (#607).** `docs/host-steps.md`'s start text and
  Rule 1 stop on project-level files and leave user scope outside those stops: the owner's user-level
  Claude folder and config file (or where `CLAUDE_CONFIG_DIR` puts them), the claude.ai account's
  connectors, managed settings, and the options and environment the owner starts `claude` with. So
  whatever the owner has set there (a user-level `CLAUDE.md`, a hook, a plugin, an MCP server or
  connector, a status line, a helper command, an `env` setting, a permission mode) is in force in a host
  session, and some of those run code on the host, or change how commands run, beside the Docker daemon.
  No Claude session takes part in Procedure B or reads the elevated token; the containers' sessions keep
  running throughout, the identity home being outside their mounts (the Exception above); Procedure B's
  block checks this with its reader search at its two points, within the limits `docs/host-steps.md`
  names.
  `docs/host-steps.md` step 2.5 says no Procedure A host session runs while any admin token may be
  live, which is from any mint command until the revoke that follows it, and, when that revoke is
  failed (or any revoke is failed), through the hour after it; nothing checks this. That rule names
  Procedure A host sessions only: any other host Claude session is a host process under
  `docs/host-steps.md`'s Known limits host-process bullet, the owner's rule that nothing running
  untrusted code runs on the host while any admin token may be live, and nothing checks that either.
  Container code can reach the host's user-level folder and
  config file at least through the paths the new *Untrusted inputs* row names. A check of user scope
  for host sessions is left to a separate issue.
- **Volume names collide across orgs.** Per-repo volumes are named after the checkout folder, so
  same-named checkouts of different repos share `-home`, and with it a Claude login and sessions
  (the dev token is per repo and mounted from the host, so it is not shared). `owner-check.sh`
  detects this after the fact and cannot prevent it.

- **No ruleset covers a tag named `main`, and a run on one at an old commit of `main` publishes (#383).**
  `release-tags` covers only `refs/tags/v*` and `refs/tags/devc-automerge-*` (the `ref_patterns`
  in `.ai/project.yml`), and the branch rulesets cover only the `main` branch, so none of this
  repo's three rulesets stops a tag named `main`. A writer can push such a tag at a commit of
  `main`'s history older than b4a490b and dispatch `build.yml` on it. The run uses that commit's
  own historical `build.yml`, whose publish job has no ref guard: at b4a490b's parent it runs
  whenever the event is not `pull_request`. It builds from that commit's sources and pushes to
  the same GHCR packages the current workflow publishes, `devcontainer-base`, `devcontainer-tofu`
  and `devcontainer-node` there (the devapp flavours came later), under the `REGISTRY` that file
  sets, tagged `<MAJOR>.<run number>` with that commit's own `MAJOR`, and that file's smoke tests and Trivy gate
  still run before each push, so such a run may publish only some images or none. Nothing here
  claims which existing tags it overwrites. Those images carry no provenance signed for
  `refs/heads/main` (the run's ref is `refs/tags/main`), so the consumer-side verify of
  [Boundary 3](#boundaries-meant-to-hold), which pins the signer identity and source ref to
  `refs/heads/main`, refuses them wherever it runs: on every new digest in a repo that has adopted
  #30's workflows (the gap above on verifying a new digest is the limit), and only when a human
  runs it elsewhere. That verify is the control of record; this gap is a case of the writer-dispatch
  path Boundary 3 already accepts for the `if:` guard. It qualifies two statements, which hold
  for the `build.yml` on `main` today and not for a historical copy run on a tag: Boundary 3's
  "`build.yml` publishes only from `main`", and the Sinks row for `ghcr.io/603-identity/devcontainer-*`
  that lists manual dispatch on `main`.
  A tag at a commit of `main`'s history from b4a490b on publishes nothing: every such copy of
  `build.yml` keeps `publish` off any ref but `refs/heads/main`, through `publish`'s own `if:` at
  b4a490b, through its `needs` on the ref-guarded `scope` job from ff9539f, and through its own `if:`
  again from 9d38b76. A tag at a commit outside `main`'s history carries whatever `build.yml` that
  commit has, which is Boundary 3's existing edited-copy case, not a new one.
  The route needs two capabilities: creating a tag outside the protected patterns, and dispatching
  `build.yml`. Any human account with write access holds both, which for a human writer is the same
  reach as editing a workflow directly: defence in depth, not an outsider path. Whether any App
  token on this repo holds both is not verified (the [Credential holders](#credential-holders)
  table records that the bump-binaries App can create tags outside the protected patterns, and that
  the dev token lacks the Workflows permission). The effect on the scope lookup stays bounded as the
  `GITHUB_TOKEN` row with `actions: read` there already says: the commit must be an ancestor of
  HEAD, so a successful publish job from such a run only widens the next diff and so builds.
  The remedy not taken is extending `release-tags`, or adding a tag ruleset, to restrict creating
  a tag named `main` (and possibly any tag that shadows a branch name). That is a live ruleset edit
  by an admin identity (the owner's admin login, or `603id-admin[bot]` with Administration write),
  which no lane makes; it is left to the owner (#383).
