These fixtures are HAND-BUILT, not recorded. They are modeled on the shape of
`gh attestation verify --format json` output and on the in-toto SLSA provenance v1 field
paths the design spec lists. The raw spike evidence (`prov.json`, `a2-verify.json`) was not
available when they were written, so replace them with recorded output when it is.

- provenance.json: one attempt-1 provenance result for devcontainer-node, run 36800000144.
- sbom.json: the matching CycloneDX result.
- run.json: `gh api repos/603-Identity/devcontainers/actions/runs/36800000144`, run_number 144.

> Fixture run ids are made up on purpose (36800000144): they must not collide with the real run ids recorded in the design spec.

Added for #392 (the first two are copies, not hand-built):

- legacy.devcontainer.json: `template/.devcontainer/devcontainer.json` as v1.5 shipped it, the
  legacy template plain mode's allowlist is built from. A test asserts it still equals the
  template until #418's PR D replaces that.
- pilot.devcontainer.json: terraform-cloudflare-dns's `.devcontainer/devcontainer.json` at
  `922e9c6`. terraform-microsoft365-entra's was byte-identical on 2026-11-02 (that repo is
  private, so it is not copied).
- devapp/template/: a dev-App template shaped as the #418 design (section 2) describes it, for
  the dev-App self-test. It is a fixture, not the template.
