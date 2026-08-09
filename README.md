# gar-build-env

Gapless Agent Runtime 用の Codespaces/devcontainer ビルド環境です。

このリポジトリは Codespaces/devcontainer の共通実行基盤です。

`main` は共通 devspace runtime だけを持ちます。製品ごとの設定は
`gar-build-env` の製品ブランチに保存します。製品ブランチは
`config/product.env`、任意の `scripts/product-*.sh`、必要なら
`sources/*` submodule を持ちます。

## Layout

```text
gar-build-env/
  .devcontainer/
  config/
    common.env
    artifact-manifest.example.json
    product.env.example
  Makefile
  scripts/
    bootstrap.sh
    setup-common.sh
    setup-product-branch.sh
    product-sim-build.sh.example
  artifacts/             # generated output, ignored
```

## Setup

Codespaces 起動時は `.devcontainer/devcontainer.json` の `postCreateCommand` が
`scripts/post-create.sh` を実行します。実体は `scripts/bootstrap.sh` です。

起動時の流れ:

```text
scripts/setup-common.sh
scripts/setup-product-branch.sh
  config/product.env があれば読む
  .gitmodules があれば git submodule update --init --recursive
  scripts/product-install.sh が実行可能なら実行
```

手動で実行する場合:

```bash
make setup
```

製品ブランチ側で submodule を使っている場合に明示的に最新化するには:

```bash
make sync
```

`make setup` は製品ブランチに定義された設定を読み、必要な準備だけを実行します。
`.gitmodules` がある場合は、親リポジトリが記録している submodule commit を再現します。
`make sync` は branch checkout されている submodule だけ `git pull --ff-only` します。
`make build` と `make artifacts` はセットアップを自動実行しません。起動時セットアップは
Devcontainer の `postCreateCommand` に限定し、必要な場合だけ明示的に `make setup` を実行します。

## GAR Simulation Build Hook

`gar sim build` の入口は Codespaces 固有ではなく、ローカルまたは Codespaces 上で動く
GaplessAgentRuntime です。製品 branch で simulation build が必要な場合は、
`scripts/product-sim-build.sh.example` を `scripts/product-sim-build.sh` にコピーして
アプリ固有の build コマンドを定義してください。GAR はその script を呼び出します。

通常、製品 branch はアプリを `sources/<app>`、共有 simulation asset を
`sources/gar-tools` に submodule として持ちます。template の `GAR_SIM_APP_DIR` と
`GAR_TOOLS_DIR` はその配置を参照し、アプリ側の command には
`GAR_TOOLS_ROOT` として後者を渡せます。

## Product Branches

製品ブランチでは、共通シーケンスをなるべく触らず、個別定義だけを追加します。

```text
config/product.env
scripts/product-install.sh
scripts/product-build.sh
scripts/product-artifacts.sh
scripts/product-clean.sh
scripts/product-sim-build.sh
sources/* submodules
AGENTS.md
```

関連リポジトリを submodule として持つ製品ブランチでは、子リポジトリを先に
commit/push し、そのあと親の submodule pointer を更新してください。

```bash
cd path/to/submodule
git add -A
git commit -m "Update product repo"
git push

cd path/to/gar-build-env
git add path/to/submodule
git commit -m "Update product submodule pointer"
git push
```

## Product Build Hooks

`main` は製品固有のビルド手順を持ちません。製品ブランチで必要に応じて
次の hook を追加します。

```text
scripts/product-install.sh
scripts/product-build.sh
scripts/product-artifacts.sh
scripts/product-clean.sh
```

`make build` は `scripts/product-build.sh` があれば実行します。
`make artifacts` は `scripts/product-artifacts.sh` があれば実行します。
Artifact manifest は製品固有の定義です。必要な製品ブランチで
`config/artifact-manifest.example.json` を参考に、製品用の設定ファイルや
`scripts/product-artifacts.sh` を追加してください。

PlatformIO は Python 仮想環境 `~/.venvs/platformio` にインストールされ、
`~/.bashrc` に PATH が追加されます。

## GarStreamRx simulation

Rx アプリは実機と同じ UDP port 5600 で MJPEG/RTP を受け、デコードした RGB565
フレームを `/dev/spidev0.0` の ILI9341 インターフェースへ書き込みます。EC2 上では
GAR の CUSE SPI device がその書き込みを受け、Bridge を通じて Web Panel に表示します。
したがって受信アプリから見た UDP・GPIO・SPI のインターフェースはシミュレータと実機で
共通です。

TXはUDP 5601でSourceとして自己広告します。RXは検出したTXをチャンネル一覧として保持し、
`SOURCE`メニューで選択されたTXへlease付き送信要求を返します。同一LANでは設定不要です。
EC2のようにbroadcastが届かないnetworkでは、product build hookがRuntimeのworkspace情報から
TX private IPをRX側の`GAR_STREAM_DISCOVERY_PEERS`へ渡し、unicast queryで同じprotocolを使います。
