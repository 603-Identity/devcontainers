# Next steps

**Now:** Milestone 5, Trivy renewal 2026-11, `implementing`. The Python 3.15 base image (#556) has merged; its two follow-ups are being specced so they ship in the same release. Milestone 6 is parked.

**Just done:**
- #556 (Python standard): filed, specced, built in a lane, merged as PR #557. The base image's default `python3` is a pinned python-build-standalone CPython 3.15.2 (DEVC-D11). The owner's host Trivy run found no component under `/opt/devc/python`, and the docs say so. #556 stays open for the consuming-repo checklist.
- PR #541 (betterleaks 2.0.0-rc.8) merged ahead of #557, so both go into the next release.
- Follow-ups from #557's reviews filed on milestone 5: #560 (smoke check that `python3 -m venv` gives a working pip) and #561 (re-pin the interpreter within its minor through `bump-binaries.sh`). Triage issues #558 and #559 closed with pointers.
- #550 (root `CLAUDE.md`) escalated twice; the second escalation is unanswered on purpose. #551 broadened to correct the stale devcontainer, review-gate and ruleset claims in `README.md` and the threat model first. Both are on milestone 6 and don't block the release.
- Critic gate: this session wrote no code itself (the #557 lane ran its own critic gate), so none ran here.

**Next:** driver: review the #560 and #561 spec comments once their spec sessions post them, and advise the owner before reacting. Then start a lane for each approved spec (`lane.sh groups 5` first; both edit `docs/threat_model.md`, so expect consecutive lanes). Cut the release once #557, #560 and #561 are on `main` and the post-merge Build images run is green. Then task #484 before the `.trivyignore.yaml` exceptions expire on 2026-12-01. Model: **opus** (architect, as driver).

**HITL Gate: OPEN** — the owner reacts to each posted spec comment for #560 and #561 after the driver has reviewed it; no task is anchored, so nothing auto-starts.

**Open for the owner (non-blocking):**
- Lanes in the devcontainer can't run the Docker gate entries or the gpg-backed `claude-fetch` gate test. Tell each lane up front to ship anyway and mark those entries pending (#550 will record the rule).
- #551: react, then run `wowl 603-Identity/devcontainers -Spec 551`. After it merges, re-spec #550 slim (answer or delete escalated comment 6952215523).
- `.claude/hooks/merge-guard.sh` still names `restrict-updates-to-main`, a ruleset that is not live; this needs an issue of its own.
- #427: pick early warning, stagger, or both, before its step starts.
- Milestone 5's description doesn't list #556, #560 or #561 in its build order.
- Milestone 10 needs owner setup in GitHub settings before it starts. Milestone 3's description is stale.
- Use the JaredGroves-603 login for this repo. Create issues, comments and PRs with `gh api ... --input -`.

**Pointers:** [docs/roadmap.md](../docs/roadmap.md) · sprint plan:
https://github.com/603-Identity/devcontainers/milestone/5 · parked sprints: `.ai/parked/`
