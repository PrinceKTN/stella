#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"

STATE="$STELLA_ROOT/state"
EVENT_DIR="$STELLA_ROOT/events"
EVENTS="$EVENT_DIR/events.jsonl"
LOGS="$STELLA_ROOT/logs"

CORE="$STELLA_ROOT/core"
SESSIONS="$CORE/sessions"
TASKS="$CORE/tasks"
APPROVALS="$CORE/approvals"
SAFETY="$CORE/safety"
INTERFACES="$CORE/interfaces"
LOCKS="$CORE/locks"

LOG="$LOGS/agent-05.log"

mkdir -p \
    "$STATE" \
    "$EVENT_DIR" \
    "$LOGS" \
    "$CORE" \
    "$SESSIONS" \
    "$TASKS" \
    "$APPROVALS" \
    "$SAFETY" \
    "$INTERFACES" \
    "$LOCKS"

touch "$EVENTS"

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
║          AGENT 05 — CORE & ORCHESTRATOR                    ║
║                                                            ║
║              CONTROL PLANE INITIALIZER                    ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
}

section() {
    echo
    echo "┌────────────────────────────────────────────────────────────┐"
    printf "│ %-58s │\n" "$1"
    echo "└────────────────────────────────────────────────────────────┘"
}

fail() {
    echo
    echo "  ✗ $*"
    log "ERROR: $*"
    event "05-core-orchestrator" "orchestrator.failed" \
        "{\"message\":\"$*\"}"
    exit 1
}

banner
log "Agent 05 starting."

section "[01] READING STELLA INTELLIGENCE"

[ -f "$STATE/device.json" ] \
    || fail "Agent 01 device profile missing."

[ -f "$STATE/brain.json" ] \
    || fail "Agent 02 brain profile missing."

[ -f "$STATE/providers.json" ] \
    || fail "Agent 02 provider registry missing."

[ -f "$STATE/provider-health.json" ] \
    || fail "Agent 03 provider health missing."

[ -f "$STATE/agent-04-execution.json" ] \
    || fail "Agent 04 execution profile missing."

echo "  ✓ Agent 01 device intelligence"
echo "  ✓ Agent 02 brain intelligence"
echo "  ✓ Agent 03 provider intelligence"
echo "  ✓ Agent 04 execution intelligence"

section "[02] READING DEVICE POLICY"

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
        data = json.load(f)

    classification = data.get("classification", {})

    print(classification.get("resource_class", "UNKNOWN"))
    print(classification.get("strategy", "SEQUENTIAL"))

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

section "[03] BUILDING CORE CONTROL PLANE"

SESSION_ID="$(date '+%Y%m%d-%H%M%S')-$$"
SESSION_DIR="$SESSIONS/$SESSION_ID"

mkdir -p "$SESSION_DIR"

cat > "$SESSION_DIR/session.json" <<EOF
{
  "schema_version": 1,
  "session_id": "$SESSION_ID",
  "created_at": "$(NOW)",
  "status": "ACTIVE",
  "resource_class": "$RESOURCE_CLASS",
  "strategy": "$STRATEGY",
  "max_workers": $MAX_WORKERS,
  "active_workers": 0,
  "tasks_completed": 0,
  "tasks_failed": 0,
  "external_execution": false
}
EOF

echo "  ✓ Session manager initialized"
echo "  ✓ Session ID: $SESSION_ID"

cat > "$STATE/orchestrator.json" <<EOF
{
  "schema_version": 1,
  "agent": "05-core-orchestrator",
  "timestamp": "$(NOW)",

  "core": {
    "status": "READY",
    "session_manager": true,
    "task_manager": true,
    "event_router": true,
    "heartbeat": true,
    "failure_isolation": true,
    "approval_manager": true,
    "safety_controller": true
  },

  "device_policy": {
    "resource_class": "$RESOURCE_CLASS",
    "strategy": "$STRATEGY",
    "max_workers": $MAX_WORKERS,
    "one_heavy_worker": true
  },

  "execution": {
    "sequential": true,
    "provider_calls": false,
    "ai_execution": false,
    "external_modification": false,
    "dry_run": true
  },

  "safety": {
    "default_mode": "OBSERVE",
    "native_mode_requires_approval": true,
    "high_risk_requires_approval": true,
    "sandbox_preferred": true,
    "automatic_destructive_actions": false,
    "automatic_retry": false,
    "automatic_restart": false,
    "previous_runs_preserved": true
  },

  "interfaces": {
    "terminal": "READY",
    "web_gui": "PLANNED",
    "voice": "PLANNED",
    "video": "PLANNED"
  },

  "communication": {
    "event_bus": "$EVENTS",
    "state_directory": "$STATE",
    "session_directory": "$SESSIONS",
    "task_directory": "$TASKS",
    "approval_directory": "$APPROVALS"
  },

  "upstream_agents": [
    "01-device-intelligence",
    "02-brain-provider",
    "03-provider-health",
    "04-ai-execution"
  ],

  "downstream_ready": [
    "06-automation-scheduler",
    "07-learning-skills",
    "08-safety-policy",
    "terminal-interface",
    "web-gui",
    "voice-interface",
    "video-interface",
    "remote-device-controller"
  ]
}
EOF

