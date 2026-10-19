from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(PACKAGE_ROOT))

from Reinstall.reinstall_config import ReinstallConfiguration  # noqa: E402
from Setup.setup_protocol import SetupBridgeError  # noqa: E402


WORKSPACE = Path(__file__).resolve().parents[5]


def config_value(validator: Path) -> dict[str, str]:
    return {
        "workspaceRoot": str(WORKSPACE),
        "pythonPath": str(WORKSPACE / "work" / "mac-setup-env" / "bin" / "python"),
        "developerDirectory": "/Applications/Xcode.app/Contents/Developer",
        "projectPath": str(WORKSPACE / "app" / "GoFly" / "GoFly.xcodeproj"),
        "targetBundleID": "com.neven.gofly",
        "targetName": "GoFly",
        "stateRoot": str(Path.home() / "Library" / "Application Support" / "GoFlySetup"),
        "validatorPath": str(validator),
    }


class ReinstallConfigTests(unittest.TestCase):
    def _valid_config(self, root: Path) -> tuple[Path, Path]:
        root = root.resolve()
        macos = root / "MacOS"
        macos.mkdir()
        validator = macos / "GoFlyTransferValidator"
        validator.write_bytes(b"#!/bin/sh\nexit 0\n")
        validator.chmod(0o755)
        config = root / "ReinstallConfiguration.json"
        config.write_text(json.dumps(config_value(validator)), encoding="utf-8")
        return config, validator

    def test_load_preserves_exact_eight_key_schema_and_readonly_validation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config_path, validator = self._valid_config(Path(directory))
            config = ReinstallConfiguration.load(config_path)
            self.assertEqual(config.as_dict(), config_value(validator))
            state_root = config.state_root
            before = state_root.exists()
            config.validate_read_only_paths()
            self.assertEqual(state_root.exists(), before)

    def test_load_rejects_unknown_duplicate_or_wrong_validator_path_without_writes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            config_path, validator = self._valid_config(root)
            original = config_path.read_text(encoding="utf-8")
            config_path.write_text(json.dumps({**config_value(validator), "extra": True}), encoding="utf-8")
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                ReinstallConfiguration.load(config_path)
            duplicate = json.dumps(config_value(validator), separators=(",", ":"))
            duplicate = duplicate[:-1] + ',"targetName":"GoFly"}'
            config_path.write_text(duplicate, encoding="utf-8")
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                ReinstallConfiguration.load(config_path)
            config_path.write_text(original.replace(str(validator), str(root / "WrongValidator")), encoding="utf-8")
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                ReinstallConfiguration.load(config_path)
            self.assertEqual(config_path.read_text(encoding="utf-8"), original.replace(str(validator), str(root / "WrongValidator")))

    def test_readonly_validation_rejects_nonregular_or_nonexecutable_validator_without_repair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            config_path, validator = self._valid_config(root)
            validator.chmod(0o644)
            config = ReinstallConfiguration.load(config_path)
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                config.validate_read_only_paths()
            self.assertEqual(stat.S_IMODE(validator.stat().st_mode), 0o644)
            validator.unlink()
            validator.mkdir()
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                config.validate_read_only_paths()
            self.assertTrue(validator.is_dir())

    def test_validator_mode_requires_owner_execute_without_writes_or_special_bits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            config_path, validator = self._valid_config(root)
            config = ReinstallConfiguration.load(config_path)
            for mode in (0o777, 0o1755, 0o055):
                validator.chmod(mode)
                with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                    config.validate_read_only_paths()
                self.assertEqual(stat.S_IMODE(validator.stat().st_mode), mode)
            validator.chmod(0o755)
            config.validate_read_only_paths()
            validator.chmod(0o700)
            config.validate_read_only_paths()

    def test_readonly_validation_rejects_symlinked_validator(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            config_path, validator = self._valid_config(root)
            target = root / "real-validator"
            target.write_bytes(b"validator")
            target.chmod(0o755)
            validator.unlink()
            validator.symlink_to(target)
            config_path.write_text(json.dumps(config_value(validator)), encoding="utf-8")
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                ReinstallConfiguration.load(config_path)
            self.assertTrue(validator.is_symlink())

    def test_readonly_validation_rejects_any_symlinked_ancestor(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            real = root / "real" / "MacOS"
            real.mkdir(parents=True)
            validator = real / "GoFlyTransferValidator"
            validator.write_bytes(b"validator")
            validator.chmod(0o755)
            link = root / "link"
            link.symlink_to(root / "real", target_is_directory=True)
            config_path = root / "ReinstallConfiguration.json"
            config_path.write_text(json.dumps(config_value(link / "MacOS" / "GoFlyTransferValidator")), encoding="utf-8")
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                ReinstallConfiguration.load(config_path)
            self.assertTrue(link.is_symlink())

    def test_readonly_validation_rejects_non_directory_ancestor(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            config_path, validator = self._valid_config(root)
            config = ReinstallConfiguration.load(config_path)
            macos = validator.parent
            renamed = root / "MacOS-real"
            macos.rename(renamed)
            macos.write_bytes(b"not a directory")
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                config.validate_read_only_paths()
            self.assertTrue(macos.is_file())

    def test_readonly_validation_checks_ancestor_mode_without_repair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            config_path, validator = self._valid_config(root)
            macos = validator.parent
            macos.chmod(0o777)
            config = ReinstallConfiguration.load(config_path)
            with self.assertRaisesRegex(SetupBridgeError, "configuration-invalid"):
                config.validate_read_only_paths()
            self.assertEqual(stat.S_IMODE(macos.stat().st_mode), 0o777)


if __name__ == "__main__":
    unittest.main()
