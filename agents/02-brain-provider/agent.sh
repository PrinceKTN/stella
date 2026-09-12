#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# STELLA — AGENT 02
# BRAIN & PROVIDER INTELLIGENCE AGENT
# ============================================================

set -u

STELLA_ROOT="${STELLA_ROOT:-$HOME/stella}"

STATE_DIR="$STELLA_ROOT/state"
EVENT_DIR="$STELLA_ROOT/events"
LOG_DIR="$STELLA_ROOT/logs"
CONFIG_DIR="$STELLA_ROOT/config"
SECRETS_DIR="$STELLA_ROOT/secrets"
BRAIN_DIR="$STELLA_ROOT/brain"

DEVICE_PROFILE="$STATE_DIR/device.json"
BRAIN_PROFILE="$STATE_DIR/brain.json"
PROVIDER_PROFILE="$STATE_DIR/providers.json"

LOG="$LOG_DIR/agent-02.log"
EVENTS="$EVENT_DIR/events.jsonl"

mkdir -p \
    "$STATE_DIR" \
    "$EVENT_DIR" \
    "$LOG_DIR" \
    "$CONFIG_DIR" \
    "$SECRETS_DIR" \
    "$BRAIN_DIR"

chmod 700 "$SECRETS_DIR"

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(timestamp)] $*" | tee -a "$LOG"
}

event() {
    local type="$1"
    local data="${2:-{}}"

    printf '{"timestamp":"%s","agent":"02-brain-provider","event":"%s","data":%s}\n' \
        "$(timestamp)" "$type" "$data" >> "$EVENTS"
}

# ------------------------------------------------------------
# HEADER
# ------------------------------------------------------------

clear 2>/dev/null || true

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  S T E L L A  ✦                          ║"
echo "║                                                            ║"
echo "║          AGENT 02 — BRAIN & PROVIDER INTELLIGENCE          ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

log "Agent 02 starting."

# ------------------------------------------------------------
# CHECK AGENT 01
# ------------------------------------------------------------

echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] READING DEVICE INTELLIGENCE                           │"
echo "└────────────────────────────────────────────────────────────┘"

if [ ! -f "$DEVICE_PROFILE" ]; then
    echo
    echo "  ✗ Agent 01 profile not found."
    echo
    echo "  Expected:"
    echo "  $DEVICE_PROFILE"
    echo
    log "ERROR: Agent 01 device profile missing."
    event "brain.blocked" '{"reason":"device_profile_missing"}'
    exit 10
fi

echo "  ✓ Device profile found"
echo "  ✓ Reading device constraints"

# Extract values without requiring jq.
RESOURCE_CLASS="$(grep -o '"resource_class": "[^"]*"' "$DEVICE_PROFILE" \
    | head -1 | cut -d'"' -f4)"

STRATEGY="$(grep -o '"strategy": "[^"]*"' "$DEVICE_PROFILE" \
    | head -1 | cut -d'"' -f4)"

INTERNET="$(grep -o '"internet": "[^"]*"' "$DEVICE_PROFILE" \
    | head -1 | cut -d'"' -f4)"

MEMORY_MB="$(grep -o '"memory_mb": [0-9]*' "$DEVICE_PROFILE" \
    | head -1 | grep -o '[0-9]*$')"

ARCH="$(grep -o '"architecture": "[^"]*"' "$DEVICE_PROFILE" \
    | head -1 | cut -d'"' -f4)"

echo
echo "  Device class : ${RESOURCE_CLASS:-unknown}"
echo "  Strategy     : ${STRATEGY:-unknown}"
echo "  Internet     : ${INTERNET:-unknown}"
echo "  Memory       : ${MEMORY_MB:-unknown} MB"
echo "  Architecture : ${ARCH:-unknown}"

# ------------------------------------------------------------
# BRAIN STRATEGY
# ------------------------------------------------------------

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] CALCULATING BRAIN STRATEGY                            │"
echo "└────────────────────────────────────────────────────────────┘"

BRAIN_MODE="REMOTE_FIRST"
LOCAL_MODEL_ALLOWED="false"
MAX_HEAVY_WORKERS=1
MAX_CONCURRENT_AGENTS=1

case "$RESOURCE_CLASS" in

    MINI)
        BRAIN_MODE="REMOTE_ONLY"
        LOCAL_MODEL_ALLOWED="false"
        MAX_HEAVY_WORKERS=0
        MAX_CONCURRENT_AGENTS=1
        ;;

    MICRO)
        BRAIN_MODE="REMOTE_FIRST"
        LOCAL_MODEL_ALLOWED="false"
        MAX_HEAVY_WORKERS=1
        MAX_CONCURRENT_AGENTS=1
        ;;

    MEDIUM)
        BRAIN_MODE="HYBRID_LIGHT"
        LOCAL_MODEL_ALLOWED="true"
        MAX_HEAVY_WORKERS=1
        MAX_CONCURRENT_AGENTS=2
        ;;

    LARGE)
        BRAIN_MODE="HYBRID"
        LOCAL_MODEL_ALLOWED="true"
        MAX_HEAVY_WORKERS=2
        MAX_CONCURRENT_AGENTS=3
        ;;

    XL)
        BRAIN_MODE="FULL"
        LOCAL_MODEL_ALLOWED="true"
        MAX_HEAVY_WORKERS=4
        MAX_CONCURRENT_AGENTS=5
        ;;

    *)
        BRAIN_MODE="SAFE_REMOTE"
        LOCAL_MODEL_ALLOWED="false"
        MAX_HEAVY_WORKERS=1
        MAX_CONCURRENT_AGENTS=1
        ;;

