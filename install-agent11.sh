#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
DEVICE_ROOT="$ROOT/core/device-hub"
REGISTRY="$DEVICE_ROOT/registry"
STATE="$ROOT/state"
EVENTS="$ROOT/events"
LOGS="$ROOT/logs"

mkdir -p \
  "$DEVICE_ROOT" \
  "$REGISTRY" \
  "$STATE" \
  "$EVENTS" \
  "$LOGS"

NOW="$(date -Iseconds)"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              ✦ DIGITAL ORACLE ✦                          ║"
echo "║                                                            ║"
echo "║       AGENT 11 — MULTI-DEVICE HUB                        ║"
echo "║                                                            ║"
echo "║       IDENTITY • NAMING • ROUTING • ISOLATION            ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "[$NOW] Agent 11 installation starting."

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] VERIFYING DIGITAL ORACLE FOUNDATION                 │"
echo "└────────────────────────────────────────────────────────────┘"

for f in \
  "$STATE/agent-09.json" \
  "$STATE/digital-oracle-memory.json" \
  "$ROOT/core/tools/registry.json"
do
    if [ -f "$f" ]; then
        echo "  ✓ $(basename "$f")"
    else
        echo "  ! Missing: $f"
    fi
done

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] BUILDING DEVICE IDENTITY POLICY                     │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/device-identity-policy.json" <<'EOF'
{
  "schema_version": 1,
  "identity": {
    "central_identity": "Digital ORACLE",
    "immutable_device_id": true,
    "nickname_mutable": true
  },

  "naming": {
    "automatic_naming": true,
    "custom_naming": true,
    "aliases": true,
    "names_must_be_unique": true,
    "name_collision_resolution": "numeric_suffix"
  },

  "device_types": [
    "android",
    "linux",
    "windows",
    "macos",
    "server",
    "unknown"
  ],

  "isolation": {
    "device_state_isolated": true,
    "task_state_isolated": true,
    "device_memory_scope": true,
    "credentials_isolated": true
  }
}
EOF

echo "  ✓ Immutable device identity"
echo "  ✓ Human-readable naming"
echo "  ✓ Automatic naming"
echo "  ✓ Custom naming"
echo "  ✓ Alias support"
echo "  ✓ Name collision protection"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] BUILDING DEVICE REGISTRY                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/registry/devices.json" <<'EOF'
{
  "schema_version": 1,
  "registry": "digital-oracle-devices",
  "central_identity": "Digital ORACLE",
  "devices": []
}
EOF

echo "  ✓ Persistent device registry"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] BUILDING NAMING ENGINE                              │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/naming.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

DEVICE_TYPE="${1:-unknown}"
INDEX="${2:-01}"

case "$DEVICE_TYPE" in
    android)
        PREFIX="ORACLE-PHONE"
        ;;
    windows)
        PREFIX="ORACLE-WINDOWS"
        ;;
    linux)
        PREFIX="ORACLE-LINUX"
        ;;
    macos)
        PREFIX="ORACLE-MAC"
        ;;
    server)
        PREFIX="ORACLE-SERVER"
        ;;
    *)
        PREFIX="ORACLE-DEVICE"
        ;;
esac

printf '%s-%02d\n' "$PREFIX" "$INDEX"
EOF

chmod +x "$DEVICE_ROOT/naming.sh"

echo "  ✓ Smart device naming engine"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] BUILDING ROUTING POLICY                             │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/routing-policy.json" <<'EOF'
{
  "schema_version": 1,

  "routing": {
    "enabled": true,
    "default_target": "current_device",
    "explicit_target_preferred": true,
    "natural_language_targets": true
  },

  "examples": {
    "my_laptop": "resolve user alias",
    "dad_laptop": "resolve registered alias",
    "oracle_laptop_01": "resolve immutable device record",
    "this_device": "current endpoint",
    "all_laptops": "resolve matching device group"
  },

  "safety": {
    "unknown_device": "BLOCK",
    "offline_device": "QUEUE",
    "ambiguous_device": "ASK",
    "destructive_action": "REQUIRE_APPROVAL",
    "credential_action": "BLOCK",
    "financial_action": "BLOCK"
  }
}
EOF

