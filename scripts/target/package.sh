#!/usr/bin/env bash
# Build and stage the physical Luckfox Lyra (RK3506/armv7l) artifact.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "${repo_root}/config/product.env" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/config/product.env"
fi

target="${GAR_TARGET:-luckfox-rk3506}"
artifact_root_setting="${GAR_TARGET_ARTIFACT_ROOT:-artifacts/from-codespace}"
if [[ "${artifact_root_setting}" == /* ]]; then
  artifact_root="${artifact_root_setting}"
else
  artifact_root="${repo_root}/${artifact_root_setting}"
fi
artifact_root="$(realpath -m "${artifact_root}")"
case "${artifact_root}" in
  /|/home|/home/user|"${repo_root}")
    echo "refusing unsafe target artifact root: ${artifact_root}" >&2
    exit 2
    ;;
esac
artifact_dir="${artifact_root}/files/gar-stream-rx"
deploy_dest="${GAR_TARGET_ARTIFACT_DEST:-/opt/gar/apps/gar-stream-rx}"
builder="${GAR_RX_TARGET_BUILDER:-${repo_root}/scripts/target/build-native.sh}"
target_configurer="${repo_root}/scripts/target/configure-target"
spi_overlay="${repo_root}/scripts/target/rk3506-gar-stream-rx-spi0-overlay.dts"

if [[ "$#" -gt 1 || ( "$#" -eq 1 && "$1" != "clean" ) ]]; then
  echo "usage: $0 [clean]" >&2
  exit 2
fi
if [[ "${1:-}" == "clean" ]]; then
  rm -rf "${artifact_root}"
  echo "Removed target artifact: ${artifact_root}"
  exit 0
fi
if [[ "${target}" != "luckfox-rk3506" ]]; then
  echo "unsupported physical target for GarStreamRx: ${target}" >&2
  echo "select Luckfox Lyra Plus (luckfox-rk3506) in gar setup" >&2
  exit 1
fi
if [[ ! -x "${builder}" ]]; then
  echo "RK3506 target builder is not executable: ${builder}" >&2
  exit 1
fi
if [[ ! -x "${target_configurer}" || ! -f "${spi_overlay}" ]]; then
  echo "RK3506 target hardware configuration files are missing" >&2
  exit 1
fi

mkdir -p "${artifact_root}/files"
staging_dir="$(mktemp -d "${artifact_root}/files/.gar-stream-rx-target.XXXXXX")"
manifest_staging="${artifact_root}/artifact.json.gar-new"
cleanup() {
  rm -rf "${staging_dir}" "${manifest_staging}"
}
trap cleanup EXIT
"${builder}" "${staging_dir}/gar-stream-rx"
if [[ ! -f "${staging_dir}/gar-stream-rx" ]]; then
  echo "RK3506 target builder did not produce gar-stream-rx" >&2
  exit 1
fi
chmod 0755 "${staging_dir}/gar-stream-rx"
install -m 0755 "${target_configurer}" "${staging_dir}/configure-target"
install -m 0644 "${spi_overlay}" "${staging_dir}/rk3506-gar-stream-rx-spi0-overlay.dts"

cat >"${staging_dir}/run" <<'EOF'
#!/bin/sh
# Physical RK3506 defaults for the documented Lyra Plus header wiring.
set -eu

env_file=/etc/gar/gar-stream-rx.env
if [ -r "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
fi

missing=""
for variable in GAR_LCD_DC_GPIO GAR_LCD_RST_GPIO GAR_ENC_CLK_GPIO GAR_ENC_DT_GPIO GAR_ENC_SW_GPIO; do
    eval "value=\${$variable:-}"
    if [ -z "$value" ]; then
        missing="$missing $variable"
    fi
done
if [ -n "$missing" ]; then
    echo "gar-stream-rx: set the physical GPIO offsets in $env_file:$missing" >&2
    exit 2
fi

export GAR_GPIO_CHIP="${GAR_GPIO_CHIP:-/dev/gpiochip0}"
export GAR_SPI_DEVICE="${GAR_SPI_DEVICE:-/dev/spidev0.0}"
export GAR_SPI_MAX_HZ="${GAR_SPI_MAX_HZ:-10000000}"
export GAR_STREAM_DISCOVERY_PORT="${GAR_STREAM_DISCOVERY_PORT:-5601}"
export GAR_STREAM_RX_PORT="${GAR_STREAM_RX_PORT:-5600}"

app_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

# RK3506 RM_IO remapping is restored on every boot. SPI0 uses RM_IO7/6/5/4
# for CLK/MOSI/MISO/CS; LCD control and KY-040 lines stay in GPIO mode.
if command -v iomux >/dev/null 2>&1; then
    iomux 0 7 82 >/dev/null
    iomux 0 6 83 >/dev/null
    iomux 0 5 84 >/dev/null
    iomux 0 4 85 >/dev/null
    for gpio in 2 3 8 9 10; do
        iomux 0 "$gpio" 0 >/dev/null
    done
fi

# The stock Lyra Plus 6.1.84 image omits the standard Rockchip SPI and spidev
# drivers. Keep them application-owned so no kernel/rootfs image replacement is
# required. A future image with built-in drivers simply skips this block.
if [ ! -e "$GAR_SPI_DEVICE" ]; then
    kernel_release=$(uname -r)
    module_dir="$app_dir/modules/$kernel_release"
    [ -d "$module_dir" ] || {
        echo "gar-stream-rx: no SPI modules for target kernel $kernel_release" >&2
        exit 11
    }
    if ! grep -q '^spi_rockchip ' /proc/modules; then
        insmod "$module_dir/spi-rockchip.ko"
    fi
    if ! grep -q '^spidev ' /proc/modules; then
        insmod "$module_dir/spidev.ko"
    fi
    # Device creation is synchronous, but leave udev one short grace period.
    [ -e "$GAR_SPI_DEVICE" ] || sleep 1
fi
[ -e "$GAR_SPI_DEVICE" ] || {
    echo "gar-stream-rx: $GAR_SPI_DEVICE is unavailable after loading the SPI modules" >&2
    exit 11
}

export LD_LIBRARY_PATH="$app_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GST_PLUGIN_SYSTEM_PATH_1_0=
export GST_PLUGIN_PATH_1_0="$app_dir/lib/gstreamer-1.0"
export GST_REGISTRY_1_0=/tmp/gar-stream-rx-gstreamer-registry.bin
export GST_REGISTRY_FORK=no
export FONTCONFIG_FILE="$app_dir/share/fonts/fonts.conf"
export FONTCONFIG_PATH="$app_dir/share/fonts"
export XDG_CACHE_HOME=/tmp/gar-stream-rx-cache
exec "$app_dir/gar-stream-rx"
EOF
chmod 0755 "${staging_dir}/run"

cat >"${staging_dir}/gar-stream-rx.env.example" <<'EOF'
# Copy to /etc/gar/gar-stream-rx.env and replace the GPIO offsets with values
# documented for the Luckfox Lyra Plus header wiring.
GAR_GPIO_CHIP=/dev/gpiochip0
GAR_SPI_DEVICE=/dev/spidev0.0
GAR_SPI_MAX_HZ=10000000
GAR_LCD_DC_GPIO=3
GAR_LCD_RST_GPIO=2
GAR_ENC_CLK_GPIO=8
GAR_ENC_DT_GPIO=9
GAR_ENC_SW_GPIO=10

# Usually no network address is required on one LAN. For routed networks only:
# GAR_STREAM_DISCOVERY_PEERS=192.0.2.10
GAR_STREAM_DISCOVERY_PORT=5601
GAR_STREAM_RX_PORT=5600
EOF

python3 - "${manifest_staging}" "${target}" "${deploy_dest}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

output, target, destination = sys.argv[1:]
files = [
    {
        "src": "files/gar-stream-rx",
        "dest": destination,
        "mode": "0755",
    }
]
payload = {
    "name": "gar-stream-rx-target",
    "target": target,
    "deploy": {
        "app": {
            "files": files
        }
    },
}
Path(output).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

rm -rf "${artifact_dir}"
mv "${staging_dir}" "${artifact_dir}"
mv "${manifest_staging}" "${artifact_root}/artifact.json"
trap - EXIT

echo "Target: ${target}"
echo "Artifact: ${artifact_root}"
