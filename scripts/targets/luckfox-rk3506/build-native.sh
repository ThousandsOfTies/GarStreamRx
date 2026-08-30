#!/usr/bin/env bash
# Cross-compile GarStreamRx for the 32-bit RK3506 Buildroot userspace.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
if [[ -f "${repo_root}/config/rk3506-sdk.env" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/config/rk3506-sdk.env"
fi
source_dir="${repo_root}/${GAR_TARGET_APP_DIR:-${GAR_SIM_APP_DIR:-sources/gar-stream-rx}}/native"
output="${1:-${repo_root}/artifacts/native/rk3506/gar-stream-rx}"
sdk_root="${RK3506_SDK_ROOT:-${LUCKFOX_LYRA_SDK_ROOT:-}}"
buildroot_output="${RK3506_BUILDROOT_OUTPUT:-}"

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [output-binary]" >&2
  exit 2
fi
if [[ ! -f "${source_dir}/CMakeLists.txt" ]]; then
  echo "missing native source: ${source_dir}" >&2
  exit 1
fi

if [[ -z "${buildroot_output}" && -n "${sdk_root}" ]]; then
  buildroot_output="${sdk_root}/buildroot/output/rockchip_rk3506_luckfox"
fi

host_dir="${RK3506_HOST_DIR:-}"
toolchain_bin="${RK3506_TOOLCHAIN_BIN:-}"
sysroot="${RK3506_SYSROOT:-}"
runtime_root="${RK3506_RUNTIME_ROOT:-}"
if [[ -n "${buildroot_output}" ]]; then
  host_dir="${host_dir:-${buildroot_output}/host}"
  toolchain_bin="${toolchain_bin:-${host_dir}/bin}"
  sysroot="${sysroot:-${host_dir}/arm-buildroot-linux-gnueabihf/sysroot}"
  runtime_root="${runtime_root:-${buildroot_output}/target}"
fi
triple="${RK3506_TRIPLE:-arm-buildroot-linux-gnueabihf}"

if [[ -z "${toolchain_bin}" || -z "${sysroot}" ]]; then
  cat >&2 <<'EOF'
RK3506 Buildroot SDK is not configured.
Set RK3506_SDK_ROOT to the Luckfox Lyra SDK root after building its rootfs, or set:
  RK3506_TOOLCHAIN_BIN=/path/to/buildroot/output/rockchip_rk3506_luckfox/host/bin
  RK3506_SYSROOT=/path/to/buildroot/output/rockchip_rk3506_luckfox/host/arm-buildroot-linux-gnueabihf/sysroot
  RK3506_TRIPLE=arm-buildroot-linux-gnueabihf
EOF
  exit 1
fi
if [[ -z "${host_dir}" && "${toolchain_bin}" == */bin ]]; then
  host_dir="${toolchain_bin%/bin}"
fi
if [[ -z "${host_dir}" || ! -d "${host_dir}" ]]; then
  echo "RK3506 Buildroot host directory does not exist: ${host_dir:-unset}" >&2
  exit 1
fi

cxx="${toolchain_bin}/${triple}-g++"
if [[ ! -x "${cxx}" ]]; then
  echo "RK3506 C++ compiler is not executable: ${cxx}" >&2
  echo "The official SDK toolchain runs on an x86_64 build host such as WSL." >&2
  exit 1
fi
if [[ ! -d "${sysroot}" ]]; then
  echo "RK3506 sysroot does not exist: ${sysroot}" >&2
  echo "Build the Luckfox SDK rootfs with the required GStreamer packages first." >&2
  exit 1
fi
if [[ ! -d "${runtime_root}" ]]; then
  echo "RK3506 Buildroot target runtime does not exist: ${runtime_root}" >&2
  exit 1
fi
case "${sysroot}" in
  "${host_dir}"/*) sysroot_relative="${sysroot#${host_dir}/}" ;;
  *)
    echo "RK3506_SYSROOT must be inside RK3506_HOST_DIR so Docker can mount one relocatable SDK host tree." >&2
    echo "host: ${host_dir}" >&2
    echo "sysroot: ${sysroot}" >&2
    exit 1
    ;;
esac

pkg_config="${RK3506_PKG_CONFIG:-}"
if [[ -z "${pkg_config}" && -x "${toolchain_bin}/${triple}-pkg-config" ]]; then
  pkg_config="${toolchain_bin}/${triple}-pkg-config"
elif [[ -z "${pkg_config}" && -x "${host_dir}/bin/pkg-config" ]]; then
  pkg_config="${host_dir}/bin/pkg-config"
fi
if [[ -z "${pkg_config}" || ! -x "${pkg_config}" ]]; then
  echo "pkg-config for the RK3506 sysroot was not found" >&2
  exit 1
fi
case "${pkg_config}" in
  "${host_dir}/bin/"*) pkg_config_name="${pkg_config#${host_dir}/bin/}" ;;
  *)
    echo "RK3506_PKG_CONFIG must be in ${host_dir}/bin so it is available in the build container." >&2
    exit 1
    ;;
esac
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required for the reproducible RK3506 target build" >&2
  exit 1
fi
case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo "The official Luckfox SDK host tools require an x86_64 build machine." >&2
    echo "Run gar target build from the local WSL workspace, not the Graviton simulation host." >&2
    exit 1
    ;;
esac

build_root="$(mktemp -d /tmp/gar-stream-rx-rk3506.XXXXXX)"
trap 'rm -rf -- "${build_root}"' EXIT
image="${GAR_RX_BUILD_IMAGE:-gar-build-env:latest}"
container_sysroot="/rk3506-host/${sysroot_relative}"
container_pkg_config="/rk3506-host/bin/${pkg_config_name}"

docker build -t "${image}" "${repo_root}"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  --env RK3506_TOOLCHAIN_BIN=/rk3506-host/bin \
  --env RK3506_TRIPLE="${triple}" \
  --env RK3506_SYSROOT="${container_sysroot}" \
  --env RK3506_PKG_CONFIG="${container_pkg_config}" \
  --env PKG_CONFIG_SYSROOT_DIR="${container_sysroot}" \
  --env PKG_CONFIG_LIBDIR="${container_sysroot}/usr/lib/pkgconfig:${container_sysroot}/usr/share/pkgconfig:${container_sysroot}/lib/pkgconfig" \
  --mount "type=bind,src=${source_dir},dst=/src,readonly" \
  --mount "type=bind,src=${repo_root}/config/rk3506-buildroot-toolchain.cmake,dst=/toolchain.cmake,readonly" \
  --mount "type=bind,src=${host_dir},dst=/rk3506-host,readonly" \
  --mount "type=bind,src=${build_root},dst=/build" \
  "${image}" sh -eu -c '
    if ! "$RK3506_PKG_CONFIG" --exists gstreamer-1.0 gstreamer-app-1.0 glib-2.0; then
      echo "RK3506 sysroot is missing GStreamer/GLib development metadata." >&2
      echo "Enable the packages documented in sources/gar-stream-rx/README.md and rebuild the SDK rootfs." >&2
      exit 1
    fi
    cmake -S /src -B /build -GNinja \
      -DCMAKE_TOOLCHAIN_FILE=/toolchain.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DPKG_CONFIG_EXECUTABLE="$RK3506_PKG_CONFIG" \
      -DBUILD_TESTING=OFF
    cmake --build /build
    description=$(file /build/gar-stream-rx)
    case "$description" in
      *"ELF 32-bit"*"ARM"*) ;;
      *) echo "unexpected RK3506 binary: $description" >&2; exit 1 ;;
    esac
    strip=/rk3506-host/bin/${RK3506_TRIPLE}-strip
    if [ -x "$strip" ]; then
      "$strip" /build/gar-stream-rx
    fi
    echo "$description"
  '

binary="${build_root}/gar-stream-rx"
if [[ ! -f "${binary}" ]]; then
  echo "RK3506 build did not produce ${binary}" >&2
  exit 1
fi
mkdir -p "$(dirname "${output}")"
install -m 0755 "${binary}" "${output}"
collector="${repo_root}/scripts/targets/luckfox-rk3506/collect-runtime.py"
if [[ ! -x "${collector}" ]]; then
  echo "RK3506 runtime collector is not executable: ${collector}" >&2
  exit 1
fi
"${collector}" \
  --readelf "${toolchain_bin}/${triple}-readelf" \
  --runtime-root "${runtime_root}" \
  --binary "${output}" \
  --output "$(dirname "${output}")"
module_builder="${repo_root}/scripts/targets/luckfox-rk3506/build-kernel-modules.sh"
if [[ ! -x "${module_builder}" ]]; then
  echo "RK3506 kernel module builder is not executable: ${module_builder}" >&2
  exit 1
fi
"${module_builder}" "$(dirname "${output}")/modules"
echo "RK3506 target binary: ${output}"
