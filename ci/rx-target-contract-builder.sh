#!/usr/bin/env bash
# CI-only armhf ELF used to exercise the real Target hook and GAR metadata path.
# Production RK3506 artifacts continue to use scripts/build-native-rx-target.sh
# with the official Buildroot SDK and sysroot.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 OUTPUT" >&2
  exit 2
fi
if ! command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
  echo "arm-linux-gnueabihf-gcc is required" >&2
  exit 1
fi

output="$1"
temporary="$(mktemp -d)"
cleanup() {
  rm -rf -- "$temporary"
}
trap cleanup EXIT

source_file="$temporary/main.c"
printf '%s\n' 'int main(void) {' '    return 0;' '}' >"$source_file"
mkdir -p "$(dirname "$output")"
arm-linux-gnueabihf-gcc -Os -Wl,--build-id -o "$output" "$source_file"
chmod 0755 "$output"
