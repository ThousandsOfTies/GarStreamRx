#!/usr/bin/env bash
# Build the two loadable SPI modules omitted from the stock Lyra Plus image.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "${repo_root}/config/rk3506-sdk.env" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/config/rk3506-sdk.env"
fi

destination="${1:-${repo_root}/artifacts/native/rk3506/modules}"
sdk_root="${RK3506_SDK_ROOT:-${LUCKFOX_LYRA_SDK_ROOT:-}}"
kernel_source="${RK3506_KERNEL_SOURCE:-${sdk_root:+${sdk_root}/kernel}}"
target_release="${RK3506_TARGET_KERNEL_RELEASE:-6.1.84}"

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [output-directory]" >&2
  exit 2
fi
if [[ -z "${sdk_root}" || ! -d "${sdk_root}" ]]; then
  echo "RK3506_SDK_ROOT does not identify the Luckfox Lyra SDK" >&2
  exit 1
fi
if [[ ! -f "${kernel_source}/Makefile" || ! -x "${kernel_source}/scripts/config" ]]; then
  echo "RK3506 kernel source is unavailable: ${kernel_source}" >&2
  exit 1
fi
case "${target_release}" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "invalid RK3506_TARGET_KERNEL_RELEASE: ${target_release}" >&2; exit 1 ;;
esac

source_version="$(make -s -C "${kernel_source}" kernelversion)"
if [[ "${source_version%.*}" != "${target_release%.*}" ]]; then
  echo "RK3506 kernel source ${source_version} is incompatible with target kernel ${target_release}" >&2
  exit 1
fi

vendor_toolchain="${sdk_root}/prebuilts/gcc/linux-x86/arm/gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf/bin"
buildroot_toolchain="${RK3506_TOOLCHAIN_BIN:-${sdk_root}/buildroot/output/rockchip_rk3506_luckfox/host/bin}"
if [[ -n "${RK3506_KERNEL_CROSS_COMPILE:-}" ]]; then
  cross_compile="${RK3506_KERNEL_CROSS_COMPILE}"
elif [[ -x "${buildroot_toolchain}/arm-buildroot-linux-gnueabihf-gcc" ]]; then
  # This is also used for the application and does not enable the vendor GCC
  # host plugin build, so a plain C-only WSL build host is sufficient.
  cross_compile="${buildroot_toolchain}/arm-buildroot-linux-gnueabihf-"
elif [[ -x "${vendor_toolchain}/arm-none-linux-gnueabihf-gcc" ]]; then
  cross_compile="${vendor_toolchain}/arm-none-linux-gnueabihf-"
else
  echo "RK3506 ARM cross compiler was not found in the SDK" >&2
  exit 1
fi

host_make_args=()
if [[ -n "${RK3506_KERNEL_HOSTCC:-}" ]]; then
  host_make_args+=("HOSTCC=${RK3506_KERNEL_HOSTCC}")
elif command -v gcc >/dev/null 2>&1; then
  host_make_args+=("HOSTCC=$(command -v gcc)")
else
  # GAR's WSL bootstrap can provide an unprivileged, extracted Ubuntu compiler
  # here when the base WSL distribution intentionally omits build-essential.
  host_root="${GAR_HOST_TOOL_ROOT:-${HOME}/.cache/gar-host-gcc/root}"
  host_gcc="${host_root}/usr/bin/x86_64-linux-gnu-gcc-13"
  if [[ ! -x "${host_gcc}" ]]; then
    cat >&2 <<'EOF'
A native host C compiler is required to prepare the RK3506 kernel modules.
Install build-essential, flex, bison and m4 in WSL, or set RK3506_KERNEL_HOSTCC.
EOF
    exit 1
  fi
  export PATH="${host_root}/usr/bin:${PATH}"
  export LD_LIBRARY_PATH="${host_root}/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  export BISON_PKGDATADIR="${host_root}/usr/share/bison"
  export M4="${host_root}/usr/bin/m4"
  host_make_args+=("HOSTCC=${host_gcc} -B${host_root}/usr/lib/gcc/x86_64-linux-gnu/13/ -B${host_root}/usr/bin/")
fi

for command in make flex bison; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "missing RK3506 kernel build dependency: ${command}" >&2
    exit 1
  }
done

build_dir="${RK3506_KERNEL_BUILD_DIR:-${sdk_root}/output/gar-kernel-modules/${target_release}}"
make_args=(
  -C "${kernel_source}"
  "O=${build_dir}"
  ARCH=arm
  "CROSS_COMPILE=${cross_compile}"
  "KERNELVERSION=${target_release}"
  "${host_make_args[@]}"
)

make "${make_args[@]}" rk3506_luckfox_defconfig
"${kernel_source}/scripts/config" --file "${build_dir}/.config" \
  --module SPI_ROCKCHIP \
  --module SPI_SPIDEV \
  --disable SPI_ROCKCHIP_MISCDEV
make "${make_args[@]}" olddefconfig
make "${make_args[@]}" modules_prepare
make "${make_args[@]}" \
  drivers/spi/spi-rockchip.ko \
  drivers/spi/spidev.ko

module_destination="${destination}/${target_release}"
mkdir -p "${module_destination}"
for module in spi-rockchip.ko spidev.ko; do
  source_module="${build_dir}/drivers/spi/${module}"
  [[ -f "${source_module}" ]] || {
    echo "RK3506 kernel build did not produce ${source_module}" >&2
    exit 1
  }
  strings "${source_module}" | grep -Fx \
    "vermagic=${target_release} SMP preempt mod_unload ARMv7 thumb2 p2v8 " >/dev/null || {
      echo "unexpected module ABI: ${source_module}" >&2
      exit 1
    }
  install -m 0644 "${source_module}" "${module_destination}/${module}"
done

echo "RK3506 kernel modules: ${module_destination}"
