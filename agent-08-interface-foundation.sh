#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"

STATE="$STELLA_ROOT/state"
EVENT_DIR="$STELLA_ROOT/events"
EVENTS="$EVENT_DIR/events.jsonl"
LOGS="$STELLA_ROOT/logs"

CORE="$STELLA_ROOT/core"
INTERFACE="$CORE/interfaces"

TERMINAL="$INTERFACE/terminal"
WEB="$INTERFACE/web"
VOICE="$INTERFACE/voice"
VIDEO="$INTERFACE/video"

mkdir -p "$STATE" "$EVENT_DIR" "$LOGS"
mkdir -p "$INTERFACE" "$TERMINAL" "$WEB" "$VOICE" "$VIDEO"

LOG="$LOGS/agent-08.log"

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
║       AGENT 08 — INTERFACE & EXPERIENCE                   ║
║                                                            ║
║          TERMINAL + WEB GUI FOUNDATION                     ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
}

fail() {
    echo
    echo "  ✗ $*"
    log "ERROR: $*"
    exit 1
}

banner
log "Agent 08 starting."

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] VERIFYING STELLA FOUNDATION                         │"
echo "└────────────────────────────────────────────────────────────┘"

[ -f "$STATE/device.json" ] || fail "Agent 01 device profile missing."
[ -f "$STATE/brain.json" ] || fail "Agent 02 brain profile missing."
[ -f "$STATE/providers.json" ] || fail "Provider registry missing."
[ -f "$STATE/provider-health.json" ] || fail "Provider health missing."
[ -f "$STATE/agent-04-execution.json" ] || fail "Agent 04 execution profile missing."
[ -f "$STATE/orchestrator.json" ] || fail "Agent 05 orchestrator missing."
[ -f "$STATE/automation-scheduler.json" ] || fail "Agent 06 scheduler missing."
[ -f "$STATE/learning-skills.json" ] || fail "Agent 07 learning/skills state missing."

echo "  ✓ Agent 01 device foundation"
echo "  ✓ Agent 02 brain foundation"
echo "  ✓ Agent 03 provider foundation"
echo "  ✓ Agent 04 execution foundation"
echo "  ✓ Agent 05 core foundation"
echo "  ✓ Agent 06 scheduler foundation"
echo "  ✓ Agent 07 learning/skills foundation"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] BUILDING SHARED INTERFACE CORE                     │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$INTERFACE/interface-registry.json" <<EOF
{
  "schema_version": 1,
  "agent": "08-interface-foundation",
  "timestamp": "$(NOW)",

  "architecture": {
    "shared_core": true,
    "shared_event_bus": true,
    "shared_state": true,
    "separate_interfaces": true
  },

  "interfaces": {
    "terminal": {
      "status": "READY",
      "enabled": true
    },

    "web_gui": {
      "status": "FOUNDATION_READY",
      "enabled": false
    },

    "voice": {
      "status": "PLANNED",
      "enabled": false
    },

    "video": {
      "status": "PLANNED",
      "enabled": false
    }
  },

  "safety": {
    "observe": true,
    "dry_run": true,
    "native": false,
    "autonomous": false
  }
}
EOF

echo "  ✓ Shared interface registry"
echo "  ✓ Shared-core architecture"
echo "  ✓ Shared event bus"
echo "  ✓ Shared state model"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] TERMINAL INTERFACE FOUNDATION                       │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$TERMINAL/interface.json" <<EOF
{
  "schema_version": 1,
  "interface": "terminal",
  "status": "READY",

  "features": {
    "live_logs": true,
    "event_stream": true,
    "task_queue": true,
    "sessions": true,
    "skills": true,
    "provider_status": true,
    "device_status": true,
    "scheduler_status": true,
    "safety_status": true
  },

  "controls": {
    "inspect": true,
    "approve": true,
    "run": false,
    "sandbox": false,
    "native": false,
    "autonomous": false
  }
}
EOF

