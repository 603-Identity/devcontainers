# devc-verify

The verification tool behind `verify-devcontainer-image.yml` and
`devcontainer-bump-decision.yml`. It is pure Go (no cgo, no `unsafe` in our own code),
vendored, and built by the workflows at the caller's pinned SHA before any consumer content
is on disk:

```sh
GOWORK=off GOFLAGS=-mod=vendor GOPROXY=off GOTOOLCHAIN=local CGO_ENABLED=0 go build -trimpath -o devc-verify .
```

## CLI

| Command | What it does |
|---|---|
| `devc-verify files --consumer-dir DIR [--base-dir D --tip-dir D --template-dir T --repo OWNER/REPO]` | The offline rules (below) on `DIR/.devcontainer/`, in the mode the given trees imply, and no other `devcontainer.json` or `.devcontainer.json` anywhere under `DIR` (`DIR/.git` is skipped). On success prints one JSON line: `{"image":"ghcr.io/603-identity/devcontainer-<name>","major":N,"minor":N,"digest":"sha256:...","mode":"plain"}` (`"mode":"dev-app"` in dev-App mode). |
| `devc-verify attest --image <repo>:<MAJOR>.<MINOR>@sha256:<digest>` | Runs `gh attestation verify` twice (provenance, then `--predicate-type https://cyclonedx.org/bom`), binds the signed statement to the image, and checks that the build run's `run_number` (from `gh api`) equals MINOR. |
| `devc-verify verify --consumer-dir DIR --base-dir D --tip-dir D --template-dir T --repo OWNER/REPO --default-branch B` | `files`; in dev-App mode, the approval rule on branch `B` (below); then `attest` on the image `files` found. Every flag is required. |
| `devc-verify decide --consumer-dir DIR --patch FILE --template-dir T --repo OWNER/REPO` | Parses the head Dockerfile and exits 3 for a dev-App `FROM` before reading anything else, then `files`, then the bump predicate on the compare API's `patch` text for `.devcontainer/Dockerfile`, then `attest`. The predicate is: exactly one `-` and one `+` line, both `FROM <base>` with the same image (never a dev-App one), the same MAJOR and a strictly greater MINOR, and the `+` line equal to the base `files` found. The offline checks run first, so a plain "no" needs no network. |

`DIR` is what `tools/fetch-consumer.sh` wrote for the PR head; `--base-dir` and `--tip-dir` are
what `fetch-consumer.sh --mode-only` wrote for the PR base and the default branch's tip. `T` is
the verifier checkout's `template/` (it holds `.devcontainer/devcontainer.json`), and `OWNER/REPO`
is `github.repository`, never a workflow input.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Every check passed. |
| `3` | A check plainly failed (the predicate is false). One line on stderr gives the reason, with PR-derived values quoted (`%q`). |
| any other (`2`) | An error: usage, I/O, `gh` or network failure, unparseable data. Never `3`. |

`gh attestation verify` exits non-zero both for a bad signature and for a network fault and
does not say which, so any failed `gh` call is an error (`2`), not a `3`. Only a bad binding in
an attestation that did verify (wrong `run_number`, attempt 2, wrong repository id, and so on)
is a `3`. The same holds for the approval rule's read: a rule that cannot be read is `2`.

## Rules in brief

Both modes:

- Dockerfile: ASCII only (no BOM, CR or NUL); exactly one parser directive, `# syntax=`, whose
  value is in `AllowedSyntax` (`internal/dockerfile`), and on `PreviousSyntax` (in any spelling of
  the directive) no `<<` in the file or on any instruction's joined line (a heredoc; see
  "Releasing and maintenance"); BuildKit's parser sees one stage, no meta
  `ARG`, no `$` in the base, no `COPY --from`, `RUN --mount from=` or `ONBUILD`, no stage name,
  no `--platform`, and no `LABEL devcontainer.metadata` (the devcontainer CLI merges that label
  into the container's configuration; quotes, escapes and letter case do not hide it, and a
  label key holding `$` is refused); the base matches the spec regex, whose images are `base`,
  `tofu`, `node`, `devapp` and `devapp-tofu`.
