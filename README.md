# 603-Identity devcontainers

These are the shared devcontainer images for 603-Identity and glunk-works repositories. Every repo gets its
**own container**, built from **shared, digest-pinned images**. Isolation between repos
costs almost no disk, because the image layers are stored once per machine.

| Image | Contents |
|---|---|
| `ghcr.io/603-identity/devcontainer-base` | Ubuntu, non-root `app` (uid 1000), git, gh, jq, yq, Python (system), uv, pre-commit, bc-detect-secrets, betterleaks, zizmor |
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
   - Copy [`secret-scan.yml`](template/.github/workflows/secret-scan.yml) too, unchanged: it
     runs the org secret scan as the check `secrets / scan`. Follow [Secret
     scanning](#secret-scanning-190), which sets the order for requiring it.
   - Add `.devcontainer` to `.github/dependabot.yml` under the `docker` ecosystem, and
     configure the `github-actions` ecosystem too. Image bumps and verify-pin bumps then
     arrive as pull requests. **Dependabot's image bump is not exempt from review**: a human
     merges it (auto-merge is off, see below).
   - Run `tools/check-consumer-workflows.sh` from a checkout of this repo, against the
     consuming repo's `.github/workflows`, before opening the adoption PR.
4. Delete the dependency-volume lines the repo doesn't use (`node_modules`, `.venv`), and the
   trailing comma left on the last remaining mount.
   Leave the `--read-only` and tmpfs `runArgs`, the `init` line and the home volume alone.
   Then the repo-side housekeeping the pilot of terraform-cloudflare-dns turned up:
   - **Force LF checkouts.** On a Windows host with `core.autocrlf=true`, every file in the
     bind mount is CRLF, so the container's git (no `autocrlf`) reports the whole tree as
     modified and a gate that reads the git index fails (detect-secrets: "baseline file is
     unstaged"). Add `* text=auto eol=lf` to `.gitattributes` (this repo does), or at least
     `.devcontainer/** text eol=lf`, which `verify / verify` needs anyway (it rejects CR).
   - **Ignore `.terraform-devcontainer/`** in tofu repos. The tofu image sets
     `TF_DATA_DIR=.terraform-devcontainer` so the container's `tofu init` stays apart from
     the host's `.terraform`, and it lands untracked in the workspace.
   - **detect-secrets will flag the digests** (the org's Betterleaks scan does not, so a repo
     on `secrets / scan` skips this). The two pinned digests (the `# syntax=` line
     and the `FROM` line) read as `Hex High Entropy String` to detect-secrets. Allowlist them
     in the scanner's baseline (the inline `pragma: allowlist secret` form would break the
     Dockerfile shape `verify / verify` enforces), keeping the baseline in the version the
     repo's CI pins: the image's own `detect-secrets` can be newer than that pin, and a
     baseline it rewrites is rejected by the older one. The baseline entries carry line
     numbers, so a bump that moves those lines needs the entries moved too.
   - **`tofu init` in the container rewrites the lock file** (it adds the `linux_amd64` hash
     and its header comment). Commit that as its own change or discard it; do not let it
     ride along in the adoption PR.
5. Open the repo's checkout with **Dev Containers: Open Folder in Container**, started from
   PowerShell, cmd or the Start menu (not Git Bash). Do not use *Clone Repository in
   Container Volume*: the template bind-mounts the host checkout, and a clone of a branch
   without `.devcontainer/` just offers VS Code's own template picker. Then store the repo's
   GitHub credential once, without echoing it into the terminal (see
   [Credentials](#credentials)):
   ```sh
   read -rs T && printf '%s' "$T" | gh auth login --with-token; unset T
   ```

### Checking a container

What a healthy container looks like (from the terraform-cloudflare-dns pilot):

- `grep -E 'CapEff|NoNewPrivs' /proc/self/status` prints `CapEff: 0000000000000000` and
  `NoNewPrivs: 1`; `id -un` is `app`; `touch /usr/local/x` fails with "Read-only file system".
- `/home/app` and `/home/app/.cache/tofu-plugins` are owned by `app`. `/tmp` is the volume's
  root-owned directory, mode 1777, which is normal: `app` writes there through the sticky bit.
- **`docker diff` is not literally empty.** Expect exactly `A /vscode` (the mount point VS Code
  creates for its server) and `C /usr/sbin`, `A /usr/sbin/docker-init` (the init binary Docker
  injects for `"init": true`). Anything else is a write the container should not be making,
  and it stayed that way after a full working session (editor, git, tofu, tflint, pre-commit,
  Claude Code, `gh`).
- Commit signing goes through VS Code's forwarded agent: the passphrase prompt appears on the
  host. Inside the container `git log --show-signature` prints "Can't check signature: No
  public key" in red even when the signature was made; that only means the container's
  keyring lacks your public key. Check with `git log --format=%G?` on the host (`G` is good).
- **`tofu init` dirties the tree.** It adds a `linux_amd64` hash and its own header comment to
  `.terraform.lock.hcl`, and the image's `detect-secrets` then rewrites `.secrets.baseline` to
  its own, newer version, which the repo's pinned CI version rejects. Before committing, run
  `git checkout -- .terraform.lock.hcl .secrets.baseline`. A lock committed without the
  `linux_amd64` hash makes `tofu validate` and `tofu test` fail until `tofu init` has run;
  record the Linux hash in the repo's lock (`tofu providers lock -platform=linux_amd64 ...`)
  as its own reviewed change.

### What the consuming repo needs

[`devcontainer-image.yml`](template/.github/workflows/devcontainer-image.yml) and the
[gate](template/.github/workflows/architect-review-gate.yml) only mean something with these
in place. `tools/check-consumer-workflows.sh` lints the workflow shapes named below (the caller, write
permissions, `uses:` in the gate's `resolve` and `post`, the `.github/` rule, the pin shapes). It runs
when you run it, at adoption and from the pilots; nothing re-runs it in the repo's CI. The rest is
settings the adoption PR records, and review.

- **Required checks, pinned.** The ruleset requires `architect-review`, `verify / verify` and,
  once the repo has adopted [secret scanning](#secret-scanning-190), `secrets / scan`,
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
- **Private repos: the push ruleset that blocks secret-bearing files.** Apply
  [`rulesets/block-secret-bearing-files.json`](rulesets/block-secret-bearing-files.json) with
  `gh api -X POST repos/<org>/<repo>/rulesets --input rulesets/block-secret-bearing-files.json`.
  GitHub then rejects, server-side, any push containing a `*.tfstate*`, `*.tfvars` or
  `*.tfvars.json` file (`*.example.tfvars` and `*.example.tfvars.json` are exempt) or a `.pfx`,
  `.p12`, `.pem` or `.key` file. `git push --no-verify` doesn't get past it, the owner gets no
  bypass, and every commit in the push is checked, so a file added and then deleted is still
  rejected. Rulesets are set per repo (organisation-level rulesets need Enterprise), and they
  check new pushes only, so files already in history are left to the CI secret scan (#190).
  Before applying it, list the repo's tracked files that match and decide each exception: a
  fixture that must stay goes in that repo's `ignored_file_paths`, recorded in the adoption PR.
  Tested on the Team plan in #192. GitHub offers push rulesets for private repos only.
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

### Secret scanning (#190)

Every 603 repo is scanned for committed secrets on every pull request by
[Betterleaks](https://github.com/betterleaks/betterleaks), through a reusable workflow in this repo.
This repo owns the scanner version and the org rule set; a consuming repo owns almost nothing.
It replaces the per-repo bc-detect-secrets baseline (which ties every repo to one exact version).
The design, the fail-open cases it closes and the acceptance results are in #190; the trust
model is in [`docs/threat_model.md`](docs/threat_model.md#org-secret-scanning-190).

**What the check does.** `secrets / scan` scans the **full history** of the PR head (merge
commits included, `-diff` attributes ignored), with `images/base/files/secret-scan/org.toml` and the scanner pinned
by the `BETTERLEAKS_*` ARGs in `images/base/Dockerfile`, both read at the commit your caller pins.
It reads the repo's `betterleaks.toml` and `.betterleaksignore` from the PR's **base** commit,
never the PR's own, so a PR cannot switch off its own scan. A scan that errors or does not
complete is red, never green. `betterleaks:allow` comments and credential validation are off.

**A red `secrets / scan` means rotate the secret.** Never rewrite history and re-push: the
commit is already visible to everything that fetched it. The finding names the rule, file and
line, not the value.

#### Adopting it in a repo

Do these in order, so the repo is never covered by neither scanner:

1. **Run the one-off full-history scan first**, before any allowlist exists, from a checkout
   with every ref fetched (`git fetch origin '+refs/pull/*/head:refs/remotes/origin/pull/*'`).
   `org.toml` is in this repo at the commit you will pin:
   ```sh
   betterleaks git . -c <path to org.toml> --ignore-file /dev/null --no-allow-signatures \
     --redact --jsonl --log-opts="-m --text --all" > scan.jsonl
   jq -c 'select(.scan).scan.state' scan.jsonl     # must print "complete"
   jq -c 'select(.finding).finding | {rule_id, path: .location.path, line: .location.start_line}' scan.jsonl
   ```
   Rotate anything real. A scan that does not say `"complete"` proves nothing: run it again.
2. **Add the ignore file for reviewed false positives only.** Copy the `fingerprint` of each
   one into `.betterleaksignore` with a comment saying why. A fingerprint is a hash of the secret
   *value*, so the entry suppresses that value everywhere in the repo. A false-positive *shape*
   that recurs gets a rule fix in `images/base/files/secret-scan/org.toml` here instead.
   - A finding from a **path rule** (a committed `*.tfstate`, `*.tfvars`, `*.pem` and so on) has
     no value and cannot be ignored this way. If history really holds a reviewed file, the only
     way to accept it is a commit-bound `filter` on that org rule (`attributes["git.sha"]`),
     reviewed in this repo with a link to the assessment beside each SHA.
3. **Add the caller beside the old scanner.** Copy
   [`template/.github/workflows/secret-scan.yml`](template/.github/workflows/secret-scan.yml)
   unchanged into `.github/workflows/`, and make sure Dependabot's `github-actions` ecosystem
   is configured so the pin is bumped as a reviewed PR. Run `tools/check-consumer-workflows.sh`
   against the repo's `.github/workflows` before opening the PR.
4. **Require the new check, then drop the old one.** Once `secrets / scan` has reported on a
   PR, add it to the ruleset's required checks with `integration_id: 15368`, and read the
   ruleset back through the API to confirm the pin. Then remove the old scanner's required
   context and delete its job, in one PR.

**The cost to know about.** The config is read from the base commit, so a PR that adds its own
false positive is red until the ignore entry (or rule change) is merged first. Merge that as
its own small PR.

**A repo's own `betterleaks.toml`** is optional, and may only `extend` the org config and add
rules whose ids start with `repo-`. `tools/secret-scan-lint.sh` rejects anything else (`useDefault`,
`filter`, `disabledRules`, overriding a rule, unknown keys), because a repo file must not be able
to weaken the org rules.

**Pre-commit hook (a convenience, not the control).** In a repo that uses the shared image,
(the base image ships the binary at `/usr/local/bin/betterleaks`), add this to
`.pre-commit-config.yaml`. The absolute path matters: `~/.local/bin` leads `PATH`.
```yaml
default_install_hook_types: [pre-commit]
repos:
  - repo: local
    hooks:
      - id: betterleaks
        name: betterleaks (staged changes)
        language: system
        entry: /usr/local/bin/betterleaks git . --staged -c /usr/local/share/devc/secret-scan/org.toml --ignore-file .betterleaksignore --no-allow-signatures --redact --no-banner
        pass_filenames: false
        always_run: true
```
Hooks can be skipped, and edits made on github.com or outside the container are not scanned
until CI, so CI is what you rely on. To stop an agent skipping the hook to get a commit
through, add `Bash(git commit --no-verify:*)`, `Bash(git commit -n:*)` and
`Bash(git push --no-verify:*)` (and the `PowerShell(...)` forms) to the repo's
`.claude/settings.json` `permissions.deny`, as this repo does for force-push.

### Toolchain versions must match CI

A container that validates with a different tool version than CI reports a result CI
doesn't share. The OpenTofu and Node versions here are the ones every consuming repo's
workflows pin, in every org. **For OpenTofu, the consumer moves the pin**: a consuming repo
changes `tofu_version` in its setup-opentofu step in the same PR that takes the new image
digest, so the two never differ for long. **For Node, bump the image and every repo's
workflow pin together**, never one without the other. The one known exception is npm: the
image ships npm 12 ahead of CI's bundled npm 11 until each repo takes it (#27).

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

A token that covers one repo is created with the resource owner set to the org (the personal
account's picker only offers public or all repositories). A working set for a pilot is Contents,
Issues and Pull requests at read and write, Metadata read-only, and nothing else. Leave out
**Workflows**: with it, anything that reads the token in the container could push a workflow
change. Push `.github/workflows/` changes from the host login instead.

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
- Signing goes through VS Code's forwarded GPG agent. SSH signing is out of scope. See [Host signing policy](#host-signing-policy) for the host cache TTL.

## Host signing policy

Signing uses the passphrase cache of the **host's** gpg-agent, reached through VS Code's
forwarded socket. No image component warms or extends that cache, and nothing in one can raise the host's TTL. When it expires
mid-session, the host agent raises a pinentry prompt on the host, where nobody is watching,
and the container's commit fails with `gpg: signing failed: Timeout`. A retry signs immediately
once the prompt is answered. The cause is a cache shorter than the session, so set it to
cover a working day (8 hours). In the host's `gpg-agent.conf` (Gpg4win:
`%APPDATA%\gnupg\gpg-agent.conf`; elsewhere `~/.gnupg/gpg-agent.conf`):

```
default-cache-ttl 28800
max-cache-ttl 28800
```

Apply it with `gpgconf --reload gpg-agent`, which also clears the cache, so the next
signature prompts once. The cost of fewer prompts: any container attached to the host agent
can sign without a prompt for up to 8 hours (see the identity-selection gap in the
[threat model](docs/threat_model.md)). Re-prompting as a deliberate presence check was considered and declined
(#5).

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
node, npm and betterleaks. **It cannot run for real yet**: it needs a GitHub App that hasn't been
created (docs/threat_model.md's Known gaps). Until that App exists and its secrets are
set, every run fails at the token step, and the fallback below is how to bump a tool.
The workflow resolves each tool's newest release (node: the current LTS line; npm:
the newest release the current node pin supports), takes the sha256 from that release's
own published checksum file (npm: the registry's `integrity` field) -- never from
hashing the download -- and opens one PR per tool that is behind, with the release page
linked in the body (not a diff -- see step 1 below). **betterleaks is the exception on
both counts** (#190): it takes the highest-versioned release *including release candidates*
(it is on 2.0.0-rc.1), and it takes the sha256 only after `cosign verify-blob` accepts the
release's sigstore bundle for `checksums.txt` against the signer identity for that exact tag
(`betterleaks/betterleaks` `release.yml` at `refs/tags/v<version>`, issuer GitHub Actions). A
failed or missing verification fails the job, never falls back. The cosign binary is pinned
by version and sha256 in `bump-binaries.yml`; nothing bumps it, so re-pin it by hand from
its own `cosign_checksums.txt` when you move it. `tests/smoke.sh` reads the expected
version from the same `ARG` lines the workflow rewrites, so there is nothing else to
edit there. (The Python tools are not `ARG`s: they live in
`images/base/tools/pyproject.toml` and `uv.lock`, and Dependabot bumps those on its own
schedule, except bc-detect-secrets: see below.)

A human still has to:

1. Read the linked release notes and the diff since the current tag (not linked -- open
   it yourself from the release page or the tags comparison on GitHub).
2. Check the Dockerfile's own prose for anything tied to the specific version being
   replaced -- the node image's npm-bundled-CVE override block and its "Node X bundles
   npm Y" comments, the tofu image's per-bump CVE/Trivy-count notes and its
   `SHA256SUMS` signature record (repeat the whole check it describes, cosign and the
   grep against the pin, or leave the record naming the version it covers) -- and update or remove what the new version
   makes stale. The workflow only ever touches the `ARG`
   lines themselves.
3. For Node, open the matching CI-pin PRs in every consuming repo. For OpenTofu there is
   nothing to open here: each consumer moves `tofu_version` in the PR that takes the new
   image digest (see "Toolchain versions must match CI").
4. If the Trivy scan now passes without an entry in `.trivyignore.yaml`, delete that
   entry in the same PR.
5. Merge -- the workflow never does.
6. For betterleaks, accepting the bump also means cutting a `vX.Y` tag of this repo on the
   merge commit (see "Secret scanning"): consuming repos' `secrets / scan` pins take the
   scanner version and the org rules from the commit they pin, so the new scanner reaches
   them through the Dependabot pin bump, not before. The image and CI use one version: the
   same `BETTERLEAKS_*` ARGs.

To bump a tool the workflow doesn't cover, or while it's down, do the same by hand: read
the release notes, take the sha256 from the release's own checksum file (never
`sha256sum` a download and paste the result), and change the Dockerfile's `ARG`s.

The `# syntax=docker/dockerfile:...@sha256:...` line on line 1 of all four Dockerfiles is
pinned by digest but no bot bumps it (Dependabot's docker updater reads only `FROM`
lines). Move the four together, taking the digest from `docker buildx imagetools inspect
docker/dockerfile:<tag>`.

Dependabot handles the base image digest, the GitHub Actions pins, and the Python tool lock (`uv` ecosystem on `images/base/tools`). Dependabot
ignores `bc-detect-secrets`, because its version is not "the newest on PyPI": it is the one
[checkov-ledger-action](https://github.com/603-Identity/checkov-ledger-action)'s latest
`vX.Y.Z` tag uses. Checkov pins it exactly, and every 603 repo's `.secrets.baseline` and CI
secret-scan pin follow that release, so a different version on the image's PATH rewrites a
repo's baseline to one its CI rejects. `bump-binaries.yml`'s `sync (bc-detect-secrets)` job
(`.github/scripts/sync-detect-secrets.sh`) reads that tag's `.secrets.baseline` version and
the version its example ledger's `checkov_version` pins on PyPI, fails if the two disagree,
and otherwise opens a `bump/bc-detect-secrets-<version>` PR when the image is behind. The
check runs with the job's read token, so it works before the App exists: a run that finds
drift then fails at the token step, and the failed run is the signal to bump by hand. To bump
by hand, change the pin in `pyproject.toml` and run `uv lock --upgrade-package
bc-detect-secrets` there. Merge the image bump alongside the consuming repos' baseline
regeneration and CI pin (and their ledgers' `checkov_version`).
