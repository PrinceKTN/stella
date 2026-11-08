#!/usr/bin/env bash
# Stella Token Tracker — Simple wrapper for Python implementation

set -euo pipefail

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
PY_SCRIPT="$(dirname "$REAL_SCRIPT")/token_tracker.py"

if [[ ! -f "$PY_SCRIPT" ]]; then
    echo "Error: Python script not found at $PY_SCRIPT" >&2
    exit 1
fi

exec python3 "$PY_SCRIPT" "$@"