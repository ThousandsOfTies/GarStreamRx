from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DeploymentProfileTests(unittest.TestCase):
    def test_default_deployment_is_composable(self) -> None:
        result = subprocess.run(
            [str(ROOT / "scripts/product-target-build.sh"), "--describe"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        description = json.loads(result.stdout)
        self.assertEqual("luckfox-rk3506", description["deployment"])
        self.assertEqual("gar-stream-rx", description["application"])
        self.assertEqual("active", description["status"])
        self.assertEqual(
            "scripts/targets/luckfox-rk3506/package.sh",
            description["paths"]["packager"],
        )


if __name__ == "__main__":
    unittest.main()
