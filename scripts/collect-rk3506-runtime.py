#!/usr/bin/env python3
"""Compatibility wrapper for the Luckfox RK3506 Target Capsule."""

from pathlib import Path
import runpy

runpy.run_path(
    str(Path(__file__).resolve().parent / "target/collect-runtime.py"),
    run_name="__main__",
)