esac

echo
echo "  Brain mode              : $BRAIN_MODE"
echo "  Local models allowed    : $LOCAL_MODEL_ALLOWED"
echo "  Maximum heavy workers  : $MAX_HEAVY_WORKERS"
echo "  Maximum concurrent AI  : $MAX_CONCURRENT_AGENTS"

# ------------------------------------------------------------
# PROVIDER CAPABILITY DETECTION
# ------------------------------------------------------------

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] PROVIDER SYSTEM                                       │"
echo "└────────────────────────────────────────────────────────────┘"

echo
echo "  Stella will use a provider registry."
echo "  No API keys are requested or stored by this test."
echo

# These are provider definitions, NOT credentials.
cat > "$PROVIDER_PROFILE" <<'JSON'
{
  "schema_version": 1,
  "providers": {
    "groq": {
      "enabled": false,
      "configured": false,
      "health": "unknown",
      "priority": 0,
      "cost_mode": "free_or_paid",
      "api_key_env": "STELLA_GROQ_API_KEY"
    },
    "gemini": {
      "enabled": false,
      "configured": false,
      "health": "unknown",
      "priority": 0,
      "cost_mode": "free_or_paid",
      "api_key_env": "STELLA_GEMINI_API_KEY"
    },
    "openrouter": {
      "enabled": false,
      "configured": false,
      "health": "unknown",
      "priority": 0,
      "cost_mode": "free_or_paid",
      "api_key_env": "STELLA_OPENROUTER_API_KEY"
    },
    "ollama": {
      "enabled": false,
      "configured": false,
      "health": "unknown",
      "priority": 0,
      "cost_mode": "local",
      "api_key_env": null
    }
  }
}
JSON

echo "  ✓ Provider registry created"
echo "  ✓ Groq slot prepared"
echo "  ✓ Gemini slot prepared"
echo "  ✓ OpenRouter slot prepared"
echo "  ✓ Local/Ollama slot prepared"

# ------------------------------------------------------------
# BRAIN PROFILE
# ------------------------------------------------------------

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] BUILDING ISOLATED BRAIN                               │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$BRAIN_PROFILE" <<JSON
{
  "schema_version": 1,
  "agent": "02-brain-provider",
  "timestamp": "$(timestamp)",
  "device_dependency": {
    "resource_class": "$RESOURCE_CLASS",
    "strategy": "$STRATEGY",
    "architecture": "$ARCH",
    "memory_mb": ${MEMORY_MB:-0},
    "internet": "$INTERNET"
  },
  "brain": {
    "mode": "$BRAIN_MODE",
    "local_model_allowed": $LOCAL_MODEL_ALLOWED,
    "max_heavy_workers": $MAX_HEAVY_WORKERS,
    "max_concurrent_agents": $MAX_CONCURRENT_AGENTS,
    "token_optimization": true,
    "provider_fallback": true,
    "sequential_execution": true
  },
  "security": {
    "secrets_directory": "$SECRETS_DIR",
    "credentials_in_repository": false
  }
}
JSON

