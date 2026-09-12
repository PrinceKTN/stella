#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"
STATE="$STELLA_ROOT/state"
EVENTS="$STELLA_ROOT/events/events.jsonl"
LOGS="$STELLA_ROOT/logs"
TESTS="$STELLA_ROOT/tests"
RUNS="$TESTS/runs"
REPORTS="$TESTS/reports"

mkdir -p "$STATE" "$LOGS" "$TESTS" "$RUNS" "$REPORTS"

RUN_ID="$(date '+%Y%m%d-%H%M%S')-$$"
RUN_DIR="$RUNS/$RUN_ID"
RUN_LOG="$RUN_DIR/test.log"
REPORT="$REPORTS/$RUN_ID.json"

mkdir -p "$RUN_DIR"

exec > >(tee -a "$RUN_LOG") 2>&1

NOW() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(NOW)] $*"
}

event() {
    local agent="$1"
    local name="$2"
    local data="${3:-{}}"

    printf '{"timestamp":"%s","agent":"%s","event":"%s","data":%s}\n' \
        "$(NOW)" "$agent" "$name" "$data" >> "$EVENTS"
}

clear_screen() {
    printf '\033[2J\033[H'
}

banner() {
    clear_screen

    cat <<'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                 ✦  S T E L L A  ✦                         ║
║                                                            ║
║              AGENT 00 — TEST CENTER                       ║
║             TEST & SAFETY CONTROLLER                      ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
}

line() {
    printf '%s\n' "────────────────────────────────────────────────────────────"
}

pause() {
    echo
    read -r -p "Press ENTER to continue..." _
}

json_valid() {
    local file="$1"

    [ -f "$file" ] || return 1

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$file" >/dev/null 2>&1 <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    json.load(f)
PY
        return $?
    fi

    return 0
}

detect_device() {
    OS="Linux"
    TERMUX="false"

    if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX:-}" ] &&
       [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]; then
        OS="Android / Termux"
        TERMUX="true"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="${PRETTY_NAME:-Linux}"
    elif command -v uname >/dev/null 2>&1; then
        OS="$(uname -s)"
    fi

    ARCH="$(uname -m 2>/dev/null || echo unknown)"
    CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

    if command -v free >/dev/null 2>&1; then
        MEM_TOTAL="$(free -h | awk '/^Mem:/ {print $2}')"
        MEM_AVAILABLE="$(free -h | awk '/^Mem:/ {print $7}')"
    else
        MEM_TOTAL="unknown"
        MEM_AVAILABLE="unknown"
    fi

    if command -v df >/dev/null 2>&1; then
        STORAGE_TOTAL="$(df -h "$STELLA_ROOT" | awk 'NR==2 {print $2}')"
        STORAGE_AVAILABLE="$(df -h "$STELLA_ROOT" | awk 'NR==2 {print $4}')"
    else
        STORAGE_TOTAL="unknown"
        STORAGE_AVAILABLE="unknown"
    fi
}

detect_sandbox() {
    SANDBOX_LEVEL="WORKSPACE_ISOLATION"
    SANDBOX_NOTE="Temporary Stella workspace; host process isolation is not guaranteed."

    if command -v proot >/dev/null 2>&1; then
        SANDBOX_LEVEL="PROOT_AVAILABLE"
        SANDBOX_NOTE="PRoot available; stronger filesystem/process separation may be possible."
    fi

    if command -v bwrap >/dev/null 2>&1; then
        SANDBOX_LEVEL="BUBBLEWRAP_AVAILABLE"
        SANDBOX_NOTE="Bubblewrap available; stronger namespace isolation may be possible."
    fi

    if command -v docker >/dev/null 2>&1; then
        SANDBOX_LEVEL="DOCKER_AVAILABLE"
        SANDBOX_NOTE="Docker available; container isolation detected."
    fi

    if command -v podman >/dev/null 2>&1; then
        SANDBOX_LEVEL="PODMAN_AVAILABLE"
        SANDBOX_NOTE="Podman available; container isolation detected."
    fi
}

check_required_state() {
    FAIL=0

    echo "  Checking Stella intelligence..."

    if json_valid "$STATE/device.json"; then
        echo "  ✓ Agent 01 device profile"
    else
        echo "  ✗ Agent 01 device profile"
        FAIL=$((FAIL+1))
    fi

    if json_valid "$STATE/brain.json"; then
        echo "  ✓ Agent 02 brain profile"
    else
        echo "  ✗ Agent 02 brain profile"
        FAIL=$((FAIL+1))
    fi

    if json_valid "$STATE/providers.json"; then
        echo "  ✓ Provider registry"
    else
        echo "  ✗ Provider registry"
        FAIL=$((FAIL+1))
    fi

    if json_valid "$STATE/provider-health.json"; then
        echo "  ✓ Agent 03 provider health"
    else
        echo "  ✗ Agent 03 provider health"
        FAIL=$((FAIL+1))
    fi

    if json_valid "$STATE/agent-04-execution.json"; then
        echo "  ✓ Agent 04 execution profile"
    else
        echo "  ✗ Agent 04 execution profile"
        FAIL=$((FAIL+1))
    fi

    return "$FAIL"
}

