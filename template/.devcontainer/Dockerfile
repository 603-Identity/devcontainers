# syntax=docker/dockerfile:1.28@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
#
# This repo's dev-App devcontainer (DEVC-D9): one published shared image, pinned by tag AND
# digest, plus this repo's own extras (if any) between the FROM and the final USER line.
# A Dependabot docker bump of the FROM line is checked by `verify / verify` like any other
# change, and `decide` never auto-merges it for a dev-App repo: a human approves it.
#
# Choose ONE image: devcontainer-devapp (no OpenTofu) or devcontainer-devapp-tofu. Take the
# tag@digest from the latest "Build images" run summary in 603-Identity/devcontainers.
#
# Every pull request is checked by `verify / verify` (.github/workflows/devcontainer-image.yml).
# In dev-App mode the FROM line must be one of the two images above, by tag and digest, with
# signed provenance and an SBOM from that repo's build.yml on main, and its MINOR may not be
# below the base branch's. The file must keep this shape or the check fails:
#   - the `# syntax=` line above, unchanged, and no other directive;
#   - ASCII only, no CR (LF line endings), no NUL, no BOM, and at most 1 MiB;
#   - one stage only: no second FROM, no ARG before FROM, no `$` in the image reference;
#   - a plain FROM: no `AS <name>` and no `--platform`;
#   - no `COPY --from`, `RUN --mount from=` or ONBUILD, and no `LABEL devcontainer.metadata`;
#   - the file ends with `USER 1000:1000`; everything between the FROM and it is this repo's
#     extras. The extras may COPY files from this directory (regular files only, at most 64 of
#     at most 1 MiB each) and may not ADD a local file;
#   - the extras may not write the identity layer (/run/wow, /usr/local/libexec,
#     /usr/local/bin/gh and claude, /etc/gitconfig, /etc/claude-code, /usr/local/share/devc),
#     set GIT_*, HTTP_PROXY, HTTPS_PROXY or ANTHROPIC_BASE_URL, or run `git config --system`.
#     That list catches accidents, not attacks: a human reviews the extras.
# devcontainer.json is held to the same template exactly (see its header), no other
# devcontainer.json may exist anywhere in the repo, and the default branch must require an
# approval and a code-owner review. Do not bypass any of it: it is what makes a new digest safe
# to take. It also accepts only an image from a first-attempt `build.yml` run (a re-run's
# digest fails), which the command below does not check, so a digest that passes it can still
# fail the PR. For a first look by hand, for the digest on the FROM line:
#   gh attestation verify oci://ghcr.io/603-identity/devcontainer-devapp-tofu@sha256:<digest> \
#     --repo 603-Identity/devcontainers \
#     --cert-identity https://github.com/603-Identity/devcontainers/.github/workflows/build.yml@refs/heads/main \
#     --cert-oidc-issuer https://token.actions.githubusercontent.com \
#     --source-ref refs/heads/main --deny-self-hosted-runners
FROM ghcr.io/603-identity/devcontainer-devapp-tofu:TAG@sha256:DIGEST

# The mount points for the home and dependency volumes in devcontainer.json are
# pre-created app-owned in the shared images, so there is nothing to add here for them.
# The container's root filesystem is read-only at run time (devcontainer.json runArgs):
# install anything extra in this Dockerfile, not in a running container. Install it outside
# /home/app: the home volume copies the image's /home/app once, at first mount, so an
# install there never reaches an existing volume, and a root install that writes there
# (npm's cache, ~/.local) leaves it root-owned and breaks the app user. As root, send
# caches elsewhere, for example (this one assumes a node toolchain you installed yourself; a
# package that downloads a browser also needs PUPPETEER_CACHE_DIR=/tmp/... as root):
#   USER 0
#   RUN npm install -g --prefix /usr/local --cache /tmp/npm-cache <pkg>@<ver> \
#       && rm -rf /tmp/npm-cache
#   USER 1000:1000
# Repo-specific extras go here, following the same rules as the shared images:
# version plus sha256 from the upstream checksum file, never trust-on-first-use.

USER 1000:1000