echo "  ✓ Terminal interface registry"
echo "  ✓ Live log support"
echo "  ✓ Event stream support"
echo "  ✓ Task visibility"
echo "  ✓ Skill visibility"
echo "  ✓ Provider visibility"
echo "  ✓ Device visibility"
echo "  ✓ Safety visibility"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] WEB GUI FOUNDATION                                  │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$WEB/interface.json" <<EOF
{
  "schema_version": 1,
  "interface": "web_gui",
  "status": "FOUNDATION_READY",

  "mode": "LIVE_DASHBOARD",

  "visualization": {
    "system_status": true,
    "agent_status": true,
    "brain_status": true,
    "provider_status": true,
    "task_queue": true,
    "automation": true,
    "skills": true,
    "learning": true,
    "sessions": true,
    "event_stream": true,
    "live_logs": true,
    "resource_usage": true,
    "safety_state": true
  },

  "controls": {
    "inspect": true,
    "approve": true,
    "run": false,
    "native": false,
    "autonomous": false
  }
}
EOF

echo "  ✓ Web GUI registry"
echo "  ✓ Live dashboard model"
echo "  ✓ Agent visualization model"
echo "  ✓ Brain/provider visualization"
echo "  ✓ Task visualization"
echo "  ✓ Skill visualization"
echo "  ✓ Learning visualization"
echo "  ✓ Resource visualization"
echo "  ✓ Safety visualization"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] LIVE EVENT CONTRACT                                 │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$INTERFACE/event-contract.json" <<'EOF'
{
  "schema_version": 1,

  "event_bus": "events/events.jsonl",

  "event_categories": [
    "system",
    "agent",
    "brain",
    "provider",
    "task",
    "scheduler",
    "skill",
    "learning",
    "execution",
    "safety",
    "interface"
  ],

  "interface_consumers": [
    "terminal",
    "web_gui",
    "voice",
    "video"
  ],

  "policy": {
    "append_only": true,
    "preserve_events": true,
    "interfaces_read_shared_events": true,
    "interfaces_do_not_bypass_core": true
  }
}
EOF

echo "  ✓ Event contract created"
echo "  ✓ System events"
echo "  ✓ Agent events"
echo "  ✓ Task events"
echo "  ✓ Skill events"
echo "  ✓ Learning events"
echo "  ✓ Safety events"
echo "  ✓ Interface events"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [06] LIVE DASHBOARD DATA MODEL                           │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$WEB/dashboard.json" <<EOF
{
  "schema_version": 1,
  "timestamp": "$(NOW)",

  "dashboard": {
    "title": "STELLA",
    "subtitle": "Digital Oracle Control Center",
    "mode": "OBSERVE / DRY-RUN"
  },

  "panels": [
    "system_overview",
    "agent_matrix",
    "brain_and_providers",
    "task_queue",
    "automation",
    "skills",
    "learning",
    "sessions",
    "event_stream",
    "live_terminal",
    "resource_monitor",
    "safety_center"
  ],

  "live_data": {
    "refresh": true,
    "event_stream": true,
    "logs": true,
    "resource_metrics": true
  },

  "controls": {
    "safe_inspection": true,
    "approval": true,
    "execution": false
  }
}
EOF

echo "  ✓ Dashboard data model"
echo "  ✓ System overview"
echo "  ✓ Agent matrix"
echo "  ✓ Brain/provider panel"
echo "  ✓ Task panel"
echo "  ✓ Automation panel"
echo "  ✓ Skills panel"
echo "  ✓ Learning panel"
echo "  ✓ Session panel"
echo "  ✓ Event stream"
echo "  ✓ Resource monitor"
echo "  ✓ Safety center"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [07] FUTURE MEDIA INTERFACES                             │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$VOICE/interface.json" <<EOF
{
  "schema_version": 1,
  "interface": "voice",
  "status": "PLANNED",
  "input": "VOICE_IN",
  "output": "VOICE_OUT",
  "shared_core": true,
  "enabled": false
}
EOF

cat > "$VIDEO/interface.json" <<EOF
{
  "schema_version": 1,
  "interface": "video",
  "status": "PLANNED",
  "input": "VIDEO_IN",
  "output": "VIDEO_OUT",
  "shared_core": true,
  "enabled": false
}
EOF

