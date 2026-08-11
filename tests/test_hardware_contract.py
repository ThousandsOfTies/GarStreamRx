from __future__ import annotations

import csv
import ipaddress
import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class HardwareContractTests(unittest.TestCase):
    def test_requirements_and_luckfox_binding_are_complete_and_neutral(self) -> None:
        hardware = REPOSITORY_ROOT / "hardware"
        requirements = json.loads((hardware / "requirements.json").read_text(encoding="utf-8"))
        binding = json.loads(
            (hardware / "bindings" / "luckfox-rk3506.json").read_text(encoding="utf-8")
        )

        self.assertEqual({"schema_version", "product", "requirements"}, set(requirements))
        self.assertEqual(1, requirements["schema_version"])
        self.assertEqual("gar-stream-rx", requirements["product"])
        by_id = {requirement["id"]: requirement for requirement in requirements["requirements"]}
        self.assertEqual(
            {"display", "lcd-dc", "lcd-rst", "encoder-a", "encoder-b", "encoder-switch", "network"},
            set(by_id),
        )
        self.assertEqual(10000000, by_id["display"]["min_speed_hz"])
        self.assertEqual("ili9341", by_id["display"]["component"])
        self.assertEqual(
            {"ky-040"},
            {by_id[name]["component"] for name in ("encoder-a", "encoder-b", "encoder-switch")},
        )
        self.assertTrue(all(item["required_drivers"] for item in by_id.values()))

        self.assertEqual(1, binding["schema_version"])
        self.assertEqual("gar-stream-rx", binding["product"])
        self.assertEqual("luckfox-rk3506", binding["target_id"])
        self.assertEqual(set(by_id), {item["requirement"] for item in binding["mappings"]})
        lines = {item["requirement"]: item["line"] for item in binding["mappings"] if "line" in item}
        self.assertEqual(
            {"lcd-dc": 3, "lcd-rst": 2, "encoder-a": 8, "encoder-b": 9, "encoder-switch": 10},
            lines,
        )
        self.assertEqual(
            ["RM_IO6:MOSI", "RM_IO5:MISO", "RM_IO7:SCLK", "RM_IO4:CS0"],
            binding["mappings"][0]["physical_pins"],
        )
        self.assertEqual("spi0", binding["mappings"][0]["pinmux"])

        def assert_no_machine_ip(value: object) -> None:
            if isinstance(value, str):
                with self.assertRaises(ValueError):
                    ipaddress.ip_address(value)
            elif isinstance(value, dict):
                for nested in value.values():
                    assert_no_machine_ip(nested)
            elif isinstance(value, list):
                for nested in value:
                    assert_no_machine_ip(nested)

        assert_no_machine_ip(binding)

    def test_legacy_simulator_mapping_remains_product_owned(self) -> None:
        with (REPOSITORY_ROOT / "hardware" / "gpio.csv").open(encoding="utf-8", newline="") as handle:
            gpio = {row["name"]: int(row["line"]) for row in csv.DictReader(handle)}

        self.assertEqual(
            {"encoder_a": 20, "encoder_b": 21, "encoder_sw": 22, "lcd_dc": 23, "lcd_rst": 24},
            gpio,
        )


if __name__ == "__main__":
    unittest.main()
