#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/env.sh"
node --version
npm --version
python3 --version
java -version
rea --version
rea doctor --client codex --provider ghidra --skill --json
