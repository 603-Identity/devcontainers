# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# This repo's devcontainer: one published shared image, pinned by tag AND digest,
# plus this repo's own extras (if any) below. Dependabot's docker ecosystem bumps the
# FROM line; add this directory to the repo's .github/dependabot.yml:
#
#   - package-ecosystem: docker
#     directory: /.devcontainer
#     schedule: { interval: weekly }
#
# Choose ONE image: devcontainer-base, devcontainer-tofu or devcontainer-node. Take the
# tag@digest from the latest "Build images" run summary in 603-Identity/devcontainers.
#
# Every pull request is checked by `verify / verify` (.github/workflows/devcontainer-image.yml):
# the FROM line must be one of the three images above, by tag and digest, with signed
# provenance and an SBOM from that repo's build.yml on main, and the file must keep this
# shape or the check fails:
#   - the `# syntax=` line above, unchanged, and no other directive;
#   - ASCII only, no CR (LF line endings), no NUL, no BOM, and at most 1 MiB;
#   - one stage only: no second FROM, no ARG before FROM, no `$` in the image reference;
#   - a plain FROM: no `AS <name>` and no `--platform`;
#   - no `COPY --from`, `RUN --mount from=` or ONBUILD.
# devcontainer.json is held to rules too: no top-level `image`, `features`, `dockerComposeFile`,
# `dockerfile` or `context` key (in any letter case), `build` holding only `dockerfile:
# "Dockerfile"` and, optionally, `context: "."`, and no other devcontainer.json anywhere in
# the repo (a symlink or a case-variant path such as dockerfile also fails).
# Do not bypass it: it is what makes a new digest safe to take. It also accepts only an image
# from a first-attempt `build.yml` run (a re-run's digest fails), which the command below does
# not check, so a digest that passes it can still fail the PR. For a first look by hand, for
# the digest on the FROM line:
#   gh attestation verify oci://ghcr.io/603-identity/devcontainer-tofu@sha256:<digest> \
#     --repo 603-Identity/devcontainers \
#     --cert-identity https://github.com/603-Identity/devcontainers/.github/workflows/build.yml@refs/heads/main \
#     --cert-oidc-issuer https://token.actions.githubusercontent.com \
#     --source-ref refs/heads/main --deny-self-hosted-runners
FROM ghcr.io/603-identity/devcontainer-tofu:TAG@sha256:DIGEST

# The mount points for the home, dependency and cache volumes in devcontainer.json are
# pre-created app-owned in the shared images, so there is nothing to add here for them.
# The container's root filesystem is read-only at run time (devcontainer.json runArgs):
# install anything extra in this Dockerfile, not in a running container. Install it outside
# /home/app: the home volume copies the image's /home/app once, at first mount, so an
# install there never reaches an existing volume, and a root install that writes there
# (npm's cache, ~/.local) leaves it root-owned and breaks the app user. As root, send
# caches elsewhere, for example (this one assumes the devcontainer-node image; a package that downloads a
# browser also needs PUPPETEER_CACHE_DIR=/tmp/... as root):
#   USER 0
#   RUN npm install -g --prefix /usr/local --cache /tmp/npm-cache <pkg>@<ver> \
#       && rm -rf /tmp/npm-cache
#   USER 1000:1000
USER 1000:1000

# Repo-specific extras go here, following the same rules as the shared images:
# version plus sha256 from the upstream checksum file, never trust-on-first-use.