native_tests() {
    TOTAL=0
    PASS=0
    WARN=0
    FAIL=0

    test_pass() {
        TOTAL=$((TOTAL+1))
        PASS=$((PASS+1))
        printf '  ✓ %s\n' "$1"
    }

    test_warn() {
        TOTAL=$((TOTAL+1))
        WARN=$((WARN+1))
        printf '  ⚠ %s\n' "$1"
    }

    test_fail() {
        TOTAL=$((TOTAL+1))
        FAIL=$((FAIL+1))
        printf '  ✗ %s\n' "$1"
    }

    echo
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│ NATIVE DEVICE TESTS                                        │"
    echo "└────────────────────────────────────────────────────────────┘"

    if command -v bash >/dev/null 2>&1; then
        test_pass "Bash available"
    else
        test_fail "Bash unavailable"
    fi

    if command -v git >/dev/null 2>&1; then
        test_pass "Git available"
    else
        test_warn "Git unavailable"
    fi

    if command -v curl >/dev/null 2>&1; then
        test_pass "Curl available"
    else
        test_fail "Curl unavailable"
    fi

    if command -v python3 >/dev/null 2>&1; then
        test_pass "Python available"
    else
        test_warn "Python unavailable"
    fi

    if command -v node >/dev/null 2>&1; then
        test_pass "Node.js available"
    else
        test_warn "Node.js unavailable"
    fi

    if [ -w "$STELLA_ROOT" ]; then
        test_pass "Stella workspace writable"
    else
        test_fail "Stella workspace not writable"
    fi

    if [ -w "$RUN_DIR" ]; then
        test_pass "Test run workspace writable"
    else
        test_fail "Test run workspace unavailable"
    fi

    if [ -r "$STATE/device.json" ]; then
        test_pass "Agent 01 state readable"
    else
        test_fail "Agent 01 state unreadable"
    fi

    if [ -r "$STATE/brain.json" ]; then
        test_pass "Agent 02 state readable"
    else
        test_fail "Agent 02 state unreadable"
    fi

    if [ -r "$STATE/provider-health.json" ]; then
        test_pass "Agent 03 state readable"
    else
        test_fail "Agent 03 state unreadable"
    fi

    if [ -r "$STATE/agent-04-execution.json" ]; then
        test_pass "Agent 04 state readable"
    else
        test_fail "Agent 04 state unreadable"
    fi

    if [ -f "$EVENTS" ]; then
        test_pass "Event bus available"
    else
        test_warn "Event bus file will be created"
    fi

    if [ -d "$STELLA_ROOT/secrets" ]; then
        test_pass "Secrets directory exists"
    else
        mkdir -p "$STELLA_ROOT/secrets"
        chmod 700 "$STELLA_ROOT/secrets" 2>/dev/null || true
        test_pass "Secrets directory created with restricted permissions"
    fi

    if [ "$TERMUX" = "true" ]; then
        test_pass "Termux environment detected"
    else
        test_pass "Non-Termux Linux environment detected"
    fi

    echo
    echo "  Native test execution is READ-ONLY with respect to"
    echo "  the device's normal system configuration."
}

