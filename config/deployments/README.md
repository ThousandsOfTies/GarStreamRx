# Deployment Profiles

A Deployment Profile composes one source-owned Application Capsule with one
physical target, Product hardware binding, artifact contract, and Product-side
Target Capsule.

- Application behavior stays in `sources/<app>`.
- Product wiring stays in `hardware/`.
- Product controller implementation stays in `scripts/targets/<target-id>/`.
- Reusable board lifecycle support stays in `sources/gar-tools/targets/`.

Use `scripts/package-target.sh --deployment <id> --describe` to validate the
composition without building or modifying artifacts. Top-level
`scripts/product-target-build.sh` remains a GAR compatibility entrypoint.
A profile marked `planned` can be inspected but cannot produce an artifact.

