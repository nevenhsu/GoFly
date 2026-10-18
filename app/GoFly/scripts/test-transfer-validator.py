"""Exercise the actual host executable; never connects to a device."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


EXECUTABLE = os.environ["GOFLY_TRANSFER_VALIDATOR"]
FIXTURE = Path(__file__).resolve().parents[1] / "Tests/Fixtures/Transfer/empty-manifest.json"


class TransferValidatorProcessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gofly-validator-", dir="/private/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.raw = FIXTURE.read_bytes()
        self.manifest = self.root / "manifest.json"
        self.manifest.write_bytes(self.raw)
        self.manifest.chmod(0o600)

    def invoke(self, *arguments):
        return subprocess.run([EXECUTABLE, *map(str, arguments)], capture_output=True, timeout=20)

    def test_actual_valid_package_reports_bound_identity_raw_digest_and_counts(self):
        result = self.invoke("validate", self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b"")
        value = json.loads(result.stdout)
        manifest = json.loads(self.raw)
        expected = {key: manifest[key] for key in (
            "version", "transferID", "dataSetID", "nonce", "sourceDeviceUDID",
            "destinationDeviceUDID", "sourceApp", "targetApp", "setupID", "categories")}
        expected["rawManifestSHA256"] = hashlib.sha256(self.raw).hexdigest()
        expected["counts"] = dict(favorites=0, importedRoutes=0, favoriteRoutes=0, draftNodes=0, gpxPoints=0)
        self.assertEqual(value, expected)
        self.assertEqual(result.stdout, json.dumps(expected, sort_keys=True, separators=(",", ":")).encode() + b"\n")
        self.assertEqual(self.manifest.read_bytes(), self.raw)

    def assert_rejected(self, *arguments):
        result = self.invoke(*arguments)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(result.stderr, (b"invalid-input\n", b"backup-invalid\n"))
        self.assertNotIn(str(self.root).encode(), result.stderr)

    def test_invalid_argv_missing_package_and_closed_schema_fail_safely(self):
        for arguments in ((), ("validate",), ("validate", "."), ("inspect", self.root),
                          ("validate", self.root, "extra"), ("validate", self.root / "missing")):
            with self.subTest(arguments=arguments):
                self.assert_rejected(*arguments)
        self.manifest.write_bytes(self.raw[:-2] + b',"privateDiagnostic":"secret"}\n')
        self.assert_rejected("validate", self.root)
        self.assertIn(b"privateDiagnostic", self.manifest.read_bytes())

    def test_duplicate_keys_or_unlisted_files_do_not_become_valid_backup(self):
        self.manifest.write_bytes(self.raw.replace(b'"version":1', b'"version":1,"version":1'))
        self.assert_rejected("validate", self.root)
        self.manifest.write_bytes(self.raw)
        orphan = self.root / "private-unlisted-file"
        orphan.write_bytes(b"keep this file")
        orphan.chmod(0o600)
        self.assert_rejected("validate", self.root)
        self.assertEqual(orphan.read_bytes(), b"keep this file")

    def test_unsafe_modes_links_and_parent_links_are_rejected_without_repair(self):
        self.manifest.chmod(0o644)
        self.assert_rejected("validate", self.root)
        self.assertEqual(self.manifest.stat().st_mode & 0o7777, 0o644)
        self.manifest.chmod(0o600)
        other = self.root / "alias"
        os.link(self.manifest, other)
        self.assert_rejected("validate", self.root)
        other.unlink()
        link = self.root / "linked-package"
        link.symlink_to(self.root, target_is_directory=True)
        self.assert_rejected("validate", link)
        self.assert_rejected("validate", link / ".." / self.root.name)
        self.assertTrue(link.is_symlink())

    def test_empty_selection_still_requires_bound_identity_and_exact_inventory(self):
        value = json.loads(self.raw)
        value["destinationDeviceUDID"] = "d" * 40
        self.manifest.write_text(json.dumps(value))
        self.assert_rejected("validate", self.root)
        self.assertEqual(json.loads(self.manifest.read_bytes())["destinationDeviceUDID"], "d" * 40)


if __name__ == "__main__":
    unittest.main()
