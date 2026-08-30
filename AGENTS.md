# GarStreamRx Agent Rules

This Product repository fixes `gar-stream-rx` to `luckfox-rk3506`. Do not add another
physical target or restore a Deployment dispatcher. Create another Product
repository when the same application needs a different physical target.

- `sources`: pinned application and reusable-tool submodules
- `hardware`: Product-specific hardware requirements and fixed binding
- `config/artifact.json`: fixed target artifact contract
- `scripts/target`: Product-specific physical target implementation

Keep reusable board support in `sources/gar-tools`. Commit and push child
repository changes before updating parent submodule pointers. Generated
artifacts are not committed.
