#!/usr/bin/env python3
"""USB-only LocalGo first setup. Default is a read-only preflight."""
from __future__ import annotations

import argparse
import asyncio
import datetime as dt
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import uuid

BUNDLE_ID = 'com.neven.localgo'
CONTAINER = 'Library/Application Support/LocalGoSetup'
MAX_PAYLOAD = 1024 * 1024 + 65536


class SetupFailure(Exception):
    """Only fixed, non-sensitive messages may leave this tool."""


def checked_id(value: str) -> str:
    if not re.fullmatch(r'(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{16}|[0-9a-fA-F]{40})', value):
        raise SetupFailure('invalid-device-identifier')
    return value.lower()


def private_directory(path: Path) -> Path:
    if path.is_symlink():
        raise SetupFailure('unsafe-state-directory')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not path.is_dir() or path.stat().st_uid != os.getuid():
        raise SetupFailure('unsafe-state-directory')
    path.chmod(0o700)
    return path


def private_write(path: Path, data: bytes) -> None:
    private_directory(path.parent)
    fd, name = tempfile.mkstemp(prefix='.localgo-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextmanager
def exclusive_setup(directory: Path):
    private_directory(directory)
    try:
        fd = os.open(directory / '.setup.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    except OSError:
        raise SetupFailure('state-lock-unavailable') from None
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise SetupFailure('another-setup-is-running') from None
        yield
    finally:
        os.close(fd)


def run(arguments: list[str], *, stage: str, timeout: int = 90) -> bytes:
    try:
        result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise SetupFailure(stage) from None
    if result.returncode:
        raise SetupFailure(stage)
    return result.stdout


def exclude_state_from_backup(directory: Path) -> None:
    run(['/usr/bin/tmutil', 'addexclusion', str(directory)], stage='backup-protection-failed')
    data = run(['/usr/bin/tmutil', 'isexcluded', '-X', str(directory)], stage='backup-protection-failed')
    try:
        items = plistlib.loads(data)
        if not isinstance(items, list) or len(items) != 1 or items[0].get('IsExcluded') != 1:
            raise ValueError()
    except Exception:
        raise SetupFailure('backup-protection-failed') from None


def plist_output(data: bytes) -> dict:
    try:
        value = plistlib.loads(data)
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except Exception:
        raise SetupFailure('invalid-tool-response') from None


def validate_profile(info: dict, signed: dict, profile: dict, *, device: str, team: str,
                     now: dt.datetime | None = None) -> dt.datetime:
    expected = f'{team}.{BUNDLE_ID}'
    entitlements = profile.get('Entitlements', {})
    if not isinstance(entitlements, dict):
        raise SetupFailure('profile-identity-mismatch')
    if (info.get('CFBundleIdentifier') != BUNDLE_ID
        or not re.fullmatch(r'[A-Z0-9]{10}', team)
        or signed.get('application-identifier') != expected
        or entitlements.get('application-identifier') != expected
        or signed.get('com.apple.developer.team-identifier') != team
        or entitlements.get('com.apple.developer.team-identifier') != team
        or profile.get('TeamIdentifier') != [team]
        or info.get('CFBundleExecutable') != 'StikDebug'):
        raise SetupFailure('profile-identity-mismatch')
    if signed.get('get-task-allow') is not True or entitlements.get('get-task-allow') is not True:
        raise SetupFailure('development-signing-required')
    devices = profile.get('ProvisionedDevices', [])
    if not isinstance(devices, list) or device.lower() not in [str(x).lower() for x in devices]:
        raise SetupFailure('device-not-in-profile')
    if 'iOS' not in profile.get('Platform', []):
        raise SetupFailure('ios-profile-required')
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, dt.datetime):
        raise SetupFailure('profile-expired')
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=dt.timezone.utc)
    now = now or dt.datetime.now(dt.timezone.utc)
    if expiry <= now:
        raise SetupFailure('profile-expired')
    return expiry


