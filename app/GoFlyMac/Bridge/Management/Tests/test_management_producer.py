import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from app.GoFlyMac.Bridge.Management.management_journal import ManagementJournal
from app.GoFlyMac.Bridge.Management.management_producer import ManagementProducer
from app.GoFlyMac.Bridge.Management.management_protocol import decode_request, encode_response
from app.GoFlyMac.Bridge.Management.management_adapters import ManagementDeviceObservation, ManagementInstalledIdentity
from app.GoFlyMac.Bridge.Management.management_lineage import ManagementGeneration
from app.GoFlyMac.Bridge.Management.Tests.test_management_lineage import (
    APP, DEVICE, MANAGEMENT_ID, ORIGIN_SETUP, SOURCE_SETUP, TEAM, TARGET_NONCE,
    _activation, _management_fixture, _restore_fixture,
)


class ManagementProducerBoundaryTests(unittest.TestCase):
    def test_query_payload_is_built_from_validated_journal_and_encodes_protocol5(self) -> None:
        request_raw = {
            "protocol": 5, "operation": "management",
            "requestID": "33333333-3333-4333-8333-333333333333",
            "managementID": "11111111-1111-4111-8111-111111111111",
            "deviceID": "00008110-0000000000000001",
            "selectionID": "22222222-2222-4222-8222-222222222222",
            "kind": "repair", "transport": "USB", "connectionRevision": 0,
            "action": "apply", "options": None,
        }
        apply_request = decode_request(json.dumps(request_raw).encode())
        query_request = decode_request(json.dumps({key: value for key, value in request_raw.items() if key != "options"} | {"action": "query"}).encode())
        with tempfile.TemporaryDirectory() as directory:
            store = ManagementJournal(Path(directory) / "state")
            with store.lock():
                store.create(apply_request)
            producer = ManagementProducer(SimpleNamespace(state_root=Path(directory) / "state"), store=store)
            payload = producer.handle(query_request)
            encoded = encode_response(query_request, payload)
            self.assertEqual(json.loads(encoded)["payload"]["stage"], "source")
            self.assertFalse(json.loads(encoded)["payload"]["proof"]["sourceBound"])

    def test_preflight_validates_full_activation_and_repeated_lineage_without_writes(self) -> None:
        old_activation = _activation(ORIGIN_SETUP, "44444444-4444-4444-8444-444444444444")
        current_activation = _activation(SOURCE_SETUP, TARGET_NONCE)
        restore_intent, restore_root, _ = _restore_fixture()
        management_root, generation_request, _ = _management_fixture(restore_root, old_activation)

        class Config:
            def __init__(self, state_root: Path):
                self.state_root = state_root

            def validate_read_only_paths(self) -> None:
                return None

        class Device:
            def observe(self, device_id: str) -> ManagementDeviceObservation:
                return ManagementDeviceObservation(device_id, "27.0", "USB", True, True)

            def installed_identity(self, _device_id: str) -> ManagementInstalledIdentity:
                return ManagementInstalledIdentity(True, build=APP["build"], team_id=TEAM)

            def read_activation(self, _device_id: str) -> bytes:
                return current_activation

            def source_pid(self, _device_id: str) -> int:
                return 0

        class Preparation:
            def read_file(self, _device_id: str, name: str) -> bytes | None:
                return {"restoreIntent": restore_intent, "restoreRoot": restore_root}.get(name)

            def read_management_root(self, _device_id: str) -> bytes:
                return management_root

            def read_management_generation(self, _device_id: str, management_id: str) -> ManagementGeneration | None:
                if management_id != MANAGEMENT_ID:
                    return None
                return ManagementGeneration(generation_request, old_activation, restore_root)

        request = decode_request(json.dumps({
            "protocol": 5, "operation": "management",
            "requestID": "33333333-3333-4333-8333-333333333333",
            "managementID": "11111111-1111-4111-8111-111111111111",
            "deviceID": DEVICE, "selectionID": "22222222-2222-4222-8222-222222222222",
            "kind": "repair", "transport": "USB", "connectionRevision": 0,
            "action": "preflight", "options": None,
        }).encode())
        with tempfile.TemporaryDirectory() as directory:
            payload = ManagementProducer(
                Config(Path(directory) / "state"), device=Device(), preparation=Preparation()
            ).handle(request)
        self.assertEqual(payload["outcome"], "ready")
        self.assertEqual(payload["stage"], "preflight")


if __name__ == "__main__":
    unittest.main()
