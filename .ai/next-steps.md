# Next steps

**Now:** P0: cross-org images -- implementing, milestone 1.

**Just done:**
- Fresh-session architect review of [#157](https://github.com/603-Identity/devcontainers/pull/157)
  (head `8e2dca5`): no blocking findings. The gate went green as a commit status; merged as
  `ff9539f`, closing #124 and #81.
- The review's non-blocking findings are filed: #159 (an image change can go unpublished
  until the weekly run, by concurrency coalescing or a failed publish), #160 (restore
  `publish`'s own event/ref guard), #161 (test-file leftovers).

**Next:** task #58 — close the unsigned-`SHA256SUMS` gap for the tofu image: verify the cosign
keyless signature on `tofu_<v>_SHA256SUMS` for the pinned version, record the verified signer
identity in the Dockerfile comment beside `TOFU_SHA256` (no new tool in the image), and extend
`docs/threat_model.md`'s Known gaps from Node.js to every ARG-pinned binary whose upstream signs
its checksum file (check gh, yq, uv, tflint). Then the gate tests and `/way-of-working:ship`.
Model: **opus** (architect; a security judgment call).

**HITL Gate: NONE OPEN** -- the milestone 1 anchor re-verified (`match`) at this handoff. Next
gate: the fresh-session architect review on #58's PR.

**Open for the owner (non-blocking):** merging this docs-only PR is the first docs-only push to
`main` since #157, and so the live proof that `publish` skips: watch the `Did the push change an
image?` job give `build=0`. Amend spec §4 to the lint's wider scope; run the tag ruleset's
App-token delete negative test once the bump-binaries App exists (#102). Still to delete in the
UI: `Seuss27/devc-spike2-host` and `glunk-works/devc-spike2-consumer`. The active `gh` account
can flip to Seuss27: use the JaredGroves-603 token for this repo's `gh` calls. Run WSL jobs from
the Windows side as one foreground `wsl` process; from Git Bash set `MSYS_NO_PATHCONV=1` before
passing a `/mnt/c/...` path.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/1
