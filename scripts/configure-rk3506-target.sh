#!/bin/sh
# Add only GarStreamRx's SPI0 node to the currently installed Lyra Plus DTB.
set -eu

fail() {
    echo "gar-stream-rx target configuration: $*" >&2
    exit 2
}

[ "$(id -u)" -eq 0 ] || fail "root is required"
model=$(tr -d '\000' </proc/device-tree/model 2>/dev/null || true)
[ "$model" = "Luckfox Lyra Plus" ] || fail "unsupported board: ${model:-unknown}"

app_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
tools="$app_dir/tools"
export LD_LIBRARY_PATH="$app_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
for tool in dtc fdtget fdtoverlay fdtput; do
    [ -x "$tools/$tool" ] || fail "bundled tool is missing: $tool"
done

if [ -e /dev/spidev0.0 ]; then
    rm -f /var/lib/gar/reboot-required/gar-stream-rx
    exit 0
fi

boot_device=/dev/mtdblock1
[ -r "$boot_device" ] && [ -w "$boot_device" ] || fail "$boot_device is unavailable"
[ -r "$app_dir/rk3506-gar-stream-rx-spi0-overlay.dts" ] || fail "SPI0 overlay is missing"

work=$(mktemp -d /tmp/gar-stream-rx-dtb.XXXXXX)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

header="$work/header.dtb"
patched_header="$work/header.patched.dtb"
current_dtb="$work/current.dtb"
overlay="$work/spi0.dtbo"
patched_dtb="$work/patched.dtb"

dd if="$boot_device" of="$header" bs=2048 count=1 >/dev/null 2>&1
fdt_position=$($tools/fdtget -ti "$header" /images/fdt data-position) || \
    fail "FIT Device Tree position could not be read"
current_size=$($tools/fdtget -ti "$header" /images/fdt data-size) || \
    fail "FIT Device Tree size could not be read"
kernel_position=$($tools/fdtget -ti "$header" /images/kernel data-position) || \
    fail "FIT kernel position could not be read"
hash_algorithm=$($tools/fdtget -ts "$header" /images/fdt/hash algo) || \
    fail "FIT Device Tree hash algorithm could not be read"
for value in "$fdt_position" "$current_size" "$kernel_position"; do
    case "$value" in
        ""|*[!0-9]*) fail "invalid FIT image metadata: $value" ;;
    esac
done
[ "$hash_algorithm" = "sha256" ] || fail "unsupported FIT Device Tree hash: $hash_algorithm"

dd if="$boot_device" of="$current_dtb" bs=1 \
    skip="$fdt_position" count="$current_size" >/dev/null 2>&1

status=$($tools/fdtget -ts "$current_dtb" /spi@ff120000 status 2>/dev/null || true)
compatible=$($tools/fdtget -ts "$current_dtb" /spi@ff120000/spidev@0 compatible 2>/dev/null || true)
if [ "$status" = "okay" ] && [ "$compatible" = "rockchip,spidev" ]; then
    live_status=$(tr -d '\000' </proc/device-tree/spi@ff120000/status 2>/dev/null || true)
    if [ "$live_status" = "okay" ]; then
        rm -f /var/lib/gar/reboot-required/gar-stream-rx
        exit 0
    fi
    mkdir -p /var/lib/gar/reboot-required
    touch /var/lib/gar/reboot-required/gar-stream-rx
    echo "GarStreamRx SPI0 configuration is installed; target reboot is still required."
    exit 10
fi

$tools/dtc -@ -I dts -O dtb \
    -o "$overlay" "$app_dir/rk3506-gar-stream-rx-spi0-overlay.dts"
$tools/fdtoverlay -i "$current_dtb" -o "$patched_dtb" "$overlay"

[ "$($tools/fdtget -ts "$patched_dtb" /spi@ff120000 status)" = "okay" ] || \
    fail "patched SPI0 status verification failed"
[ "$($tools/fdtget -ts "$patched_dtb" /spi@ff120000/spidev@0 compatible)" = "rockchip,spidev" ] || \
    fail "patched spidev verification failed"

patched_size=$(wc -c <"$patched_dtb" | tr -d ' ')
[ $((fdt_position + patched_size)) -le "$kernel_position" ] || \
    fail "patched Device Tree overlaps the FIT kernel image"
mtd_size=$(cat /sys/class/mtd/mtd1/size 2>/dev/null || echo 0)
[ $((fdt_position + patched_size)) -lt "$mtd_size" ] || \
    fail "patched Device Tree exceeds the boot partition"

backup_dir=/var/lib/gar/backups
backup="$backup_dir/luckfox-lyra-plus-boot-original.img"
mkdir -p "$backup_dir"
if [ ! -f "$backup" ]; then
    dd if="$boot_device" of="$backup" bs=4096 >/dev/null 2>&1
    sync
fi

cp "$header" "$patched_header"
$tools/fdtput -ti "$patched_header" /images/fdt data-size "$patched_size"
sha256=$(sha256sum "$patched_dtb" | awk '{print $1}')
hash_values=""
remaining="$sha256"
while [ -n "$remaining" ]; do
    word=$(printf '%s' "$remaining" | cut -c 1-8)
    hash_values="$hash_values 0x$word"
    remaining=$(printf '%s' "$remaining" | cut -c 9-)
done
# hash_values contains eight validated hexadecimal words from sha256sum.
# shellcheck disable=SC2086
$tools/fdtput -tx "$patched_header" /images/fdt/hash value $hash_values
[ "$(wc -c <"$patched_header" | tr -d ' ')" -le "$fdt_position" ] || \
    fail "updated FIT header exceeds its reserved area"

dd if="$patched_header" of="$boot_device" bs=1 seek=0 \
    count="$(wc -c <"$patched_header" | tr -d ' ')" conv=notrunc >/dev/null 2>&1
dd if="$patched_dtb" of="$boot_device" bs=1 \
    seek="$fdt_position" count="$patched_size" conv=notrunc >/dev/null 2>&1
sync

mkdir -p /var/lib/gar/reboot-required
touch /var/lib/gar/reboot-required/gar-stream-rx
echo "GarStreamRx SPI0 configuration installed; target reboot is required."
exit 10