- devcontainer.json: hujson; duplicate keys rejected after unescaping; any top-level key that
  lowercases to `image`, `dockerfile`, `context`, `dockercomposefile`, `features` or `build` is
  rejected unless it is exactly `build`; `build` holds only `dockerfile` (`"Dockerfile"`,
  required) and `context` (`"."`).

**The mode** (#418). A repo is in dev-App mode when the PR head, the PR base or the default
branch's tip is dev-App. The base and the tip are read leniently, as the raw bytes of their two
files: any of `devcontainer-devapp`, `glunk-identity` or `/run/wow` makes them dev-App, so a
base with a retired syntax line or bad JSON never wedges the PR that repairs it. The base's
`FROM` MAJOR.MINOR is read from the same bytes (surface 2). A file that
`fetch-consumer.sh --mode-only` did not write is absent from that commit: it writes the
sentinel `_listed` only after an untruncated tree listing, and a tree without it is an error
(red), never "absent". The head is dev-App when its `FROM` is a dev-App image. Its two files are
read for the markers the same way, raw bytes with comments, so a plain `FROM` beside any marker
fails (FROM and mount must agree): a head that passes as plain can never make a later PR's
base dev-App. A dev-App head must then carry the token mount (surface 1). In dev-App mode the
head must itself be dev-App.

**Plain mode** is an allowlist built from the legacy template (`internal/devcontainer/plain.go`;
`testdata/legacy.devcontainer.json` is that template, now kept only for this), #392's cloud-credential guard widened:

- `runArgs` is exactly the legacy five; `workspaceFolder` and `workspaceMount` are exactly the
  legacy strings;
- each mount is a string: one of the legacy mounts, or
  `source=${localWorkspaceFolderBasename}-<[a-z_]+>,target=/<path>,type=volume` and no other key;
- no `${localEnv:`, `${env:` or `${localWorkspaceFolder}` (also with a `:<arg>`) in any key or string (`containerEnv`
  and `remoteEnv` included) outside those exact legacy strings in their own places;
- no `appPort`, `privileged`, `capAdd`, `securityOpt` or `initializeCommand` (any letter case),
  and no object-form mount.

Both pilots' real files pass it (`testdata/pilot.devcontainer.json`).

**Dev-App mode** compares the head with the template, with four per-repo surfaces taken out:

1. **The token mount**,
   `source=${localEnv:USERPROFILE}/.config/glunk-identity/tokens/OWNER/REPO,target=/run/wow,type=bind,readonly`,
   exactly once. `OWNER/REPO` must equal `github.repository`, case-sensitively. Each segment
   matches `[A-Za-z0-9._-]+`, is not `.` or `..`, has no trailing dot and is not a Windows
   reserved name.
2. **The FROM**: `devapp` or `devapp-tofu`, by tag and digest, and not older (MAJOR.MINOR) than
   the base's `FROM`, read leniently.
3. **The extras**: the instructions between `FROM` and a final `USER 1000:1000` (which must be
   the last instruction), plus the files they copy from `.devcontainer/`. `fetch-consumer.sh`
   fetches the regular files there, at most 64 of at most 1 MiB each; anything else marks the
   tree, and dev-App mode rejects the mark. **The filter catches accidents, not attacks**:
   - no `ENV` of `ANTHROPIC_BASE_URL`, `HTTP_PROXY`, `HTTPS_PROXY` or `GIT_*` (any case), and no
     `ENV` key holding `$`;
   - nothing names an identity path (`/run/wow` and `/var/run/wow`, `/usr/local/libexec`,
     `/usr/local/bin/gh`, `/usr/local/bin/claude`, `/etc/gitconfig`, `/etc/claude-code`,
     `/usr/local/share/devc`) or runs `git config --system`: not `RUN` text or a heredoc, not a
     file a `COPY` or a `RUN --mount=type=bind` takes from `.devcontainer/`, and not a
     `WORKDIR`, a `VOLUME` or a path a `COPY` writes (its destination, joined with each copied
     file's name, its path under a copied directory and, for `--parents`, its whole path; a
     `--parents` source holding any `.` segment, a pivot or a leading `./`, is refused). Relative paths resolve from `/workspace`,
     the images' `WORKDIR`;
   - every `COPY` or bind-mount source is a literal path to fetched files, and `ADD` takes URLs
     only (a local `ADD` unpacks archives, which no check here can see into: use `COPY`). A URL
     is checked where it lands, joined with its last path segment when it parses as one.
4. **`appPort`**, optional: a string, or a list of up to 5, each `127.0.0.1:<host>:<container>`
   with both ports in 1024..65535.

Everything else must be, as parsed JSON, equal to either the template at the verifier's pin or
`templates/previous.devcontainer.json`, the previous release's snapshot, which the binary
embeds. A candidate that is not dev-App is never used, so a pin whose template is the legacy one
(any release before v1.6) rejects every dev-App head.

**The approval rule** (#418 owner decision 8; `verify` only, dev-App mode only):
`GET /repos/{repo}/rules/branches/{default}` with the caller's token, every page, must hold a
`pull_request` rule with `required_approving_review_count` of at least 1 and
`require_code_owner_review` true. Rules from org rulesets count. What it does not see: bypass
actors (a host procedure), whether a `CODEOWNERS` file covers the repo (without one,
code-owner review requires nothing), and whether stale approvals are dismissed on push.

## Releasing and maintenance

- `AllowedSyntax` is `{current, previous}`. A test asserts the current value equals the first
  line of `images/*/Dockerfile`, and that the first line of `template/.devcontainer/Dockerfile`
  is one of the two. `tools/check-self-pins.sh` (CI) asserts the template's line is allowed by
  the verifier at the release the template's workflows pin, so bumping the template's
  `# syntax=` without a tool release fails CI (#125). On a bump, move the old current value
  into `PreviousSyntax`, and follow README.md "Cutting a release" for the template.
- The vendored `moby/buildkit` release must be the one that ships the frontend `CurrentSyntax`
  pins; `TestBuildkitMatchesFrontend` asserts the mapping (see the comment there).
  `PreviousSyntax` comes from the release before, and the vendored parser reads it too. That is
  safe only while the delta between the two releases leaves alone the code `Check` runs (#429):
  the parser and instructions packages and the three frontend packages they import, shell,
  command and linter. So at each bump, for the retiring and the new release, run (a blobless
  clone: the compare API lists at most 300 files, and a release delta is larger):

  ```sh
  git clone -q --bare --filter=blob:none https://github.com/moby/buildkit.git bk.git
  git -C bk.git diff --name-only <old> <new> -- frontend/dockerfile/parser \
    frontend/dockerfile/instructions frontend/dockerfile/shell \
    frontend/dockerfile/command frontend/dockerfile/linter | grep -v _test.go
  ```

  Record the output in the bump PR. Empty means the previous pin may stay. A listed file means
  `PreviousSyntax = CurrentSyntax` (fail closed), unless the PR fences the change off with a
  rule under which a file that passes never reaches the changed code in either release. The 1.27 to 1.28 case is the
  example: the one file listed was `shell/lex.go`, which the parser reaches only to lex heredoc
  words on an instruction whose joined line holds `<<`, so a Dockerfile on `PreviousSyntax` may
  not contain `<<`, in its bytes or on any joined line (`PreviousSyntax`'s comment says why). The rule goes when `PreviousSyntax` moves on.
- `templates/previous.devcontainer.json` is rotated per README.md "Cutting a release", and
  `tools/check-self-pins.sh` checks it against the pinned release.
- `testdata/` fixtures are hand-built, not recorded (see `testdata/README.md`), except
  `legacy.devcontainer.json` and `pilot.devcontainer.json`, which are copies.
- The dev-App self-tests read the real `template/` (there is no template fixture): the
  consumer and `main` tests fill it in as a head, and the `internal/devapp` tests hold one
  negative case per surface and per rule, plus what the template must never carry (extensions,
  `containerEnv`, the shared tofu cache, `~/.aws`).

## Re-vendoring

```sh
cd tools/devc-verify && go mod tidy && go mod vendor
```

CI re-runs `go mod vendor` and fails on any diff in `vendor/` or `go.sum`. Run the tests the
way CI does:

```sh
GOFLAGS=-mod=vendor GOPROXY=off GOWORK=off GOTOOLCHAIN=local go test ./...
```