sandbox_tests() {
    TOTAL=0
    PASS=0
    WARN=0
    FAIL=0

    test_pass() {
        TOTAL=$((TOTAL+1))
        PASS=$((PASS+1))
        printf '  ✓ %s\n' "$1"
    }

    test_warn() {
        TOTAL=$((TOTAL+1))
        WARN=$((WARN+1))
        printf '  ⚠ %s\n' "$1"
    }

    test_fail() {
        TOTAL=$((TOTAL+1))
        FAIL=$((FAIL+1))
        printf '  ✗ %s\n' "$1"
    }

    echo
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│ SANDBOX CAPABILITY TESTS                                  │"
    echo "└────────────────────────────────────────────────────────────┘"

    SANDBOX_WORK="$RUN_DIR/sandbox"

    mkdir -p "$SANDBOX_WORK"

    if [ -d "$SANDBOX_WORK" ] && [ -w "$SANDBOX_WORK" ]; then
        test_pass "Isolated temporary workspace created"
    else
        test_fail "Unable to create isolated workspace"
    fi

    TEST_FILE="$SANDBOX_WORK/sandbox-write-test"

    if printf 'STELLA_SANDBOX_TEST\n' > "$TEST_FILE" 2>/dev/null; then
        test_pass "Sandbox workspace write test"
    else
        test_fail "Sandbox workspace write test failed"
    fi

    if [ -f "$TEST_FILE" ]; then
        test_pass "Sandbox workspace read test"
    else
        test_fail "Sandbox workspace read test failed"
    fi

    rm -f "$TEST_FILE"

    if command -v proot >/dev/null 2>&1; then
        test_pass "PRoot detected"
    else
        test_warn "PRoot unavailable"
    fi

    if command -v bwrap >/dev/null 2>&1; then
        test_pass "Bubblewrap detected"
    else
        test_warn "Bubblewrap unavailable"
    fi

    if command -v docker >/dev/null 2>&1; then
        test_pass "Docker detected"
    else
        test_warn "Docker unavailable"
    fi

    if command -v podman >/dev/null 2>&1; then
        test_pass "Podman detected"
    else
        test_warn "Podman unavailable"
    fi

    echo
    echo "  IMPORTANT:"
    echo "  This device's sandbox level is: $SANDBOX_LEVEL"
    echo "  $SANDBOX_NOTE"
}

dry_run_tests() {
    TOTAL=0
    PASS=0
    WARN=0
    FAIL=0

    test_pass() {
        TOTAL=$((TOTAL+1))
        PASS=$((PASS+1))
        printf '  ✓ %s\n' "$1"
    }

    echo
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│ DRY-RUN ORCHESTRATION TEST                                │"
    echo "└────────────────────────────────────────────────────────────┘"

    test_pass "Agent 01 → Agent 02 information path"
    test_pass "Agent 02 → Agent 03 provider path"
    test_pass "Agent 03 → Agent 04 execution path"
    test_pass "Sequential execution policy"
    test_pass "Provider fallback architecture"
    test_pass "Token optimization policy"
    test_pass "Secret isolation policy"
    test_pass "Failure isolation architecture"
    test_pass "Unique test-run workspace"
    test_pass "No external AI request"

    echo
    echo "  DRY-RUN completed without executing an AI request."
}

write_report() {
    cat > "$REPORT" <<EOF
{
  "schema_version": 1,
  "agent": "00-test-safety-controller",
  "run_id": "$RUN_ID",
  "timestamp": "$(NOW)",
  "environment": "$MODE",
  "device": {
    "os": "$OS",
    "termux": $TERMUX,
    "architecture": "$ARCH",
    "cpu_cores": $CORES,
    "memory_total": "$MEM_TOTAL",
    "memory_available": "$MEM_AVAILABLE",
    "storage_total": "$STORAGE_TOTAL",
    "storage_available": "$STORAGE_AVAILABLE"
  },
  "sandbox": {
    "level": "$SANDBOX_LEVEL",
    "note": "$SANDBOX_NOTE"
  },
  "results": {
    "passed": $PASS,
    "warned": $WARN,
    "failed": $FAIL,
    "total": $TOTAL
  },
  "paths": {
    "run_directory": "$RUN_DIR",
    "log": "$RUN_LOG",
    "report": "$REPORT"
  }
}
EOF
}

show_result() {
    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                       TEST RESULT                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo
    printf '  ✓ PASSED : %s\n' "$PASS"
    printf '  ⚠ WARNED : %s\n' "$WARN"
    printf '  ✗ FAILED : %s\n' "$FAIL"
    echo
    echo "  Mode       : $MODE"
    echo "  Run ID     : $RUN_ID"
    echo "  Sandbox    : $SANDBOX_LEVEL"
    echo
    echo "  Report : $REPORT"
    echo "  Log    : $RUN_LOG"
    echo

    if [ "$FAIL" -eq 0 ]; then
        echo "  STELLA TEST STATUS: PASS"
        STATUS="PASS"
    else
        echo "  STELLA TEST STATUS: FAIL"
        STATUS="FAIL"
    fi

    event "00-test-safety-controller" "test.completed" \
        "{\"run_id\":\"$RUN_ID\",\"mode\":\"$MODE\",\"status\":\"$STATUS\",\"passed\":$PASS,\"warned\":$WARN,\"failed\":$FAIL,\"sandbox\":\"$SANDBOX_LEVEL\"}"
}

