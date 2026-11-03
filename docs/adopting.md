# Adopting the devcontainer template in a repo

This is the adoption procedure for the **dev-App template** (DEVC-D9, #418): the repo's container
gets a per-repository dev App installation token from the host broker instead of a personal
access token. The legacy PAT route is **frozen** and takes no new adoptions. The two pilots
(terraform-cloudflare-dns and terraform-microsoft365-entra, #10) keep their copies of the legacy
template until their own cutover, and the 603-Identity rows of #26 to #28 wait for 603-Identity's
dev-App cutover. For a repo still on the legacy route, the procedure is the one in this file at
the last commit before the template became dev-App only, [`9af5b4c`](https://github.com/603-Identity/devcontainers/blob/9af5b4c/docs/adopting.md).

One ordered procedure for moving a repo onto the shared images. Each step says what to do and in
what order, and links the README section that holds the detail and the reason.

The adoption PR is one PR per repo. Never merge your own adoption PR: the review gate, and the
repo owner, do that. Ruleset edits and pushes to `.github/workflows/` come from the **host**
login, never from the container.

## 0. Before you start

- **Host: Windows only.** The template reads the host broker's token directory from
  `%USERPROFILE%`, and says so in its header. The repo is opened through the launcher only
  (planned, tracked at glunk-works/claude-workbench#1276). Until it ships, the interim entry is the
  devcontainer CLI from PowerShell: `devcontainer up --skip-post-attach --workspace-folder <absolute path>`, then
  `devcontainer exec --workspace-folder <absolute path> claude`, run from a directory outside the checkout (untested by this repo; the README's "Using an image in a repo" has the
  stop-inspect-`up` rule for a written-to checkout and the secret-free-shell rule). VS Code attach is unsupported in a dev-App
  container. Opening the folder in host VS Code is itself the exposure (see the README's
  "Using an image in a repo"). Open only a fresh clone that no container has run on; a
  checkout a container has written to must be inspected first, without host git or VS Code
  (`.devcontainer/`, `.devcontainer.json`, `.vscode/`, `.git/config`, `.git/hooks`, every nested
  `.git` directory and `.git/modules/*`). `%USERPROFILE%\.gitconfig.d\` must exist and
  hold one `<anything>.gitconfig` that lists this repo's org (see [Git
  identity](../README.md#git-identity)).
- **The host broker must be running for this repo.** It writes
  `%USERPROFILE%\.config\glunk-identity\tokens\<owner>\<repo>\dev-token` (token on line 1,
  `expires_at` on line 2). The broker and the dev App are not part of this repo. Without that
  file the container's `gh` and git refuse, so there is nothing to fall back to: arrange the
  broker and the App installation for this repo first.
- **The checkout folder name** must be unique across every checkout on the host, in every org
  ([Consuming from another org](../README.md#consuming-from-another-org), step 3). If it is
  not, rename it first. Every volume below is named after that folder, not the repo.
- **Is the repo on the exceptions list?** If it is in
  [Exceptions](threat_model.md#exceptions), stop: it gets no container.
- **Does the repo need Dev Container Features, or a second `devcontainer.json`?** Then it
  cannot adopt the template as it stands; `verify / verify` rejects both
  ([What the consuming repo needs](../README.md#what-the-consuming-repo-needs)). Raise it on the
  wave issue.
- **Does the repo currently run the legacy route** (a PAT in its home volume)? Then this is a
  cutover, not a new adoption: it is allowed only for a repo the freeze names, and step 6 says what
  carries over.

## 1. Move secret scanning first, as its own PRs

Do this before the container adoption, so no image digest ever lands under the old scanner (a
detect-secrets baseline allowlists each digest by hash, so any digest it has not seen fails it,
#189). Follow [Secret scanning, Adopting it in a repo](../README.md#adopting-it-in-a-repo), and
keep each of these separate:

1. Run the one-off full-history scan with every ref fetched and `--ignore-file /dev/null`. It
   must end `"complete"`. Rotate anything real.
2. If it found reviewed false positives (or the repo will use the pre-commit hook, which needs
   the file to exist, even with only a comment line), merge `.betterleaksignore` as its own
   small PR. `secrets / scan` reads that file from the PR's **base** commit, so it must already
   be on the default branch before the caller PR.
3. Merge the `secret-scan.yml` caller PR (copied unchanged, with Dependabot's
   `github-actions` ecosystem configured and `tools/check-consumer-workflows.sh` run).
4. Once the caller is merged and `secrets / scan` has reported on a PR opened after that,
   require it from the host login with `integration_id: 15368` and read the ruleset back. Then, if the repo has an old scanner, drop its required context from the
   ruleset **first**, and only then merge the PR that deletes the old job (a deleted job whose
   context is still required leaves the PR waiting forever).

A repo already on `secrets / scan` skips this step.

## 2. The approval ruleset, then the template and the image

**The approval ruleset comes before the dev App is installed** on the repo, and before the
adoption PR can merge: a ruleset on the default branch requiring at least 1 approving review and
code-owner review, a `CODEOWNERS` file, and no bypass actors. `verify / verify` reads the first
two from the API and fails without them; it cannot see bypass actors, a missing `CODEOWNERS`
file or dismissal of stale approvals, so check those by hand. Note the ruleset's current approval
count and the repo's "Allow auto-merge" setting in the adoption PR description (not the whole
ruleset JSON, which lists bypass actors), so a reader can see the adoption lowered neither: step 9
keeps the approval count at 1 or more and leaves auto-merge off.

1. Copy [`template/.devcontainer/`](../template/.devcontainer/) into the repo.
2. Change **only** two things in `devcontainer.json` and the `FROM`. In `devcontainer.json`, replace `OWNER/REPO` in the token mount
   with the repo's `github.repository`, in GitHub's case (`verify / verify` fails any other
   spelling). In the `Dockerfile`, set `FROM` to `devcontainer-devapp` or
   `devcontainer-devapp-tofu`, by tag **and** digest, both taken from the latest *Build images*
   run summary (a first-attempt run, not a re-run). Tools the repo needs go between the `FROM`
   and the final `USER 1000:1000`; a loopback-only `appPort` is the one optional line in
   `devcontainer.json`. Leave the volume mounts the repo does not use (`node_modules`, `.venv`):
   the file is compared with the template exactly, and an unused named volume is empty.
3. Run `gh attestation verify` on that digest before relying on CI to do it: the command is in
   [Using an image in a repo](../README.md#using-an-image-in-a-repo), step 3.

## 3. Match the toolchain pins to CI

The image's OpenTofu and Node versions are the ones the repo's workflows must pin
([Toolchain versions must match CI](../README.md#toolchain-versions-must-match-ci), #98). In
**this same PR**, set `tofu_version` in every `setup-opentofu` step to the image's
`TOFU_VERSION`. The dev-App images are built on base or tofu and carry no Node.js; a repo that
needs it installs it between the `FROM` and the final `USER`, and pins CI to that version. Read
what the new version changes before moving a pin.

## 4. Repo housekeeping in the same PR

From [step 5 of Using an image in a repo](../README.md#using-an-image-in-a-repo):

- `.gitattributes` forces LF (`* text=auto eol=lf`, or at least `.devcontainer/** text eol=lf`).
  An existing Windows checkout stays CRLF until re-checked-out (see [Checking a
  container](../README.md#checking-a-container)).
- Tofu repos: ignore `.terraform-devcontainer/`.
- Do not commit the `.terraform.lock.hcl` change `tofu init` makes in the container, unless it
  is the deliberate `linux_amd64` hash, as its own reviewed change.

## 5. Wire up CI

From [step 4 of Using an image in a repo](../README.md#using-an-image-in-a-repo) and [What the
consuming repo needs](../README.md#what-the-consuming-repo-needs):

1. Copy [`devcontainer-image.yml`](../template/.github/workflows/devcontainer-image.yml)
   unchanged (it is the check `verify / verify`). **This and `secret-scan.yml` are the only two
   workflow files you copy.**
2. **The review gate comes from the way-of-working plugin** (`review.ci_gate`, WB-D37/D38), which
   posts the check `architect-review`, not from a copy of this repo's
   `architect-review-gate.yml`. Do not copy the template gate: `tools/check-consumer-workflows.sh`
   fails a dev-App repo that carries its `resolve`, `decide` or `post` jobs. Set the plugin gate
   up as that plugin documents; its status writer is the one job the lint exempts, and only in
   the plugin gate's shape. Choose `code_paths` knowing that anything outside it is guarded only
   by the two secret scans.
3. `secret-scan.yml` is already in place from step 1; do not add it here.
4. Add `.devcontainer` under the `docker` ecosystem in `.github/dependabot.yml` (the
   `github-actions` ecosystem was configured in step 1).
5. Run `tools/check-consumer-workflows.sh` from a checkout of this repo against the repo's
   `.github/workflows`. It recognises a dev-App repo from the `.devcontainer/` beside `.github/`
   and applies the dev-App profile. Nothing re-runs it later, so do it now. It also needs `git`
   and network access to github.com: it clones this repo's `main` to
   confirm each pinned SHA is on `main`'s first-parent line and that its `# vX.Y` tag points at it
   (a pin to a fork-only commit fails). If it cannot reach GitHub it exits 3 (or 1 when it has findings), which is not a
   pass; `--no-provenance` skips that check offline and also exits 3.
6. Private repos: apply the push ruleset that blocks secret-bearing files, and record each
   exception in the PR.

## 6. Cutting over from the legacy layout, if the repo had it

Skip this for a repo with no earlier container from this template. The dev-App template
mounts the **same per-repo volume names** as the legacy one (`<folder>-home`, `-tmp`,
`-node_modules`, `-venv`), so a cutover reuses them: there are no separate "old" volumes to keep.
What carries over, and what to do about it:

- **The PAT login.** `devapp-check.sh` deletes `hosts.yml` and `.git-credentials` at every start,
  so the dev-App container never uses it, and a rollback must store the PAT again (Rollback step 4).
  Revoke the old token once the adoption has settled and update the credential ledger (#439 tracks
  revoking the broad OAuth token the PAT route replaced).
- **VS Code extensions.** `~/.vscode-server/extensions` in that home volume still holds the legacy
  template's extensions (GitHub pull requests, GitHub Actions, Claude Code), and the VS Code server
  loads them whatever `devcontainer.json` lists. The first two reach the host's GitHub session, the
  broad token #439 exists to revoke; Claude Code's own native `claude` shadows the verified one.
  Remove the whole `~/.vscode-server` directory before the first dev-App start (it also holds the
  machine settings file; the server is downloaded
  again), with the image you just pinned, never an unpinned one:
  `docker run --rm --network none --read-only --user 1000:1000 --entrypoint /usr/bin/rm -v
  <folder>-home:/home/app <FROM image>@sha256:<digest> -rf /home/app/.vscode-server`, then confirm it is gone with the same container shape and
  `--entrypoint /usr/bin/test ... ! -e /home/app/.vscode-server` (a directory a legacy session made
  read-only defeats `rm`; if so, remove the volume). Check the volume name first (`docker volume ls`):
  `docker run -v` quietly creates a volume that does not exist, and the cleanup would then report
  success on an empty stray one. Or remove the
  `<folder>-home` volume and lose its Claude sessions. Also check that the host's
  `dev.containers.defaultExtensions` setting is empty, and do not reopen the legacy template's
  branch in this folder after the cleanup (it reinstalls the extensions).
- **The shared `devc-tofu-plugins` volume** is not mounted by the dev-App template and belongs to
  every legacy container on the host: do not remove it while any of them remains.

## 7. Open the PR and check the container

Open the PR from the host login. Then, with the PR branch checked out (in a fresh clone you reviewed, not by running host git on a checkout a container has written to), start the container from
the launcher (until it ships, `devcontainer up --skip-post-attach --workspace-folder <absolute path>` from PowerShell outside the checkout, then `devcontainer exec --workspace-folder <absolute path> bash`; on a cutover, remove the legacy container first, since `up` restarts it; stop and inspect before any later `up`, per the README). There is no `gh auth login` step. Prove the container, using [Checking a
container](../README.md#checking-a-container):

- no capabilities, `NoNewPrivs: 1`, user `app`, read-only root filesystem;
- `/run/wow` is mounted read-only and holds `dev-token`; `gh auth status` reports a login through
  `GH_TOKEN` (the wrapper's); `gpg` is not on `PATH`;
- `docker diff` shows only `C /usr/sbin` and `A /usr/sbin/docker-init` (an `A /vscode` is the Dev Containers extension's mount, which the CLI entry is expected not to show);
- `/home/app` is owned by `app` and the volumes survive a rebuild (`/tmp` is root-owned, mode
  1777: that is normal);
- `~/.vscode-server` does not exist (step 6 removed it, or the home volume is new; the CLI entry does not create it);
- a commit works and is unsigned (`git log --format=%G?` prints `N`);
- the repo's own gate runs in the container with CI's tool versions: for a tofu repo,
  `tofu init`, then `tofu test -filter=<mocked file>`, then restore the lock;
- the dev token cannot do admin work: `branches/main/protection` returns 403;
- the PR's `verify / verify` is green. To see it go red, push a wrong digest on a throwaway PR,
  not the adoption PR.

## 8. Merge the adoption PR

The repo owner merges it, once `architect-review`, `verify / verify` and `secrets / scan` have
all reported green on it. If the repo had no gate on its default branch before, post the
review on this PR as a formal PR review, not a comment: a comment never counts, and it runs
the default branch's copy of the gate, which does not exist yet. The review must also carry the
line `Reviewed against head <sha>` on a line of its own, where `<sha>` is the PR's full head
SHA as you read it (#278); a review without it does not count. (That passage describes the template gate. A dev-App repo's gate is the plugin's, and its rules are the plugin's to state; the one thing this file adds is that the step 2 ruleset needs a code-owner approval before the merge.) Until step 9 nothing requires `verify / verify`
(unless the repo already did), so other PRs are not blocked. Do step 9 straight away, and merge no Dependabot image bump before it is done.

## 9. Require the checks

The callers must be on the default branch first (step 8), or every PR is blocked by a check
that never reports. From the host login, in the ruleset: require `architect-review` and
`verify / verify`, each with `integration_id: 15368` (`secrets / scan` has been required since
step 1), **keeping the approval count at 1 or more with code-owner review required** (the
step 2 ruleset): a dev-App repo may not use an approval count of 0, and the verifier fails it.
Make the update in one ruleset call. Read the ruleset back through the API and attach the
result to a comment on the merged PR. Do not turn "Allow auto-merge" on for a dev-App repo: no
image bump auto-merges (`decide` exits 3 for a dev-App image, #396). Private repos: "Send write
tokens to workflows from fork pull requests" stays off.

## 10. Watch the first bump

The first Dependabot image bump is the real test. It needs a review and a human merge, and the
repo moves its `tofu_version` pin in that same PR.

## Rollback

If adoption fails, or the container proves unusable, return to the previous setup. This rolls
back the **container** only. Keep `secret-scan.yml`, the required `secrets / scan`, Dependabot's
`github-actions` ecosystem, the private-repo push ruleset **and the approval ruleset from step
2**: none of them depends on the container, and the old scanner is not coming back. If the
adoption PR never merged, close it, keep the repo's volumes, and skip Rollback steps 2 and 3. Step 4 still applies if step 7 started the dev-App container: that start deleted the PAT login from the shared home volume.

1. **Stop using the container.** Stop the container (`docker ps` to find it, then `docker stop` it). Keep the repo's volumes:
   the legacy layout uses the same names, and step 6 explains what the dev-App container already
   removed from them.
2. **Revert the container files** in a PR from the host login (it changes
   `.github/workflows/`): `.devcontainer/` back to what it was or removed,
   `devcontainer-image.yml`, the plugin gate's workflow only if the repo did not have one
   before, the `docker` Dependabot entry and the toolchain pin move. A revert keeps history; do
   not force-push. `verify / verify` refuses a plain head while the PR's base or the default
   branch is dev-App, so the revert PR cannot go green on that check: step 3 drops it from the
   required checks for the merge, and afterwards the base is plain again.
3. **Ask the owner to merge it.** Just before the merge, from the host login, in one ruleset
   update drop `verify / verify` from the required checks (and `architect-review` too if the
   repo did not require it before), or the revert PR can never go green. **Leave the approval
   count and code-owner review as they are.** Close any open Dependabot `docker` bump first, so
   none merges unverified in that window. After the merge, put the `verify / verify` requirement
   back if the repo keeps the caller.
4. **Rebuild** the container from the restored `.devcontainer/` if there is one. A legacy
   container needs the repo's PAT stored again with
   `read -rs T && printf '%s' "$T" | gh auth login --with-token; unset T`; a dev-App container
   needs only the broker's token file.
5. **Volumes.** The legacy layout used the same volume names, so there is nothing new to remove
   when restoring it: do not delete `<folder>-home`, which the restored container is using. Remove
   the volumes (`docker volume ls --filter name=<folder>-`, only this checkout's) only if the repo
   is leaving containers altogether. The folder is the checkout directory's name, which may differ
   from the repo's.
6. **Ask the broker's owner to remove the repo's token directory** and the dev App installation,
   unless the restored setup reuses them. Revoke a legacy PAT in GitHub settings and update the
   credential ledger.
7. **Tell the wave issue** what failed, so the template or the README changes before the next
   repo hits it.
