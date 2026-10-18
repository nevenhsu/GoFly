"""Public durable transaction boundary; no App or device proof substitutes."""

import tempfile
import unittest
from pathlib import Path

from app.GoFlyMac.Bridge.Management.management_journal import ManagementJournal
from app.GoFlyMac.Bridge.Management.management_protocol import ManagementBridgeError, decode_request
import json
from app.GoFlyMac.Bridge.Setup.setup_config import SetupConfiguration
from app.GoFlyMac.Bridge.Setup.setup_producer import SetupProducer
from app.GoFlyMac.Bridge.Setup.setup_protocol import SetupBridgeError, SetupOptions, SetupRequest


def request(operation="11111111-1111-4111-8111-111111111111", selection="22222222-2222-4222-8222-222222222222"):
    return decode_request(json.dumps({
        "protocol": 5, "operation": "management", "requestID": "33333333-3333-4333-8333-333333333333",
        "managementID": operation, "deviceID": "00008110-0000000000000001", "selectionID": selection,
        "kind": "repair", "transport": "USB", "connectionRevision": 0, "action": "apply", "options": None,
    }).encode())


class ManagementJournalTests(unittest.TestCase):
    def test_selection_and_unknown_write_survive_reopen_without_resubmission(self):
        with tempfile.TemporaryDirectory() as directory:
            store = ManagementJournal(Path(directory) / "state")
            with store.lock():
                initial = store.create(request())
                store.put_evidence("sourceActivation", b"original activation bytes")
                store.record_intent("update")
                store.mark_unknown("update", "update-unknown")
            reopened = ManagementJournal(store.root)
            self.assertEqual(reopened.read()["header"], initial["header"])
            self.assertEqual(reopened.read_evidence("sourceActivation"), b"original activation bytes")
            # The real M1 public producer must stop before any device method.
            # object() has no device operations; it cannot fabricate success.
            workspace = Path(__file__).resolve().parents[5]
            config = SetupConfiguration(workspace, workspace / "work/mac-setup-env/bin/python",
                                        Path("/Applications/Xcode.app/Contents/Developer"),
                                        workspace / "app/GoFly/GoFly.xcodeproj",
                                        "com.neven.gofly", "GoFly", store.root)
            setup_request = SetupRequest("33333333-3333-4333-8333-333333333333", "apply",
                                         "66666666-6666-4666-8666-666666666666", request().device_id,
                                         SetupOptions("project", None, "ABCDEFGHIJ", False))
            with self.assertRaises(SetupBridgeError) as blocked:
                SetupProducer(config, device=object()).handle(setup_request)
            self.assertEqual(blocked.exception.code, "transaction-conflict")
            with reopened.lock():
                self.assertEqual(reopened.create(request())["header"], initial["header"])
                with self.assertRaises(ManagementBridgeError):
                    reopened.create(request("44444444-4444-4444-8444-444444444444"))
                with self.assertRaises(ManagementBridgeError):
                    reopened.record_intent("update")
                with self.assertRaises(ManagementBridgeError):
                    reopened.append_revision("55555555-5555-4555-8555-555555555555", "Network")
                with self.assertRaises(ManagementBridgeError):
                    reopened.put_evidence("sourceActivation", b"replacement")
                with self.assertRaises(ManagementBridgeError):
                    reopened.record_intent("complete")
                reopened.put_evidence("activationReceipt", b"exact observed receipt")
                reopened.confirm("update", "activationReceipt")
                changed = reopened.append_revision("55555555-5555-4555-8555-555555555555", "Network")
                self.assertEqual(changed["revisions"][1]["transport"], "Network")
                self.assertEqual(changed["stages"]["update"]["revision"], 0)
                self.assertEqual(changed["header"]["transport"], "USB")

    def test_released_selection_stays_consumed_after_next_transaction(self):
        with tempfile.TemporaryDirectory() as directory:
            store = ManagementJournal(Path(directory) / "state")
            with store.lock():
                first = store.create(request())
                store.release()
                second = request("44444444-4444-4444-8444-444444444444", "55555555-5555-4555-8555-555555555555")
                store.create(second)
                self.assertEqual(store.find_selection(first["header"]["selectionID"])["managementID"], first["header"]["managementID"])
                with self.assertRaises(ManagementBridgeError):
                    store.create(request("66666666-6666-4666-8666-666666666666"))
                store.release()
                with self.assertRaises(ManagementBridgeError):
                    store.create(request(first["header"]["managementID"], "77777777-7777-4777-8777-777777777777"))
            self.assertEqual(ManagementJournal(store.root).read()["header"]["managementID"], second.management_id)
            # Reject an incomplete record even if a disk edit labels it done.
            malformed = store.read()
            malformed["stages"]["complete"] = {"state": "confirmed", "revision": 0, "evidence": None}
            malformed["outcome"] = "confirmed"
            store.path.write_text(json.dumps(malformed))
            with self.assertRaises(ManagementBridgeError):
                ManagementJournal(store.root).read()


if __name__ == "__main__":
    unittest.main()
