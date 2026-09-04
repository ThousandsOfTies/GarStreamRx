#!/usr/bin/env bash
# Configure and build the Luckfox Lyra Plus Buildroot sysroot/rootfs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mode="${1:-build}"
case "${mode}" in
  config|build) ;;
  *)
    echo "usage: $0 [config|build]" >&2
    exit 2
    ;;
esac

if [[ "${GAR_RK3506_SDK_CONTAINER:-0}" != 1 ]]; then
  if [[ -f "${repo_root}/config/rk3506-sdk.env" ]]; then
    # shellcheck disable=SC1091
    source "${repo_root}/config/rk3506-sdk.env"
  fi
  sdk_root="${RK3506_SDK_ROOT:-${LUCKFOX_LYRA_SDK_ROOT:-}}"
  if [[ -z "${sdk_root}" || ! -x "${sdk_root}/build.sh" ]]; then
    echo "RK3506 SDK working tree is not configured." >&2
    echo "Set RK3506_SDK_ROOT in ${repo_root}/config/rk3506-sdk.env." >&2
    exit 1
  fi
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
      echo "The Luckfox SDK requires an x86_64 build host." >&2
      exit 1
      ;;
  esac
  command -v docker >/dev/null 2>&1 || {
    echo "Docker is required for the Ubuntu 22.04 SDK environment." >&2
    exit 1
  }

  image="${GAR_RK3506_SDK_IMAGE:-gar-rk3506-sdk:22.04}"
  docker build \
    --build-arg "BUILDER_UID=$(id -u)" \
    --build-arg "BUILDER_GID=$(id -g)" \
    -t "${image}" \
    -f "${repo_root}/infra/rk3506-sdk/Dockerfile" \
    "${repo_root}/infra/rk3506-sdk"
  exec docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env HOME=/home/builder \
    --env USER=builder \
    --env FORCE_UNSAFE_CONFIGURE=1 \
    --env GAR_RK3506_SDK_CONTAINER=1 \
    --mount "type=bind,src=${sdk_root},dst=/sdk" \
    --mount "type=bind,src=${repo_root},dst=/gar,readonly" \
    "${image}" \
    /gar/scripts/target/build-sdk-rootfs.sh "${mode}"
fi

cd /sdk
buildroot_output=/sdk/buildroot/output/rockchip_rk3506_luckfox
config_file="${buildroot_output}/.config"

defconfig="${GAR_RK3506_DEFCONFIG:-luckfox_lyra_plus_buildroot_spinand_defconfig}"
./build.sh "${defconfig}"
make -C buildroot \
  O="${buildroot_output}" \
  rockchip_rk3506_luckfox_defconfig

# The exported WSL SDK does not always carry a usable .repo Git checkout.
# RKADK's CMake version helper only generates version.h when it sees .git, so
# provide a deterministic fallback for this source-only SDK export.
rkadk_version="/sdk/app/rkadk/include/version.h"
if [[ ! -f "${rkadk_version}" ]]; then
  install -D -m 0644 /dev/stdin "${rkadk_version}" <<'EOF'
/* Generated fallback for SDK sources without a linked Git checkout. */
#ifndef SRC_VERSION_H_
#define SRC_VERSION_H_

#define RKADK_VERSION_INFO "recovered SDK build"
#define RKADK_BUILD_INFO   "built in Docker"

#endif /* SRC_VERSION_H_ */
EOF
fi

# Use Buildroot's generic 6.1 headers instead of the vendor make-4.3 archive
# reference, which is no longer available at the original mirror.  Keep the
# source mirror explicit so the build can reuse a populated dl/ cache.
buildroot/utils/config --file "${config_file}" --disable BR2_KERNEL_HEADERS_AS_KERNEL
buildroot/utils/config --file "${config_file}" --enable BR2_KERNEL_HEADERS_6_1
buildroot/utils/config --file "${config_file}" --disable BR2_LINUX_KERNEL_CUSTOM_LOCAL
buildroot/utils/config --file "${config_file}" --set-str BR2_DEFAULT_KERNEL_HEADERS "6.1.79"
buildroot/utils/config --file "${config_file}" --set-str BR2_PRIMARY_SITE 'https\://sources.buildroot.net'
buildroot/utils/config --file "${config_file}" --set-str BR2_BACKUP_SITE 'https\://sources.buildroot.net'

