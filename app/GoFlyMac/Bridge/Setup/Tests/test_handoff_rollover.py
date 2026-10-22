from __future__ import annotations
import hashlib
import json
import sys
import unittest
import uuid
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1]))
from setup_adapters import (PinnedPymobiledeviceAdapter, APP_SETUP_ROOT, READBACK_REQUEST,
                            READBACK_RESPONSE, FORMAL_INPUT, ACTIVATION_RECEIPT, V1_INCOMING)
from setup_protocol import SetupBridgeError

DEVICE = "0" * 40
PATHS = (READBACK_REQUEST, READBACK_RESPONSE, FORMAL_INPUT)


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


class MemoryAFC:
    def __init__(self):
        self.files = {}
        self.dirs = {APP_SETUP_ROOT}
        self.renames = 0
        self.fail_after = None
        self.links = set()
    async def stat(self, path):
        if path in self.links: return {"st_ifmt": "S_IFLNK", "st_size": 0}
        if path in self.dirs: return {"st_ifmt": "S_IFDIR"}
        if path not in self.files: raise FileNotFoundError(path)
        return {"st_ifmt": "S_IFREG", "st_size": len(self.files[path])}
    async def makedirs(self, path): self.dirs.add(path)
    async def listdir(self, path):
        prefix = path + "/"
        return [p[len(prefix):] for p in self.files if p.startswith(prefix) and "/" not in p[len(prefix):]]
    async def fopen(self, path, mode): return [path, 0]
    async def fread(self, handle, size):
        value = self.files[handle[0]][handle[1]:handle[1]+size]
        handle[1] += len(value)
        return value
    async def fclose(self, handle): pass
    async def rename(self, source, target):
        if self.fail_after is not None and self.renames >= self.fail_after:
            raise OSError("controlled interrupted rename")
        self.files[target] = self.files.pop(source)
        self.renames += 1


def completed_fixture(service):
    setup, nonce = str(uuid.uuid4()), str(uuid.uuid4())
    app = {"bundleID": "com.neven.gofly", "build": "26", "profileSHA256": "a"*64, "executableSHA256": "b"*64}
    formal = {"version": 1, "setupID": setup, "nonce": nonce, "expectedDeviceUDID": DEVICE,
              "pairingTransactionID": str(uuid.uuid4()), "pairingSHA256": "c"*64, "app": app,
              "teamID": "ABCDEFGHIJ", "signingExpiry": "2030-01-01T00:00:00Z",
              "deviceOS": "26.0", "method": "personalized", "artifacts": []}
    for name in ("MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"):
        content = b"personalized" if name == "MountMethod" else b"fixture"
        formal["artifacts"].append({"id": str(uuid.uuid4()), "filename": name, "byteCount": len(content), "sha256": hashlib.sha256(content).hexdigest()})
    request = {key: formal[key] for key in ("version", "setupID", "nonce", "expectedDeviceUDID", "app")}
    response = dict(request, pairing={"kind": "absent"})
    receipt = dict(formal, rawManifestSHA256=hashlib.sha256(encoded(formal)).hexdigest(), generationID=setup, status="committed")
    service.files.update({READBACK_REQUEST: encoded(request), READBACK_RESPONSE: encoded(response),
                          FORMAL_INPUT: encoded(formal), ACTIVATION_RECEIPT: encoded({"version": 1, "activeSetupID": setup, "receipts": [receipt]})})
    return setup, nonce


