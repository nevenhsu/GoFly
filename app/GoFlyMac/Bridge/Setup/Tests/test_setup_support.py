from __future__ import annotations

import os
import plistlib
import stat
import tempfile
import types
import unittest
import uuid
from pathlib import Path
from unittest import mock

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
import sys

sys.path.append(str(PACKAGE_ROOT))

import setup_support  # noqa: E402
from setup_protocol import SetupBridgeError  # noqa: E402
from setup_journal import JournalStore, MAX_SUPPORT_GENERATION_BYTES  # noqa: E402


class SupportFixture:
    def __init__(self, root: Path, *, version: str = "27A5228h", nested: bool = False):
        self.root = root
        self.version = version
        self.paths = {
            "Cryptex1,GenericDmg": "nested/Image.dmg" if nested else "Image.dmg",
            "Cryptex1,GenericTrustCache": "nested/Image.dmg.trustcache" if nested else "Image.dmg.trustcache",
            "Cryptex1,CryptexInfoPlist": "nested/Image.dmg.cryptex_info" if nested else "Image.dmg.cryptex_info",
            "Cryptex1,GenericVolume": "nested/Image.dmg.root_hash" if nested else "Image.dmg.root_hash",
        }
        self.payloads = {
            "Cryptex1,GenericDmg": b"image",
            "Cryptex1,GenericTrustCache": b"trustcache",
            "Cryptex1,CryptexInfoPlist": plistlib.dumps({
                "CFBundleIdentifier": "com.apple.MobileAsset.DDI", "CFBundleVersion": version
            }),
            "Cryptex1,GenericVolume": b"root-hash",
        }

    def manifest(self, *, include_version: bool = True) -> bytes:
        identity = {
            "Info": {"Variant": "iOS Developer Disk Image Cryptex"},
            "Cryptex1,UseProductClass": True,
            "Cryptex1,SubType": 1,
            "Cryptex1,NonceDomain": 1,
            "Cryptex1,PreauthorizationVersion": 1,
            "Manifest": {
                key: {"Info": {"Path": path}}
                for key, path in self.paths.items()
            },
        }
        if include_version:
            identity["Cryptex1,Version"] = self.version
        return plistlib.dumps({"BuildIdentities": [identity]}, fmt=plistlib.FMT_BINARY)

    def write_source(self) -> None:
        (self.root / "BuildManifest.plist").write_bytes(self.manifest())
        for key, path in self.paths.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(self.payloads[key])

    def write_formal(self, target: Path, *, include_version: bool = True) -> None:
        target.mkdir(mode=0o700)
        (target / "MountMethod").write_bytes(b"cryptex")
        (target / "BuildManifest.plist").write_bytes(self.manifest(include_version=include_version))
        for key, filename in {
            "Cryptex1,GenericDmg": "Image.dmg",
            "Cryptex1,GenericTrustCache": "Image.dmg.trustcache",
            "Cryptex1,CryptexInfoPlist": "Image.dmg.cryptex_info",
            "Cryptex1,GenericVolume": "Image.dmg.root_hash",
        }.items():
            (target / filename).write_bytes(self.payloads[key])
        for child in target.iterdir():
            child.chmod(0o600)


class SupportSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        patcher = mock.patch.object(setup_support, "LOCAL_XCODE_DDI_RESTORE", Path("/nonexistent/gofly-test-ddi"))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_observed_version_matches_payload_info_instead_of_manifest_placeholder(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            formal = Path(directory) / "formal"
            fixture = SupportFixture(Path(directory), version="39.999.999.0.0,0")
            fixture.payloads["Cryptex1,CryptexInfoPlist"] = plistlib.dumps({
                "CFBundleIdentifier": "com.apple.MobileAsset.DDI", "CFBundleVersion": "27.1.9275.0"
            })
            fixture.write_formal(formal)
            adapter = setup_support.PinnedSupportAdapter(object(), restore_dir=formal)
            self.assertEqual(adapter._selected_cryptex_version(), "27.1.9275.0")
            setup_support.PinnedSupportAdapter._require_matching_ddi(
                [types.SimpleNamespace(identifier="com.apple.MobileAsset.DDI", version="27.1.9275.0")],
                adapter._selected_cryptex_version(),
            )

    def test_local_xcode_source_is_validated_before_download_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "xcode"
            source.mkdir()
            fixture = SupportFixture(source)
            fixture.write_source()
            with mock.patch.object(setup_support, "LOCAL_XCODE_DDI_RESTORE", source), \
                 mock.patch.object(setup_support.importlib, "import_module", side_effect=AssertionError("must not download")):
                formal = root / "formal"
                setup_support._ensure_fetched_generation("cryptex", formal)
            self.assertEqual((formal / "BuildManifest.plist").read_bytes(), fixture.manifest())

    def test_small_journal_can_describe_real_support_payload_sizes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = JournalStore(Path(directory) / "state")
            setup_id = str(uuid.uuid4())
            journal = store.create(setup_id, "0" * 40, {
                "source": "project", "artifactPath": None, "teamID": "ABCDEFGHIJ",
                "allowProvisioningUpdates": False, "targetBundleID": "com.neven.gofly",
                "targetName": "GoFly", "artifact": None,
            })
            inventory = [
                {"id": str(uuid.uuid4()), "filename": name, "byteCount": size, "sha256": "a" * 64}
                for name, size in (("BuildManifest.plist", 804946), ("Image.dmg", 16000000))
            ]
            journal["handoff"] = {"nonce": str(uuid.uuid4()), "setupID": setup_id, "formalArtifacts": inventory}
            store.update(journal)
            self.assertEqual(store.read()["handoff"]["formalArtifacts"], inventory)
            inventory[0]["byteCount"] = MAX_SUPPORT_GENERATION_BYTES
            with self.assertRaisesRegex(SetupBridgeError, "storage-unavailable"):
                store.update(journal)
            inventory[0]["byteCount"] = MAX_SUPPORT_GENERATION_BYTES + 1
            with self.assertRaisesRegex(SetupBridgeError, "storage-unavailable"):
                store.update(journal)

    def test_apple_manifest_larger_than_protocol_manifest_survives_full_copy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            fixture = SupportFixture(base)
            fixture.write_source()
            manifest = plistlib.loads(fixture.manifest())
            manifest["FixtureMetadata"] = "x" * (805 * 1024)
            raw = plistlib.dumps(manifest)
            (base / "BuildManifest.plist").write_bytes(raw)
            formal = base / "formal"
            formal.mkdir(mode=0o700)
            setup_support._copy_fetched_cryptex(base, formal)
            setup_support._write_method(formal, "cryptex")
            generation = setup_support.validate_generation("cryptex", formal)
            actual = setup_support._materialize_cryptex_restore(formal)
            self.assertEqual(generation.files["manifest"][0], len(raw))
            self.assertEqual((actual / "BuildManifest.plist").read_bytes(), raw)

    def test_oversized_apple_manifest_remains_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "BuildManifest.plist"
            path.write_bytes(b"x" * (setup_support.MAX_SUPPORT_MANIFEST_BYTES + 1))
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support._read_manifest(path, private=False)

    def test_missing_cryptex_version_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = SupportFixture(Path(directory))
            fixture.write_formal(Path(directory) / "formal", include_version=False)
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support.PinnedSupportAdapter._selected_cryptex_version(
                    mock.Mock(restore_dir=Path(directory) / "formal")
                )

    def test_installed_cryptex_version_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = SupportFixture(Path(directory))
            fixture.write_formal(Path(directory) / "formal")
            adapter = mock.Mock(restore_dir=Path(directory) / "formal")
            adapter._selected_cryptex_version = setup_support.PinnedSupportAdapter._selected_cryptex_version.__get__(
                adapter, type(adapter)
            )
            self.assertEqual(adapter._selected_cryptex_version(), "27A5228h")
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support.PinnedSupportAdapter._require_matching_ddi(
                    [types.SimpleNamespace(identifier="com.apple.MobileAsset.DDI", version="27A5227h")],
                    "27A5228h",
                )

    def test_actual_restore_preserves_nested_manifest_paths_and_revalidates_reuse(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            fixture = SupportFixture(base, nested=True)
            formal = base / "formal"
            fixture.write_formal(formal)
            actual = setup_support._materialize_cryptex_restore(formal)
            self.assertTrue((actual / "nested/Image.dmg").is_file())
            self.assertEqual((actual / "nested/Image.dmg").read_bytes(), b"image")
            (actual / "nested/Image.dmg").write_bytes(b"tampered")
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support._materialize_cryptex_restore(formal)

    def test_apply_rebuilds_only_missing_derived_restore_from_exact_private_formal_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            formal = base / "formal"
            SupportFixture(base, nested=True).write_formal(formal)
            adapter = setup_support.PinnedSupportAdapter(object())
            # A missing derived copy can result from a crash between the two
            # sibling publications. It carries no independent device proof.
            adapter.prepare_generation("cryptex", formal)
            actual = formal.with_name(formal.name + ".actual")
            self.assertEqual((actual / "nested/Image.dmg").read_bytes(), (formal / "Image.dmg").read_bytes())
            (actual / "nested/Image.dmg").write_bytes(b"corrupt")
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                adapter.prepare_generation("cryptex", formal)
            self.assertEqual((actual / "nested/Image.dmg").read_bytes(), b"corrupt")

    def test_generation_labels_match_the_frozen_handoff_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            formal = base / "formal"
            SupportFixture(base).write_formal(formal)
            generation = setup_support.validate_generation("cryptex", formal)
            self.assertEqual(set(generation.files), {"MountMethod", "manifest", "image", "trustcache", "cryptex_info", "root_hash"})
            self.assertEqual(generation.files["MountMethod"][0], len(b"cryptex"))

    def test_pinned_local_loader_reads_exact_nested_derived_inventory(self) -> None:
        # Explicit path is required: the dependency must never fetch a DDI.
        from pymobiledevice3.services.cryptexd import load_cryptex1_assets
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            formal = base / "formal"
            fixture = SupportFixture(base, nested=True)
            fixture.write_formal(formal)
            setup_support.PinnedSupportAdapter(object()).prepare_generation("cryptex", formal)
            assets = load_cryptex1_assets(formal.with_name(formal.name + ".actual"))
            self.assertEqual(assets.image, fixture.payloads["Cryptex1,GenericDmg"])
            self.assertEqual(assets.trustcache, fixture.payloads["Cryptex1,GenericTrustCache"])
            self.assertEqual(assets.info, fixture.payloads["Cryptex1,CryptexInfoPlist"])
            self.assertEqual(assets.volumehash, fixture.payloads["Cryptex1,GenericVolume"])
            self.assertEqual(assets.cryptex1_properties["Cryptex1,Version"], fixture.version)

    def test_symlinked_manifest_ancestor_is_rejected_without_escape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            fixture = SupportFixture(base, nested=True)
            formal = base / "formal"
            fixture.write_formal(formal)
            outside = base / "outside"
            outside.mkdir()
            (formal / "nested").symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support._copy_regular(formal / "Image.dmg", formal / "nested" / "escape", max_bytes=1024)
            self.assertFalse((outside / "Image.dmg").exists())

    def test_failed_fetch_does_not_publish_final_and_explicit_retry_succeeds(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / "source"
            source.mkdir()
            fixture = SupportFixture(source)
            fixture.write_source()
            restore = base / "restore"
            original_import = setup_support.importlib.import_module

            def fake_import(name: str):
                if name == "pymobiledevice3.services.cryptexd":
                    return types.SimpleNamespace(fetch_cryptex_ddi=lambda: source)
                return original_import(name)

            with mock.patch.object(setup_support.importlib, "import_module", side_effect=fake_import):
                (source / "Image.dmg.root_hash").unlink()
                with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                    setup_support._ensure_fetched_generation("cryptex", restore)
                self.assertFalse(restore.exists())
                (source / "Image.dmg.root_hash").write_bytes(fixture.payloads["Cryptex1,GenericVolume"])
                setup_support._ensure_fetched_generation("cryptex", restore)
                self.assertTrue(restore.is_dir())
                self.assertTrue((restore / "BuildManifest.plist").is_file())

    def test_private_files_require_the_current_user_even_when_root_owned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            formal = base / "formal"
            SupportFixture(base).write_formal(formal)
            original_fstat = os.fstat
            def root_file_stat(fd):
                value = original_fstat(fd)
                if stat.S_ISREG(value.st_mode):
                    fields = list(value)
                    fields[4] = 0
                    return os.stat_result(fields)
                return value
            with mock.patch.object(setup_support.os, "fstat", side_effect=root_file_stat):
                with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                    setup_support.validate_generation("cryptex", formal)

    def test_private_wrong_mode_hardlink_and_fifo_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            fixture = SupportFixture(base)
            formal = base / "formal"
            fixture.write_formal(formal)
            (formal / "Image.dmg").chmod(0o644)
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support.validate_generation("cryptex", formal)
            (formal / "Image.dmg").chmod(0o600)
            hardlink = base / "hardlink"
            os.link(formal / "Image.dmg", hardlink)
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support._copy_regular(hardlink, base / "copy", max_bytes=1024)
            hardlink.unlink()
            fifo = formal / "Image.dmg"
            fifo.unlink()
            os.mkfifo(fifo, 0o600)
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                setup_support.validate_generation("cryptex", formal)


if __name__ == "__main__":
    unittest.main()
