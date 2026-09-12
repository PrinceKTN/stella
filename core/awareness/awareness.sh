#!/data/data/com.termux/files/usr/bin/bash

set +e

STELLA="$HOME/stella"
POLICY="$STELLA/core/awareness/awareness-policy.json"
STATE_DIR="$STELLA/state"
STATE="$STATE_DIR/awareness.json"
EVENTS="$STELLA/events/events.jsonl"

mkdir -p "$STATE_DIR" "$STELLA/events"

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

TIMESTAMP="$(timestamp)"

# ------------------------------------------------------------
# Basic system measurements
#
# Android/Termux may restrict /proc access.
# Use Termux-compatible commands first and never
# replace an unavailable live measurement with fake zero.
# ------------------------------------------------------------

# CPU count
CPU_COUNT="UNKNOWN"

if command -v nproc >/dev/null 2>&1; then
    CPU_COUNT="$(nproc 2>/dev/null)"
fi

if ! [[ "$CPU_COUNT" =~ ^[0-9]+$ ]] || [ "$CPU_COUNT" -lt 1 ]; then
    CPU_COUNT="UNKNOWN"
fi

# Uptime + load averages
UPTIME_SECONDS="UNKNOWN"
LOAD1="UNKNOWN"
LOAD5="UNKNOWN"
LOAD15="UNKNOWN"

UPTIME_OUTPUT="$(uptime 2>/dev/null || true)"

