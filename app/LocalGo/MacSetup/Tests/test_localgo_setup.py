import asyncio
import datetime as dt
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import localgo_setup as setup

DEVICE = '00008130-0011223344556677'
TEAM = 'ABCDEFGHIJ'


class ProfileTests(unittest.TestCase):
    def fixtures(self):
        now = dt.datetime(2026, 10, 15, tzinfo=dt.timezone.utc)
        entitlements = {'application-identifier': TEAM + '.' + setup.BUNDLE_ID,
                        'com.apple.developer.team-identifier': TEAM, 'get-task-allow': True}
        profile = {'TeamIdentifier': [TEAM], 'Entitlements': entitlements.copy(),
                   'ProvisionedDevices': [DEVICE], 'Platform': ['iOS'],
                   'ExpirationDate': (now + dt.timedelta(days=7)).replace(tzinfo=None)}
        return {'CFBundleIdentifier': setup.BUNDLE_ID, 'CFBundleExecutable': 'StikDebug'}, entitlements, profile, now

    def test_valid_free_profile_reports_real_expiry(self):
        info, signed, profile, now = self.fixtures()
        self.assertEqual(setup.validate_profile(info, signed, profile, device=DEVICE, team=TEAM, now=now),
                         now + dt.timedelta(days=7))

    def test_mismatched_bundle_team_app_identifier_or_device_fail(self):
        variants = [('info', 'CFBundleIdentifier', 'com.other.app'),
                    ('signed', 'application-identifier', TEAM + '.*'),
                    ('signed', 'com.apple.developer.team-identifier', 'OTHERTEAM1'),
                    ('profile', 'TeamIdentifier', ['OTHERTEAM1']),
                    ('profile', 'ProvisionedDevices', ['00008130-FFFFFFFFFFFFFFFF'])]
        for target, field, value in variants:
            with self.subTest(target=target, field=field):
                info, signed, profile, now = self.fixtures()
                {'info': info, 'signed': signed, 'profile': profile}[target][field] = value
                with self.assertRaises(setup.SetupFailure):
                    setup.validate_profile(info, signed, profile, device=DEVICE, team=TEAM, now=now)

    def test_codesign_uses_inline_requirement_and_certificate_prefix(self):
        info, signed, profile, now = self.fixtures()
        profile['DeveloperCertificates'] = [b'test-certificate']
        commands = []
        def invoke(args, **kwargs):
            commands.append(args)
            if '--entitlements' in args: return plistlib.dumps(signed)
            if args[0] == '/usr/bin/security': return plistlib.dumps(profile)
            for option in args:
                if option.startswith('--extract-certificates='):
                    Path(option.split('=', 1)[1] + '0').write_bytes(b'test-certificate')
            return b''
        display = types.SimpleNamespace(returncode=0,
            stderr=('Authority=Apple Development: Test\nTeamIdentifier=' + TEAM).encode())
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'StikDebug.app'
            app.mkdir()
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            with patch.object(setup, 'run', side_effect=invoke), patch.object(setup.subprocess, 'run', return_value=display):
                setup.validate_app(app, DEVICE, TEAM)
        self.assertTrue(any('-R=anchor apple generic' in args for args in commands))
        self.assertTrue(any(any(arg.startswith('--extract-certificates=') for arg in args) for args in commands))

    def test_production_or_expired_profiles_rejected(self):
        for change in ('profile-task', 'signed-task', 'expired', 'missing-date'):
            with self.subTest(change=change):
                info, signed, profile, now = self.fixtures()
                if change == 'profile-task': profile['Entitlements']['get-task-allow'] = False
                if change == 'signed-task': signed['get-task-allow'] = False
                if change == 'expired': profile['ExpirationDate'] = now.replace(tzinfo=None)
                if change == 'missing-date': profile.pop('ExpirationDate')
                with self.assertRaises(setup.SetupFailure):
                    setup.validate_profile(info, signed, profile, device=DEVICE, team=TEAM, now=now)


class TransferTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin', 'Time Machine metadata is macOS-only')
    def test_state_is_confirmed_excluded_from_macos_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            setup.exclude_state_from_backup(Path(directory))

    def test_launch_argv_places_device_options_before_app_arguments(self):
        transport = '00008130-AABBCCDDEEFF0011'
        control = setup.DeviceControl(transport)
        response = b'{"result":{"process":{"processIdentifier":32}}}'
        with patch.object(setup, 'run', return_value=response) as runner:
            self.assertEqual(control.launch(), 32)
        args = runner.call_args.args[0]
        self.assertLess(args.index('--device'), args.index(setup.BUNDLE_ID))
        self.assertLess(args.index('--json-output'), args.index(setup.BUNDLE_ID))
        self.assertEqual(args[args.index('--device') + 1], transport)

    def test_running_app_prevents_payload_copy(self):
        class Control:
            copied = False
            def launch(self): return 32
            def ensure_stopped(self, pid): raise setup.SetupFailure('localgo-still-running')
            def copy_to(self, local, remote): self.copied = True
        control = Control()
        with tempfile.TemporaryDirectory() as directory, patch.object(setup, 'poll_receipt'):
            with self.assertRaisesRegex(setup.SetupFailure, 'localgo-still-running'):
                setup.deliver(control, b'test-record', DEVICE, Path(directory))
        self.assertFalse(control.copied)

    def test_setup_lock_rejects_second_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            with setup.exclusive_setup(Path(directory)):
                with self.assertRaisesRegex(setup.SetupFailure, 'another-setup-is-running'):
                    with setup.exclusive_setup(Path(directory)):
                        self.fail('second writer acquired lock')

    def test_transfer_order_and_private_payload(self):
        events = []
        captured = {}
        class Control:
            def launch(self): events.append('launch'); return 32
            def ensure_stopped(self, pid): events.append('stopped')
            def copy_to(self, local, remote):
                events.append('copy')
                self_mode = local.stat().st_mode & 0o777
                captured.update(plistlib.loads(local.read_bytes()))
                assert self_mode == 0o600
        def poll(control, remote, local, transaction, **kwargs):
            events.append('ready' if transaction is None else 'receipt')
            if transaction:
                self.assertEqual(transaction, captured['transactionID'])
        with tempfile.TemporaryDirectory() as directory, patch.object(setup, 'poll_receipt', side_effect=poll):
            setup.deliver(Control(), b'record-data', DEVICE, Path(directory))
        self.assertEqual(events, ['launch', 'ready', 'stopped', 'copy', 'launch', 'receipt'])
        self.assertEqual(captured['expectedDeviceUDID'], DEVICE.lower())
        self.assertEqual(captured['sha256'], hashlib.sha256(b'record-data').digest())

    def test_wrong_or_rejected_receipt_never_confirms(self):
        for status, transaction in [('success', 'wrong'), ('rejected', 'expected')]:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                class Control:
                    def copy_from(self, remote, local):
                        local.write_bytes(plistlib.dumps({'version': 1, 'transactionID': transaction, 'status': status}))
                with self.assertRaises(setup.SetupFailure), patch.object(setup.time, 'sleep'):
                    setup.poll_receipt(Control(), 'receipt', Path(directory) / 'receipt', 'expected', attempts=1)

    def test_unknown_process_schema_fails_closed(self):
        control = setup.DeviceControl(DEVICE)
        with patch.object(control, 'call', side_effect=[{}, {'unknown': []}]), self.assertRaises(setup.SetupFailure):
            control.ensure_stopped(32)


class PipelineTests(unittest.TestCase):
    def test_personal_team_selection_never_selects_other_paid_team(self):
        preferences = {'IDEProvisioningTeamByIdentifier': {'account': [
            {'teamID': 'PAIDTEAM01', 'isFreeProvisioningTeam': False},
            {'teamID': TEAM, 'isFreeProvisioningTeam': True}]}}
        self.assertEqual(setup.personal_team(preferences), TEAM)
        preferences['IDEProvisioningTeamByIdentifier']['account'].append(
            {'teamID': 'SECONDTEAM', 'isFreeProvisioningTeam': True})
        with self.assertRaises(setup.SetupFailure): setup.personal_team(preferences)

    def test_multiple_usb_devices_prevent_automatic_build(self):
        async def devices(): return [{'udid': DEVICE}, {'udid': DEVICE}]
        fake = types.SimpleNamespace(check_compatibility=lambda: None,
                                     inspect_devices=devices, inspect_target=None)
        args = types.SimpleNamespace(device=None, team=None, execute=True)
        with patch.dict(sys.modules, {'localgo_device': fake}), patch.object(setup, 'build_app') as build:
            with self.assertRaises(setup.SetupFailure): asyncio.run(setup.first_setup(args))
            build.assert_not_called()

    def test_invalid_signature_does_not_pair_or_install(self):
        events = []
        async def inspect_target(*args): events.append('target')
        async def pair_device(*args, **kwargs): events.append('pair'); raise AssertionError('must not pair')
        fake = types.SimpleNamespace(check_compatibility=lambda: events.append('api'),
                                     inspect_target=inspect_target, pair_device=pair_device)
        args = types.SimpleNamespace(device=DEVICE, team=TEAM, app=Path('/unused.app'), execute=True)
        with patch.dict(sys.modules, {'localgo_device': fake}), patch.object(setup, 'validate_app',
            side_effect=setup.SetupFailure('bad-signature')), patch.object(setup, 'DeviceControl') as control:
            with self.assertRaises(setup.SetupFailure): asyncio.run(setup.install(args))
            control.assert_not_called()
        self.assertEqual(events, ['api', 'target'])

    def test_preflight_does_not_pair_or_install(self):
        events = []
        async def inspect_target(*args): events.append('target')
        async def pair_device(*args, **kwargs): events.append('pair')
        fake = types.SimpleNamespace(check_compatibility=lambda: None, inspect_target=inspect_target,
                                     pair_device=pair_device)
        args = types.SimpleNamespace(device=DEVICE, team=TEAM, app=Path('/unused.app'), execute=False)
        with patch.dict(sys.modules, {'localgo_device': fake}), patch.object(setup, 'validate_app',
            return_value=dt.datetime(2026, 10, 22, tzinfo=dt.timezone.utc)), patch.object(setup, 'DeviceControl') as control:
            asyncio.run(setup.install(args))
            control.assert_not_called()
        self.assertEqual(events, ['target'])

    def test_safe_failure_does_not_print_dependency_secret(self):
        fake = types.SimpleNamespace(check_compatibility=lambda: (_ for _ in ()).throw(RuntimeError('SECRET-PAIRING')),
                                     inspect_devices=None)
        from io import StringIO
        output = StringIO()
        with patch.dict(sys.modules, {'localgo_device': fake}), patch.object(sys, 'argv', ['localgo_setup', 'devices']), \
             patch.object(sys, 'stderr', output):
            self.assertEqual(setup.main(), 1)
        self.assertNotIn('SECRET', output.getvalue())
        self.assertIn('setup-failed', output.getvalue())


if __name__ == '__main__':
    unittest.main()
