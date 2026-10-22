#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PYTHONDONTWRITEBYTECODE=1
exec "$root/work/mac-setup-env/bin/python" "$root/scripts/install-ios-test.py" "$@"
