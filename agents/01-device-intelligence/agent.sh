#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# STELLA — AGENT 01
# DEVICE INTELLIGENCE AGENT
# ============================================================

set -u

STELLA_ROOT="${STELLA_ROOT:-$HOME/stella}"

STATE_DIR="$STELLA_ROOT/state"
EVENT_DIR="$STELLA_ROOT/events"
LOG_DIR="$STELLA_ROOT/logs"

PROFILE="$STATE_DIR/device.json"
LOG="$LOG_DIR/agent-01.log"
EVENTS="$EVENT_DIR/events.jsonl"

mkdir -p "$STATE_DIR" "$EVENT_DIR" "$LOG_DIR"

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(timestamp)] $*" | tee -a "$LOG"
}

event() {
    local type="$1"
    local data="${2:-{}}"

    printf '{"timestamp":"%s","agent":"01-device-intelligence","event":"%s","data":%s}\n' \
        "$(timestamp)" "$type" "$data" >> "$EVENTS"
}

line() {
    printf '%*s\n' 60 '' | tr ' ' '─'
}

# ------------------------------------------------------------
# START
# ------------------------------------------------------------

clear 2>/dev/null || true

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  S T E L L A  ✦                          ║"
echo "║                                                            ║"
echo "║          AGENT 01 — DEVICE INTELLIGENCE                    ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

log "Agent 01 starting."

# ------------------------------------------------------------
# OS
# ------------------------------------------------------------

if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then
    OS="Android / Termux"
    TERMUX=true
elif command -v systemd-detect-virt >/dev/null 2>&1; then
    OS="Linux"
    TERMUX=false
else
    OS="$(uname -s)"
    TERMUX=false
fi

ARCH="$(uname -m 2>/dev/null || echo unknown)"
KERNEL="$(uname -sr 2>/dev/null || echo unknown)"
HOST="$(uname -n 2>/dev/null || echo unknown)"

# ------------------------------------------------------------
# CPU
# ------------------------------------------------------------

CPU="$(getprop ro.product.cpu.abi 2>/dev/null || true)"

if [ -z "$CPU" ]; then
    CPU="$(uname -p 2>/dev/null || echo unknown)"
fi

CPU_CORES="$(nproc 2>/dev/null || echo 1)"

# ------------------------------------------------------------
# MEMORY
# ------------------------------------------------------------

if command -v free >/dev/null 2>&1; then
    MEM_TOTAL="$(free -m | awk '/^Mem:/ {print $2}')"
    MEM_AVAILABLE="$(free -m | awk '/^Mem:/ {print $7}')"
    SWAP_TOTAL="$(free -m | awk '/^Swap:/ {print $2}')"
    SWAP_AVAILABLE="$(free -m | awk '/^Swap:/ {print $4}')"
else
    MEM_TOTAL="unknown"
    MEM_AVAILABLE="unknown"
    SWAP_TOTAL="unknown"
    SWAP_AVAILABLE="unknown"
fi

# ------------------------------------------------------------
# STORAGE
# ------------------------------------------------------------

STORAGE_TOTAL="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $2}')"
STORAGE_AVAILABLE="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"

# Convert KB → MB where possible
if [[ "$STORAGE_TOTAL" =~ ^[0-9]+$ ]]; then
    STORAGE_TOTAL_MB=$((STORAGE_TOTAL / 1024))
    STORAGE_AVAILABLE_MB=$((STORAGE_AVAILABLE / 1024))
else
    STORAGE_TOTAL_MB=0
    STORAGE_AVAILABLE_MB=0
fi

# ------------------------------------------------------------
# NETWORK
# ------------------------------------------------------------

if command -v curl >/dev/null 2>&1; then
    if curl -Is --max-time 5 https://example.com >/dev/null 2>&1; then
        INTERNET="ONLINE"
    else
        INTERNET="OFFLINE"
    fi
else
    INTERNET="UNKNOWN"
fi

# ------------------------------------------------------------
# TOOL DETECTION
# ------------------------------------------------------------

has_command() {
    command -v "$1" >/dev/null 2>&1 && echo true || echo false
}

BASH_AVAILABLE="$(has_command bash)"
GIT_AVAILABLE="$(has_command git)"
CURL_AVAILABLE="$(has_command curl)"
WGET_AVAILABLE="$(has_command wget)"
NODE_AVAILABLE="$(has_command node)"
NPM_AVAILABLE="$(has_command npm)"
PYTHON_AVAILABLE="$(has_command python)"
PYTHON3_AVAILABLE="$(has_command python3)"
PHP_AVAILABLE="$(has_command php)"
JAVA_AVAILABLE="$(has_command java)"
DOCKER_AVAILABLE="$(has_command docker)"
PODMAN_AVAILABLE="$(has_command podman)"
OLLAMA_AVAILABLE="$(has_command ollama)"

# ------------------------------------------------------------
# RESOURCE CLASSIFICATION
# ------------------------------------------------------------

RESOURCE_CLASS="MICRO"

if [[ "$MEM_TOTAL" =~ ^[0-9]+$ ]]; then

    if [ "$MEM_TOTAL" -ge 8192 ]; then
        RESOURCE_CLASS="XL"
    elif [ "$MEM_TOTAL" -ge 4096 ]; then
        RESOURCE_CLASS="LARGE"
    elif [ "$MEM_TOTAL" -ge 2048 ]; then
        RESOURCE_CLASS="MEDIUM"
    elif [ "$MEM_TOTAL" -ge 1024 ]; then
        RESOURCE_CLASS="MICRO"
    else
        RESOURCE_CLASS="MINI"
    fi

fi