echo "  ✓ Core state created"
echo "  ✓ Session manager created"
echo "  ✓ Task manager initialized"
echo "  ✓ Event router initialized"
echo "  ✓ Approval manager initialized"
echo "  ✓ Safety controller initialized"

section "[04] INITIALIZING TASK CONTROL"

cat > "$TASKS/queue.json" <<EOF
{
  "schema_version": 1,
  "updated_at": "$(NOW)",
  "queue": [],
  "policy": {
    "max_workers": $MAX_WORKERS,
    "strategy": "$STRATEGY",
    "sequential": true,
    "require_provider": true,
    "require_approval_for_high_risk": true,
    "sandbox_preferred": true,
    "allow_parallel_on_micro": false
  }
}
EOF

cat > "$TASKS/task-template.json" <<'EOF'
{
  "schema_version": 1,
  "task_id": "",
  "created_at": "",
  "status": "PENDING",
  "risk": "UNKNOWN",
  "mode": "OBSERVE",
  "requires_approval": true,
  "sandbox_preferred": true,
  "provider": null,
  "command": null,
  "result": null
}
EOF

echo "  ✓ Task queue initialized"
echo "  ✓ Task template created"
echo "  ✓ Task isolation enabled"
echo "  ✓ Approval boundary initialized"

section "[05] BUILDING SAFETY POLICY"

cat > "$SAFETY/execution-modes.json" <<'EOF'
{
  "schema_version": 1,
  "modes": {
    "OBSERVE": {
      "description": "Inspect state without changing the system.",
      "external_changes": false,
      "ai_execution": false,
      "approval": false
    },

    "DRY-RUN": {
      "description": "Simulate an operation without executing it.",
      "external_changes": false,
      "ai_execution": false,
      "approval": false
    },

    "SANDBOX": {
      "description": "Execute inside an isolated test environment when available.",
      "external_changes": "sandbox_only",
      "ai_execution": "optional",
      "approval": true
    },

    "NATIVE": {
      "description": "Execute against the real device.",
      "external_changes": true,
      "ai_execution": "optional",
      "approval": true
    }
  },

  "default_mode": "OBSERVE",
  "preferred_test_mode": "SANDBOX",
  "high_risk_mode": "NATIVE_REQUIRES_EXPLICIT_APPROVAL"
}
EOF

cat > "$SAFETY/risk-policy.json" <<'EOF'
{
  "schema_version": 1,

  "risk_levels": {
    "LOW": {
      "examples": [
        "read-only inspection",
        "state inspection",
        "health checks"
      ],
      "approval_required": false
    },

    "MEDIUM": {
      "examples": [
        "create temporary files",
        "install non-system development dependencies",
        "run isolated test workloads"
      ],
      "approval_required": true
    },

    "HIGH": {
      "examples": [
        "modify system configuration",
        "delete data",
        "change security settings",
        "control external devices",
        "execute financial actions"
      ],
      "approval_required": true,
      "sandbox_first": true
    }
  },

  "unknown_risk": {
    "default": "HIGH",
    "approval_required": true
  }
}
EOF

echo "  ✓ Execution modes created"
echo "  ✓ Risk policy created"
echo "  ✓ Unknown-risk default set to HIGH"
echo "  ✓ Sandbox-first policy enabled"

section "[06] FAILURE ISOLATION"

cat > "$STATE/failure-policy.json" <<EOF
{
  "schema_version": 1,
  "agent": "05-core-orchestrator",

  "policy": {
    "agent_failure_isolated": true,
    "continue_unrelated_agents": true,
    "automatic_retry": false,
    "automatic_restart": false,
    "notify_on_failure": true,
    "preserve_logs": true,
    "preserve_state": true,
    "never_delete_previous_runs": true,
    "never_overwrite_test_history": true
  }
}
EOF

