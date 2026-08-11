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

正式なRxアプリは`sources/gar-stream-rx/native/`のC++実装です。host-independentな
state/PnPテストを実行した後、EC2用aarch64 ELFをクロスビルドしてartifactへ格納します。

```bash
gar sim app build --workspace Local/GarStreamRx
gar sim app deploy --workspace Local/GarStreamRx
gar sim runtime start --workspace Local/GarStreamRx
```

Rxアプリは実機と同じ UDP port 5600 で MJPEG/RTP を受け、デコードした RGB565
フレームを `/dev/spidev0.0` の ILI9341 インターフェースへ書き込みます。EC2 上では
GAR の CUSE SPI device がその書き込みを受け、Bridge を通じて Web Panel に表示します。
したがって受信アプリから見た UDP・GPIO・SPI のインターフェースはシミュレータと実機で
共通です。

TXはUDP 5601でSourceとして自己広告します。RXは検出したTXをチャンネル一覧として保持し、
`SOURCE`メニューで選択されたTXへlease付き送信要求を返します。同一LANでは設定不要です。
simulation artifactは接続情報を含みません。EC2のようにbroadcastが届かないnetworkでunicast
queryを使う場合は、RX Target上で明示的に`GAR_STREAM_DISCOVERY_PEERS`を設定してください。

EC2はaarch64、Luckfox Lyra Plusはarmv7lなので、同じCPUバイナリにはなりません。
ソース、GStreamer pipeline、PnP、GPIO/SPI I/Fは共通にし、Lyra版だけはRK3506
Buildroot SDKのtoolchain/sysrootで別ビルドします。`product-target-build.sh`は
`luckfox-rk3506`だけを受け付け、生成物がARM 32-bit ELFであることを検査するため、
aarch64 simulation artifactを実機へ誤配布しません。

## GarStreamRx physical target

最初にLuckfox SDKでrootfsを一度buildし、`sources/gar-stream-rx/README.md`に列挙した
GStreamer packageをsysroot/target stagingへ生成します。target artifactは必要なruntime
library、plugin、fontだけを同梱するため、実機rootfs全体の書き換えは不要です。SDKの場所と
実機設定はGit管理しないlocal設定へ記入します。

```bash
cp config/rk3506-sdk.env.example config/rk3506-sdk.env
cp config/gar-stream-rx.target.env.example config/gar-stream-rx.target.env
# SDK pathを修正。GPIO値は同梱exampleが下記の標準配線に対応
```

SDKの作業ツリーを用意した後は、公式対応環境のUbuntu 22.04コンテナでLyra Plus
（256MB SPI NAND版）のBuildrootを構成・buildできます。必要なGStreamer pluginはscriptが
毎回明示的に有効化するため、vendor SDKのdefconfigを直接変更しません。

```bash
# 設定だけを生成・確認
scripts/build-rk3506-sdk-rootfs.sh config

# toolchain/sysrootと実機用rootfs imageを生成
scripts/build-rk3506-sdk-rootfs.sh build
```

target buildは再現可能なDocker build環境へSDKの`output/.../host`をread-only mountし、
SDK付属の`arm-buildroot-linux-gnueabihf-g++`とsysrootでARMv7 binaryを作成します。
またstock 6.1.84 imageで省略されている`spi-rockchip.ko`と`spidev.ko`だけをSDK kernel
sourceから同じABIで作り、artifact内へ同梱します。このmodule buildのhost tool生成には
WSL側の`gcc`、`flex`、`bison`、`m4`が必要です。

```bash
gar target build --workspace Local/GarStreamRx

# 初回、またはTarget recipe更新後だけ
gar target prepare --workspace Local/GarStreamRx

# Targetの接続・GPIO設定は明示的に配置する
gar target configure --workspace Local/GarStreamRx --app gar-stream-rx --file config/gar-stream-rx.target.env

gar target deploy --workspace Local/GarStreamRx
```

`config/gar-stream-rx.target.env`はartifactへ自動で含めません。Target環境変数を変更する場合は
`gar target configure --workspace Local/GarStreamRx --app gar-stream-rx --file config/gar-stream-rx.target.env`
を明示的に実行してください。通常のbuild/deployは既存のTarget
`/etc/gar/gar-stream-rx.env`を保持します。`prepare`はBuildroot用の限定installerと
BusyBox init templateだけを導入します。初回`deploy`は現在のboot DTBへSPI0/spidevだけを
追加し、元boot imageを`/var/lib/gar/backups`へ保存します。このとき再起動が必要です。
再起動後は`/etc/init.d/S95gar-stream-rx`から起動し、artifact内のSPI moduleを必要な場合
だけloadしてから同じ実機binaryを実行します。以後のdeployはアプリdirectoryをatomicに
交換して直ちに再起動します。将来のimageがdriverを内蔵した場合、module loadは自動的に
skipされます。
systemd、Python、simulation用GPIO/SPI deviceは実機へ配置しません。

実機上の確認:

```bash
ssh luckfox-lyra '/etc/init.d/S95gar-stream-rx status'
ssh luckfox-lyra 'tail -n 50 /var/log/gar/gar-stream-rx.log'
```
