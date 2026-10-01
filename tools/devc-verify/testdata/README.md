These fixtures are HAND-BUILT, not recorded. They are modeled on the shape of
`gh attestation verify --format json` output and on the in-toto SLSA provenance v1 field
paths the design spec lists. The raw spike evidence (`prov.json`, `a2-verify.json`) was not
available when they were written, so replace them with recorded output when it is.

- provenance.json: one attempt-1 provenance result for devcontainer-node, run 36800000144.
- sbom.json: the matching CycloneDX result.
- run.json: `gh api repos/603-Identity/devcontainers/actions/runs/36800000144`, run_number 144.

> Fixture run ids are made up on purpose (36800000144): they must not collide with the real run ids recorded in the design spec.
