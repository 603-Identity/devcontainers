# templates

`previous.devcontainer.json`, when present, is the template's `devcontainer.json` as the
release that `main`'s self-pins named when this release was cut shipped it (#418 owner decision
5). `devc-verify` embeds this directory, so a release built at a pin carries its own snapshot,
and in dev-App mode a consumer's `devcontainer.json` may match either the template at the pin
or this snapshot. A snapshot that is not dev-App is never used.

`tools/check-self-pins.sh` compares it byte for byte with the template at the pinned release,
and warns while it is missing (expected through v1.6). README.md "Cutting a release" says when
to rotate it, and who may ship a release without one.
