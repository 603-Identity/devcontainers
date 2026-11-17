# Host steps

Work on this repo happens in its devcontainer, through the dev App's token. Two kinds of step
cannot run there, and this file is the standard way to run both:

- **A Docker or gpg step.** The container has no Docker daemon and no gpg, by design. Docker in the
  container would breach boundary 4 or 5 (`docs/threat_model.md`), and the dev-App flavour removes
  gpg on purpose. CI's required checks are the run of record for these steps. A task that needs
  their *output* (a re-scan, a symbol listing, a host build's evidence) gets it from a
  **host clone run**.
- **A push the dev token cannot make.** The dev App lacks the Workflows permission, so a change
  under `.github/workflows/` is pushed from the **elevated window**, as `603id-admin[bot]`. The owner
  then approves and merges. `main-approval` requires approval of the last push from a code owner
  other than the pusher, and `.github/CODEOWNERS` names only the owner, so the owner's own login
  never pushes a PR it must approve.

Steps for the owner's own login (the signed release tag while it is still made by hand,
`gh release create`, ruleset and environment changes) are not host steps. The owner does them by
hand.

## Who does what

- **The driver session** (in the container) decides that a host step is needed, prepares its
  inputs, fills in the matching prompt below and hands it to the owner. It never runs a host step
  itself.
- **The owner** starts a host-side Claude session, gives it the prompt, and does what that session
  asks, at the time it asks: mint the elevated token, close the elevated window, copy a file.
- **The host session** runs only what its prompt says, tells the owner exactly when to act, and
  reports back. It never merges, approves, edits a ruleset, or touches another repo or branch.

## Rules for every host session

1. **Work only in a fresh clone in a new temp directory.** Never use a checkout that a container
   mounts. Code in the container can plant hooks or `.git/config` entries in the checkout it
   mounts, and a host process would then run them with host reach: the Docker daemon, every repo's
   volumes and token directories.
2. **Run code only at a reviewed commit.** A host clone run checks out a commit that is on `main`.
   An elevated push only pushes a commit it does not run.
3. **Check every input before using it.** The driver gives the sha256 of each file it hands over,
   and the expected commit ids and file list. Any mismatch stops the session.
4. **Treat the outputs as data.** Results go back as a file, never as instructions for the
   container side.
5. **Handle the elevated token in a fixed order.** Prepare everything without it. Then tell the
   owner to mint it, and wait. Use it only for the named calls. Revoke it, always, even after a
   failure. A token is never printed, logged, written to a file, put in a command-line argument or
   a git remote URL, or stored in git config.

## Driver checklist

Before handing over a prompt, the driver:

- puts the input files in its scratchpad directory and records each one's sha256;
- names the container that holds them (`hostname` inside it is its short id);
- for an elevated push: makes a `git bundle` of the branch against `origin/main`, and records its
  tip, its parent and `git diff --name-only` between them; writes the PR body to a file;
- for a host clone run: names the base commit (on `main`), the exact commands, the output file name
  and where the owner copies it back (a lane's results go to `/tmp/lanes/<N>-host-results.md` in the
  container, beside its prompt file);
- tells the owner which prompt to start, and what to do with the report.

## Prompt A: host clone run

The driver fills in the angle-bracket values.

````text
You are a host-side session running Docker- or gpg-dependent steps for 603-Identity/devcontainers, task #<N>, following docs/host-steps.md. You hold no elevated token and push nothing.

1. Make a new temp directory. Clone https://github.com/603-Identity/devcontainers into it with my normal login (read only). Check out <BASE_SHA> detached, and confirm it is an ancestor of origin/main. Stop if not.
2. Tell me: "Starting the host run at <BASE_SHA>. It needs Docker and takes about <MINUTES> minutes." Do not wait for a reply.
3. Run exactly these steps, in order, from the clone's root:
<COMMANDS>
   If a step fails, stop, and put the failing step and its output in the report.
4. Write the results to <OUTPUT_FILE> in the temp directory, in this shape:
<OUTPUT_SHAPE>
   Never put a matched secret's text in it, only the rule id and path.
