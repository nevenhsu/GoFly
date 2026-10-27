from __future__ import annotations

import hashlib
import json
import plistlib
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[1]))

from setup_adapters import ArtifactIdentity, FormalSetupInput, build_formal_setup_input
from setup_support import validate_generation
from setup_protocol import SetupBridgeError, bundle_id_for_team


class FrozenSupportPlanIntegrationTests(unittest.TestCase):
    def check_actual_generation(self, method: str, os_version: str) -> FormalSetupInput:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            support = root / 'support'
            support.mkdir(mode=0o700)
            payloads = {
                'MountMethod': method.encode(),
                'Image.dmg': b'image',
                'Image.dmg.trustcache': b'trustcache',
            }
            manifest = {'BuildIdentities': []}
            if method == 'cryptex':
                payloads.update({'Image.dmg.cryptex_info': b'info', 'Image.dmg.root_hash': b'root'})
                manifest['BuildIdentities'] = [{
                    'Info': {'Variant': 'Developer Disk Image Cryptex'},
                    'Cryptex1,Version': '27A5228h',
                    'Manifest': {
                        key: {'Info': {'Path': name}}
                        for key, name in (
                            ('Cryptex1,GenericDmg', 'Image.dmg'),
                            ('Cryptex1,GenericTrustCache', 'Image.dmg.trustcache'),
                            ('Cryptex1,CryptexInfoPlist', 'Image.dmg.cryptex_info'),
                            ('Cryptex1,GenericVolume', 'Image.dmg.root_hash'),
                        )
                    },
                }]
            payloads['BuildManifest.plist'] = plistlib.dumps(manifest)
            for name, data in payloads.items():
                path = support / name
                path.write_bytes(data)
                path.chmod(0o600)
            generation = validate_generation(method, support)
            app = root / 'GoFly.app'
            app.mkdir()
            (app / 'GoFly').write_bytes(b'fixture executable')
            artifact = ArtifactIdentity(
                str(app), bundle_id_for_team('ABCDEFGHIJ'), 'GoFly', 'ABCDEFGHIJ',
                'a' * 64, 'b' * 64, 'c' * 64, '2026-10-22T00:00:00Z', {}, '19',
            )
            plan = build_formal_setup_input(
                device_id='0123456789abcdef0123456789abcdef01234567',
                setup_id=str(uuid.uuid4()), nonce=str(uuid.uuid4()),
                artifact=artifact, pairing_transaction_id=str(uuid.uuid4()),
                pairing_sha256='d' * 64,
                support={
                    'method': method, 'osVersion': os_version,
                    'inputFiles': {key: list(value) for key, value in generation.files.items()},
                    'inputManifestSHA256': generation.manifest_sha256,
                },
            )
            decoded = json.loads(plan.raw_manifest)
            self.assertEqual(decoded['method'], method)
            self.assertEqual(decoded['deviceOS'], os_version)
            self.assertEqual(plan.sha256, hashlib.sha256(plan.raw_manifest).hexdigest())
            self.assertEqual({item['filename'] for item in decoded['artifacts']}, set(payloads))
            for item in decoded['artifacts']:
                self.assertEqual(item['byteCount'], len(payloads[item['filename']]))
                self.assertEqual(item['sha256'], hashlib.sha256(payloads[item['filename']]).hexdigest())
            return plan

    def test_actual_personalized_generation_builds_the_frozen_plan(self) -> None:
        self.check_actual_generation('personalized', '26.0')

    def test_major_only_os_is_not_a_frozen_wire_version(self) -> None:
        with self.assertRaisesRegex(SetupBridgeError, 'handoff-unknown'):
            self.check_actual_generation('personalized', '26')

    def test_actual_cryptex_generation_builds_the_frozen_plan(self) -> None:
        self.check_actual_generation('cryptex', '27.0')


if __name__ == '__main__':
    unittest.main()