# The Product needs GStreamer/DTC, not the vendor's optional multimedia,
# debug, network-test, or target-Python stack. Disabling these avoids the
# obsolete FFmpeg host-make download and keeps SDK preparation finite while
# preserving the application runtime.
disabled_symbols=(
  BR2_PACKAGE_FFMPEG
  BR2_PACKAGE_SDL2
  BR2_PACKAGE_VIM
  BR2_PACKAGE_VIM_RUNTIME
  BR2_PACKAGE_NANO
  BR2_PACKAGE_RIPGREP
  BR2_PACKAGE_STRESSAPPTEST
  BR2_PACKAGE_DHRYSTONE
  BR2_PACKAGE_SOX
  BR2_PACKAGE_DOSFSTOOLS
  BR2_PACKAGE_FATRESIZE
  BR2_PACKAGE_EVTEST
  BR2_PACKAGE_INPUT_EVENT_DAEMON
  BR2_PACKAGE_MEMTESTER
  BR2_PACKAGE_MHZ
  BR2_PACKAGE_MINICOM
  BR2_PACKAGE_NANOCOM
  BR2_PACKAGE_PARTED
  BR2_PACKAGE_PICOCOM
  BR2_PACKAGE_PM_UTILS
  BR2_PACKAGE_USBMOUNT
  BR2_PACKAGE_CAN_UTILS
  BR2_PACKAGE_DNSMASQ
  BR2_PACKAGE_HOSTAPD
  BR2_PACKAGE_IPERF
  BR2_PACKAGE_IPERF3
  BR2_PACKAGE_TIFF
  BR2_PACKAGE_SQLITE
  BR2_PACKAGE_HOST_RUSTC
  BR2_PACKAGE_HOST_RUST_BIN
  BR2_PACKAGE_PYTHON3
  BR2_PACKAGE_PYTHON3_PYC_ONLY
  BR2_PACKAGE_PYTHON3_PYEXPAT
  BR2_PACKAGE_PYTHON3_SQLITE
  BR2_PACKAGE_PYTHON3_SSL
  BR2_PACKAGE_PYTHON3_UNICODEDATA
  BR2_PACKAGE_PYTHON3_ZLIB
)
for symbol in "${disabled_symbols[@]}"; do
  buildroot/utils/config --file "${config_file}" --disable "${symbol}"
done

symbols=(
  BR2_PACKAGE_GSTREAMER1
  BR2_PACKAGE_GSTREAMER1_PARSE
  BR2_PACKAGE_GSTREAMER1_INSTALL_TOOLS
  BR2_PACKAGE_GST1_PLUGINS_BASE
  BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_APP
  BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_PLAYBACK
  BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_VIDEOCONVERTSCALE
  BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_VIDEOTESTSRC
  BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_PANGO
  BR2_PACKAGE_GST1_PLUGINS_GOOD
  BR2_PACKAGE_GST1_PLUGINS_GOOD_JPEG
  BR2_PACKAGE_GST1_PLUGINS_GOOD_PLUGIN_RTP
  BR2_PACKAGE_GST1_PLUGINS_GOOD_PLUGIN_RTPMANAGER
  BR2_PACKAGE_GST1_PLUGINS_GOOD_PLUGIN_UDP
  BR2_PACKAGE_GST1_PLUGINS_GOOD_PLUGIN_VIDEOFILTER
  BR2_PACKAGE_PANGO
  BR2_PACKAGE_FONTCONFIG
  BR2_PACKAGE_DEJAVU
  BR2_PACKAGE_DEJAVU_SANS
)
for symbol in "${symbols[@]}"; do
  buildroot/utils/config --file "${config_file}" --enable "${symbol}"
done
make -C buildroot O="${buildroot_output}" olddefconfig

if [[ "${mode}" == config ]]; then
  echo "RK3506 Buildroot configuration: ${config_file}"
  exit 0
fi

unset LD_LIBRARY_PATH
# The SDK's connectivity probe can reject an otherwise complete local dl/
# cache. Keep it opt-in for this reproducible/offline preparation flow.
if [[ "${GAR_RK3506_NETWORK_CHECK:-0}" != 1 ]]; then
  sed -i 's/^RK_NETWORK_CHECK=y$/# RK_NETWORK_CHECK is not set/' /sdk/output/.config
fi
# This helper prepares the userspace SDK without building the kernel. Avoid the
# optional debug-information copy that expects kernel/.config to exist.
if [[ "${GAR_RK3506_ROOTFS_DEBUG_INFO:-0}" != 1 ]]; then
  sed -i 's/^RK_ROOTFS_DEBUG_INFO=y$/# RK_ROOTFS_DEBUG_INFO is not set/' /sdk/output/.config
fi
if [[ "${GAR_RK3506_ROOTFS_LOGS:-0}" != 1 ]]; then
  sed -i 's/^RK_ROOTFS_GENERATE_LOGS=y$/# RK_ROOTFS_GENERATE_LOGS is not set/' /sdk/output/.config
fi
# Use Luckfox's wrapper even though the Buildroot configuration has already
# been prepared. It supplies RK_SESSION and the other Rockchip post-build
# context that a direct `make`/`brmake` invocation does not provide.
./build.sh buildroot-make

required_outputs=(
  "${buildroot_output}/host/bin/arm-buildroot-linux-gnueabihf-g++"
  "${buildroot_output}/host/arm-buildroot-linux-gnueabihf/sysroot/usr/lib/pkgconfig/gstreamer-1.0.pc"
  "${buildroot_output}/host/arm-buildroot-linux-gnueabihf/sysroot/usr/lib/pkgconfig/gstreamer-app-1.0.pc"
  "${buildroot_output}/images/rootfs.ubi"
)
for output in "${required_outputs[@]}"; do
  if [[ ! -e "${output}" ]]; then
    echo "Luckfox Buildroot output is missing: ${output}" >&2
    echo "Inspect /sdk/output/log/br.log for details." >&2
    exit 1
  fi
done
echo "RK3506 Buildroot host/sysroot: ${buildroot_output}/host"
echo "RK3506 rootfs images: ${buildroot_output}/images"