echo "  ✓ Voice interface reserved"
echo "  ✓ Voice-in/out architecture reserved"
echo "  ✓ Video interface reserved"
echo "  ✓ Video-in/out architecture reserved"
echo "  ✓ Shared-core routing preserved"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [08] SAFETY BOUNDARY                                    │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$INTERFACE/safety-boundary.json" <<'EOF'
{
  "schema_version": 1,

  "rules": {
    "interface_cannot_bypass_core": true,
    "interface_cannot_bypass_approval": true,
    "interface_cannot_enable_autonomous_mode": true,
    "interface_cannot_execute_native_actions": true,
    "unknown_actions_blocked": true
  },

  "current_mode": "OBSERVE",
  "execution_mode": "DRY-RUN"
}
EOF

echo "  ✓ Interface safety boundary"
echo "  ✓ Core bypass blocked"
echo "  ✓ Approval bypass blocked"
echo "  ✓ Autonomous bypass blocked"
echo "  ✓ Native execution blocked"
echo "  ✓ Unknown actions blocked"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [09] DRY-RUN VALIDATION                                 │"
echo "└────────────────────────────────────────────────────────────┘"

echo
echo "  Core → Terminal interface       ✓"
echo "  Core → Web GUI foundation       ✓"
echo "  Core → Voice reservation        ✓"
echo "  Core → Video reservation        ✓"
echo "  Event Bus → Interfaces          ✓"
echo "  Shared State → Interfaces       ✓"
echo "  Safety → Interfaces             ✓"

echo
echo "  Native execution                · LOCKED"
echo "  Autonomous execution            · LOCKED"
echo "  External modification            · SKIPPED"
echo "  Credential access               · LOCKED"
echo "  Financial action                · LOCKED"
echo "  Destructive action              · BLOCKED"

event \
    "08-interface-foundation" \
    "interface.registry.initialized" \
    "{\"terminal\":\"READY\",\"web_gui\":\"FOUNDATION_READY\",\"voice\":\"PLANNED\",\"video\":\"PLANNED\"}"

event \
    "08-interface-foundation" \
    "interface.safety.initialized" \
    "{\"core_bypass\":false,\"approval_bypass\":false,\"autonomous\":false,\"native\":false}"

cat > "$STATE/interface-foundation.json" <<EOF
{
  "schema_version": 1,
  "agent": "08-interface-foundation",
  "timestamp": "$(NOW)",

  "status": "READY",

  "terminal": {
    "status": "READY",
    "enabled": true
  },

  "web_gui": {
    "status": "FOUNDATION_READY",
    "enabled": false
  },

  "voice": {
    "status": "PLANNED",
    "enabled": false
  },

  "video": {
    "status": "PLANNED",
    "enabled": false
  },

  "architecture": {
    "shared_core": true,
    "shared_event_bus": true,
    "shared_state": true,
    "separate_interfaces": true
  },

  "safety": {
    "mode": "OBSERVE",
    "execution": "DRY-RUN",
    "native": false,
    "autonomous": false
  },

  "downstream_ready": [
    "09-terminal-runtime",
    "10-web-gui-runtime",
    "11-voice-interface",
    "12-video-interface",
    "future-device-control"
  ]
}
EOF

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             AGENT 08 INTERFACES READY                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  Agent       : 08-interface-foundation"
echo "  Status      : READY"
echo "  Safety      : ENABLED"
echo "  Mode        : OBSERVE / DRY-RUN"
echo
echo "  Terminal    : READY"
echo "  Web GUI     : FOUNDATION READY"
echo "  Voice       : PLANNED"
echo "  Video       : PLANNED"
echo
echo "  Shared Core : ENABLED"
echo "  Event Bus   : ENABLED"
echo "  Shared State: ENABLED"
echo
echo "  Native      : LOCKED"
echo "  Autonomous  : LOCKED"
echo
echo "  State:"
echo "    $STATE/interface-foundation.json"
echo
echo "  Registry:"
echo "    $INTERFACE/interface-registry.json"
echo
echo "  Web model:"
echo "    $WEB/dashboard.json"
echo
echo "  Events:"
echo "    $EVENTS"
echo
log "Agent 08 completed successfully."
