import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from app.GoFlyMac.Bridge.Management.management_journal import ManagementJournal
from app.GoFlyMac.Bridge.Management.management_producer import ManagementProducer
from app.GoFlyMac.Bridge.Management.management_protocol import ManagementBridgeError, decode_request, encode_response


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

    def test_unresolved_operation_blocks_preflight_before_any_device_access(self) -> None:
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
        preflight = decode_request(json.dumps(request_raw | {"action": "preflight"}).encode())
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            # Configuration validation is outside this journal seam; no
            # hardware or App observation is substituted by this local input.
            config = SimpleNamespace(state_root=state, validate_read_only_paths=lambda: None)
            store = ManagementJournal(state)
            with store.lock():
                store.create(apply_request)
            # These objects cannot return device, PID, or App proof. The
            # public boundary must reject before consulting either one.
            producer = ManagementProducer(config, store=store, device=object(), preparation=object())
            with self.assertRaises(ManagementBridgeError) as blocked:
                producer.handle(preflight)
            self.assertEqual(blocked.exception.code, "transaction-conflict")
            self.assertEqual(store.read()["header"]["managementID"], apply_request.management_id)


if __name__ == "__main__":
    unittest.main()
