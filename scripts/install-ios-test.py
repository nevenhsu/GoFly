#!/usr/bin/env python3
"""Device-test install/update entry: full shared setup, never install-only."""
from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "app/GoFlyMac/Bridge/Setup"))
from setup_adapters import PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, close_async_runtime
from setup_config import SetupConfiguration
from setup_journal import JournalStore
from setup_producer import SetupProducer
from setup_protocol import SetupBridgeError, SetupOptions, SetupRequest, bundle_id_for_team, bundle_id_matches_team, normalized_device
from setup_support import PinnedSupportAdapter


def fully_complete(payload) -> bool:
    return (payload.stage == "complete" and payload.outcome == "confirmed"
            and payload.installation_confirmed and payload.pairing_imported
            and payload.support_observed and bool(payload.receipt_sha256))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Exact intended USB iPhone UDID")
    parser.add_argument("--team", help="Existing 10-character signing Team ID")
    parser.add_argument("--mode", choices=("install", "renew"), default="renew")
    parser.add_argument("--action", choices=("preflight", "apply", "status"), default="preflight")
    parser.add_argument("--setup-id", help="Transaction UUID; required for read-only status")
    parser.add_argument("--allow-provisioning-updates", action="store_true")
    args = parser.parse_args(argv)
    if args.action in {"preflight", "apply"} and (not args.team or len(args.team) != 10 or not args.team.isascii() or not args.team.isalnum() or args.team.upper() != args.team):
        parser.error("--team requires the existing 10-character uppercase signing Team ID")
    if args.action == "status" and not args.setup_id:
        parser.error("read-only status requires --setup-id")
    # This maintainer-only test installer uses an explicit source-tree runtime.
    # The shipped Mac App instead derives its interpreter and project from Bundle.main.
    target_bundle_id = bundle_id_for_team(args.team) if args.action in {"preflight", "apply"} else None
    config = SetupConfiguration.for_development(
        ROOT,
        ROOT / "work/mac-setup-env/bin/python",
        Path("/Applications/Xcode.app/Contents/Developer"),
        ROOT / "app/GoFly/GoFly.xcodeproj",
        target_bundle_id,
    )
    try:
        config.validate_read_only_paths()
        device_id = normalized_device(args.device)
        setup_id = str(uuid.UUID(args.setup_id)) if args.setup_id else str(uuid.uuid4())
        team_val = args.team
        if args.action == "status":
            journal = JournalStore(config.state_root).read()
            if not isinstance(journal, dict) or journal.get("setupID") != setup_id or journal.get("deviceID") != device_id:
                raise SetupBridgeError("transaction-unknown")
            intent = journal.get("intent", {})
            saved_team = intent.get("teamID")
            saved_bundle_id = intent.get("targetBundleID")
            if (
                not isinstance(saved_team, str)
                or (team_val is not None and team_val != saved_team)
                or not bundle_id_matches_team(saved_bundle_id, saved_team)
            ):
                raise SetupBridgeError("transaction-unknown")
            team_val = saved_team
            config = SetupConfiguration.for_development(
                ROOT,
                ROOT / "work/mac-setup-env/bin/python",
                Path("/Applications/Xcode.app/Contents/Developer"),
                ROOT / "app/GoFly/GoFly.xcodeproj",
                saved_bundle_id,
            )
            config.validate_read_only_paths()
        options = SetupOptions(team_val, args.allow_provisioning_updates) if args.action in {"preflight", "apply"} else None
        request = SetupRequest(str(uuid.uuid4()), args.action, setup_id, device_id, args.mode, options, team_val)
        device = PinnedPymobiledeviceAdapter(
            state_root=config.state_root,
            target_bundle_id=config.target_bundle_id,
        )
        producer = SetupProducer(config, device=device, process=PinnedXcodeProcessAdapter(config),
                                 support=PinnedSupportAdapter(device))
        # Existing journal/lock and exact receipts are shared with the Mac UI.
        # Apply always starts a fresh transaction; no silent retry or app reset.
        print(json.dumps({"action": args.action, "mode": args.mode, "setupID": setup_id}), flush=True)
        if args.action in {"preflight", "apply"}:
            producer.preflight(SetupRequest(request.request_id, "preflight", setup_id, device_id, args.mode,
                                           options, team_val))
            installed = device.installed(device_id)
            print(json.dumps({"installedBuild": installed.build, "pairingWillBeVerified": True}), flush=True)
        payload = producer.handle(request)
        complete = fully_complete(payload)
        print(json.dumps({
            "stage": payload.stage, "outcome": payload.outcome,
            "complete": complete, "proof": payload.as_dict()["proof"],
            "build": payload.app.get("build") if payload.app else None,
            "expiresAt": payload.expires_at,
        }), flush=True)
        if args.action == "preflight":
            return 0
        return 0 if complete else 2
    except SetupBridgeError as error:
        print(json.dumps({"status": "error", "code": error.code}), file=sys.stderr)
        return 1
    except (ValueError, OSError):
        print(json.dumps({"status": "error", "code": "invalid-input-or-storage"}), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted; start over with a new preflight and apply.", file=sys.stderr)
        return 130
    except Exception:
        # Dependency errors may contain credentials; never print exception text.
        print(json.dumps({"status": "error", "code": "operation-failed"}), file=sys.stderr)
        return 1
    finally:
        close_async_runtime()


if __name__ == "__main__":
    raise SystemExit(main())
