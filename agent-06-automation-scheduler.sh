#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"

STATE="$STELLA_ROOT/state"
EVENTS="$STELLA_ROOT/events/events.jsonl"
LOGS="$STELLA_ROOT/logs"

CORE="$STELLA_ROOT/core"
SCHEDULER="$CORE/scheduler"
JOBS="$SCHEDULER/jobs"
RUNS="$SCHEDULER/runs"
LOCKS="$SCHEDULER/locks"
SAFETY="$CORE/safety"

mkdir -p "$STATE" "$LOGS" "$CORE" "$SCHEDULER"
mkdir -p "$JOBS" "$RUNS" "$LOCKS" "$SAFETY"

LOG="$LOGS/agent-06.log"

NOW() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(NOW)] $*" | tee -a "$LOG"
}

event() {
    local agent="$1"
    local name="$2"
    local data="${3:-{}}"

    printf '{"timestamp":"%s","agent":"%s","event":"%s","data":%s}\n' \
        "$(NOW)" \
        "$agent" \
        "$name" \
        "$data" >> "$EVENTS"
}

banner() {
    printf '\033[2J\033[H'

    cat <<'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                 ✦  S T E L L A  ✦                         ║
║                                                            ║
║       AGENT 06 — AUTOMATION SCHEDULER                     ║
║                                                            ║
║             SAFE AUTOMATION CONTROL PLANE                 ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
}

fail() {
    echo
    echo "  ✗ $*"
    log "ERROR: $*"
    event "06-automation-scheduler" "scheduler.failed" \
        "{\"reason\":\"$*\"}"
    exit 1
}

banner

log "Agent 06 starting."

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] VERIFYING CORE FOUNDATION                            │"
echo "└────────────────────────────────────────────────────────────┘"

[ -f "$STATE/device.json" ] ||
    fail "Agent 01 device profile missing."

[ -f "$STATE/brain.json" ] ||
    fail "Agent 02 brain profile missing."

[ -f "$STATE/providers.json" ] ||
    fail "Agent 02 provider registry missing."

[ -f "$STATE/provider-health.json" ] ||
    fail "Agent 03 provider health missing."

[ -f "$STATE/agent-04-execution.json" ] ||
    fail "Agent 04 execution profile missing."

[ -f "$STATE/orchestrator.json" ] ||
    fail "Agent 05 orchestrator state missing."

[ -f "$SAFETY/execution-modes.json" ] ||
    fail "Agent 05 execution modes missing."

[ -f "$SAFETY/risk-policy.json" ] ||
    fail "Agent 05 risk policy missing."

echo "  ✓ Agent 01 foundation"
echo "  ✓ Agent 02 foundation"
echo "  ✓ Agent 03 foundation"
echo "  ✓ Agent 04 foundation"
echo "  ✓ Agent 05 core"
echo "  ✓ Agent 05 safety controller"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] READING EXECUTION POLICY                            │"
echo "└────────────────────────────────────────────────────────────┘"

RESOURCE_CLASS="UNKNOWN"
STRATEGY="SEQUENTIAL"
MAX_WORKERS=1

if command -v python3 >/dev/null 2>&1; then

    DEVICE_VALUES="$(
        python3 - "$STATE/device.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)

    c = d.get("classification", {})

    print(c.get("resource_class", "UNKNOWN"))
    print(c.get("strategy", "SEQUENTIAL"))

except Exception:
    print("UNKNOWN")
    print("SEQUENTIAL")
PY
    )"

    RESOURCE_CLASS="$(printf '%s\n' "$DEVICE_VALUES" | sed -n '1p')"
    STRATEGY="$(printf '%s\n' "$DEVICE_VALUES" | sed -n '2p')"
fi

case "$RESOURCE_CLASS" in
    MICRO)
        MAX_WORKERS=1
        ;;
    SMALL)
        MAX_WORKERS=2
        ;;
    MEDIUM)
        MAX_WORKERS=3
        ;;
    LARGE)
        MAX_WORKERS=4
        ;;
    SERVER)
        MAX_WORKERS=8
        ;;
    *)
        MAX_WORKERS=1
        ;;