class HandoffRolloverTests(unittest.TestCase):
    def setUp(self):
        self.service = MemoryAFC()
        self.adapter = PinnedPymobiledeviceAdapter()
    def retire(self): self.adapter._retire_completed_controls(self.service, device_id=DEVICE)
    def test_fresh_container_does_not_write(self):
        self.retire()
        self.assertEqual(self.service.renames, 0)
    def test_two_completed_transactions_archive_only_controls(self):
        self.service.files['Documents/favorites.json'] = b'user data'
        for _ in range(2):
            setup, nonce = completed_fixture(self.service)
            expected = {path: self.service.files[path] for path in PATHS}
            activation = self.service.files[ACTIVATION_RECEIPT]
            self.retire()
            for path in PATHS:
                self.assertNotIn(path, self.service.files)
                archived = f"{APP_SETUP_ROOT}/retired/{setup}-{nonce}/{path.rsplit('/',1)[1]}"
                self.assertEqual(self.service.files[archived], expected[path])
            self.assertEqual(self.service.files[ACTIVATION_RECEIPT], activation)
        self.assertEqual(self.service.files['Documents/favorites.json'], b'user data')
    def test_partial_roots_fail_before_any_write(self):
        for absent in PATHS:
            with self.subTest(absent=absent):
                self.service = MemoryAFC(); completed_fixture(self.service)
                del self.service.files[absent]
                with self.assertRaises(SetupBridgeError): self.retire()
                self.assertEqual(self.service.renames, 0)
    def test_each_interrupted_rename_refuses_retry(self):
        for fail_after in range(3):
            with self.subTest(fail_after=fail_after):
                self.service = MemoryAFC(); completed_fixture(self.service)
                self.service.fail_after = fail_after
                with self.assertRaises(SetupBridgeError): self.retire()
                previous = self.service.renames
                self.service.fail_after = None
                with self.assertRaises(SetupBridgeError): self.retire()
                self.assertEqual(self.service.renames, previous)
    def test_finished_archive_without_new_publish_stays_unknown(self):
        completed_fixture(self.service)
        self.retire()
        with self.assertRaises(SetupBridgeError): self.retire()
        self.assertEqual(self.service.renames, 3)

    def test_existing_archive_even_empty_refuses_rollover(self):
        setup, nonce = completed_fixture(self.service)
        self.service.dirs.add(f"{APP_SETUP_ROOT}/retired/{setup}-{nonce}")
        with self.assertRaises(SetupBridgeError): self.retire()
        self.assertEqual(self.service.renames, 0)
    def test_inactive_historical_receipt_cannot_retire_controls(self):
        completed_fixture(self.service)
        active = json.loads(self.service.files[ACTIVATION_RECEIPT])
        active['activeSetupID'] = str(uuid.uuid4())
        self.service.files[ACTIVATION_RECEIPT] = encoded(active)
        with self.assertRaises(SetupBridgeError): self.retire()
        self.assertEqual(self.service.renames, 0)
    def test_pending_staging_foreign_or_mismatched_controls_fail(self):
        for variant in ('pending', 'staging', 'foreign', 'tamper', 'response', 'symlink'):
            with self.subTest(variant=variant):
                self.service = MemoryAFC(); completed_fixture(self.service)
                if variant == 'pending': self.service.files[V1_INCOMING] = b'pending'
                if variant == 'staging': self.service.files[FORMAL_INPUT+'.staging'] = b'pending'
                if variant == 'foreign':
                    request = json.loads(self.service.files[READBACK_REQUEST]); request['expectedDeviceUDID'] = '1'*40
                    self.service.files[READBACK_REQUEST] = encoded(request)
                if variant == 'tamper': self.service.files[FORMAL_INPUT] += b' '
                if variant == 'response':
                    response = json.loads(self.service.files[READBACK_RESPONSE]); response['app']['build'] = 'wrong'
                    self.service.files[READBACK_RESPONSE] = encoded(response)
                if variant == 'symlink': self.service.links.add(READBACK_RESPONSE)
                with self.assertRaises(SetupBridgeError): self.retire()
                self.assertEqual(self.service.renames, 0)

class CompletedJournalNonceTests(unittest.TestCase):
    def test_uuid_case_does_not_block_repeat_renew_but_other_nonce_does(self):
        import tempfile
        from setup_journal import _completed_eligible
        with tempfile.TemporaryDirectory() as directory:
            transaction = Path(directory)
            candidate = transaction/'pairing.candidate'
            candidate.write_bytes(b'fixture'); candidate.chmod(0o600)
            app_path = transaction/'artifact/GoFly.app'; app_path.mkdir(parents=True)
            setup, nonce = str(uuid.uuid4()), str(uuid.uuid4())
            artifact = dict(path=str(app_path), bundleID='com.neven.gofly', build='26',
                            artifactSHA256='a'*64, executableSHA256='b'*64,
                            profileSHA256='c'*64, teamID='ABCDEFGHIJ', expiresAt='2030-01-01T00:00:00Z')
            formal = [{'fixture': True}]
            manifest = '{}'
            manifest_hash = hashlib.sha256(manifest.encode()).hexdigest()
            tx = str(uuid.uuid4())
            activation = {key: artifact[key] for key in ('bundleID','build','profileSHA256','executableSHA256','teamID')}
            activation.update(setupID=setup,deviceID=DEVICE,nonce=nonce,rawManifestSHA256=manifest_hash,
                              pairingTransactionID=tx,pairingSHA256='d'*64,signingExpiry=artifact['expiresAt'],
                              deviceOS='26.0',method='personalized',generationID=setup,artifacts=formal)
            journal = dict(setupID=setup,deviceID=DEVICE,mode='renew',
                intent=dict(fullSetup=True,artifact=artifact,pairingTransactionID=tx),
                stages={key: {'state':'confirmed'} for key in ('artifact','pairing','install','support','handoff','complete')},
                proof={key:True for key in ('installationConfirmed','pairingImported','supportObserved')},
                delivery={'state':'delivered'},pairing={'sha256':'d'*64},
                support=dict(osVersion='26.0',method='personalized',generationID=setup),
                handoff=dict(nonce=nonce.upper(),manifestSHA256=manifest_hash,formalArtifacts=formal,rawManifest=manifest),
                activationReceipt=activation)
            journal['installOwnership']={key:artifact[key] for key in ('bundleID','build','artifactSHA256','executableSHA256','profileSHA256')}
            journal['installOwnership']['transactionID']=setup
            def seal():
                journal.pop('receiptSHA256',None)
                journal['receiptSHA256']=hashlib.sha256(encoded(journal)).hexdigest()
            seal()
            self.assertTrue(_completed_eligible(journal,transaction))
            activation['nonce']=str(uuid.uuid4()); seal()
            self.assertFalse(_completed_eligible(journal,transaction))

if __name__ == '__main__': unittest.main()
