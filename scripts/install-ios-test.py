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
from setup_protocol import SetupBridgeError, SetupOptions, SetupRequest, normalized_device
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
    parser.add_argument("--action", choices=("preflight", "apply", "status", "resume"), default="preflight")
    parser.add_argument("--setup-id", help="Original transaction UUID; required for status/resume")
    parser.add_argument("--allow-provisioning-updates", action="store_true")
    args = parser.parse_args(argv)
    if args.action in {"preflight", "apply"} and (not args.team or len(args.team) != 10 or not args.team.isascii() or not args.team.isalnum() or args.team.upper() != args.team):
        parser.error("--team requires the existing 10-character uppercase signing Team ID")
    if args.action in {"status", "resume"} and not args.setup_id:
        parser.error("status/resume requires the original --setup-id; never start another transaction to retry")
    config = SetupConfiguration(
        ROOT, ROOT / "work/mac-setup-env/bin/python",
        Path("/Applications/Xcode.app/Contents/Developer"),
        ROOT / "app/GoFly/GoFly.xcodeproj", "com.neven.gofly", "GoFly",
        Path.home() / "Library/Application Support/GoFlySetup",
    )
    try:
        config.validate_read_only_paths()
        device_id = normalized_device(args.device)
        setup_id = str(uuid.UUID(args.setup_id)) if args.setup_id else str(uuid.uuid4())
        options = SetupOptions(args.team, args.allow_provisioning_updates) if args.action in {"preflight", "apply"} else None
        request = SetupRequest(str(uuid.uuid4()), args.action, setup_id, device_id, args.mode, options)
        device = PinnedPymobiledeviceAdapter(state_root=config.state_root)
        producer = SetupProducer(config, device=device, process=PinnedXcodeProcessAdapter(config),
                                 support=PinnedSupportAdapter(device))
        # Existing journal/lock and exact receipts are shared with the Mac UI.
        # No alternate install, no silent retry, no deletion or app reset.
        print(json.dumps({"action": args.action, "mode": args.mode, "setupID": setup_id}), flush=True)
        if args.action in {"preflight", "apply"}:
            producer.preflight(SetupRequest(request.request_id, "preflight", setup_id, device_id, args.mode, options))
            installed = device.installed(device_id)
            print(json.dumps({"installedBuild": installed.build, "pairingWillBeVerified": True}), flush=True)
        payload = producer.handle(request)
        complete = fully_complete(payload)
        print(json.dumps({
            "stage": payload.stage, "outcome": payload.outcome, "canResume": payload.can_resume,
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
        print("Interrupted; query this original setupID before any resume.", file=sys.stderr)
        return 130
    except Exception:
        # Dependency errors may contain credentials; never print exception text.
        print(json.dumps({"status": "error", "code": "operation-failed", "next": "query-original-transaction"}), file=sys.stderr)
        return 1
    finally:
        close_async_runtime()


if __name__ == "__main__":
    raise SystemExit(main())