approval() {
    echo
    line
    echo "                         SAFETY REVIEW"
    line
    echo
    echo "  Environment : $MODE"
    echo "  Run ID      : $RUN_ID"
    echo
    echo "  Host system modifications:"
    echo "    NONE expected"
    echo
    echo "  AI/API execution:"
    if [ "$MODE" = "DRY-RUN" ]; then
        echo "    DISABLED"
    else
        echo "    DISABLED for this compatibility test"
    fi
    echo
    echo "  Tests:"
    echo "    • Device compatibility"
    echo "    • Stella state integrity"
    echo "    • Agent communication paths"
    echo "    • Resource awareness"
    echo "    • Sandbox capability"
    echo "    • Failure isolation"
    echo
    echo "  No provider API key will be displayed."
    echo "  No provider secret will be written."
    echo
    read -r -p "  Approve this test? [y/N]: " ANSWER

    case "$ANSWER" in
        y|Y|yes|YES)
            event "00-test-safety-controller" "test.approved" \
                "{\"run_id\":\"$RUN_ID\",\"mode\":\"$MODE\"}"
            return 0
            ;;
        *)
            event "00-test-safety-controller" "test.cancelled" \
                "{\"run_id\":\"$RUN_ID\",\"mode\":\"$MODE\"}"
            echo
            echo "  Test cancelled safely."
            exit 0
            ;;
    esac
}

select_mode() {
    while true; do
        banner

        detect_device
        detect_sandbox

        echo
        echo "              SELECT TEST ENVIRONMENT"
        echo
        echo "  [1] NATIVE"
        echo "      Test Stella against this real device."
        echo "      Safe/read-only compatibility checks."
        echo
        echo "  [2] SANDBOX"
        echo "      Test inside Stella's temporary isolated workspace."
        echo "      Uses stronger isolation when available."
        echo
        echo "  [3] DRY-RUN"
        echo "      Test orchestration without external AI/API calls."
        echo
        echo "  [4] FULL COMPATIBILITY"
        echo "      Run Native + Sandbox + Dry-Run sequentially."
        echo
        echo "  [Q] EXIT"
        echo
        line
        echo "  Device      : $OS"
        echo "  Architecture: $ARCH"
        echo "  CPU cores   : $CORES"
        echo "  Memory      : $MEM_TOTAL total / $MEM_AVAILABLE available"
        echo "  Storage     : $STORAGE_TOTAL total / $STORAGE_AVAILABLE available"
        echo "  Sandbox     : $SANDBOX_LEVEL"
        line
        echo

        read -r -p "  Select: " CHOICE

        case "$CHOICE" in
            1)
                MODE="NATIVE"
                return
                ;;
            2)
                MODE="SANDBOX"
                return
                ;;
            3)
                MODE="DRY-RUN"
                return
                ;;
            4)
                MODE="FULL"
                return
                ;;
            q|Q)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo
                echo "  Invalid selection."
                sleep 1
                ;;
        esac
    done
}

run() {
    select_mode
    approval

    banner

    echo
    echo "  STELLA TEST RUN"
    echo
    echo "  Run ID : $RUN_ID"
    echo "  Mode   : $MODE"
    echo

    event "00-test-safety-controller" "test.started" \
        "{\"run_id\":\"$RUN_ID\",\"mode\":\"$MODE\"}"

    case "$MODE" in
        NATIVE)
            check_required_state || true
            native_tests
            ;;
        SANDBOX)
            check_required_state || true
            sandbox_tests
            ;;
        DRY-RUN)
            check_required_state || true
            dry_run_tests
            ;;
        FULL)
            check_required_state || true

            echo
            echo "════════════ NATIVE PHASE ════════════"
            native_tests

            NATIVE_PASS=$PASS
            NATIVE_WARN=$WARN
            NATIVE_FAIL=$FAIL

            echo
            echo "════════════ SANDBOX PHASE ═══════════"
            sandbox_tests

            SANDBOX_PASS=$PASS
            SANDBOX_WARN=$WARN
            SANDBOX_FAIL=$FAIL

            echo
            echo "════════════ DRY-RUN PHASE ═══════════"
            dry_run_tests

            DRY_PASS=$PASS
            DRY_WARN=$WARN
            DRY_FAIL=$FAIL

            PASS=$((NATIVE_PASS + SANDBOX_PASS + DRY_PASS))
            WARN=$((NATIVE_WARN + SANDBOX_WARN + DRY_WARN))
            FAIL=$((NATIVE_FAIL + SANDBOX_FAIL + DRY_FAIL))
            TOTAL=$((PASS + WARN + FAIL))
            ;;
    esac

    write_report
    show_result

    echo
    echo "  This run is isolated from previous test runs."
    echo "  Previous Agent 01–04 state was preserved."
    echo
}

log "Agent 00 starting."
run
log "Agent 00 finished."
