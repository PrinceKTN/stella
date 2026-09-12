#!/data/data/com.termux/files/usr/bin/bash

# STELLA TEST CENTER
# Safe, sequential, evidence-producing system test runner.

set +e

STELLA="$HOME/stella"
STATE="$STELLA/state"
EVENTS="$STELLA/events/events.jsonl"
LOG="$STELLA/logs/test-center.log"
REPORT="$STATE/test-report.json"

mkdir -p "$STATE" "$STELLA/logs" "$STELLA/events"

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(timestamp)] $*" | tee -a "$LOG"
}

banner() {
    printf '\n'
    printf '╔════════════════════════════════════════════════════════════╗\n'
    printf '║                 S T E L L A  TEST CENTER                  ║\n'
    printf '╚════════════════════════════════════════════════════════════╝\n'
    printf '\n'
}

line() {
    printf '%s\n' '────────────────────────────────────────────────────────────'
}

# ------------------------------------------------------------------
# Test accounting
# ------------------------------------------------------------------

pass=0
warn=0
fail=0

RESULTS_FILE="$STATE/.test-results.tmp"

: > "$RESULTS_FILE"

result() {
    local status="$1"
    local message="$2"

    case "$status" in
        PASS)
            printf ' ✓ %s\n' "$message"
            pass=$((pass + 1))
            printf 'PASS\t%s\n' "$message" >> "$RESULTS_FILE"
            ;;
        WARN)
            printf ' ⚠ %s\n' "$message"
            warn=$((warn + 1))
            printf 'WARN\t%s\n' "$message" >> "$RESULTS_FILE"
            ;;
        FAIL)
            printf ' ✗ %s\n' "$message"
            fail=$((fail + 1))
            printf 'FAIL\t%s\n' "$message" >> "$RESULTS_FILE"
            ;;
    esac
}

reset_results() {
    pass=0
    warn=0
    fail=0
    : > "$RESULTS_FILE"
}

test_file() {
    local file="$1"
    local description="$2"

    if [ -f "$file" ]; then
        result PASS "$description"
        return 0
    fi

    result FAIL "$description"
    return 1
}

test_executable() {
    local file="$1"
    local description="$2"

    if [ -x "$file" ]; then
        result PASS "$description"
        return 0
    fi

    result FAIL "$description"
    return 1
}

test_json() {
    local file="$1"
    local description="$2"

    if [ ! -f "$file" ]; then
        result FAIL "$description — file missing"
        return 1
    fi

    if python3 - "$file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        json.load(f)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
        result PASS "$description"
        return 0
    fi

    result FAIL "$description — invalid JSON"
    return 1
}

# ------------------------------------------------------------------
# Agent registry
# ------------------------------------------------------------------

agent_path() {
    case "$1" in
        01) echo "agents/01-device-intelligence/agent.sh" ;;
        02) echo "agents/02-brain-provider/agent.sh" ;;
        03) echo "agent-03-provider-health.sh" ;;
        04) echo "agent-04-ai-execution.sh" ;;
        *) return 1 ;;
    esac
}

agent_name() {
    case "$1" in
        01) echo "Device Intelligence" ;;
        02) echo "Brain & Provider Intelligence" ;;
        03) echo "Provider Health" ;;
        04) echo "AI Execution & Token Intelligence" ;;
        *) echo "Unknown Agent" ;;
    esac
}

run_agent() {
    local id="$1"
    local file
    local name
    local start
    local end
    local elapsed
    local rc

    file="$(agent_path "$id")"
    name="$(agent_name "$id")"

    printf '\n'
    line
    printf 'AGENT %s — %s\n' "$id" "$name"
    line

    if [ ! -f "$STELLA/$file" ]; then
        result FAIL "Agent $id script exists"
        log "TEST: Agent $id missing: $file"
        return 1
    fi

    if [ ! -x "$STELLA/$file" ]; then
        result FAIL "Agent $id script is executable"
        log "TEST: Agent $id not executable: $file"
        return 1
    fi

    result PASS "Agent $id script exists and is executable"

    log "TEST: starting Agent $id ($file)"

    start=$(date +%s)

    (
        cd "$STELLA"
        "./$file"
    )

    rc=$?

    end=$(date +%s)
    elapsed=$((end - start))

    if [ "$rc" -eq 0 ]; then
        result PASS "Agent $id completed successfully"
        log "TEST: Agent $id completed successfully in ${elapsed}s"
    else
        result FAIL "Agent $id failed with exit code $rc"
        log "TEST: Agent $id failed with exit code $rc after ${elapsed}s"
    fi

    printf '  Exit code: %s\n' "$rc"
    printf '  Duration : %ss\n' "$elapsed"

    return "$rc"
}