echo "  ✓ Brain profile created"
echo "  ✓ Token optimization enabled"
echo "  ✓ Provider fallback enabled"
echo "  ✓ Sequential execution enabled"
echo "  ✓ Secrets isolated from repository"

# ------------------------------------------------------------
# LOCAL BRAIN README
# ------------------------------------------------------------

cat > "$BRAIN_DIR/README.txt" <<'EOF'
STELLA BRAIN
============

This directory is reserved for Stella's brain runtime.

The brain is intentionally separated from the agents.

Agents communicate through:
    ~/stella/state/
    ~/stella/events/

Provider credentials must NEVER be committed to GitHub.

Use environment variables or the protected secrets directory.

The brain should select providers according to:

1. Device capability
2. Provider availability
3. Reliability
4. Latency
5. Context capability
6. Token efficiency
7. Cost
8. User-selected preferences

On low-resource devices, remote AI is preferred.
Heavy local models must remain disabled unless the device profile
explicitly allows them.
EOF

# ------------------------------------------------------------
# CONFIG TEMPLATE
# ------------------------------------------------------------

if [ ! -f "$CONFIG_DIR/providers.env.example" ]; then

cat > "$CONFIG_DIR/providers.env.example" <<'EOF'
# ============================================================
# STELLA PROVIDER CONFIGURATION TEMPLATE
# ============================================================
#
# COPY VALUES INTO YOUR PRIVATE ENVIRONMENT.
# NEVER COMMIT REAL API KEYS TO GITHUB.
#
# Example:
#
# export STELLA_GROQ_API_KEY="your-key"
# export STELLA_GEMINI_API_KEY="your-key"
# export STELLA_OPENROUTER_API_KEY="your-key"
#
# Stella will later provide a safer interactive configuration
# system.
EOF

fi

# ------------------------------------------------------------
# GIT SAFETY
# ------------------------------------------------------------

GITIGNORE="$STELLA_ROOT/.gitignore"

if [ ! -f "$GITIGNORE" ]; then
    cat > "$GITIGNORE" <<'EOF'
# Stella secrets
secrets/
*.key
*.secret
*.token
.env
.env.*
!.env.example

# Runtime state
state/*.runtime.json

# Local logs
logs/

# Temporary files
tmp/
cache/
EOF
else
    grep -q '^secrets/$' "$GITIGNORE" || echo 'secrets/' >> "$GITIGNORE"
    grep -q '^\.env$' "$GITIGNORE" || echo '.env' >> "$GITIGNORE"
fi

# ------------------------------------------------------------
# EVENT
# ------------------------------------------------------------

event "brain.initialized" \
"{\"mode\":\"$BRAIN_MODE\",\"resource_class\":\"$RESOURCE_CLASS\",\"local_model_allowed\":$LOCAL_MODEL_ALLOWED,\"max_concurrent_agents\":$MAX_CONCURRENT_AGENTS}"

event "provider.registry.created" \
"{\"providers\":4,\"credentials_stored\":false}"

log "Brain profile saved: $BRAIN_PROFILE"
log "Provider registry saved: $PROVIDER_PROFILE"

# ------------------------------------------------------------
# RESULT
# ------------------------------------------------------------

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ RESULT                                                     │"
echo "└────────────────────────────────────────────────────────────┘"
echo
echo "  ✓ Agent 01 information received"
echo "  ✓ Device-aware brain strategy selected"
echo "  ✓ Isolated brain directory created"
echo "  ✓ Provider registry created"
echo "  ✓ Provider fallback enabled"
echo "  ✓ Token optimization enabled"
echo "  ✓ Sequential execution enabled"
echo "  ✓ Secrets protected from Git"
echo
echo "  Brain mode       : $BRAIN_MODE"
echo "  Local AI         : $LOCAL_MODEL_ALLOWED"
echo "  Max concurrency  : $MAX_CONCURRENT_AGENTS"
echo
echo "  Brain profile:"
echo "  $BRAIN_PROFILE"
echo
echo "  Provider registry:"
echo "  $PROVIDER_PROFILE"
echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             AGENT 02 COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

exit 0
