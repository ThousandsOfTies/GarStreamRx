# gar-build-env Agent Rules

This repository is the GAR Codespaces/devcontainer runtime. Product-specific
configuration lives on long-lived product branches of this repository.

## Roles

- `main`: common devspace runtime, setup sequence, shared defaults.
- Product branches: product-specific config, optional `sources/*` submodules,
  and setup/build hooks.
- Submodules, when present on a product branch: official editable source
  repositories, not ignored scratch space.

## Setup Flow

Codespaces runs `scripts/post-create.sh`, which delegates to:

```text
scripts/bootstrap.sh
  scripts/setup-common.sh
  scripts/setup-product-branch.sh
```

`setup-product-branch.sh` is the common product-branch dispatcher. It is
intentionally optional-file friendly:

```bash
[ -f config/product.env ] && source config/product.env
[ -f .gitmodules ] && git submodule update --init --recursive
[ -x scripts/product-install.sh ] && scripts/product-install.sh
```

## Product Branches

Do not add product-specific source repositories to `main`. Put each product's
repository set, config, and setup/build hooks on that product's branch.
Artifact manifests are product-specific config, not shared runtime code. Use
`config/artifact-manifest.example.json` as a template when a product branch
needs a deploy manifest.

GarStream connection ownership is RX-driven. TX devices advertise themselves,
while RX retains discovered Sources, selects a channel, and renews its stream
request lease. Routed-network discovery peers are RX configuration; never add
an RX address setting to TX. Keep `source_browser.py` compatible with the TX
repository's `gar-stream/1` messages in `source_advertiser.py`.

## Submodule Edits

On product branches that use submodules, commit and push the child repository
first, then commit the parent submodule pointer.

```bash
cd path/to/submodule
git add -A
git commit -m "Describe child repo change"
git push

cd path/to/gar-build-env
git add path/to/submodule
git commit -m "Update <repo> submodule pointer"
git push
```

Do not treat product-branch submodules as disposable generated directories. They
are canonical product repositories for AI-assisted edits.
