from __future__ import annotations

import ipaddress
import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class SystemTopologyTests(unittest.TestCase):
    def test_garstream_topology_is_complete_and_machine_neutral(self) -> None:
        topology = json.loads((REPOSITORY_ROOT / "gar-system.json").read_text(encoding="utf-8"))

        self.assertEqual(1, topology["schema_version"])
        nodes = {node["id"]: node for node in topology["nodes"]}
        self.assertEqual({"tx", "rx"}, set(nodes))
        self.assertEqual("Local/GarStreamTx", nodes["tx"]["workspace"])
        self.assertEqual("Local/GarStreamRx", nodes["rx"]["workspace"])
        self.assertEqual("gar-stream-tx", nodes["tx"]["app"])
        self.assertEqual("gar-stream-rx", nodes["rx"]["app"])
        self.assertEqual("sim", nodes["tx"]["environment"])
        self.assertEqual("sim", nodes["rx"]["environment"])

        links = {link["id"]: link for link in topology["links"]}
        self.assertEqual({"discovery", "discovery-announce", "media"}, set(links))
        self.assertEqual(
            {"id": "discovery", "protocol": "udp", "port": 5601, "from": "rx", "to": "tx"},
            links["discovery"],
        )
        self.assertEqual(
            {"id": "discovery-announce", "protocol": "udp", "port": 5601, "from": "tx", "to": "rx"},
            links["discovery-announce"],
        )
        self.assertEqual(
            {"id": "media", "protocol": "rtp/udp", "port": 5600, "from": "tx", "to": "rx"},
            links["media"],
        )
        self.assertEqual({"node_private_ip": "tx"}, nodes["rx"]["runtime_env"]["GAR_STREAM_DISCOVERY_PEERS"])
        self.assertEqual({"link_port": "discovery"}, nodes["rx"]["runtime_env"]["GAR_STREAM_DISCOVERY_PORT"])
        self.assertEqual({"link_port": "media"}, nodes["rx"]["runtime_env"]["GAR_STREAM_RX_PORT"])
        self.assertEqual({"link_port": "discovery"}, nodes["tx"]["runtime_env"]["GAR_STREAM_DISCOVERY_PORT"])
        self.assertEqual(["tx", "rx"], topology["order"])

        def walk(value: object) -> None:
            if isinstance(value, str):
                try:
                    ipaddress.ip_address(value)
                except ValueError:
                    return
                self.fail(f"machine IP must not be embedded in topology: {value}")
            elif isinstance(value, dict):
                for item in value.values():
                    walk(item)
            elif isinstance(value, list):
                for item in value:
                    walk(item)

        walk(topology)


if __name__ == "__main__":
    unittest.main()