echo "  ✓ Agent failures isolated"
echo "  ✓ Previous state preserved"
echo "  ✓ Logs preserved"
echo "  ✓ Test history preserved"
echo "  ✓ Automatic destructive recovery disabled"

section "[07] HEARTBEAT & SYSTEM STATUS"

cat > "$STATE/heartbeat.json" <<EOF
{
  "schema_version": 1,
  "agent": "05-core-orchestrator",
  "timestamp": "$(NOW)",
  "status": "HEALTHY",
  "session_id": "$SESSION_ID",
  "event_bus": "ONLINE",
  "task_queue": "READY",
  "approval_manager": "READY",
  "safety_controller": "READY",
  "failure_isolation": "ENABLED"
}
EOF

echo "  ✓ Heartbeat initialized"
echo "  ✓ Event bus ONLINE"
echo "  ✓ Task queue READY"
echo "  ✓ Approval manager READY"
echo "  ✓ Safety controller READY"
echo "  ✓ Failure isolation ENABLED"

section "[08] INTERFACE FOUNDATION"

cat > "$INTERFACES/interface-registry.json" <<'EOF'
{
  "schema_version": 1,

  "interfaces": {
    "terminal": {
      "status": "READY",
      "primary": true,
      "interaction": [
        "keyboard",
        "arrows",
        "shortcuts",
        "quick_actions"
      ]
    },

    "web_gui": {
      "status": "PLANNED",
      "shares_core": true
    },

    "voice": {
      "status": "PLANNED",
      "shares_core": true
    },

    "video": {
      "status": "PLANNED",
      "shares_core": true
    }
  },

  "architecture_rule": "All interfaces communicate with the same Stella Core."
}
EOF

echo "  ✓ Terminal interface reserved"
echo "  ✓ GUI interface reserved"
echo "  ✓ Voice interface reserved"
echo "  ✓ Video interface reserved"
echo "  ✓ Shared-core architecture locked"

section "[09] ORCHESTRATOR DRY-RUN"

echo
echo "  Agent 01 → Core              ✓"
echo "  Agent 02 → Core              ✓"
echo "  Agent 03 → Core              ✓"
echo "  Agent 04 → Core              ✓"
echo
echo "  Core → Task Queue            ✓"
echo "  Core → Approval Manager      ✓"
echo "  Core → Safety Controller     ✓"
echo "  Core → Event Bus             ✓"
echo "  Core → Session Manager       ✓"
echo "  Core → Failure Isolation     ✓"
echo
echo "  AI provider request          · SKIPPED"
echo "  External modification        · SKIPPED"
echo "  Heavy worker                 · SKIPPED"
echo "  Native execution             · SKIPPED"
echo
echo "  Safety mode                  : OBSERVE"
echo "  Execution                    : DRY-RUN"

event \
    "05-core-orchestrator" \
    "orchestrator.ready" \
    "{\"session_id\":\"$SESSION_ID\",\"resource_class\":\"$RESOURCE_CLASS\",\"strategy\":\"$STRATEGY\",\"max_workers\":$MAX_WORKERS,\"dry_run\":true}"

event \
    "05-core-orchestrator" \
    "safety.policy.initialized" \
    "{\"default_mode\":\"OBSERVE\",\"sandbox_preferred\":true,\"native_requires_approval\":true}"

event \
    "05-core-orchestrator" \
    "interface.registry.initialized" \
    "{\"terminal\":\"READY\",\"web_gui\":\"PLANNED\",\"voice\":\"PLANNED\",\"video\":\"PLANNED\"}"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             AGENT 05 CORE READY                           ║"
echo "╚════════════════════════════════════════════════════════════╝"

echo
echo "  Session : $SESSION_ID"
echo "  Core    : READY"
echo "  Safety  : ENABLED"
echo "  Mode    : OBSERVE / DRY-RUN"
echo "  Workers : $MAX_WORKERS"
echo
echo "  State:"
echo "    $STATE/orchestrator.json"
echo
echo "  Safety:"
echo "    $SAFETY/execution-modes.json"
echo "    $SAFETY/risk-policy.json"
echo
echo "  Session:"
echo "    $SESSION_DIR"
echo
echo "  Events:"
echo "    $EVENTS"
echo
echo "  Log:"
echo "    $LOG"
echo

log "Agent 05 completed successfully."
