#!/usr/bin/env bash
# Build and test the common GarStreamRx C++ source, then cross-compile the
# deployable Ubuntu/aarch64 binary used by the EC2 simulation runtime.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${repo_root}/${GAR_SIM_APP_DIR:-sources/gar-stream-rx}/native"
image="${GAR_RX_BUILD_IMAGE:-gar-build-env:latest}"
output="${1:-${repo_root}/artifacts/native/aarch64/gar-stream-rx}"

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [output-binary]" >&2
  exit 2
fi
if [[ ! -f "${source_dir}/CMakeLists.txt" ]]; then
  echo "missing native source: ${source_dir}" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build the aarch64 simulation binary" >&2
  exit 1
fi

build_root="$(mktemp -d /tmp/gar-stream-rx-build.XXXXXX)"
trap 'rm -rf -- "${build_root}"' EXIT

docker build -t "${image}" "${repo_root}"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  --mount "type=bind,src=${source_dir},dst=/src,readonly" \
  --mount "type=bind,src=${build_root},dst=/build" \
  "${image}" sh -lc '
    cmake -S /src -B /build/host -GNinja \
      -DGAR_RX_BUILD_APP=OFF \
      -DBUILD_TESTING=ON
    cmake --build /build/host
    ctest --test-dir /build/host --output-on-failure
  '

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  --env PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig \
  --mount "type=bind,src=${source_dir},dst=/src,readonly" \
  --mount "type=bind,src=${build_root},dst=/build" \
  "${image}" sh -lc '
    cmake -S /src -B /build/aarch64 -GNinja \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
      -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF
    cmake --build /build/aarch64
    file /build/aarch64/gar-stream-rx
  '

mkdir -p "$(dirname "${output}")"
install -m 0755 "${build_root}/aarch64/gar-stream-rx" "${output}"
echo "Native RX binary: ${output}"
