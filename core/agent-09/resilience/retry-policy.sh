#!/data/data/com.termux/files/usr/bin/bash
set -u

ATTEMPT="${1:-1}"
BASE="${2:-1}"
MAX="${3:-30}"

DELAY=$((BASE * (2 ** (ATTEMPT-1))))

if [ "$DELAY" -gt "$MAX" ]; then
    DELAY="$MAX"
fi

JITTER=$((RANDOM % 3))
DELAY=$((DELAY + JITTER))

echo "$DELAY"
