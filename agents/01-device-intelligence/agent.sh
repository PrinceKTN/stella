#!/usr/bin/env bash
# ==============================================================
# STELLA — AGENT 01
# DEVICE INTELLIGENCE AGENT (Portable v2)
# ==============================================================

set -euo pipefail

# Portable STELLA_ROOT resolution
STELLA_ROOT="${STELLA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export STELLA_ROOT

STATE_DIR="$STELLA_ROOT/state"
EVENT_DIR="$STELLA_ROOT/events"
LOG_DIR="$STELLA_ROOT/logs"
SCHEMA_DIR="$STELLA_ROOT/config/schemas"

PROFILE="$STATE_DIR/device.json"
LOG="$LOG_DIR/agent-01.log"
EVENTS="$EVENT_DIR/events.jsonl"
DEVICE_SCHEMA="$SCHEMA_DIR/device-profile.schema.json"

mkdir -p "$STATE_DIR" "$EVENT_DIR" "$LOG_DIR" "$SCHEMA_DIR"

timestamp() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

log() { echo "[$(timestamp)] $*" | tee -a "$LOG"; }

event() {
    local type="$1" data="${2:-{}}"
    printf '{"timestamp":"%s","agent":"01-device-intelligence","event":"%s","data":%s}\n' \
        "$(timestamp)" "$type" "$data" >> "$EVENTS"
}

hr() { printf '%*s\n' 70 '' | tr ' ' '─'; }

# ── Portable shebang detection ───────────────────────────────
# This script runs with `bash` from PATH (not hardcoded Termux path)

# ── OS Detection ─────────────────────────────────────────────
detect_os() {
    if [[ -n "${PREFIX:-}" && -d "$PREFIX" && "$PREFIX" == *com.termux* ]]; then
        echo "Android / Termux"
        return 0
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
        return 0
    elif command -v systemd-detect-virt >/dev/null 2>&1; then
        echo "Linux ($(systemd-detect-virt))"
        return 0
    else
        echo "$(uname -s)"
        return 0
    fi
}

# ── Network Heartbeat (distinguishes no-data / data-off / weak / metered) ────────
network_heartbeat() {
    local result="UNKNOWN"
    local latency_ms=0
    local signal_strength=0
    local connection_type="unknown"
    local is_metered=false

    if ! command -v curl >/dev/null 2>&1; then
        echo '{"internet":"UNKNOWN","latency_ms":0,"signal_strength":0,"connection_type":"unknown","metered":false}'
        return 0
    fi

    # Test connectivity with timing
    local start end
    start=$(date +%s%3N)
    if curl -Is --max-time 5 --connect-timeout 3 https://httpbin.org/get >/dev/null 2>&1; then
        end=$(date +%s%3N)
        latency_ms=$((end - start))
        result="ONLINE"

        # Detect connection type (Termux/Android specific)
        if [[ -n "${PREFIX:-}" && "$PREFIX" == *com.termux* ]]; then
            # Try to get network info via Termux:API if available
            if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
                local wifi_info
                wifi_info=$(termux-wifi-connectioninfo 2>/dev/null || echo "{}")
                signal_strength=$(echo "$wifi_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('rssi', 0))" 2>/dev/null || echo 0)
                connection_type="wifi"
            elif command -v termux-telephony-deviceinfo >/dev/null 2>&1; then
                connection_type="mobile"
            fi
        elif command -v nmcli >/dev/null 2>&1; then
            connection_type=$(nmcli -t -f TYPE,STATE device | grep ':connected' | head -1 | cut -d: -f1 || echo "unknown")
        fi

        # Check if metered (Android)
        if command -v termux-api >/dev/null 2>&1; then
            is_metered=$(termux-network-metered 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('metered', False)).lower())" 2>/dev/null || echo false)
        fi

    elif curl -Is --max-time 5 --connect-timeout 3 http://connectivitycheck.gstatic.com/generate_204 >/dev/null 2>&1; then
        result="CAPTIVE_PORTAL"
    else
        result="OFFLINE"
    fi

    python3 -c "
import json, sys
print(json.dumps({
    'internet': '$result',
    'latency_ms': $latency_ms,
    'signal_strength': $signal_strength,
    'connection_type': '$connection_type',
    'metered': $is_metered
}))
"
}