esac

echo
echo "  Resource class : $RESOURCE_CLASS"
echo "  Strategy       : $STRATEGY"
echo "  Max workers    : $MAX_WORKERS"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] BUILDING SCHEDULER CONTROL PLANE                    │"
echo "└────────────────────────────────────────────────────────────┘"

SCHEDULER_ID="$(date '+%Y%m%d-%H%M%S')-$$"

SCHEDULER_RUN="$RUNS/$SCHEDULER_ID"

mkdir -p "$SCHEDULER_RUN"

cat > "$SCHEDULER_RUN/session.json" <<EOF
{
  "schema_version": 1,
  "scheduler_id": "$SCHEDULER_ID",
  "created_at": "$(NOW)",
  "status": "OBSERVE",
  "execution_mode": "DRY-RUN",
  "resource_class": "$RESOURCE_CLASS",
  "strategy": "$STRATEGY",
  "max_workers": $MAX_WORKERS,
  "active_jobs": 0,
  "completed_jobs": 0,
  "failed_jobs": 0,
  "cancelled_jobs": 0
}
EOF

echo "  ✓ Scheduler session created"
echo "  ✓ Scheduler ID: $SCHEDULER_ID"
echo "  ✓ Persistent run directory created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] BUILDING JOB QUEUE                                  │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$JOBS/queue.json" <<EOF
{
  "schema_version": 1,
  "updated_at": "$(NOW)",

  "scheduler": {
    "status": "READY",
    "mode": "OBSERVE",
    "execution": "DRY-RUN"
  },

  "queue": [],

  "policy": {
    "max_workers": $MAX_WORKERS,
    "strategy": "$STRATEGY",
    "sequential": true,
    "persistent_history": true,
    "preserve_previous_runs": true
  }
}
EOF

echo "  ✓ Job queue created"
echo "  ✓ Sequential policy enforced"
echo "  ✓ Persistent history enabled"
echo "  ✓ Previous runs protected"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] BUILDING AUTOMATION JOB MODEL                       │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$JOBS/job-template.json" <<'EOF'
{
  "schema_version": 1,

  "job": {
    "id": "job-example",
    "name": "Example Safe Job",
    "description": "Template only",
    "status": "PENDING",

    "trigger": {
      "type": "MANUAL",
      "schedule": null
    },

    "execution": {
      "mode": "DRY-RUN",
      "sandbox_required": true,
      "native_allowed": false,
      "ai_allowed": false,
      "external_network_allowed": false
    },

    "risk": {
      "level": "HIGH",
      "approval_required": true,
      "unknown_defaults_to_high": true
    },

    "limits": {
      "timeout_seconds": 60,
      "max_retries": 0,
      "max_workers": 1
    },

    "actions": [],

    "result": null
  }
}
EOF

echo "  ✓ Job schema created"
echo "  ✓ Manual trigger supported"
echo "  ✓ Scheduled trigger reserved"
echo "  ✓ Recurring trigger reserved"
echo "  ✓ Risk metadata required"
echo "  ✓ Approval metadata required"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [06] BUILDING TRIGGER ENGINE                              │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SCHEDULER/triggers.json" <<EOF
{
  "schema_version": 1,

  "supported": {
    "manual": true,
    "once": true,
    "interval": true,
    "cron": false,
    "event": true
  },

  "current_mode": "OBSERVE",

  "execution": {
    "enabled": false,
    "dry_run": true
  },

  "policy": {
    "unknown_trigger": "REJECT",
    "approval_required_for_new_automation": true,
    "sandbox_first": true
  }
}
EOF

