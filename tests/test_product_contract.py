from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ProductContractTests(unittest.TestCase):
    def test_fixed_product_target_and_artifact(self) -> None:
        app = json.loads(next((ROOT / "sources").glob("*/app.json")).read_text(encoding="utf-8"))
        artifact = json.loads((ROOT / "config/artifact.json").read_text(encoding="utf-8"))
        self.assertEqual("gar-stream-rx", app["id"])
        self.assertEqual("luckfox-rk3506", artifact["target"])
        self.assertTrue((ROOT / "scripts/target/package.sh").is_file())
        binding = json.loads((ROOT / "hardware/binding.json").read_text(encoding="utf-8"))
        self.assertEqual("gar-stream-rx", binding["product"])
        self.assertEqual("luckfox-rk3506", binding["target_id"])

    def test_dispatcher_is_absent_and_foreign_target_is_rejected(self) -> None:
        self.assertFalse((ROOT / "scripts/package-target.sh").exists())
        self.assertFalse((ROOT / "scripts/package_target.py").exists())
        self.assertFalse(any((ROOT / "config/deployments").glob("*.json")))
        environment = dict(os.environ)
        environment["GAR_TARGET"] = "raspberry-pi-5"
        result = subprocess.run(
            (str(ROOT / "scripts/product-target-build.sh"), "clean"),
            cwd=ROOT,
            env=environment,
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(2, result.returncode)
        self.assertIn("fixed target luckfox-rk3506", result.stderr)


if __name__ == "__main__":
    unittest.main()