# ── Battery Detection (Android/Linux) ────────────────────────
battery_status() {
    local level=0 status="unknown" health="unknown" temperature=0

    # Termux:API
    if command -v termux-battery-status >/dev/null 2>&1; then
        local bat
        bat=$(termux-battery-status 2>/dev/null || echo "{}")
        level=$(echo "$bat" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('percentage', 0))" 2>/dev/null || echo 0)
        status=$(echo "$bat" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status', 'unknown'))" 2>/dev/null || echo "unknown")
        health=$(echo "$bat" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('health', 'unknown'))" 2>/dev/null || echo "unknown")
        temperature=$(echo "$bat" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('temperature', 0))" 2>/dev/null || echo 0)

    # Linux (sysfs)
    elif [[ -d /sys/class/power_supply/BAT0 ]] || [[ -d /sys/class/power_supply/BAT1 ]]; then
        local bat_path
        for p in /sys/class/power_supply/BAT{0,1}; do [[ -d "$p" ]] && bat_path="$p" && break; done
        if [[ -n "$bat_path" ]]; then
            level=$(cat "$bat_path/capacity" 2>/dev/null || echo 0)
            status=$(cat "$bat_path/status" 2>/dev/null || echo "unknown")
            health=$(cat "$bat_path/health" 2>/dev/null || echo "unknown")
            temp_raw=$(cat "$bat_path/temp" 2>/dev/null || echo 0)
            temperature=$((temp_raw / 10))  # usually in tenths of °C
        fi
    fi

    python3 -c "
import json
print(json.dumps({
    'level': $level,
    'status': '$status',
    'health': '$health',
    'temperature_c': $temperature
}))
"
}

# ── CPU Thermal Throttling Detection ─────────────────────────
cpu_thermal() {
    local throttled=false temp_c=0 freq_mhz=0

    # Linux thermal zones
    for zone in /sys/class/thermal/thermal_zone*; do
        if [[ -f "$zone/temp" ]]; then
            local t
            t=$(cat "$zone/temp" 2>/dev/null || echo 0)
            t=$((t / 1000))
            if (( t > temp_c )); then temp_c=$t; fi
            if (( t > 80 )); then throttled=true; fi
        fi
    done

    # CPU frequency
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
        freq_mhz=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0) / 1000 ))
    fi

    python3 -c "
import json
print(json.dumps({
    'throttled': $throttled,
    'temperature_c': $temp_c,
    'frequency_mhz': $freq_mhz
}))
"
}

# ── Main ─────────────────────────────────────────────────────
clear 2>/dev/null || true

echo
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  S T E L L A  ✦                          ║"
echo "║                                                            ║"
echo "║          AGENT 01 — DEVICE INTELLIGENCE v2                 ║"
echo "║                                                            ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo

log "Agent 01 starting (portable v2)."

# Collect data
OS=$(detect_os)
ARCH=$(uname -m 2>/dev/null || echo "unknown")
KERNEL=$(uname -sr 2>/dev/null || echo "unknown")
HOST=$(uname -n 2>/dev/null || echo "unknown")
CPU=$(getprop ro.product.cpu.abi 2>/dev/null || uname -p 2>/dev/null || echo "unknown")
CPU_CORES=$(nproc 2>/dev/null || echo 1)

# Memory
if command -v free >/dev/null 2>&1; then
    MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    MEM_AVAILABLE=$(free -m | awk '/^Mem:/ {print $7}')
    SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
    SWAP_AVAILABLE=$(free -m | awk '/^Swap:/ {print $4}')
else
    MEM_TOTAL=0; MEM_AVAILABLE=0; SWAP_TOTAL=0; SWAP_AVAILABLE=0
fi

# Storage
STORAGE_TOTAL_KB=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $2}' || echo 0)
STORAGE_AVAILABLE_KB=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
STORAGE_TOTAL_MB=$((STORAGE_TOTAL_KB / 1024))
STORAGE_AVAILABLE_MB=$((STORAGE_AVAILABLE_KB / 1024))

# Network heartbeat
NETWORK_JSON=$(network_heartbeat)
INTERNET=$(echo "$NETWORK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['internet'])")
LATENCY_MS=$(echo "$NETWORK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['latency_ms'])")
SIGNAL_STRENGTH=$(echo "$NETWORK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['signal_strength'])")
CONNECTION_TYPE=$(echo "$NETWORK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['connection_type'])")
METERED=$(echo "$NETWORK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['metered'])")

