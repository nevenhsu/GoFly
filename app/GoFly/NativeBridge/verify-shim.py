#!/usr/bin/env python3
"""Entry point kept for NativeBridge/build.sh; the check lives in scripts/."""
import subprocess
import sys
from pathlib import Path

script = Path(__file__).resolve().parents[1] / "scripts" / "verify-native.py"
raise SystemExit(subprocess.call([sys.executable, str(script)]))