# ------------------------------------------------------------------
# Quick compatibility test
# ------------------------------------------------------------------

quick_test() {
    reset_results
    banner

    printf 'QUICK COMPATIBILITY TEST\n'
    printf 'Mode: lightweight / read-only compatibility validation\n\n'

    test_file "$STELLA/state/device.json" \
        "Agent 01 device profile available"

    test_file "$STELLA/state/brain.json" \
        "Agent 02 brain profile available"

    test_file "$STELLA/state/providers.json" \
        "Provider registry available"

    test_file "$STELLA/state/provider-health.json" \
        "Provider health state available"

    test_file "$STELLA/state/agent-04-execution.json" \
        "Agent 04 execution profile available"

    test_json "$STELLA/state/device.json" \
        "Device profile is valid JSON"

    test_json "$STELLA/state/brain.json" \
        "Brain profile is valid JSON"

    test_json "$STELLA/state/providers.json" \
        "Provider registry is valid JSON"

    test_json "$STELLA/state/provider-health.json" \
        "Provider health state is valid JSON"

    test_json "$STELLA/state/agent-04-execution.json" \
        "Agent 04 execution profile is valid JSON"

    if [ -f "$EVENTS" ]; then
        result PASS "Event bus exists"
    else
        result FAIL "Event bus exists"
    fi

    if [ -d "$STELLA/secrets" ]; then
        result PASS "Secrets directory exists"
    else
        result WARN "Secrets directory not present"
    fi
}

# ------------------------------------------------------------------
# Full sequential test
# ------------------------------------------------------------------

full_test() {
    reset_results
    banner

    log "STELLA TEST CENTER STARTED"
    log "MODE: FULL SEQUENTIAL SYSTEM TEST"

    printf 'FULL SEQUENTIAL SYSTEM TEST\n'
    printf 'Execution policy: one agent at a time\n'
    printf 'AI concurrency limit: 1\n'
    printf 'Heavy worker limit: 1\n'
    printf '\n'

    # --------------------------------------------------------------
    # Phase 1 — Static agent validation
    # --------------------------------------------------------------

    line
    printf 'PHASE 1 — AGENT AVAILABILITY\n'
    line

    for id in 01 02 03 04; do
        file="$(agent_path "$id")"
        name="$(agent_name "$id")"

        test_executable "$STELLA/$file" \
            "Agent $id — $name is available"
    done

    # --------------------------------------------------------------
    # Phase 2 — Sequential execution
    # --------------------------------------------------------------

    line
    printf 'PHASE 2 — SEQUENTIAL AGENT EXECUTION\n'
    line

    for id in 01 02 03 04; do
        run_agent "$id"
    done

    # --------------------------------------------------------------
    # Phase 3 — Output validation
    # --------------------------------------------------------------

    line
    printf 'PHASE 3 — OUTPUT VALIDATION\n'
    line

    test_json "$STELLA/state/device.json" \
        "Agent 01 output readable"

    test_json "$STELLA/state/brain.json" \
        "Agent 02 output readable"

    test_json "$STELLA/state/provider-health.json" \
        "Agent 03 output readable"

    test_json "$STELLA/state/agent-04-execution.json" \
        "Agent 04 output readable"

    if [ -s "$EVENTS" ]; then
        result PASS "Event stream contains recorded events"
    else
        result FAIL "Event stream contains recorded events"
    fi

    # --------------------------------------------------------------
    # Phase 4 — Resource safety
    # --------------------------------------------------------------

    line
    printf 'PHASE 4 — RESOURCE SAFETY\n'
    line

    if command -v free >/dev/null 2>&1; then
        available="$(free -m | awk '/^Mem:/ {print $7}')"

        if [ -n "$available" ] && [ "$available" -ge 300 ]; then
            result PASS "Available memory is ${available} MiB"
        elif [ -n "$available" ]; then
            result WARN "Available memory is ${available} MiB — constrained"
        else
            result WARN "Available memory could not be measured"
        fi
    else
        result WARN "Memory measurement unavailable"
    fi

    if grep -q '"max_concurrent_ai"[[:space:]]*:[[:space:]]*1' \
        "$STELLA/state/agent-04-execution.json" 2>/dev/null
    then
        result PASS "AI concurrency remains limited to 1"
    else
        result WARN "AI concurrency limit could not be confirmed"
    fi

    if grep -q '"max_heavy_workers"[[:space:]]*:[[:space:]]*1' \
        "$STELLA/state/agent-04-execution.json" 2>/dev/null
    then
        result PASS "Heavy worker limit remains 1"
    else
        result WARN "Heavy worker limit could not be confirmed"
    fi

    # --------------------------------------------------------------
    # IMPORTANT:
    # Do NOT call quick_test() here.
    # Quick tests are intentionally separate from full-test accounting.
    # --------------------------------------------------------------

    line
    printf 'PHASE 5 — TEST CENTER INTEGRITY\n'
    line

    if [ -x "$STELLA/stella-test.sh" ]; then
        result PASS "Test Center script is executable"
    else
        result FAIL "Test Center script is executable"
    fi

    if [ -f "$STELLA/.gitignore" ]; then
        result PASS "Git ignore policy exists"
    else
        result WARN "Git ignore policy not found"
    fi

    write_report
    summary
}