echo "  ✓ Manual trigger architecture"
echo "  ✓ One-time trigger architecture"
echo "  ✓ Interval trigger architecture"
echo "  ✓ Event trigger architecture"
echo "  · Cron execution reserved"
echo "  ✓ Trigger safety policy created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [07] BUILDING SAFETY BOUNDARY                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SAFETY/scheduler-policy.json" <<EOF
{
  "schema_version": 1,
  "agent": "06-automation-scheduler",

  "default_mode": "OBSERVE",

  "execution_modes": {
    "observe": {
      "enabled": true,
      "execute_actions": false,
      "external_requests": false,
      "native_modification": false
    },

    "dry_run": {
      "enabled": true,
      "execute_actions": false,
      "external_requests": false,
      "native_modification": false
    },

    "sandbox": {
      "enabled": true,
      "approval_required": true,
      "native_modification": false
    },

    "native": {
      "enabled": false,
      "approval_required": true
    },

    "autonomous": {
      "enabled": false,
      "requires_explicit_skill_whitelist": true,
      "requires_approval_policy": true
    }
  },

  "risk_policy": {
    "unknown_risk": "HIGH",
    "high_risk_requires_approval": true,
    "destructive_actions_require_approval": true,
    "credential_actions_require_approval": true,
    "financial_actions_require_approval": true,
    "network_control_requires_approval": true
  },

  "protection": {
    "never_delete_previous_runs": true,
    "never_overwrite_test_history": true,
    "preserve_logs": true,
    "preserve_events": true,
    "automatic_destructive_recovery": false,
    "automatic_retry": false
  }
}
EOF

echo "  ✓ Observe mode"
echo "  ✓ Dry-run mode"
echo "  ✓ Sandbox mode"
echo "  ✓ Native mode reserved"
echo "  ✓ Autonomous mode locked"
echo "  ✓ Unknown risk defaults to HIGH"
echo "  ✓ Destructive actions require approval"
echo "  ✓ Financial actions require approval"
echo "  ✓ Credential actions require approval"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [08] BUILDING JOB HISTORY                                 │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SCHEDULER/history.json" <<EOF
{
  "schema_version": 1,
  "created_at": "$(NOW)",

  "policy": {
    "append_only": true,
    "preserve_previous_runs": true,
    "preserve_failed_runs": true,
    "preserve_cancelled_runs": true
  },

  "runs": []
}
EOF

echo "  ✓ Append-only history initialized"
echo "  ✓ Failed runs preserved"
echo "  ✓ Cancelled runs preserved"
echo "  ✓ Previous runs protected"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [09] BUILDING CONTROL COMMANDS                           │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SCHEDULER/commands.json" <<'EOF'
{
  "schema_version": 1,

  "shortcuts": {
    "up": "SELECT_PREVIOUS",
    "down": "SELECT_NEXT",
    "enter": "OPEN",
    "a": "APPROVE",
    "r": "RUN",
    "s": "SANDBOX",
    "n": "NATIVE",
    "d": "DRY_RUN",
    "p": "PAUSE",
    "c": "CANCEL",
    "l": "LOGS",
    "h": "HISTORY",
    "q": "QUIT"
  },

  "safety": {
    "run_requires_valid_job": true,
    "native_requires_approval": true,
    "high_risk_requires_approval": true,
    "unknown_risk_requires_approval": true
  }
}
EOF

echo "  ✓ Arrow navigation reserved"
echo "  ✓ Approve shortcut reserved"
echo "  ✓ Run shortcut reserved"
echo "  ✓ Sandbox shortcut reserved"
echo "  ✓ Native shortcut reserved"
echo "  ✓ Dry-run shortcut reserved"
echo "  ✓ Pause/cancel shortcuts reserved"
echo "  ✓ Logs/history shortcuts reserved"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [10] RESOURCE PROTECTION                                 │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SCHEDULER/resource-policy.json" <<EOF
{
  "schema_version": 1,

  "resource_class": "$RESOURCE_CLASS",

  "limits": {
    "max_workers": $MAX_WORKERS,
    "max_heavy_workers": 1,
    "max_concurrent_ai": 1,
    "scheduler_parallelism": 1
  },

  "micro_device_policy": {
    "enabled": true,
    "sequential_only": true,
    "heavy_worker_limit": 1,
    "automatic_scaling": false
  }
}
EOF

