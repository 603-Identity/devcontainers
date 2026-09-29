# sprints

This directory is `sprints_dir` in `.ai/project.yml`. The way-of-working v0.13.0 schema
requires `sprints_dir` to name a real path, so the directory exists even though it holds no
sprint plans.

Sprints in this repo are GitHub milestones (`planning.kind: github_milestones`). Each sprint
is one milestone on 603-Identity/devcontainers, and the milestone's issues are its task
list. To plan the next sprint, run `/way-of-working:plan-sprint`, and look at the repo's
milestones to see the current one.

Don't add sprint plan files here. The skills don't read them while `planning.kind` is
`github_milestones`, so the files would go stale without anyone noticing. If this repo ever
moves to file-based planning, change `planning.kind` in the same PR that adds the first plan.
