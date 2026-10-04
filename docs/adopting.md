# Adopting the devcontainer template in a repo

One ordered procedure for moving a repo onto the shared images. It is built from what the two
pilots did (terraform-cloudflare-dns and terraform-microsoft365-entra, #10) and it is the
procedure the waves follow (#26, #27, #28). Each step says what to do and in what order, and
links the README section that holds the detail and the reason.

The adoption PR is one PR per repo. Never merge your own adoption PR: the review gate, and the
repo owner, do that. Ruleset edits and pushes to `.github/workflows/` come from the **host**
login, never from the container token.

## 0. Before you start

- **Host.** VS Code with the Dev Containers extension (no other editor is supported). On a
  Linux host your uid must be 1000. `~/.gitconfig.d/` must exist and hold one
  `<anything>.gitconfig` that lists this repo's org (see [Git
  identity](../README.md#git-identity)). The host `gpg-agent` cache should cover a working day
  (see [Host signing policy](../README.md#host-signing-policy), #5).
- **The checkout folder name** must be unique across every checkout on the host, in every org
  ([Consuming from another org](../README.md#consuming-from-another-org), step 3). If it is
  not, rename it first. Every volume below is named after that folder, not the repo.
- **A token.** The container gets a per-repo fine-grained token with no Workflows permission
  ([Credentials](../README.md#credentials), #6). Create it now and record its name, scope
  and expiry (never the value) in the org's credential ledger.
- **Is the repo on the exceptions list?** If it is in
  [Exceptions](threat_model.md#exceptions), stop: it gets no container.
- **Does the repo need Dev Container Features, or a second `devcontainer.json`?** Then it
  cannot adopt the template as it stands; `verify / verify` rejects both
  ([What the consuming repo needs](../README.md#what-the-consuming-repo-needs)). Raise it on the
  wave issue.
- **Did the repo have the template's earlier layout** (`<folder>-gh` and `<folder>-claude`
  volumes)? Note their names; step 6 migrates them.

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

## 2. Copy the template and pick the image

First, with step 1 done, note the ruleset's current approval count and the repo's "Allow
auto-merge" setting in the adoption PR description (not the whole ruleset JSON, which lists
bypass actors). Step 9 changes both, and a rollback restores those two values.

1. Copy [`template/.devcontainer/`](../template/.devcontainer/) into the repo unchanged.
2. Set `FROM` in its `Dockerfile` to one image, by tag **and** digest, both taken from the
   latest *Build images* run summary (a first-attempt run, not a re-run).
3. Run `gh attestation verify` on that digest before relying on CI to do it: the command is in
   [Using an image in a repo](../README.md#using-an-image-in-a-repo), step 2.
4. Delete the dependency-volume lines the repo does not use (`node_modules`, `.venv`) and the
   trailing comma on the last mount. Leave the `--read-only` and tmpfs `runArgs`, the `init`
   line and the home volume alone.

## 3. Match the toolchain pins to CI

The image's OpenTofu and Node versions are the ones the repo's workflows must pin
([Toolchain versions must match CI](../README.md#toolchain-versions-must-match-ci), #98). In
**this same PR**, set `tofu_version` in every `setup-opentofu` step to the image's
`TOFU_VERSION`, and a Node repo's setup-node pin to the image's `NODE_VERSION` (the image's npm
is ahead of CI's, #27). Read what the new version changes before moving a pin.

## 4. Repo housekeeping in the same PR

From [step 4 of Using an image in a repo](../README.md#using-an-image-in-a-repo):

- `.gitattributes` forces LF (`* text=auto eol=lf`, or at least `.devcontainer/** text eol=lf`).
  An existing Windows checkout stays CRLF until re-checked-out (see [Checking a
  container](../README.md#checking-a-container)).
- Tofu repos: ignore `.terraform-devcontainer/`.
- Do not commit the `.terraform.lock.hcl` change `tofu init` makes in the container, unless it
  is the deliberate `linux_amd64` hash, as its own reviewed change.

## 5. Wire up CI

From [step 3 of Using an image in a repo](../README.md#using-an-image-in-a-repo) and [What the
consuming repo needs](../README.md#what-the-consuming-repo-needs):

1. Copy [`devcontainer-image.yml`](../template/.github/workflows/devcontainer-image.yml)
   unchanged (it is the check `verify / verify`).
2. Copy [`architect-review-gate.yml`](../template/.github/workflows/architect-review-gate.yml)
   and edit only its marked per-consumer values. **Choose `code_paths` knowing that anything
   outside it is guarded only by the two secret scans.**
3. `secret-scan.yml` is already in place from step 1; do not add it here.
4. Add `.devcontainer` under the `docker` ecosystem in `.github/dependabot.yml` (the
   `github-actions` ecosystem was configured in step 1).
5. Run `tools/check-consumer-workflows.sh` from a checkout of this repo against the repo's
   `.github/workflows`. Nothing re-runs it later, so do it now.
6. Private repos: apply the push ruleset that blocks secret-bearing files, and record each
   exception in the PR.

## 6. Migrate the old volumes, if the repo had the old layout

Skip this if the repo had no container from the template before. Otherwise run the copy in
[Migrating from the old layout](../README.md#disk-speed-and-volumes) now: with the container
stopped, before the first start on the new layout, using the image from step 2. **Keep the old
volumes** until the first bump has merged (step 10): a rollback needs them. The old credential
may predate the per-repo model and carry more reach (Workflows, or other repos), so step 7 still
stores the new token over it. Once the adoption has settled, revoke the old token and update the
ledger.

## 7. Open the PR and check the container

Open the PR from the host login. Then, with the PR branch checked out, run **Dev Containers:
Open Folder in Container** from PowerShell, cmd or the Start menu (not Git Bash, not *Clone
Repository in Container Volume*). Store the repo's new token once, without echoing it
([Credentials](../README.md#credentials)), and confirm in GitHub settings that it has no
Workflows permission. `gh auth status` must list exactly one account: a migrated `hosts.yml`
can keep the old token as an inactive account, so `gh auth logout` any other. Then prove the container, using [Checking a
container](../README.md#checking-a-container):

- no capabilities, `NoNewPrivs: 1`, user `app`, read-only root filesystem;
- `docker diff` shows only `A /vscode`, `C /usr/sbin` and `A /usr/sbin/docker-init`;
- `/home/app` is owned by `app` and the volumes survive a rebuild (`/tmp` is root-owned, mode
  1777: that is normal);
- a signed commit works, with the passphrase prompt on the host;
- the repo's own gate runs in the container with CI's tool versions: for a tofu repo,
  `tofu init`, then `tofu test -filter=<mocked file>`, then restore the lock;
- the container token cannot do admin work: `branches/main/protection` returns 403;
- the PR's `verify / verify` is green. To see it go red, push a wrong digest on a throwaway PR,
  not the adoption PR.

## 8. Merge the adoption PR

The repo owner merges it, once `architect-review`, `verify / verify` and `secrets / scan` have
all reported green on it. If the repo had no gate on its default branch before, post the
review on this PR as a formal PR review, not a comment: a comment runs the default branch's
copy of the gate, which does not exist yet. Until step 9 nothing requires `verify / verify`
(unless the repo already did), so other PRs are not blocked. Do step 9 straight away, and merge no Dependabot image bump before it is done.

## 9. Require the checks, and set the repo settings

The callers must be on the default branch first (step 8), or every PR is blocked by a check
that never reports. From the host login, in the ruleset: require `architect-review` and
`verify / verify`, each with `integration_id: 15368` (`secrets / scan` has been required since
step 1), with an approval count of 0, as one ruleset update so the approvals never drop before the
checks are required. Read the ruleset back through the API and attach the
result to a comment on the merged PR. Only then turn "Allow auto-merge" on in the repo
settings. Private repos: "Send write tokens to workflows from fork pull requests" stays off.

## 10. Watch the first bump

The first Dependabot image bump is the real test. It needs a review and a human merge (the
repo setting from step 9 is on, but no bump auto-merges until the kill-switch tag exists,
#30), and the repo moves its `tofu_version` pin in that same PR. When it has merged, remove
the old volumes from step 6.

## Rollback

If adoption fails, or the container proves unusable, return to the previous setup. This rolls
back the **container** only. Keep `secret-scan.yml`, the required `secrets / scan`, Dependabot's
`github-actions` ecosystem and the private-repo push ruleset: the org scan does not depend on
the container, and the old scanner is not coming back. If the adoption PR never merged, close
it, keep the old volumes, and skip Rollback steps 2 and 3.

1. **Stop using the container.** Close VS Code's window on the repo. If the repo had the old
   layout, keep its old volumes (`<folder>-gh`, `<folder>-claude`): the migration copied them,
   it did not move them.
2. **Revert the container files** in a PR from the host login (it changes
   `.github/workflows/`): `.devcontainer/` back to what it was or removed,
   `devcontainer-image.yml`, the gate only if the repo did not have one before, the `docker`
   Dependabot entry and the toolchain pin move. A revert keeps history; do not force-push.
3. **Ask the owner to merge it.** Just before the merge, from the host login, turn "Allow
   auto-merge" off. Then, in one ruleset update, drop `verify / verify` from the required
   checks (and `architect-review` too if the repo did not require it before), or the revert PR
   can never go green, and restore the step 2 approval count. Close any open Dependabot
   `docker` bump first, so none merges unverified in that window. After the merge, restore the
   step 2 auto-merge value.
4. **Rebuild** the container from the restored `.devcontainer/` if there is one. If the old
   volumes were already removed, it starts with no credential: store the repo's token again with
   `read -rs T && printf '%s' "$T" | gh auth login --with-token; unset T`.
5. **Remove the new volumes** once the old setup works. List them first with `docker volume ls
   --filter name=<folder>-`, then remove only this checkout's. If the repo had the old
   layout, remove only `<folder>-home`: the old template mounted the same `-tmp`,
   `-node_modules` and `-venv` names, and the restored container is using them. Otherwise
   remove `-home`, `-tmp` and whichever dependency volumes the listing shows. The folder is the checkout directory's name, which may differ from the
   repo's: another checkout's volumes use the same pattern. `<folder>-home` holds the Claude sessions made since adoption,
   and they are lost with it; the old `<folder>-claude` volume only has those from before.
6. **Revoke the token** in GitHub settings and update the credential ledger, unless the
   restored setup reuses it.
7. **Tell the wave issue** what failed, so the template or the README changes before the next
   repo hits it.