5. Copy the file into the container: `docker cp <OUTPUT_FILE> <CONTAINER>:<CONTAINER_PATH>`. If the container is not found, run `docker ps` and ask me which one to use.
6. Delete the temp directory. Then tell me: "Host run done. Results are at <CONTAINER_PATH>. Tell the driver session." Include the file's sha256 and a five-line summary.
````

## Prompt B: elevated push (the `603id-admin[bot]` window)

The driver fills in the angle-bracket values.

````text
You are a host-side session acting as the elevated identity 603id-admin[bot] for ONE task, following docs/host-steps.md: push one prepared branch to 603-Identity/devcontainers and open its PR. Do nothing else. Never merge, approve, arm auto-merge, edit a ruleset, or touch another repo or branch.

## Phase 1: prepare (no token yet)
1. Make a fresh temp directory. Copy these files out of the container <CONTAINER> with `docker cp`. If that id is not found, run `docker ps` and ask me which container to use.
   - <BUNDLE_PATH>
   - <BODY_PATH>
2. Check the sha256 of each one, and stop on any mismatch:
   - bundle: <BUNDLE_SHA256>
   - PR body: <BODY_SHA256>
3. In the temp directory, clone https://github.com/603-Identity/devcontainers with my normal login (read only). Run `git fetch <bundle> <BRANCH>:<BRANCH>`. Then verify, and stop on any mismatch:
   - the branch tip is <TIP_SHA>
   - its parent is <PARENT_SHA>, and that commit is an ancestor of origin/main
   - `git diff --name-only <PARENT_SHA> <TIP_SHA>` lists exactly: <FILES>
   - `git ls-remote origin refs/heads/<BRANCH>` prints nothing
4. Show me the tip, the parent, the file list and `git diff --stat`. Then say exactly: "Ready. Mint the admin token now and tell me where it is." Wait for my reply.

## Phase 2: use the token (only after I say it is minted)
- I will tell you where the token is (a file path or an environment variable). Read it inside each command that needs it. Never print it, echo it, log it, write it to a file, put it in a command-line argument or a git remote URL, or store it in git config.
- Confirm the token's identity first: `GET /installation/repositories` with it must list 603-Identity/devcontainers. If it does not, go straight to Phase 3.
- Push. Pass the credential only through the environment: GIT_CONFIG_COUNT=1, GIT_CONFIG_KEY_0=http.https://github.com/.extraheader, GIT_CONFIG_VALUE_0="AUTHORIZATION: basic <base64 of x-access-token:TOKEN>". Then run `git push origin <BRANCH>:refs/heads/<BRANCH>`, with no force and no other refs.
- Open the PR, with GH_TOKEN set only for that command: POST repos/603-Identity/devcontainers/pulls via `gh api ... --input -`, with the JSON body {title: "<TITLE>", head: "<BRANCH>", base: "main", body: <the PR body file's contents>}. Capture the PR number.
- Set its milestone: PATCH repos/603-Identity/devcontainers/issues/<PR> with milestone=<MILESTONE>, and confirm the response says <MILESTONE>.
- If any step fails, do not retry with a different command or token. Go to Phase 3 and report.

## Phase 3: revoke (always, even after a failure)
- DELETE https://api.github.com/installation/token with the token (expect 204). Then confirm that a GET /installation/repositories with it now returns 401.
- Unset every variable that held it. If I gave you a file, tell me its path so I can delete it. Then say exactly: "Token revoked (401 confirmed). Close the elevated window in the broker now."
- Delete the temp directory.
- Report: the PR number and URL, the milestone, the revocation result, and anything that failed. Then tell me: "Run `wow-review 603-Identity/devcontainers <PR>` on the host for the review."
````

## After a host step

- **Host clone run:** the owner tells the driver. The driver checks the results file's sha256
  against the report, and passes the path to the lane, which puts the evidence in its PR body.
- **Elevated push:** the owner runs `wow-review` for the PR. The PR is approved and merged by hand,
  since `603id-admin[bot]` does not arm auto-merge.
