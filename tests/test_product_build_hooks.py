from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class ProductBuildHookTests(unittest.TestCase):
    def _run(
        self, script: Path, environment: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(script)],
            cwd=script.parents[1],
            text=True,
            capture_output=True,
            env={**os.environ, **(environment or {})},
            check=False,
        )

    def test_sim_service_is_connection_neutral(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "scripts").mkdir()
            shutil.copy2(
                REPOSITORY_ROOT / "scripts" / "product-sim-build.sh", root / "scripts"
            )
            (root / "scripts" / "build-native-rx.sh").write_text(
                '#!/bin/sh\nmkdir -p "$(dirname "$1")"\nprintf binary > "$1"\n',
                encoding="utf-8",
            )
            (root / "scripts" / "build-native-rx.sh").chmod(0o755)
            (root / "sources/gar-stream-rx/native").mkdir(parents=True)
            (root / "sources/gar-stream-rx/native/CMakeLists.txt").touch()
            (root / "sources/gar-tools/targets/linux-device/runtime").mkdir(
                parents=True
            )
            (root / "panel").mkdir()

            result = self._run(
                root / "scripts/product-sim-build.sh",
                {"GAR_STREAM_DISCOVERY_PEERS": "192.0.2.10"},
            )

            self.assertEqual(0, result.returncode, result.stderr)
            service = (
                root / "artifacts/from-codespace/files/gar-sim-app.service"
            ).read_text(encoding="utf-8")
            environment_file = "EnvironmentFile=-/etc/gar/system/gar-stream-rx.env"
            self.assertIn(environment_file, service)
            self.assertGreater(
                service.index(environment_file),
                service.index("Environment=GAR_STREAM_DISCOVERY_PORT=5601"),
                "the GAR topology port must override the static fallback",
            )
            self.assertGreater(
                service.index(environment_file),
                service.index("Environment=GAR_STREAM_RX_PORT=5600"),
                "the GAR topology port must override the static fallback",
            )
            self.assertNotIn("GAR_STREAM_DISCOVERY_PEERS", service)
            self.assertNotIn("/etc/gar/gar-stream-rx.env", service)
            self.assertNotIn("192.0.2.10", service)
            self.assertIn(
                "Environment=GAR_STREAM_METRICS_PATH=/run/gar/metrics/gar-stream-rx.json",
                service,
            )
            manifest = json.loads(
                (root / "artifacts/from-codespace/artifact.json").read_text(
                    encoding="utf-8"
                )
            )
            files = manifest["deploy"]["app"]["files"]
            self.assertFalse(
                any(item["dest"] == "/etc/gar/gar-stream-rx.env" for item in files)
            )

    def test_target_manifest_never_deploys_untracked_environment_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "scripts").mkdir()
            shutil.copy2(
                REPOSITORY_ROOT / "scripts" / "product-target-build.sh",
                root / "scripts",
            )
            (root / "scripts" / "configure-rk3506-target.sh").touch()
            (root / "scripts" / "configure-rk3506-target.sh").chmod(0o755)
            (root / "config").mkdir()
            (root / "config/rk3506-gar-stream-rx-spi0-overlay.dts").touch()
            (root / "config/gar-stream-rx.target.env").write_text(
                "GAR_STREAM_DISCOVERY_PEERS=192.0.2.10\n", encoding="utf-8"
            )
            builder = root / "fake-builder.sh"
            builder.write_text('#!/bin/sh\nprintf binary > "$1"\n', encoding="utf-8")
            builder.chmod(0o755)

            result = self._run(
                root / "scripts/product-target-build.sh",
                {"GAR_RX_TARGET_BUILDER": str(builder)},
            )

            self.assertEqual(0, result.returncode, result.stderr)
            manifest = json.loads(
                (root / "artifacts/from-codespace/artifact.json").read_text(
                    encoding="utf-8"
                )
            )
            files = manifest["deploy"]["app"]["files"]
            self.assertFalse(
                any(item["dest"] == "/etc/gar/gar-stream-rx.env" for item in files)
            )
            self.assertFalse(
                (
                    root
                    / "artifacts/from-codespace/files/gar-stream-rx/gar-stream-rx.env"
                ).exists()
            )


if __name__ == "__main__":
    unittest.main()