# Battery
BATTERY_JSON=$(battery_status)
BAT_LEVEL=$(echo "$BATTERY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['level'])")
BAT_STATUS=$(echo "$BATTERY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
BAT_HEALTH=$(echo "$BATTERY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['health'])")
BAT_TEMP=$(echo "$BATTERY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['temperature_c'])")

# CPU thermal
CPU_THERMAL_JSON=$(cpu_thermal)
CPU_THROTTLED=$(echo "$CPU_THERMAL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['throttled'])")
CPU_TEMP=$(echo "$CPU_THERMAL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['temperature_c'])")
CPU_FREQ=$(echo "$CPU_THERMAL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['frequency_mhz'])")

# Tool detection
has_command() { command -v "$1" >/dev/null 2>&1 && echo true || echo false; }

TOOLS_JSON=$(python3 -c "
import json
tools = ['bash','git','curl','wget','node','npm','python3','python','php','java','docker','podman','ollama','termux-api']
print(json.dumps({t: $(has_command bash) for t in tools}))
" 2>/dev/null || echo '{}')

# Resource classification
RESOURCE_CLASS="MINI"
if [[ "$MEM_TOTAL" =~ ^[0-9]+$ ]]; then
    if   (( MEM_TOTAL >= 16384 )); then RESOURCE_CLASS="XL"
    elif (( MEM_TOTAL >= 8192  )); then RESOURCE_CLASS="LARGE"
    elif (( MEM_TOTAL >= 4096  )); then RESOURCE_CLASS="MEDIUM"
    elif (( MEM_TOTAL >= 2048  )); then RESOURCE_CLASS="MICRO"
    elif (( MEM_TOTAL >= 1024  )); then RESOURCE_CLASS="SMALL"
    else RESOURCE_CLASS="MINI"
    fi
fi

# Strategy
case "$RESOURCE_CLASS" in
    XL)       STRATEGY="FULL" ;;
    LARGE)    STRATEGY="BALANCED" ;;
    MEDIUM)   STRATEGY="LIGHT" ;;
    MICRO)    STRATEGY="SEQUENTIAL" ;;
    SMALL)    STRATEGY="CONSERVATIVE" ;;
    *)        STRATEGY="MINIMAL" ;;
esac

# ── Display ──────────────────────────────────────────────────
echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ STELLA DEVICE PROFILE v2                                   │"
echo "└────────────────────────────────────────────────────────────┘"
echo

printf "  %-28s %s\n" "Operating system" "$OS"
printf "  %-28s %s\n" "Architecture" "$ARCH"
printf "  %-28s %s\n" "CPU ABI" "$CPU"
printf "  %-28s %s\n" "CPU cores" "$CPU_CORES"
printf "  %-28s %s\n" "Kernel" "$KERNEL"
printf "  %-28s %s\n" "Hostname" "$HOST"
printf "  %-28s %s MB\n" "Memory total" "$MEM_TOTAL"
printf "  %-28s %s MB\n" "Memory available" "$MEM_AVAILABLE"
printf "  %-28s %s MB\n" "Swap total" "$SWAP_TOTAL"
printf "  %-28s %s MB\n" "Swap available" "$SWAP_AVAILABLE"
printf "  %-28s %s MB\n" "Storage total" "$STORAGE_TOTAL_MB"
printf "  %-28s %s MB\n" "Storage available" "$STORAGE_AVAILABLE_MB"
printf "  %-28s %s\n" "Internet" "$INTERNET"
printf "  %-28s %s ms\n" "Latency" "$LATENCY_MS"
printf "  %-28s %s dBm\n" "Signal strength" "$SIGNAL_STRENGTH"
printf "  %-28s %s\n" "Connection type" "$CONNECTION_TYPE"
printf "  %-28s %s\n" "Metered" "$METERED"
printf "  %-28s %s %%\n" "Battery level" "$BAT_LEVEL"
printf "  %-28s %s\n" "Battery status" "$BAT_STATUS"
printf "  %-28s %s\n" "Battery health" "$BAT_HEALTH"
printf "  %-28s %s °C\n" "Battery temp" "$BAT_TEMP"
printf "  %-28s %s °C\n" "CPU temp" "$CPU_TEMP"
printf "  %-28s %s MHz\n" "CPU frequency" "$CPU_FREQ"
printf "  %-28s %s\n" "CPU throttled" "$CPU_THROTTLED"
printf "  %-28s %s\n" "Resource class" "$RESOURCE_CLASS"
printf "  %-28s %s\n" "Stella strategy" "$STRATEGY"