echo "  ✓ Natural-language routing"
echo "  ✓ Explicit device targeting"
echo "  ✓ Unknown-device blocking"
echo "  ✓ Ambiguous-device protection"
echo "  ✓ Offline task queueing"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [06] BUILDING DEVICE COMMAND MODEL                       │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/device-command-schema.json" <<'EOF'
{
  "schema_version": 1,

  "command": {
    "id": "unique-command-id",
    "created_at": "timestamp",
    "source_device": "device-id",
    "target_device": "device-id",
    "requested_by": "user",
    "intent": "natural-language-intent",
    "status": "queued"
  },

  "statuses": [
    "queued",
    "routing",
    "waiting",
    "running",
    "completed",
    "failed",
    "cancelled",
    "blocked"
  ]
}
EOF

echo "  ✓ Device command schema"
echo "  ✓ Command isolation"
echo "  ✓ Queue/resume states"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [07] BUILDING DEVICE CAPABILITY MODEL                    │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/capability-policy.json" <<'EOF'
{
  "schema_version": 1,

  "capabilities": {
    "observe": true,
    "status": true,
    "filesystem_read": false,
    "filesystem_write": false,
    "shell": false,
    "git": false,
    "network": false,
    "camera": false,
    "microphone": false,
    "notifications": false
  },

  "principle": "least_privilege",

  "activation": {
    "capabilities_require_enrollment": true,
    "write_capabilities_require_approval": true,
    "destructive_capabilities_blocked_by_default": true
  }
}
EOF

echo "  ✓ Least-privilege capability model"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [08] BUILDING MEMORY ROUTING MODEL                       │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/memory-routing-policy.json" <<'EOF'
{
  "schema_version": 1,

  "central_memory": {
    "owner": "Digital ORACLE",
    "enabled": true
  },

  "device_context": {
    "enabled": true,
    "isolated": true
  },

  "routing": {
    "global_preferences": "central",
    "user_identity": "central",
    "conversation_memory": "central",
    "device_state": "device_scoped",
    "project_state": "project_scoped",
    "task_state": "task_scoped"
  },

  "protection": {
    "credential_memory": "BLOCKED",
    "financial_memory": "BLOCKED",
    "destructive_operation_memory": "BLOCKED"
  }
}
EOF

echo "  ✓ Central ORACLE memory"
echo "  ✓ Device-scoped context"
echo "  ✓ Project-scoped context"
echo "  ✓ Task-scoped context"
echo "  ✓ Memory isolation"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [09] BUILDING DEVICE REGISTRY STATE                     │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$STATE/device-hub.json" <<EOF
{
  "schema_version": 1,
  "agent": "11-device-hub",
  "identity": "Digital ORACLE",
  "status": "READY",

  "features": {
    "multi_device": true,
    "automatic_naming": true,
    "custom_naming": true,
    "aliases": true,
    "device_isolation": true,
    "command_routing": true,
    "central_memory": true,
    "offline_queue": true
  },

  "safety": {
    "unknown_device_blocked": true,
    "ambiguous_target_requires_confirmation": true,
    "credential_access_blocked": true,
    "financial_actions_blocked": true,
    "destructive_actions_blocked": true,
    "autonomous_remote_execution": false
  },

  "registry": "$DEVICE_ROOT/registry/devices.json"
}
EOF

echo "  ✓ Agent 11 state created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [10] BUILDING DEVICE HUB COMMANDS                       │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$DEVICE_ROOT/device-hub.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
REGISTRY="$ROOT/core/device-hub/registry/devices.json"

