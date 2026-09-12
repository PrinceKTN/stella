#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"

STATE="$STELLA_ROOT/state"
EVENT_DIR="$STELLA_ROOT/events"
EVENTS="$EVENT_DIR/events.jsonl"
LOGS="$STELLA_ROOT/logs"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 ✦  S T E L L A  ✦                         ║"
echo "║                                                            ║"
echo "║                  PRE-FLIGHT CHECK                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

mkdir -p "$STATE" "$EVENT_DIR" "$LOGS"

FAIL=0

check_file() {
    if [ -f "$1" ]; then
        echo "  ✓ $2"
    else
        echo "  ✗ $2"
        FAIL=$((FAIL+1))
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo "  ✓ $2"
    else
        echo "  ✗ $2"
        FAIL=$((FAIL+1))
    fi
}

echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] FOUNDATION                                          │"
echo "└────────────────────────────────────────────────────────────┘"

check_file "$STATE/device.json" "Agent 01 device profile"
check_file "$STATE/brain.json" "Agent 02 brain profile"
check_file "$STATE/providers.json" "Provider registry"
check_file "$STATE/provider-health.json" "Provider health"
check_file "$STATE/agent-04-execution.json" "Agent 04 execution profile"
check_file "$STATE/orchestrator.json" "Agent 05 orchestrator"
check_file "$STATE/automation-scheduler.json" "Agent 06 scheduler"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] CORE DIRECTORIES                                    │"
echo "└────────────────────────────────────────────────────────────┘"

check_dir "$STELLA_ROOT/core" "Core directory"
check_dir "$STELLA_ROOT/core/sessions" "Session directory"
check_dir "$STELLA_ROOT/core/tasks" "Task directory"
check_dir "$STELLA_ROOT/core/locks" "Lock directory"
check_dir "$STELLA_ROOT/core/safety" "Safety directory"
check_dir "$STELLA_ROOT/core/scheduler" "Scheduler directory"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] EVENT BUS INTEGRITY                                 │"
echo "└────────────────────────────────────────────────────────────┘"

if [ -d "$EVENTS" ]; then
    echo "  ⚠ events.jsonl exists as a DIRECTORY"
    echo "  → Repairing event-bus path safely..."

    BACKUP="$EVENT_DIR/events.jsonl.directory-backup-$(date '+%Y%m%d-%H%M%S')"

    mv "$EVENTS" "$BACKUP"

    echo "  ✓ Old incorrect path preserved:"
    echo "    $BACKUP"
fi

if [ ! -e "$EVENTS" ]; then
    : > "$EVENTS"
    echo "  ✓ Event bus file created"
elif [ -f "$EVENTS" ]; then
    echo "  ✓ Event bus file exists"
else
    echo "  ✗ Event bus path is invalid"
    FAIL=$((FAIL+1))
fi

if [ -f "$EVENTS" ]; then
    if printf '%s\n' '{"preflight":"event-bus-test"}' >> "$EVENTS" 2>/dev/null; then
        echo "  ✓ Event bus write test"
    else
        echo "  ✗ Event bus write test"
        FAIL=$((FAIL+1))
    fi
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] SAFETY FOUNDATION                                   │"
echo "└────────────────────────────────────────────────────────────┘"

check_file \
    "$STELLA_ROOT/core/safety/execution-modes.json" \
    "Execution modes"

check_file \
    "$STELLA_ROOT/core/safety/risk-policy.json" \
    "Risk policy"

check_file \
    "$STATE/failure-policy.json" \
    "Failure policy"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] SCHEDULER FOUNDATION                                │"
echo "└────────────────────────────────────────────────────────────┘"

check_file \
    "$STELLA_ROOT/core/scheduler/jobs/queue.json" \
    "Scheduler job queue"

check_file \
    "$STELLA_ROOT/core/scheduler/history.json" \
    "Scheduler history"

check_file \
    "$STELLA_ROOT/core/scheduler/commands.json" \
    "Scheduler commands"

check_file \
    "$STELLA_ROOT/core/scheduler/resource-policy.json" \
    "Resource policy"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    PRE-FLIGHT RESULT                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

if [ "$FAIL" -eq 0 ]; then
    echo "  ✓ FOUNDATION STATUS: READY"
    echo
    echo "  Stella can safely proceed to Agent 07."
    exit 0
else
    echo "  ✗ FOUNDATION STATUS: CHECK REQUIRED"
    echo
    echo "  Failed checks: $FAIL"
    exit 1
fi