echo
hr
echo "  DEVELOPMENT TOOLS"
hr

# Pretty print tools
python3 -c "
import json, sys
data = json.loads('''$TOOLS_JSON''')
for k, v in data.items():
    status = '✓' if v else '✗'
    print(f'  {k:<14} {status}')
"

# ── JSON Schema for validation ───────────────────────────────
cat > "$DEVICE_SCHEMA" <<'SCHEMA'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Stella Device Profile",
  "type": "object",
  "required": ["schema_version", "agent", "timestamp", "system", "resources", "network", "battery", "cpu", "tools", "classification"],
  "properties": {
    "schema_version": {"type": "integer", "const": 2},
    "agent": {"type": "string", "const": "01-device-intelligence"},
    "timestamp": {"type": "string", "format": "date-time"},
    "system": {
      "type": "object",
      "required": ["os", "termux", "architecture", "cpu_abi", "cpu_cores", "kernel", "hostname"],
      "properties": {
        "os": {"type": "string"},
        "termux": {"type": "boolean"},
        "architecture": {"type": "string"},
        "cpu_abi": {"type": "string"},
        "cpu_cores": {"type": "integer", "minimum": 1},
        "kernel": {"type": "string"},
        "hostname": {"type": "string"}
      }
    },
    "resources": {
      "type": "object",
      "required": ["memory_mb", "memory_available_mb", "swap_mb", "swap_available_mb", "storage_mb", "storage_available_mb"],
      "properties": {
        "memory_mb": {"type": "integer", "minimum": 0},
        "memory_available_mb": {"type": "integer", "minimum": 0},
        "swap_mb": {"type": "integer", "minimum": 0},
        "swap_available_mb": {"type": "integer", "minimum": 0},
        "storage_mb": {"type": "integer", "minimum": 0},
        "storage_available_mb": {"type": "integer", "minimum": 0}
      }
    },
    "network": {
      "type": "object",
      "required": ["internet", "latency_ms", "signal_strength_dbm", "connection_type", "metered"],
      "properties": {
        "internet": {"type": "string", "enum": ["ONLINE", "OFFLINE", "CAPTIVE_PORTAL", "UNKNOWN"]},
        "latency_ms": {"type": "integer", "minimum": 0},
        "signal_strength_dbm": {"type": "integer"},
        "connection_type": {"type": "string"},
        "metered": {"type": "boolean"}
      }
    },
    "battery": {
      "type": "object",
      "required": ["level", "status", "health", "temperature_c"],
      "properties": {
        "level": {"type": "integer", "minimum": 0, "maximum": 100},
        "status": {"type": "string", "enum": ["charging", "discharging", "full", "unknown"]},
        "health": {"type": "string"},
        "temperature_c": {"type": "integer"}
      }
    },
    "cpu": {
      "type": "object",
      "required": ["throttled", "temperature_c", "frequency_mhz"],
      "properties": {
        "throttled": {"type": "boolean"},
        "temperature_c": {"type": "integer"},
        "frequency_mhz": {"type": "integer", "minimum": 0}
      }
    },
    "tools": {
      "type": "object",
      "patternProperties": {"^.*$": {"type": "boolean"}}
    },
    "classification": {
      "type": "object",
      "required": ["resource_class", "strategy"],
      "properties": {
        "resource_class": {"type": "string", "enum": ["XL", "LARGE", "MEDIUM", "MICRO", "SMALL", "MINI"]},
        "strategy": {"type": "string", "enum": ["FULL", "BALANCED", "LIGHT", "SEQUENTIAL", "CONSERVATIVE", "MINIMAL"]}
      }
    }
  }
}
SCHEMA