def validate_app(app: Path, device: str, team: str) -> dt.datetime:
    if not app.is_dir() or app.suffix != '.app' or app.is_symlink():
        raise SetupFailure('signed-localgo-app-required')
    try:
        info = plist_output((app / 'Info.plist').read_bytes())
    except OSError:
        raise SetupFailure('signed-localgo-app-required') from None
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise SetupFailure('localgo-bundle-required')
    run(['/usr/bin/codesign', '--verify', '--strict', '-R=anchor apple generic', str(app)],
        stage='apple-signature-invalid')
    # Display output stays in memory; never forward certificate names or identifiers.
    try:
        shown = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(app)],
                               capture_output=True, timeout=20, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise SetupFailure('signature-inspection-failed') from None
    if (shown.returncode or b'Authority=Apple Development:' not in shown.stderr
        or ('TeamIdentifier=' + team).encode() not in shown.stderr):
        raise SetupFailure('apple-development-signature-required')
    signed = plist_output(run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)],
                              stage='entitlements-unavailable'))
    profile = plist_output(run(['/usr/bin/security', 'cms', '-D', '-i',
                                str(app / 'embedded.mobileprovision')], stage='profile-unavailable'))
    expiry = validate_profile(info, signed, profile, device=device, team=team)
    with tempfile.TemporaryDirectory(prefix='localgo-cert-') as directory:
        prefix = Path(directory) / 'leaf'
        run(['/usr/bin/codesign', '-d', '--extract-certificates=' + str(prefix), str(app)],
            stage='signature-certificate-unavailable')
        try:
            leaf = Path(str(prefix) + '0').read_bytes()
        except OSError:
            raise SetupFailure('signature-certificate-unavailable') from None
        if leaf not in profile.get('DeveloperCertificates', []):
            raise SetupFailure('certificate-not-in-profile')
    return expiry