if [ -n "$UPTIME_OUTPUT" ]; then

    # Extract the three load averages from uptime.
    LOAD_VALUES="$(printf '%s\n' "$UPTIME_OUTPUT" |
        sed -n 's/.*load average: *//p' |
        tr ',' ' ')"

    if [ -n "$LOAD_VALUES" ]; then
        read -r LOAD1 LOAD5 LOAD15 _ <<< "$LOAD_VALUES"
    fi

    # Extract everything between "up" and "load average".
    # Android/Termux uptime may contain commas, for example:
    # "up 1 day, 23:53,  load average: ..."
    UPTIME_TEXT="$(printf '%s\n' "$UPTIME_OUTPUT" |
        sed -n 's/.* up *\(.*\), *load average:.*/\1/p' |
        sed 's/[[:space:]]*$//')"

    if [ -n "$UPTIME_TEXT" ]; then

        if [[ "$UPTIME_TEXT" =~ ^([0-9]+):([0-9][0-9])$ ]]; then
            UPTIME_SECONDS=$((10#${BASH_REMATCH[1]} * 60 +
                              10#${BASH_REMATCH[2]}))

        elif [[ "$UPTIME_TEXT" =~ ^([0-9]+):([0-9]+):([0-9][0-9])$ ]]; then
            UPTIME_SECONDS=$((10#${BASH_REMATCH[1]} * 3600 +
                              10#${BASH_REMATCH[2]} * 60 +
                              10#${BASH_REMATCH[3]}))

        elif [[ "$UPTIME_TEXT" =~ ^([0-9]+)[[:space:]]+days?,[[:space:]]+([0-9]+):([0-9][0-9])$ ]]; then
            UPTIME_SECONDS=$((10#${BASH_REMATCH[1]} * 86400 +
                              10#${BASH_REMATCH[2]} * 3600 +
                              10#${BASH_REMATCH[3]} * 60))

        elif [[ "$UPTIME_TEXT" =~ ^([0-9]+)[[:space:]]+days?,[[:space:]]+([0-9]+):([0-9]+):([0-9][0-9])$ ]]; then
            UPTIME_SECONDS=$((10#${BASH_REMATCH[1]} * 86400 +
                              10#${BASH_REMATCH[2]} * 3600 +
                              10#${BASH_REMATCH[3]} * 60 +
                              10#${BASH_REMATCH[4]}))
        fi
    fi
fi

# Keep unavailable values explicit rather than inventing zeros.
LOAD1="${LOAD1:-UNKNOWN}"
LOAD5="${LOAD5:-UNKNOWN}"
LOAD15="${LOAD15:-UNKNOWN}"

# ------------------------------------------------------------
# Memory
# ------------------------------------------------------------

MEM_TOTAL_MB=0
MEM_AVAILABLE_MB=0
MEM_FREE_MB=0
SWAP_TOTAL_MB=0
SWAP_FREE_MB=0

if command -v free >/dev/null 2>&1; then
    MEM_TOTAL_MB="$(free -m | awk '/^Mem:/ {print $2}')"
    MEM_AVAILABLE_MB="$(free -m | awk '/^Mem:/ {print $7}')"
    MEM_FREE_MB="$(free -m | awk '/^Mem:/ {print $4}')"
    SWAP_TOTAL_MB="$(free -m | awk '/^Swap:/ {print $2}')"
    SWAP_FREE_MB="$(free -m | awk '/^Swap:/ {print $4}')"
fi

MEM_TOTAL_MB="${MEM_TOTAL_MB:-0}"
MEM_AVAILABLE_MB="${MEM_AVAILABLE_MB:-0}"
MEM_FREE_MB="${MEM_FREE_MB:-0}"
SWAP_TOTAL_MB="${SWAP_TOTAL_MB:-0}"
SWAP_FREE_MB="${SWAP_FREE_MB:-0}"

if [ "$SWAP_TOTAL_MB" -gt 0 ] 2>/dev/null; then
    SWAP_USED_MB=$((SWAP_TOTAL_MB - SWAP_FREE_MB))
else
    SWAP_USED_MB=0
fi

# ------------------------------------------------------------
# Storage
# ------------------------------------------------------------

STORAGE_TOTAL_MB=0
STORAGE_AVAILABLE_MB=0

STORAGE_VALUES="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $2, $4}')"

if [ -n "$STORAGE_VALUES" ]; then
    read -r STORAGE_TOTAL_KB STORAGE_AVAILABLE_KB <<EOF2
$STORAGE_VALUES
EOF2

    if [[ "$STORAGE_TOTAL_KB" =~ ^[0-9]+$ ]]; then
        STORAGE_TOTAL_MB=$((STORAGE_TOTAL_KB / 1024))
    fi

    if [[ "$STORAGE_AVAILABLE_KB" =~ ^[0-9]+$ ]]; then
        STORAGE_AVAILABLE_MB=$((STORAGE_AVAILABLE_KB / 1024))
    fi
fi

# ------------------------------------------------------------
# Storage percentage
# ------------------------------------------------------------

STORAGE_USED_PERCENT=0

if [ "$STORAGE_TOTAL_MB" -gt 0 ] 2>/dev/null; then
    STORAGE_USED_MB=$((STORAGE_TOTAL_MB - STORAGE_AVAILABLE_MB))
    STORAGE_USED_PERCENT=$((STORAGE_USED_MB * 100 / STORAGE_TOTAL_MB))
fi

# ------------------------------------------------------------
# Memory percentage
# ------------------------------------------------------------

MEM_AVAILABLE_PERCENT=0

if [ "$MEM_TOTAL_MB" -gt 0 ] 2>/dev/null; then
    MEM_AVAILABLE_PERCENT=$((MEM_AVAILABLE_MB * 100 / MEM_TOTAL_MB))
fi

# ------------------------------------------------------------
# Battery
# ------------------------------------------------------------

BATTERY_AVAILABLE=false
BATTERY_PERCENT=null
BATTERY_STATUS="UNKNOWN"

if command -v termux-battery-status >/dev/null 2>&1; then
    BATTERY_JSON="$(termux-battery-status 2>/dev/null)"

    if [ -n "$BATTERY_JSON" ]; then
        BATTERY_AVAILABLE=true

        BATTERY_PERCENT="$(python3 - "$BATTERY_JSON" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
    value = data.get("percentage")
    print(value if isinstance(value, int) else "null")
except Exception:
    print("null")
PY
)"

        BATTERY_STATUS="$(python3 - "$BATTERY_JSON" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
    value = data.get("status")
    print(value if isinstance(value, str) else "UNKNOWN")
except Exception:
    print("UNKNOWN")
PY
)"
    fi
fi

# ------------------------------------------------------------
# Network
# ------------------------------------------------------------

NETWORK="UNKNOWN"

if command -v curl >/dev/null 2>&1; then
    if curl -Is --max-time 4 https://www.google.com >/dev/null 2>&1; then
        NETWORK="ONLINE"
    else
        NETWORK="OFFLINE_OR_UNREACHABLE"
    fi
fi

# ------------------------------------------------------------
# Load pressure
#
# Load average is compared with logical CPU count.
# It is a pressure signal, not direct CPU utilization.
#
# Android/Termux may restrict /proc access, so the values
# supplied here come from the supported uptime command.
# Unknown values never become fake zeros and never crash
# the awareness engine.
# ------------------------------------------------------------

LOAD_PRESSURE="UNKNOWN"

if [[ "$LOAD1" =~ ^[0-9]+([.][0-9]+)?$ ]] && \
   [[ "$CPU_COUNT" =~ ^[0-9]+$ ]] && \
   [ "$CPU_COUNT" -gt 0 ]; then

    if awk -v load_value="$LOAD1" -v cpus="$CPU_COUNT" \
        "BEGIN { exit !(load_value >= cpus * 1.5) }"; then
        LOAD_PRESSURE="HIGH"

    elif awk -v load_value="$LOAD1" -v cpus="$CPU_COUNT" \
        "BEGIN { exit !(load_value >= cpus * 0.75) }"; then
        LOAD_PRESSURE="ELEVATED"

    else
        LOAD_PRESSURE="NORMAL"
    fi
fi

# ------------------------------------------------------------
# Overall condition
#
# Conservative classification:
# HEALTHY
# GUARDED
# PRESSURED
# CRITICAL
#
# Unknown load pressure does not create a false CRITICAL
# condition by itself. Known memory/storage signals still apply.
# ------------------------------------------------------------

CONDITION="HEALTHY"

if [ "$STORAGE_USED_PERCENT" -ge 95 ] || \
   [ "$MEM_AVAILABLE_PERCENT" -le 10 ] || \
   [ "$LOAD_PRESSURE" = "HIGH" ]; then

    CONDITION="CRITICAL"

elif [ "$STORAGE_USED_PERCENT" -ge 90 ] || \
     [ "$MEM_AVAILABLE_PERCENT" -le 20 ] || \
     [ "$LOAD_PRESSURE" = "ELEVATED" ]; then

    CONDITION="PRESSURED"

elif [ "$STORAGE_USED_PERCENT" -ge 80 ] || \
     [ "$MEM_AVAILABLE_PERCENT" -le 30 ]; then

    CONDITION="GUARDED"
fi

# ------------------------------------------------------------
# Write state
# ------------------------------------------------------------

STATE_TMP="$(mktemp "$STATE_DIR/.awareness.json.tmp.XXXXXX")"
STATE_TARGET="$STATE"

python3 - \
    "$STATE_TMP" \
    "$TIMESTAMP" \
    "$CPU_COUNT" \
    "$UPTIME_SECONDS" \
    "$LOAD1" \
    "$LOAD5" \
    "$LOAD15" \
    "$LOAD_PRESSURE" \
    "$MEM_TOTAL_MB" \
    "$MEM_AVAILABLE_MB" \
    "$MEM_FREE_MB" \
    "$MEM_AVAILABLE_PERCENT" \
    "$SWAP_TOTAL_MB" \
    "$SWAP_USED_MB" \
    "$STORAGE_TOTAL_MB" \
    "$STORAGE_AVAILABLE_MB" \
    "$STORAGE_USED_PERCENT" \
    "$NETWORK" \
    "$BATTERY_AVAILABLE" \
    "$BATTERY_PERCENT" \
    "$BATTERY_STATUS" \
    "$CONDITION" <<'PY'
import json
import sys

(
    path,
    timestamp,
    cpu_count,
    uptime,
    load1,
    load5,
    load15,
    load_pressure,
    mem_total,
    mem_available,
    mem_free,
    mem_available_percent,
    swap_total,
    swap_used,
    storage_total,
    storage_available,
    storage_used_percent,
    network,
    battery_available,
    battery_percent,
    battery_status,
    condition,
) = sys.argv[1:]

report = {
    "schema_version": 1,
    "component": "live-awareness",
    "timestamp": timestamp,

    "device": {
        "cpu_count": int(cpu_count),
        "uptime_seconds": int(uptime)
    },

    "load": {
        "average_1m": float(load1),
        "average_5m": float(load5),
        "average_15m": float(load15),
        "pressure": load_pressure
    },

    "memory": {
        "total_mb": int(mem_total),
        "available_mb": int(mem_available),
        "free_mb": int(mem_free),
        "available_percent": int(mem_available_percent)
    },

    "swap": {
        "total_mb": int(swap_total),
        "used_mb": int(swap_used)
    },

    "storage": {
        "total_mb": int(storage_total),
        "available_mb": int(storage_available),
        "used_percent": int(storage_used_percent)
    },

    "network": {
        "status": network
    },

    "battery": {
        "available": battery_available == "true",
        "percentage": None if battery_percent == "null" else int(battery_percent),
        "status": battery_status
    },

    "assessment": {
        "condition": condition
    },

    "safety": {
        "read_only": True,
        "no_cleanup": True,
        "no_process_kill": True,
        "no_configuration_changes": True
    }
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
    f.write("\n")
PY

RC=$?

if [ "$RC" -eq 0 ]; then
    if python3 -m json.tool "$STATE_TMP" >/dev/null 2>&1; then
        if mv -f "$STATE_TMP" "$STATE_TARGET"; then
            STATE_TMP=""
        else
            RC=1
        fi
    else
        RC=1
    fi
fi

if [ -n "${STATE_TMP:-}" ] && [ -f "$STATE_TMP" ]; then
    rm -f "$STATE_TMP"
fi

# ------------------------------------------------------------
# Event
# ------------------------------------------------------------

if [ "$RC" -eq 0 ]; then
    printf '%s\n' \
        "{\"timestamp\":\"$TIMESTAMP\",\"component\":\"live-awareness\",\"event\":\"awareness.snapshot.updated\",\"data\":{\"condition\":\"$CONDITION\",\"memory_available_mb\":$MEM_AVAILABLE_MB,\"storage_available_mb\":$STORAGE_AVAILABLE_MB,\"load_pressure\":\"$LOAD_PRESSURE\",\"network\":\"$NETWORK\"}}" \
        >> "$EVENTS"
fi

# ------------------------------------------------------------
# Human-readable output
# ------------------------------------------------------------

printf '\n'
printf '╔════════════════════════════════════════════════════════════╗\n'
printf '║              STELLA LIVE AWARENESS                        ║\n'
printf '╚════════════════════════════════════════════════════════════╝\n'
printf '\n'

printf '  CPU cores          : %s\n' "$CPU_COUNT"
printf '  Load average       : %s / %s / %s\n' "$LOAD1" "$LOAD5" "$LOAD15"
printf '  Load pressure      : %s\n' "$LOAD_PRESSURE"
printf '\n'
printf '  Memory total       : %s MiB\n' "$MEM_TOTAL_MB"
printf '  Memory available   : %s MiB\n' "$MEM_AVAILABLE_MB"
printf '  Memory available %% : %s%%\n' "$MEM_AVAILABLE_PERCENT"
printf '\n'
printf '  Swap total         : %s MiB\n' "$SWAP_TOTAL_MB"
printf '  Swap used          : %s MiB\n' "$SWAP_USED_MB"
printf '\n'
printf '  Storage total      : %s MiB\n' "$STORAGE_TOTAL_MB"
printf '  Storage available  : %s MiB\n' "$STORAGE_AVAILABLE_MB"
printf '  Storage used       : %s%%\n' "$STORAGE_USED_PERCENT"
printf '\n'
printf '  Network            : %s\n' "$NETWORK"
printf '  Battery            : %s%% (%s)\n' "${BATTERY_PERCENT:-UNKNOWN}" "$BATTERY_STATUS"
printf '\n'
printf '  DEVICE CONDITION   : %s\n' "$CONDITION"
printf '\n'
printf '  State: %s\n' "$STATE"
printf '  Mode : READ-ONLY / ON-DEMAND\n'
printf '\n'

exit "$RC"
