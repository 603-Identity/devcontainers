# Next steps

**Now:** P0: cross-org images — implementing; next task #24 (prove the template with the devcontainer CLI in CI).

**Just done:**
- Fresh-session architect review of PR #65 (#23) posted against `2e9fe18`. No blocking defects; build, smoke and three mutation witnesses reproduced in a sandbox. The `architect-review` gate went green and the human merged it (`b59ab35`).
- Filed from that review: #68 (README migration seeds from `/etc/skel` and leaves `~/.cache` root-owned; verified fix is `cp -a /home/app/. /to/`; **fix before the infrastructure-core migration runs**) and #69 (a planted `~/.config` symlink survives `git-identity.sh`'s XDG git config delete; boundary 4 overstates it).
- #23 stays open: its template CI proof (#24) and the live pilot container are not done.
- Plan anchor re-verified against milestone 1 at this handoff (`match`), now anchored to #24.

**Next:** task #24 — build the template CI proof per #24's body, on sonnet (coder). Also assert the #65 layout: `<repo>-home` at `/home/app`, `devc-tofu-plugins` at `~/.cache/tofu-plugins`, `--read-only` (EROFS), init as PID 1, `~/.gitconfig` written on a fresh volume. The review of #65 left one risk unverified: the devcontainer CLI's own setup writes under `/etc` and `/var` and may hit `EROFS` under `--read-only`. #24 is where that surfaces. Then `/way-of-working:critic-gate` and `/way-of-working:ship`.
- The tofu Trivy entries expire 2026-10-28 (#8); 1.13.0 clears 11 of the 14 and must move with the consumers' CI pins.
- #58 (unverified tofu `SHA256SUMS` signature) is unmilestoned, for triage; so are #68 and #69.
- Not yet recorded: the version standard as an IAC-D decision in infrastructure-core (DEVC-D1).

**HITL Gate: NONE OPEN** — next gate is the fresh-session architect review of #24's PR, then the human's merge.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan: https://github.com/603-Identity/devcontainers/milestone/1
