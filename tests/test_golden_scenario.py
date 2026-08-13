from __future__ import annotations

import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class GoldenScenarioTests(unittest.TestCase):
    def test_golden_scenario_owns_every_required_recovery_assertion(self) -> None:
        scenario = json.loads(
            (REPOSITORY_ROOT / "scenarios" / "garstream_golden.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(1, scenario["schema_version"])
        encoded = json.dumps(scenario, sort_keys=True)
        steps = scenario["steps"]
        for required in (
            "source.announce_count",
            "sources.online_count",
            "source.lease_count",
            "frames.sent_count",
            "frames.fps",
            "frames.drop_count",
            "frames.latency_ms",
            "frames.display_update_count",
            "frames.framebuffer_checksum",
            "frames.stream_display_update_count",
            "frames.stream_framebuffer_checksum",
            "encoder.rotate_count",
            '"BRIGHTNESS"',
            '"EXIT"',
            '"view"',
        ):
            self.assertIn(required, encoded)
        self.assertTrue(all(step.get("type") in {"command", "observe", "assert", "wait"} for step in steps))
        self.assertIn(
            {"type": "command", "node": "tx", "via": "runtime", "action": "stop", "params": {}},
            steps,
        )
        self.assertEqual(
            [
                {"type": "command", "node": "tx", "via": "runtime", "action": "stop", "params": {}},
                {"type": "command", "node": "rx", "via": "runtime", "action": "stop", "params": {}},
                {"type": "command", "node": "rx", "via": "runtime", "action": "start", "params": {}},
                {"type": "command", "node": "tx", "via": "runtime", "action": "start", "params": {}},
            ],
            steps[:4],
        )
        self.assertIn(
            {"type": "command", "node": "tx", "via": "runtime", "action": "start", "params": {}},
            steps,
        )
        self.assertIn({"type": "wait", "milliseconds": 8000}, steps)
        self.assertIn(
            {"type": "command", "node": "rx", "action": "rotate", "params": {"device": "rotary", "direction": 1}},
            steps,
        )
        self.assertIn(
            {
                "type": "assert",
                "metric": "rx.received_after",
                "op": "gt",
                "value_metric": "rx.received_before",
                "timeout_ms": 10000,
                "interval_ms": 500,
            },
            steps,
        )
        self.assertIn(
            {
                "type": "assert",
                "metric": "rx.stream_display_after",
                "op": "gt",
                "value_metric": "rx.stream_display_before",
                "timeout_ms": 10000,
                "interval_ms": 500,
            },
            steps,
        )
        observed_paths = {step.get("path") for step in steps if step.get("type") == "observe"}
        self.assertTrue(
            {
                "source.announce_count",
                "sources.online_count",
                "source.lease_count",
                "frames.sent_count",
                "frames.display_update_count",
                "frames.framebuffer_checksum",
                "frames.stream_display_update_count",
                "frames.stream_framebuffer_checksum",
                "frames.drop_count",
                "frames.latency_ms",
                "menu.item",
                "menu.mode",
                "frames.received_count",
            }.issubset(observed_paths)
        )
        self.assertEqual(
            [
                {"type": "command", "node": "rx", "via": "runtime", "action": "start", "params": {}},
                {"type": "command", "node": "tx", "via": "runtime", "action": "start", "params": {}},
            ],
            scenario["cleanup"],
        )
        self.assertNotIn("nodes", scenario)
        self.assertNotIn("bridge_url", encoded)
        self.assertNotIn("127.0.0.1", encoded)


if __name__ == "__main__":
    unittest.main()