# ------------------------------------------------------------------
# Machine-readable report
# ------------------------------------------------------------------

write_report() {
    python3 - "$REPORT" "$pass" "$warn" "$fail" "$RESULTS_FILE" <<'PY'
import json
import sys
import datetime
import os

path = sys.argv[1]
passed = int(sys.argv[2])
warnings = int(sys.argv[3])
failed = int(sys.argv[4])
results_file = sys.argv[5]

checks = []

if os.path.exists(results_file):
    with open(results_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue

            status, message = line.split("\t", 1)

            checks.append({
                "status": status,
                "message": message
            })

report = {
    "schema_version": 2,
    "system": "STELLA",
    "component": "test-center",
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "results": {
        "passed": passed,
        "warnings": warnings,
        "failed": failed,
        "total": passed + warnings + failed
    },
    "checks": checks,
    "policy": {
        "sequential": True,
        "max_concurrent_ai": 1,
        "heavy_workers": 1,
        "safe_mode": True
    },
    "event_bus": "events/events.jsonl"
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
    f.write("\n")
PY

    rm -f "$RESULTS_FILE"
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

summary() {
    printf '\n'
    printf '╔════════════════════════════════════════════════════════════╗\n'
    printf '║                    TEST RESULT                            ║\n'
    printf '╚════════════════════════════════════════════════════════════╝\n'
    printf '\n'

    printf '  ✓ PASSED : %s\n' "$pass"
    printf '  ⚠ WARNED : %s\n' "$warn"
    printf '  ✗ FAILED : %s\n' "$fail"
    printf '  TOTAL    : %s\n' "$((pass + warn + fail))"

    printf '\n'
    printf '  Report : %s\n' "$REPORT"
    printf '  Log    : %s\n' "$LOG"
    printf '\n'

    if [ "$fail" -eq 0 ]; then
        if [ "$warn" -eq 0 ]; then
            printf '  STELLA TEST STATUS: PASS\n'
        else
            printf '  STELLA TEST STATUS: PASS WITH WARNINGS\n'
        fi
    else
        printf '  STELLA TEST STATUS: FAIL\n'
    fi

    printf '\n'

    if [ "$fail" -eq 0 ]; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------
# List
# ------------------------------------------------------------------

list_tests() {
    cat <<'LIST'

STELLA TEST CENTER

  01  Device Intelligence
  02  Brain & Provider Intelligence
  03  Provider Health
  04  AI Execution & Token Intelligence

  --quick   Fast compatibility test
  --all     Full sequential test of Agents 01-04
  --agent   Run one agent test

LIST
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

case "${1:-}" in

    --all)
        full_test
        rc=$?
        exit "$rc"
        ;;

    --quick)
        quick_test
        write_report
        summary
        rc=$?
        exit "$rc"
        ;;

    --agent)
        if [ -z "${2:-}" ]; then
            echo "Missing agent number."
            usage
            exit 1
        fi

        reset_results
        banner
        run_agent "$2"

        write_report
        summary
        rc=$?
        exit "$rc"
        ;;

    --list)
        list_tests
        exit 0
        ;;

    --help)
        usage
        exit 0
        ;;

    "")
        usage
        exit 0
        ;;

    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac
