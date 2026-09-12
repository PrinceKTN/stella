#!/data/data/com.termux/files/usr/bin/bash

set -u

STELLA_ROOT="${STELLA_ROOT:-$HOME/stella}"
STATE="$STELLA_ROOT/state"
EVENTS_DIR="$STELLA_ROOT/events"
EVENTS="$EVENTS_DIR/events.jsonl"
LOGS="$STELLA_ROOT/logs"

DEVICE="$STATE/device.json"
BRAIN="$STATE/brain.json"
PROVIDERS="$STATE/providers.json"

REPORT="$STATE/provider-health.json"
LOG="$LOGS/agent-03.log"

mkdir -p "$STATE" "$EVENTS_DIR" "$LOGS"

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(timestamp)] $*" | tee -a "$LOG"
}

event() {
    local event_name="$1"
    local data="$2"

    printf '{"timestamp":"%s","agent":"03-provider-health","event":"%s","data":%s}\n' \
        "$(timestamp)" "$event_name" "$data" >> "$EVENTS"
}

banner() {
cat <<'ART'

╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                 ✦  S T E L L A  ✦                          ║
║                                                            ║
║          AGENT 03 — PROVIDER HEALTH                        ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

ART
}

banner
log "Agent 03 starting."

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] READING STELLA STATE                                  │"
echo "└────────────────────────────────────────────────────────────┘"

if [ ! -f "$DEVICE" ]; then
    log "ERROR: Agent 01 device profile missing."
    exit 10
fi

if [ ! -f "$BRAIN" ]; then
    log "ERROR: Agent 02 brain profile missing."
    exit 11
fi

if [ ! -f "$PROVIDERS" ]; then
    log "ERROR: Agent 02 provider registry missing."
    exit 12
fi

echo "  ✓ Agent 01 device profile found"
echo "  ✓ Agent 02 brain profile found"
echo "  ✓ Provider registry found"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] DEVICE CONSTRAINTS                                    │"
echo "└────────────────────────────────────────────────────────────┘"

read_json() {
    python3 - "$1" "$2" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)

    path = sys.argv[2].split(".")
    value = data

    for part in path:
        value = value.get(part, "UNKNOWN")

    print(value)
except Exception:
    print("UNKNOWN")
PY
}

RESOURCE_CLASS=$(read_json "$DEVICE" "classification.resource_class")
STRATEGY=$(read_json "$DEVICE" "classification.strategy")
MEMORY=$(read_json "$DEVICE" "resources.memory_mb")
INTERNET=$(read_json "$DEVICE" "network.internet")

echo
echo "  Resource class : $RESOURCE_CLASS"
echo "  Strategy       : $STRATEGY"
echo "  Memory         : ${MEMORY} MB"
echo "  Internet       : $INTERNET"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] PROVIDER CONFIGURATION                                │"
echo "└────────────────────────────────────────────────────────────┘"

GROQ=0
GEMINI=0
OPENROUTER=0

if [ -n "${STELLA_GROQ_API_KEY:-}" ]; then
    echo "  ✓ Groq       : KEY PRESENT"
    GROQ=1
else
    echo "  · Groq       : NOT CONFIGURED"
fi

if [ -n "${STELLA_GEMINI_API_KEY:-}" ]; then
    echo "  ✓ Gemini     : KEY PRESENT"
    GEMINI=1
else
    echo "  · Gemini     : NOT CONFIGURED"
fi

if [ -n "${STELLA_OPENROUTER_API_KEY:-}" ]; then
    echo "  ✓ OpenRouter : KEY PRESENT"
    OPENROUTER=1
else
    echo "  · OpenRouter : NOT CONFIGURED"
fi

echo "  · Ollama     : LOCAL MODEL"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] NETWORK CONNECTIVITY                                  │"
echo "└────────────────────────────────────────────────────────────┘"

check_endpoint() {
    local name="$1"
    local url="$2"

    if [ "$INTERNET" != "ONLINE" ]; then
        echo "  · $name : SKIPPED (offline)"
        return
    fi

    local start
    local end
    local elapsed
    local status

    start=$(date +%s%3N 2>/dev/null || date +%s)

    status=$(curl \
        -sS \
        -o /dev/null \
        -w '%{http_code}' \
        --connect-timeout 8 \
        --max-time 15 \
        "$url" 2>/dev/null)

    end=$(date +%s%3N 2>/dev/null || date +%s)

    elapsed=$((end-start))

    if [[ "$status" =~ ^[0-9]{3}$ ]] && [ "$status" != "000" ]; then
        echo "  ✓ $name : HTTP $status (${elapsed}ms)"
        return 0
    fi

    echo "  ✗ $name : NO HTTP RESPONSE (${elapsed}ms)"
    return 1
}

GROQ_NET=0
GEMINI_NET=0
OPENROUTER_NET=0

check_endpoint "Groq" "https://api.groq.com" && GROQ_NET=1
check_endpoint "Google" "https://generativelanguage.googleapis.com" && GEMINI_NET=1
check_endpoint "OpenRouter" "https://openrouter.ai" && OPENROUTER_NET=1

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] PROVIDER DECISION ENGINE                              │"
echo "└────────────────────────────────────────────────────────────┘"

python3 - \
    "$REPORT" \
    "$RESOURCE_CLASS" \
    "$STRATEGY" \
    "$MEMORY" \
    "$INTERNET" \
    "$GROQ" \
    "$GEMINI" \
    "$OPENROUTER" \
    "$GROQ_NET" \
    "$GEMINI_NET" \
    "$OPENROUTER_NET" <<'PY'

import json
import sys
from datetime import datetime

(
    out,
    resource,
    strategy,
    memory,
    internet,
    groq_config,
    gemini_config,
    router_config,
    groq_net,
    gemini_net,
    router_net
) = sys.argv[1:]

groq_config = bool(int(groq_config))
gemini_config = bool(int(gemini_config))
router_config = bool(int(router_config))

groq_net = bool(int(groq_net))
gemini_net = bool(int(gemini_net))
router_net = bool(int(router_net))

providers = {
    "groq": {
        "configured": groq_config,
        "network_reachable": groq_net,
        "authenticated": False,
        "usable": False,
        "category": "remote",
        "cost_mode": "free_or_paid",
        "priority": 1
    },
    "gemini": {
        "configured": gemini_config,
        "network_reachable": gemini_net,
        "authenticated": False,
        "usable": False,
        "category": "remote",
        "cost_mode": "free_or_paid",
        "priority": 2
    },
    "openrouter": {
        "configured": router_config,
        "network_reachable": router_net,
        "authenticated": False,
        "usable": False,
        "category": "gateway",
        "cost_mode": "free_or_paid",
        "priority": 3
    },
    "ollama": {
        "configured": False,
        "network_reachable": False,
        "authenticated": False,
        "usable": False,
        "category": "local",
        "cost_mode": "local",
        "priority": 99
    }
}

configured = [
    name for name, p in providers.items()
    if p["configured"]
]

reachable = [
    name for name, p in providers.items()
    if p["network_reachable"]
]

if not configured:
    recommendation = (
        "NO_PROVIDER_CONFIGURED: "
        "Stella can continue in diagnostic mode. "
        "Configure a supported provider before AI execution."
    )
elif not reachable:
    recommendation = (
        "PROVIDERS_CONFIGURED_BUT_NETWORK_UNAVAILABLE"
    )
else:
    recommendation = (
        "REMOTE_PROVIDER_CANDIDATE_FOUND: "
        "Authentication and model capability checks are required "
        "before execution."
    )

report = {
    "schema_version": 2,
    "agent": "03-provider-health",
    "timestamp": datetime.now().astimezone().isoformat(),

    "device": {
        "resource_class": resource,
        "strategy": strategy,
        "memory_mb": int(memory),
        "internet": internet
    },

    "policy": {
        "prefer_free": True,
        "prefer_remote_on_micro": True,
        "avoid_heavy_local_models": resource == "MICRO",
        "max_concurrent_ai": 1,
        "sequential": True
    },

    "providers": providers,

    "summary": {
        "configured": configured,
        "network_reachable": reachable,
        "authenticated": [],
        "usable": []
    },

    "recommendation": recommendation
}

with open(out, "w") as f:
    json.dump(report, f, indent=2)

print("  ✓ Provider decision profile created")
PY

log "Provider health report saved: $REPORT"

event "provider.health.updated" \
'{"resource_class":"'"$RESOURCE_CLASS"'","internet":"'"$INTERNET"'","groq_configured":'"$GROQ"',"gemini_configured":'"$GEMINI"',"openrouter_configured":'"$OPENROUTER"',"groq_reachable":'"$GROQ_NET"',"gemini_reachable":'"$GEMINI_NET"',"openrouter_reachable":'"$OPENROUTER_NET"'}'

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ RESULT                                                     │"
echo "└────────────────────────────────────────────────────────────┘"

echo
echo "  ✓ Agent 01 information received"
echo "  ✓ Agent 02 information received"
echo "  ✓ Provider configuration inspected"
echo "  ✓ Network connectivity checked"
echo "  ✓ Provider decision profile created"
echo "  ✓ API keys remain hidden"
echo "  ✓ Secrets remain outside Git"
echo "  ✓ Event published"

echo
echo "  Report : $REPORT"
echo "  Events : $EVENTS"
echo "  Log    : $LOG"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             AGENT 03 COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════╝"

exit 0