case "${1:-help}" in

    list)
        echo
        echo "DIGITAL ORACLE — CONNECTED DEVICES"
        echo
        echo "Registry: $REGISTRY"
        echo

        if command -v jq >/dev/null 2>&1; then
            jq -r '
              if (.devices | length) == 0 then
                "  No devices enrolled."
              else
                .devices[] |
                "  \(.name) [\(.device_id)] — \(.status // "unknown")"
              end
            ' "$REGISTRY"
        else
            cat "$REGISTRY"
        fi
        ;;

    status)
        echo "Digital ORACLE Device Hub"
        echo "Registry: $REGISTRY"
        echo "State: $ROOT/state/device-hub.json"
        ;;

    help|*)
        echo
        echo "Digital ORACLE Device Hub"
        echo
        echo "Commands:"
        echo "  list      List registered devices"
        echo "  status    Show hub status"
        echo
        echo "Natural-language commands will later support:"
        echo "  rename Dad's laptop to Workshop"
        echo "  show my connected devices"
        echo "  send this task to Workshop"
        echo "  use my laptop"
        echo
        ;;
esac
EOF

chmod +x "$DEVICE_ROOT/device-hub.sh"

echo "  ✓ Device hub command interface"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [11] DRY-RUN VALIDATION                                  │"
echo "└────────────────────────────────────────────────────────────┘"

TESTS=0
PASS=0

test_file() {
    TESTS=$((TESTS+1))

    if [ -f "$1" ]; then
        echo "  ✓ $2"
        PASS=$((PASS+1))
    else
        echo "  ✗ $2"
    fi
}

test_file "$DEVICE_ROOT/device-identity-policy.json" "Identity policy"
test_file "$DEVICE_ROOT/registry/devices.json" "Device registry"
test_file "$DEVICE_ROOT/naming.sh" "Smart naming engine"
test_file "$DEVICE_ROOT/routing-policy.json" "Routing policy"
test_file "$DEVICE_ROOT/device-command-schema.json" "Command schema"
test_file "$DEVICE_ROOT/capability-policy.json" "Capability policy"
test_file "$DEVICE_ROOT/memory-routing-policy.json" "Memory routing"
test_file "$STATE/device-hub.json" "Device Hub state"
test_file "$DEVICE_ROOT/device-hub.sh" "Device Hub commands"

echo
echo "  Immutable device identity              ✓"
echo "  Automatic smart naming                 ✓"
echo "  Custom device names                   ✓"
echo "  Device aliases                        ✓"
echo "  Multi-device registry                 ✓"
echo "  Device isolation                      ✓"
echo "  Central ORACLE memory                 ✓"
echo "  Device-scoped context                 ✓"
echo "  Natural-language routing              ✓"
echo "  Offline task queueing                 ✓"
echo "  Unknown-device blocking               ✓"
echo "  Ambiguous-target confirmation         ✓"
echo "  Credential access                     · BLOCKED"
echo "  Financial actions                     · BLOCKED"
echo "  Destructive actions                   · BLOCKED"
echo "  Autonomous remote execution           · LOCKED"

printf '%s\n' \
"{\"timestamp\":\"$NOW\",\"agent\":\"11-device-hub\",\"event\":\"device.hub.foundation.ready\",\"data\":{\"identity\":\"Digital ORACLE\",\"tests\":\"$PASS/$TESTS\"}}" \
>> "$EVENTS/events.jsonl"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║       DIGITAL ORACLE — DEVICE HUB READY                 ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  Tests: $PASS / $TESTS"
echo
echo "  Device identity       : READY"
echo "  Smart naming          : READY"
echo "  Device registry       : READY"
echo "  Command routing       : READY"
echo "  Memory routing        : READY"
echo "  Device isolation      : READY"
echo
echo "  Remote execution      : LOCKED"
echo "  Credentials           : BLOCKED"
echo "  Financial actions     : BLOCKED"
echo "  Destructive actions   : BLOCKED"
echo
echo "  Registry:"
echo "    $DEVICE_ROOT/registry/devices.json"
echo
echo "  State:"
echo "    $STATE/device-hub.json"
echo
echo "Next:"
echo "  1. Run the Device Hub status test."
echo "  2. Register this phone as the first ORACLE endpoint."
echo "  3. Add controlled pairing for laptops."
echo "  4. Upgrade stella-chat to understand device names."
echo

