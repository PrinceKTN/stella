#!/data/data/com.termux/files/usr/bin/bash
set -u

MAX_WAIT="${STELLA_NETWORK_MAX_WAIT:-1800}"
INTERVAL="${STELLA_NETWORK_CHECK_INTERVAL:-5}"

check_connection() {
    curl -fsS --connect-timeout 5 --max-time 8 \
        https://generativelanguage.googleapis.com \
        >/dev/null 2>&1
}

echo "NETWORK_STATE=CHECKING"

if check_connection; then
    echo "NETWORK_STATE=ONLINE"
    exit 0
fi

echo "NETWORK_STATE=WAITING"
echo "Network unavailable. Waiting for connectivity..."

START="$(date +%s)"

while true; do
    sleep "$INTERVAL"

    if check_connection; then
        echo "NETWORK_STATE=RESUMING"
        echo "✓ Connection restored."
        exit 0
    fi

    NOW="$(date +%s)"
    ELAPSED=$((NOW-START))

    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        echo "NETWORK_STATE=TIMEOUT"
        echo "Network did not recover within configured wait period."
        exit 2
    fi

    echo "  … still waiting (${ELAPSED}s)"
done