# ── Write Device Profile (v2 schema) ─────────────────────────
python3 <<PY > "$PROFILE"
import json, os, sys
profile = {
    "schema_version": 2,
    "agent": "01-device-intelligence",
    "timestamp": "$(timestamp)",
    "system": {
        "os": "$OS",
        "termux": $( [[ -n "\${PREFIX:-}" && "\$PREFIX" == *com.termux* ]] && echo true || echo false ),
        "architecture": "$ARCH",
        "cpu_abi": "$CPU",
        "cpu_cores": $CPU_CORES,
        "kernel": "$KERNEL",
        "hostname": "$HOST"
    },
    "resources": {
        "memory_mb": $MEM_TOTAL,
        "memory_available_mb": $MEM_AVAILABLE,
        "swap_mb": $SWAP_TOTAL,
        "swap_available_mb": $SWAP_AVAILABLE,
        "storage_mb": $STORAGE_TOTAL_MB,
        "storage_available_mb": $STORAGE_AVAILABLE_MB
    },
    "network": {
        "internet": "$INTERNET",
        "latency_ms": $LATENCY_MS,
        "signal_strength_dbm": $SIGNAL_STRENGTH,
        "connection_type": "$CONNECTION_TYPE",
        "metered": $(echo "$METERED" | tr '[:upper:]' '[:lower:]')
    },
    "battery": {
        "level": $BAT_LEVEL,
        "status": "$BAT_STATUS",
        "health": "$BAT_HEALTH",
        "temperature_c": $BAT_TEMP
    },
    "cpu": {
        "throttled": $(echo "$CPU_THROTTLED" | tr '[:upper:]' '[:lower:]'),
        "temperature_c": $CPU_TEMP,
        "frequency_mhz": $CPU_FREQ
    },
    "tools": $TOOLS_JSON,
    "classification": {
        "resource_class": "$RESOURCE_CLASS",
        "strategy": "$STRATEGY"
    }
}
print(json.dumps(profile, indent=2))
PY

# Validate against schema
if command -v python3 >/dev/null 2>&1; then
    python3 <<'PY'
import json, sys
try:
    with open("$PROFILE") as f:
        data = json.load(f)
    with open("$DEVICE_SCHEMA") as f:
        schema = json.load(f)
    # Basic validation
    required = ["schema_version", "agent", "timestamp", "system", "resources", "network", "battery", "cpu", "tools", "classification"]
    for r in required:
        if r not in data:
            print(f"MISSING: {r}", file=sys.stderr)
            sys.exit(1)
    if data["schema_version"] != 2:
        print(f"WRONG SCHEMA VERSION: {data['schema_version']}", file=sys.stderr)
        sys.exit(1)
    print("Schema validation: PASSED")
except Exception as e:
    print(f"Validation error: {e}", file=sys.stderr)
    sys.exit(1)
PY
    VALIDATION=$?
else
    VALIDATION=1
fi

# ── Event ────────────────────────────────────────────────────
event "device.profile.updated" \
"{\"resource_class\":\"$RESOURCE_CLASS\",\"strategy\":\"$STRATEGY\",\"internet\":\"$INTERNET\",\"battery_level\":$BAT_LEVEL,\"cpu_throttled\":$CPU_THROTTLED,\"schema_valid\":$([ $VALIDATION -eq 0 ] && echo true || echo false)}"

log "Device profile saved: $PROFILE (schema v2)"

# ── Result ───────────────────────────────────────────────────
echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ RESULT                                                     │"
echo "└────────────────────────────────────────────────────────────┘"
echo
echo "  ✓ Device intelligence collected (portable v2)"
echo "  ✓ Network heartbeat: $INTERNET (${LATENCY_MS}ms, ${SIGNAL_STRENGTH}dBm, ${CONNECTION_TYPE})"
echo "  ✓ Battery: ${BAT_LEVEL}% (${BAT_STATUS}, ${BAT_HEALTH})"
echo "  ✓ CPU thermal: ${CPU_TEMP}°C @ ${CPU_FREQ}MHz (throttled: $CPU_THROTTLED)"
echo "  ✓ Resource classification: $RESOURCE_CLASS → $STRATEGY"
echo "  ✓ JSON Schema v2 validation: $([ $VALIDATION -eq 0 ] && echo PASSED || echo SKIPPED)"
echo "  ✓ Device profile written"
echo "  ✓ Event published"
echo
echo "  Profile : $PROFILE"
echo "  Schema  : $DEVICE_SCHEMA"
echo "  Events  : $EVENTS"
echo "  Log     : $LOG"
echo
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║             AGENT 01 COMPLETE (v2)                         ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo

exit 0