# ------------------------------------------------------------
# STRATEGY
# ------------------------------------------------------------

case "$RESOURCE_CLASS" in

    XL)
        STRATEGY="FULL"
        ;;

    LARGE)
        STRATEGY="BALANCED"
        ;;

    MEDIUM)
        STRATEGY="LIGHT"
        ;;

    MICRO)
        STRATEGY="SEQUENTIAL"
        ;;

    MINI)
        STRATEGY="MINIMAL"
        ;;

esac

# ------------------------------------------------------------
# DISPLAY
# ------------------------------------------------------------

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ STELLA DEVICE PROFILE                                      │"
echo "└────────────────────────────────────────────────────────────┘"
echo

printf "  %-24s %s\n" "Operating system" "$OS"
printf "  %-24s %s\n" "Architecture" "$ARCH"
printf "  %-24s %s\n" "CPU ABI" "$CPU"
printf "  %-24s %s\n" "CPU cores" "$CPU_CORES"
printf "  %-24s %s\n" "Kernel" "$KERNEL"
printf "  %-24s %s\n" "Host" "$HOST"
printf "  %-24s %s MB\n" "Memory total" "$MEM_TOTAL"
printf "  %-24s %s MB\n" "Memory available" "$MEM_AVAILABLE"
printf "  %-24s %s MB\n" "Swap total" "$SWAP_TOTAL"
printf "  %-24s %s MB\n" "Swap available" "$SWAP_AVAILABLE"
printf "  %-24s %s MB\n" "Storage total" "$STORAGE_TOTAL_MB"
printf "  %-24s %s MB\n" "Storage available" "$STORAGE_AVAILABLE_MB"
printf "  %-24s %s\n" "Internet" "$INTERNET"
printf "  %-24s %s\n" "Resource class" "$RESOURCE_CLASS"
printf "  %-24s %s\n" "Stella strategy" "$STRATEGY"

echo
line
echo "  DEVELOPMENT TOOLS"
line

printf "  %-12s %s\n" "bash" "$BASH_AVAILABLE"
printf "  %-12s %s\n" "git" "$GIT_AVAILABLE"
printf "  %-12s %s\n" "curl" "$CURL_AVAILABLE"
printf "  %-12s %s\n" "wget" "$WGET_AVAILABLE"
printf "  %-12s %s\n" "node" "$NODE_AVAILABLE"
printf "  %-12s %s\n" "npm" "$NPM_AVAILABLE"
printf "  %-12s %s\n" "python" "$PYTHON_AVAILABLE"
printf "  %-12s %s\n" "python3" "$PYTHON3_AVAILABLE"
printf "  %-12s %s\n" "php" "$PHP_AVAILABLE"
printf "  %-12s %s\n" "java" "$JAVA_AVAILABLE"
printf "  %-12s %s\n" "docker" "$DOCKER_AVAILABLE"
printf "  %-12s %s\n" "podman" "$PODMAN_AVAILABLE"
printf "  %-12s %s\n" "ollama" "$OLLAMA_AVAILABLE"

# ------------------------------------------------------------
# WRITE JSON PROFILE
# ------------------------------------------------------------

cat > "$PROFILE" <<JSON
{
  "schema_version": 1,
  "agent": "01-device-intelligence",
  "timestamp": "$(timestamp)",
  "system": {
    "os": "$OS",
    "termux": $TERMUX,
    "architecture": "$ARCH",
    "cpu_abi": "$CPU",
    "cpu_cores": $CPU_CORES,
    "kernel": "$KERNEL",
    "hostname": "$HOST"
  },
  "resources": {
    "memory_mb": ${MEM_TOTAL:-0},
    "memory_available_mb": ${MEM_AVAILABLE:-0},
    "swap_mb": ${SWAP_TOTAL:-0},
    "swap_available_mb": ${SWAP_AVAILABLE:-0},
    "storage_mb": $STORAGE_TOTAL_MB,
    "storage_available_mb": $STORAGE_AVAILABLE_MB
  },
  "network": {
    "internet": "$INTERNET"
  },
  "tools": {
    "bash": $BASH_AVAILABLE,
    "git": $GIT_AVAILABLE,
    "curl": $CURL_AVAILABLE,
    "wget": $WGET_AVAILABLE,
    "node": $NODE_AVAILABLE,
    "npm": $NPM_AVAILABLE,
    "python": $PYTHON_AVAILABLE,
    "python3": $PYTHON3_AVAILABLE,
    "php": $PHP_AVAILABLE,
    "java": $JAVA_AVAILABLE,
    "docker": $DOCKER_AVAILABLE,
    "podman": $PODMAN_AVAILABLE,
    "ollama": $OLLAMA_AVAILABLE
  },
  "classification": {
    "resource_class": "$RESOURCE_CLASS",
    "strategy": "$STRATEGY"
  }
}
JSON

# ------------------------------------------------------------
# EVENT
# ------------------------------------------------------------

event "device.profile.updated" \
"{\"resource_class\":\"$RESOURCE_CLASS\",\"strategy\":\"$STRATEGY\",\"internet\":\"$INTERNET\"}"

log "Device profile saved: $PROFILE"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ RESULT                                                     │"
echo "└────────────────────────────────────────────────────────────┘"
echo
echo "  ✓ Device intelligence collected"
echo "  ✓ Resource classification completed"
echo "  ✓ Device profile written"
echo "  ✓ Event published"
echo
echo "  Resource class : $RESOURCE_CLASS"
echo "  Strategy        : $STRATEGY"
echo
echo "  Profile : $PROFILE"
echo "  Events  : $EVENTS"
echo "  Log     : $LOG"
echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             AGENT 01 COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

exit 0