class DeviceControl:
    def __init__(self, device: str):
        checked_id(device)
        self.device = device

    def call(self, args: list[str]) -> dict:
        # Launch has trailing app arguments; options after its bundle ID would
        # be forwarded to the app instead of parsed by devicectl.
        command = args[:3] + ['--device', self.device, '--timeout', '60', '--json-output', '-'] + args[3:]
        data = run(['/usr/bin/xcrun', 'devicectl', *command], stage='device-operation-failed')
        try:
            value = json.loads(data)
            if value.get('outcome') == 'failed' or value.get('info', {}).get('outcome') == 'failed':
                raise ValueError()
            result = value['result']
            if not isinstance(result, dict):
                raise ValueError()
            return result
        except (ValueError, KeyError, TypeError):
            raise SetupFailure('device-response-unrecognized') from None

    def install(self, app: Path) -> None:
        self.call(['device', 'install', 'app', str(app)])

    def launch(self) -> int:
        result = self.call(['device', 'process', 'launch', '--terminate-existing', BUNDLE_ID])
        pid = result.get('process', {}).get('processIdentifier')
        if type(pid) is not int or pid <= 0:
            raise SetupFailure('launch-pid-unavailable')
        return pid

    def ensure_stopped(self, pid: int) -> None:
        self.call(['device', 'process', 'terminate', '--pid', str(pid)])
        for _ in range(10):
            result = self.call(['device', 'info', 'processes'])
            processes = result.get('runningProcesses')
            if not isinstance(processes, list):
                raise SetupFailure('process-state-unavailable')
            if not any(p.get('processIdentifier') == pid for p in processes):
                # Reject a manually relaunched instance too.
                if any('/StikDebug.app/' in str(p.get('executable', '')) or
                       '/StikDebug.app/' in str(p.get('executableURL', '')) for p in processes):
                    raise SetupFailure('localgo-still-running')
                return
            time.sleep(0.2)
        raise SetupFailure('localgo-still-running')

    def copy_to(self, local: Path, remote: str) -> None:
        self.call(['device', 'copy', 'to', '--source', str(local), '--destination', remote,
                   '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE_ID])

    def copy_from(self, remote: str, local: Path) -> None:
        self.call(['device', 'copy', 'from', '--source', remote, '--destination', str(local),
                   '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE_ID])


def poll_receipt(control: DeviceControl, remote: str, local: Path, transaction: str | None,
                 attempts: int = 15) -> None:
    for _ in range(attempts):
        try:
            if local.exists():
                local.unlink()
            control.copy_from(remote, local)
            if local.is_symlink() or local.stat().st_size > 4096:
                raise SetupFailure('invalid-receipt')
            value = plist_output(local.read_bytes())
            if value.get('version') != 1:
                raise SetupFailure('invalid-receipt')
            if transaction is None:
                if value.get('status') == 'ready':
                    return
            elif value.get('transactionID', '').lower() == transaction.lower():
                if value.get('status') == 'success':
                    return
                raise SetupFailure('pairing-import-rejected')
        except SetupFailure as error:
            if str(error) in ('pairing-import-rejected', 'invalid-receipt'):
                raise
        except (OSError, ValueError, TypeError):
            pass
        time.sleep(0.4)
    raise SetupFailure('receipt-not-confirmed')


def deliver(control: DeviceControl, pairing: bytes, device: str, directory: Path) -> None:
    if len(pairing) > 1024 * 1024:
        raise SetupFailure('pairing-too-large')
    transaction = str(uuid.uuid4())
    payload = plistlib.dumps({'version': 1, 'transactionID': transaction,
                             'expectedDeviceUDID': checked_id(device), 'pairingFile': pairing,
                             'sha256': hashlib.sha256(pairing).digest()}, fmt=plistlib.FMT_BINARY)
    if len(payload) > MAX_PAYLOAD:
        raise SetupFailure('payload-too-large')
    with tempfile.TemporaryDirectory(prefix='handoff-', dir=private_directory(directory)) as temp:
        temp = Path(temp)
        pid = control.launch()
        poll_receipt(control, CONTAINER + '/ready.plist', temp / 'ready.plist', None)
        control.ensure_stopped(pid)
        local = temp / 'incoming.plist'
        private_write(local, payload)
        control.copy_to(local, CONTAINER + '/incoming.plist')
        control.launch()
        poll_receipt(control, CONTAINER + '/receipts/' + transaction + '.plist',
                     temp / 'receipt.plist', transaction)


def build_app(team: str, device: str, directory: Path, allow_updates: bool) -> Path:
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise SetupFailure('xcode-team-required')
    checked_id(device)
    project = Path(__file__).resolve().parents[1] / 'StikDebug.xcodeproj'
    args = ['/usr/bin/xcrun', 'xcodebuild', '-project', str(project), '-scheme', 'StikDebug',
            '-configuration', 'Debug', '-destination', 'id=' + device, '-derivedDataPath', str(directory),
            '-clonedSourcePackagesDirPath', str(directory.parent / 'localgo-packages'),
            'DEVELOPMENT_TEAM=' + team, 'build']
    if allow_updates:
        args.insert(2, '-allowProvisioningUpdates')
    run(args, stage='signed-build-failed-check-xcode-team', timeout=900)
    app = directory / 'Build/Products/Debug-iphoneos/StikDebug.app'
    validate_app(app, device, team)
    return app


async def install(args: argparse.Namespace) -> None:
    from localgo_device import check_compatibility, inspect_target, pair_device
    checked_id(args.device)
    check_compatibility()
    target = await asyncio.wait_for(inspect_target(args.device), timeout=90)
    args.device = getattr(target, 'transport_serial', '') or args.device
    expiry = validate_app(args.app.resolve(), args.device, args.team)
    print('USB target and LocalGo development signature verified.')
    print('Signing expires (UTC): ' + expiry.isoformat())
    if not args.execute:
        print('Preflight only; no pairing, installation or file delivery performed.')
        return
    state = private_directory(args.state.absolute())
    with exclusive_setup(state):
        exclude_state_from_backup(state)
        pairing = await asyncio.wait_for(pair_device(args.device, state / 'pairing', repair=args.repair), timeout=180)
        if pairing.udid.lower() != args.device.lower():
            raise SetupFailure('device-identity-mismatch')
        control = DeviceControl(args.device)
        control.install(args.app.resolve())
        deliver(control, pairing.pairing_data, args.device, state)
    print('LocalGo installed; this setup transaction was imported by the app.')
    print('Enable separately installed LocalDevVPN, then prepare the connection in LocalGo.')
    print('Runtime connection and cross-app location effects still require on-device verification.')


def personal_team(preferences: dict) -> str:
    teams = preferences.get('IDEProvisioningTeamByIdentifier', {})
    if not isinstance(teams, dict):
        raise SetupFailure('select-personal-team-in-xcode')
    found = {item.get('teamID') for group in teams.values() if isinstance(group, list)
             for item in group if isinstance(item, dict) and item.get('isFreeProvisioningTeam') is True}
    if len(found) != 1:
        raise SetupFailure('select-personal-team-in-xcode')
    team = found.pop()
    if not isinstance(team, str) or not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise SetupFailure('select-personal-team-in-xcode')
    return team


async def first_setup(args: argparse.Namespace) -> None:
    from localgo_device import check_compatibility, inspect_devices, inspect_target
    check_compatibility()
    if not args.device:
        devices = await asyncio.wait_for(inspect_devices(), timeout=30)
        if len(devices) != 1:
            raise SetupFailure('connect-exactly-one-usb-iphone-or-select-device')
        args.device = devices[0]['udid']
    checked_id(args.device)
    target = await asyncio.wait_for(inspect_target(args.device), timeout=90)
    args.device = getattr(target, 'transport_serial', '') or args.device
    if not args.team:
        preferences = plist_output(run(['/usr/bin/defaults', 'export', 'com.apple.dt.Xcode', '-'],
                                       stage='select-personal-team-in-xcode'))
        args.team = personal_team(preferences)
    if not args.execute:
        print('USB target and Personal Team selected. Plan: signed build, private RP pairing, install, USB handoff.')
        print('Preflight only; no signing, pairing or installation performed.')
        return
    args.app = build_app(args.team, args.device, args.output.absolute(), args.allow_provisioning_updates)
    await install(args)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    listing = commands.add_parser('devices', help='List USB devices without pairing')
    listing.add_argument('--show-identifiers', action='store_true', help='Print identifiers locally for target selection')
    installing = commands.add_parser('install', help='Validate, then optionally pair/install/deliver')
    installing.add_argument('--device', required=True)
    installing.add_argument('--team', required=True)
    installing.add_argument('--app', type=Path, required=True)
    installing.add_argument('--state', type=Path, default=Path.home() / 'Library/Application Support/LocalGoSetup')
    installing.add_argument('--execute', action='store_true')
    installing.add_argument('--repair', action='store_true', help='Explicitly replace a failed remote pairing')
    building = commands.add_parser('build', help='Build a development-signed app using your Xcode team')
    building.add_argument('--device', required=True)
    building.add_argument('--team', required=True)
    building.add_argument('--output', type=Path, required=True)
    building.add_argument('--allow-provisioning-updates', action='store_true',
                          help='Explicitly allow Xcode to contact Apple to manage signing assets')
    first = commands.add_parser('setup', help='Select one USB iPhone and Personal Team; build, pair, install and deliver')
    first.add_argument('--device', help='Optional if exactly one USB iPhone is connected')
    first.add_argument('--team', help='Optional if Xcode has exactly one free Personal Team')
    first.add_argument('--output', type=Path, required=True)
    first.add_argument('--state', type=Path, default=Path.home() / 'Library/Application Support/LocalGoSetup')
    first.add_argument('--execute', action='store_true')
    first.add_argument('--repair', action='store_true')
    first.add_argument('--allow-provisioning-updates', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.command == 'devices':
            from localgo_device import check_compatibility, inspect_devices
            check_compatibility()
            devices = asyncio.run(asyncio.wait_for(inspect_devices(), timeout=30))
            print('USB devices: ' + str(len(devices)))
            if args.show_identifiers:
                for device in devices:
                    print(device['udid'])
        elif args.command == 'build':
            build_app(args.team, args.device, args.output.resolve(), args.allow_provisioning_updates)
            print('Signed LocalGo build validated.')
        elif args.command == 'setup':
            asyncio.run(first_setup(args))
        else:
            asyncio.run(install(args))
        return 0
    except KeyboardInterrupt:
        print('Setup cancelled; completed device changes are not automatically undone.', file=sys.stderr)
    except Exception as error:
        # Do not forward arbitrary dependency/subprocess errors, which may hold secrets.
        if isinstance(error, SetupFailure):
            message = str(error)
        else:
            code = getattr(error, 'code', '')
            message = code if re.fullmatch(r'[a-z][a-z0-9-]{1,80}', str(code)) else 'setup-failed'
        print('LocalGo setup stopped: ' + message, file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
