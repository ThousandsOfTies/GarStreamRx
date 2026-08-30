#!/usr/bin/env python3
"""Collect the RK3506 Target Capsule runtime closure."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from collections import deque
from pathlib import Path


PLUGINS = (
    "libgstapp.so",
    "libgstcoreelements.so",
    "libgstjpeg.so",
    "libgstpango.so",
    "libgstrtp.so",
    "libgstrtpmanager.so",
    "libgstudp.so",
    "libgstvideoconvertscale.so",
    "libgstvideofilter.so",
    "libgstvideotestsrc.so",
)

TOOLS = ("dtc", "fdtdump", "fdtget", "fdtoverlay", "fdtput")

# These are supplied by every supported RK3506 Buildroot base image.  Keeping
# the dynamic loader and glibc outside the bundle avoids mixing two libc
# installations in one process.
BASE_SYSTEM_LIBRARIES = {
    "ld-linux-armhf.so.3",
    "libc.so.6",
    "libdl.so.2",
    "libgcc_s.so.1",
    "libm.so.6",
    "libpthread.so.0",
    "libresolv.so.2",
    "librt.so.1",
}

NEEDED_PATTERN = re.compile(r"Shared library: \[([^]]+)]")


def needed(readelf: Path, elf: Path) -> list[str]:
    result = subprocess.run(
        (str(readelf), "-d", str(elf)),
        check=True,
        capture_output=True,
        text=True,
    )
    return NEEDED_PATTERN.findall(result.stdout)


def find_library(runtime_root: Path, soname: str) -> Path | None:
    for directory in (runtime_root / "lib", runtime_root / "usr/lib"):
        candidate = directory / soname
        if candidate.exists():
            return candidate.resolve()
    for directory in (runtime_root / "lib", runtime_root / "usr/lib"):
        if not directory.exists():
            continue
        for candidate in directory.rglob(soname):
            if "gstreamer-1.0" not in candidate.parts:
                return candidate.resolve()
    return None


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source.resolve(), destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--readelf", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    plugin_root = args.runtime_root / "usr/lib/gstreamer-1.0"
    output_lib = args.output / "lib"
    output_plugins = output_lib / "gstreamer-1.0"
    output_tools = args.output / "tools"
    queue: deque[Path] = deque([args.binary])

    for name in PLUGINS:
        source = plugin_root / name
        if not source.is_file():
            raise SystemExit(f"required RK3506 GStreamer plugin is missing: {source}")
        destination = output_plugins / name
        copy_file(source, destination)
        queue.append(destination)

    for name in TOOLS:
        source = args.runtime_root / "usr/bin" / name
        if not source.is_file():
            raise SystemExit(f"required RK3506 Device Tree tool is missing: {source}")
        destination = output_tools / name
        copy_file(source, destination)
        destination.chmod(0o755)
        queue.append(destination)

    copied: dict[str, Path] = {}
    scanned: set[Path] = set()
    while queue:
        elf = queue.popleft()
        resolved = elf.resolve()
        if resolved in scanned:
            continue
        scanned.add(resolved)
        for soname in needed(args.readelf, elf):
            if soname in BASE_SYSTEM_LIBRARIES or soname in copied:
                continue
            source = find_library(args.runtime_root, soname)
            if source is None:
                raise SystemExit(f"RK3506 runtime dependency is missing: {soname} (needed by {elf})")
            destination = output_lib / soname
            copy_file(source, destination)
            copied[soname] = destination
            queue.append(destination)

    font_candidates = tuple((args.runtime_root / "usr/share/fonts").rglob("DejaVuSans.ttf"))
    if not font_candidates:
        raise SystemExit("RK3506 runtime is missing DejaVuSans.ttf; enable BR2_PACKAGE_DEJAVU_SANS")
    copy_file(font_candidates[0], args.output / "share/fonts/DejaVuSans.ttf")
    (args.output / "share/fonts/fonts.conf").write_text(
        """<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">
<fontconfig>
  <dir prefix=\"relative\">.</dir>
  <cachedir>/tmp/gar-stream-rx-font-cache</cachedir>
  <match target=\"pattern\">
    <test qual=\"any\" name=\"family\"><string>sans</string></test>
    <edit name=\"family\" mode=\"prepend\" binding=\"same\"><string>DejaVu Sans</string></edit>
  </match>
</fontconfig>
""",
        encoding="utf-8",
    )

    manifest = args.output / "runtime-libraries.txt"
    manifest.write_text("\n".join(sorted(copied)) + "\n", encoding="utf-8")
    print(f"RK3506 runtime libraries: {len(copied)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