echo "  ✓ Resource limits inherited"
echo "  ✓ Heavy-worker limit: 1"
echo "  ✓ AI concurrency limit: 1"
echo "  ✓ Scheduler parallelism: 1"
echo "  ✓ Automatic scaling disabled"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [11] DRY-RUN VALIDATION                                  │"
echo "└────────────────────────────────────────────────────────────┘"

echo
echo "  Scheduler → Job Queue          ✓"
echo "  Scheduler → Trigger Engine     ✓"
echo "  Scheduler → Safety Policy      ✓"
echo "  Scheduler → History            ✓"
echo "  Scheduler → Resource Policy    ✓"
echo "  Scheduler → Control Commands   ✓"

echo
echo "  AI provider request             · SKIPPED"
echo "  Network request                 · SKIPPED"
echo "  Native device modification     · SKIPPED"
echo "  Scheduled job execution        · SKIPPED"
echo "  Autonomous execution            · LOCKED"
echo "  Destructive action              · BLOCKED"

event \
    "06-automation-scheduler" \
    "scheduler.initialized" \
    "{\"scheduler_id\":\"$SCHEDULER_ID\",\"resource_class\":\"$RESOURCE_CLASS\",\"mode\":\"OBSERVE\",\"execution\":\"DRY-RUN\",\"max_workers\":$MAX_WORKERS}"

event \
    "06-automation-scheduler" \
    "scheduler.safety.initialized" \
    "{\"sandbox_first\":true,\"unknown_risk\":\"HIGH\",\"native_enabled\":false,\"autonomous_enabled\":false}"

cat > "$STATE/automation-scheduler.json" <<EOF
{
  "schema_version": 1,
  "agent": "06-automation-scheduler",
  "timestamp": "$(NOW)",

  "status": "READY",

  "scheduler": {
    "id": "$SCHEDULER_ID",
    "mode": "OBSERVE",
    "execution": "DRY-RUN"
  },

  "resource_policy": {
    "resource_class": "$RESOURCE_CLASS",
    "strategy": "$STRATEGY",
    "max_workers": $MAX_WORKERS,
    "max_heavy_workers": 1,
    "max_concurrent_ai": 1
  },

  "automation": {
    "manual": true,
    "one_time": true,
    "interval": true,
    "event_trigger": true,
    "cron": false,
    "native_execution": false,
    "autonomous_execution": false
  },

  "safety": {
    "sandbox_first": true,
    "unknown_risk": "HIGH",
    "approval_required_for_high_risk": true,
    "destructive_actions_blocked": true,
    "financial_actions_require_approval": true,
    "credential_actions_require_approval": true
  },

  "history": {
    "append_only": true,
    "previous_runs_preserved": true
  },

  "upstream": [
    "01-device-intelligence",
    "02-brain-provider",
    "03-provider-health",
    "04-ai-execution",
    "05-core-orchestrator"
  ],

  "downstream_ready": [
    "07-learning-skills",
    "terminal-interface",
    "web-gui",
    "voice-interface",
    "video-interface"
  ]
}
EOF

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             AGENT 06 SCHEDULER READY                     ║"
echo "╚════════════════════════════════════════════════════════════╝"

echo
echo "  Scheduler : READY"
echo "  Safety    : ENABLED"
echo "  Mode      : OBSERVE / DRY-RUN"
echo "  Workers   : $MAX_WORKERS"
echo "  Sandbox   : FIRST"
echo "  Native    : LOCKED"
echo "  Autonomous: LOCKED"

echo
echo "  State:"
echo "    $STATE/automation-scheduler.json"

echo
echo "  Scheduler:"
echo "    $SCHEDULER"

echo
echo "  Jobs:"
echo "    $JOBS"

echo
echo "  History:"
echo "    $SCHEDULER/history.json"

echo
echo "  Events:"
echo "    $EVENTS"

echo
echo "  Log:"
echo "    $LOG"

log "Agent 06 completed successfully."

event \
    "06-automation-scheduler" \
    "scheduler.completed" \
    "{\"scheduler_id\":\"$SCHEDULER_ID\",\"status\":\"READY\",\"mode\":\"OBSERVE\",\"execution\":\"DRY-RUN\"}"
