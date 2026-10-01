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
| `devc-verify files --consumer-dir DIR` | Offline rules on `DIR/.devcontainer/Dockerfile` and `devcontainer.json`, and no other `devcontainer.json` or `.devcontainer.json` anywhere under `DIR` (`DIR/.git` is skipped). On success prints one JSON line: `{"image":"ghcr.io/603-identity/devcontainer-<name>","major":N,"minor":N,"digest":"sha256:..."}`. |
| `devc-verify attest --image <repo>:<MAJOR>.<MINOR>@sha256:<digest>` | Runs `gh attestation verify` twice (provenance, then `--predicate-type https://cyclonedx.org/bom`), binds the signed statement to the image, and checks that the build run's `run_number` (from `gh api`) equals MINOR. |
| `devc-verify verify --consumer-dir DIR` | `files`, then `attest` on the image `files` found. |
| `devc-verify decide --consumer-dir DIR --patch FILE` | `files`, then the bump predicate on the compare API's `patch` text for `.devcontainer/Dockerfile`, then `attest`. The predicate is: exactly one `-` and one `+` line, both `FROM <base>` with the same image, the same MAJOR and a strictly greater MINOR, and the `+` line equal to the base `files` found. The offline checks run first, so a plain "no" needs no network. |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Every check passed. |
| `3` | A check plainly failed (the predicate is false). One line on stderr gives the reason, with PR-derived values quoted (`%q`). |
| any other (`2`) | An error: usage, I/O, `gh` or network failure, unparseable data. Never `3`. |

`gh attestation verify` exits non-zero both for a bad signature and for a network fault and
does not say which, so any failed `gh` call is an error (`2`), not a `3`. Only a bad binding in
an attestation that did verify (wrong `run_number`, attempt 2, wrong repository id, and so on)
is a `3`.

## Rules in brief

- Dockerfile: ASCII only (no BOM, CR or NUL); exactly one parser directive, `# syntax=`, whose
  value is in `AllowedSyntax` (`internal/dockerfile`); BuildKit's parser sees one stage, no meta
  `ARG`, no `$` in the base, no `COPY --from`, `RUN --mount from=` or `ONBUILD`, no stage name,
  no `--platform`; the base matches the spec regex.
- devcontainer.json: hujson; duplicate keys rejected after unescaping; any top-level key that
  lowercases to `image`, `dockerfile`, `context`, `dockercomposefile`, `features` or `build` is
  rejected unless it is exactly `build`; `build` holds only `dockerfile` (`"Dockerfile"`,
  required) and `context` (`"."`).

## Releasing and maintenance

- `AllowedSyntax` is `{current, previous}`. A test asserts the current value equals the first
  line of `template/.devcontainer/Dockerfile` and of `images/*/Dockerfile`, so bumping the
  template's `# syntax=` without a tool release fails the tests. On a bump, move the old
  current value into `PreviousSyntax`.
- The `moby/buildkit` release must be the one that ships the frontend the allowed syntax pins;
  `TestBuildkitMatchesFrontend` asserts the mapping (see the comment there).
- `testdata/` fixtures are hand-built, not recorded (see `testdata/README.md`).

## Re-vendoring

```sh
cd tools/devc-verify && go mod tidy && go mod vendor
```

CI re-runs `go mod vendor` and fails on any diff in `vendor/` or `go.sum`. Run the tests the
way CI does:

```sh
GOFLAGS=-mod=vendor GOPROXY=off GOWORK=off GOTOOLCHAIN=local go test ./...
```
