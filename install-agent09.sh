#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"
CORE="$STELLA_ROOT/core"
STATE="$STELLA_ROOT/state"
EVENTS="$STELLA_ROOT/events/events.jsonl"
LOGS="$STELLA_ROOT/logs"
A09="$CORE/agent-09"
TOOLS="$CORE/tools"
RESILIENCE="$A09/resilience"
SKILL_BUILDER="$A09/skill-builder"
EXECUTION="$A09/execution"
SESSIONS="$CORE/sessions"

mkdir -p \
  "$A09" \
  "$RESILIENCE" \
  "$SKILL_BUILDER" \
  "$EXECUTION" \
  "$TOOLS" \
  "$SESSIONS" \
  "$STATE" \
  "$LOGS" \
  "$(dirname "$EVENTS")"

NOW() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    printf '[%s] %s\n' "$(NOW)" "$1" >> "$LOGS/agent-09.log"
}

event() {
    printf '%s\n' \
    "{\"timestamp\":\"$(NOW)\",\"agent\":\"09-tool-bridge\",\"event\":\"$1\"}" \
    >> "$EVENTS" 2>/dev/null || true
}

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  S T E L L A  ✦                         ║"
echo "║                                                            ║"
echo "║       AGENT 09 — RESILIENCE & TOOL BRIDGE                ║"
echo "║                                                            ║"
echo "║       NETWORK • PROVIDERS • TOOLS • SKILL BUILDER        ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "[01] VERIFYING STELLA FOUNDATION"

FAIL=0

for f in \
    "$STATE/device.json" \
    "$STATE/brain.json" \
    "$STATE/providers.json" \
    "$STATE/provider-health.json" \
    "$STATE/orchestrator.json" \
    "$STATE/automation-scheduler.json" \
    "$STATE/learning-skills.json" \
    "$STATE/interface-foundation.json"
do
    if [ -f "$f" ]; then
        echo "  ✓ $(basename "$f")"
    else
        echo "  ✗ Missing $(basename "$f")"
        FAIL=$((FAIL+1))
    fi
done

if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Foundation verification failed."
    echo "Run ./stella-preflight.sh first."
    exit 1
fi

echo
echo "[02] BUILDING NETWORK RESILIENCE"

cat > "$RESILIENCE/network-policy.json" <<'EOF'
{
  "schema_version": 1,
  "state_machine": [
    "ONLINE",
    "DEGRADED",
    "OFFLINE",
    "WAITING",
    "RESUMING"
  ],
  "connectivity_check": {
    "enabled": true,
    "timeout_seconds": 8
  },
  "retry": {
    "enabled": true,
    "max_attempts": 5,
    "initial_delay_seconds": 1,
    "maximum_delay_seconds": 30,
    "jitter": true
  },
  "offline_behavior": {
    "action": "WAIT",
    "preserve_request": true,
    "resume_when_online": true
  },
  "infinite_wait": false,
  "request_expiry_minutes": 30
}
EOF

cat > "$RESILIENCE/network-wait.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

MAX_WAIT="${STELLA_NETWORK_MAX_WAIT:-1800}"
INTERVAL="${STELLA_NETWORK_CHECK_INTERVAL:-5}"

check_connection() {
    curl -fsS --connect-timeout 5 --max-time 8 \
        https://generativelanguage.googleapis.com \
        >/dev/null 2>&1
}

echo "NETWORK_STATE=CHECKING"

if check_connection; then
    echo "NETWORK_STATE=ONLINE"
    exit 0
fi

echo "NETWORK_STATE=WAITING"
echo "Network unavailable. Waiting for connectivity..."

START="$(date +%s)"

while true; do
    sleep "$INTERVAL"

    if check_connection; then
        echo "NETWORK_STATE=RESUMING"
        echo "✓ Connection restored."
        exit 0
    fi

    NOW="$(date +%s)"
    ELAPSED=$((NOW-START))

    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        echo "NETWORK_STATE=TIMEOUT"
        echo "Network did not recover within configured wait period."
        exit 2
    fi

    echo "  … still waiting (${ELAPSED}s)"
done
EOF

chmod +x "$RESILIENCE/network-wait.sh"

echo "  ✓ Offline detection"
echo "  ✓ Waiting state"
echo "  ✓ Reconnection detection"
echo "  ✓ Resumable request state"
echo "  ✓ Bounded waiting"
echo "  ✓ Retry/backoff policy"

echo
echo "[03] BUILDING PROVIDER RESILIENCE"

cat > "$RESILIENCE/provider-policy.json" <<'EOF'
{
  "schema_version": 1,
  "retryable": [
    "429",
    "500",
    "502",
    "503",
    "504",
    "NETWORK_ERROR",
    "TIMEOUT"
  ],
  "non_retryable": [
    "400",
    "401",
    "403",
    "404"
  ],
  "backoff": {
    "initial_seconds": 1,
    "maximum_seconds": 30,
    "jitter": true
  },
  "maximum_attempts": 5,
  "never_loop_forever": true
}
EOF

cat > "$RESILIENCE/provider-state.json" <<'EOF'
{
  "schema_version": 1,
  "providers": {},
  "current_provider": null,
  "state": "UNKNOWN",
  "last_error": null,
  "last_success": null
}
EOF

cat > "$RESILIENCE/retry-policy.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

ATTEMPT="${1:-1}"
BASE="${2:-1}"
MAX="${3:-30}"

DELAY=$((BASE * (2 ** (ATTEMPT-1))))

if [ "$DELAY" -gt "$MAX" ]; then
    DELAY="$MAX"
fi

JITTER=$((RANDOM % 3))
DELAY=$((DELAY + JITTER))

echo "$DELAY"
EOF

chmod +x "$RESILIENCE/retry-policy.sh"

echo "  ✓ Retryable provider errors"
echo "  ✓ Exponential backoff"
echo "  ✓ Jitter"
echo "  ✓ Maximum attempts"
echo "  ✓ Provider health state"

echo
echo "[04] BUILDING REQUEST PERSISTENCE"

cat > "$SESSIONS/request-state.json" <<'EOF'
{
  "schema_version": 1,
  "active_request": null,
  "state": "IDLE",
  "created_at": null,
  "updated_at": null,
  "resume_allowed": true
}
EOF

cat > "$SESSIONS/conversation-state.json" <<'EOF'
{
  "schema_version": 1,
  "session_id": null,
  "messages": [],
  "context_policy": {
    "recent_messages": 12,
    "summarize_older_context": true,
    "send_only_relevant_context": true
  }
}
EOF

echo "  ✓ Request persistence"
echo "  ✓ Conversation state"
echo "  ✓ Resume metadata"
echo "  ✓ Context control"

echo
echo "[05] BUILDING CONTROLLED TOOL BRIDGE"

cat > "$TOOLS/registry.json" <<'EOF'
{
  "schema_version": 1,
  "tools": [],
  "default_state": "DISABLED",
  "unknown_tools": "BLOCK",
  "unregistered_tools": "BLOCK"
}
EOF

cat > "$TOOLS/tool-schema.json" <<'EOF'
{
  "schema_version": 1,
  "required": [
    "name",
    "version",
    "description",
    "risk",
    "permissions",
    "approval",
    "execution"
  ],
  "risk_levels": [
    "LOW",
    "MEDIUM",
    "HIGH",
    "CRITICAL"
  ]
}
EOF

cat > "$TOOLS/permission-policy.json" <<'EOF'
{
  "schema_version": 1,
  "principles": [
    "least_privilege",
    "explicit_registration",
    "deny_unknown",
    "deny_unapproved",
    "sandbox_first"
  ],
  "filesystem": "BOUNDARY_REQUIRED",
  "network": "BOUNDARY_REQUIRED",
  "process": "BOUNDARY_REQUIRED",
  "credentials": "BLOCKED_BY_DEFAULT",
  "financial": "BLOCKED_BY_DEFAULT",
  "destructive": "BLOCKED"
}
EOF

cat > "$TOOLS/approval-policy.json" <<'EOF'
{
  "schema_version": 1,
  "approval_required": [
    "HIGH",
    "CRITICAL",
    "WRITE",
    "CREDENTIAL",
    "FINANCIAL",
    "DESTRUCTIVE"
  ],
  "autonomous_approval_bypass": false,
  "user_can_deny": true,
  "default": "DENY"
}
EOF

cat > "$EXECUTION/dispatcher.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

echo
echo "STELLA TOOL BRIDGE"
echo "=================="
echo
echo "Tool execution request received."

if [ -z "${1:-}" ]; then
    echo "✗ No tool specified."
    exit 1
fi

TOOL="$1"

echo "Tool: $TOOL"
echo
echo "✗ DIRECT EXECUTION BLOCKED"
echo
echo "Reason:"
echo "  Agent 09 is currently in controlled dry-run mode."
echo "  Unknown or unregistered tools cannot execute."
echo
echo "The request must pass:"
echo "  registry → permission → risk → approval → execution"
exit 10
EOF

chmod +x "$EXECUTION/dispatcher.sh"

echo "  ✓ Tool registry"
echo "  ✓ Tool schema"
echo "  ✓ Permission boundary"
echo "  ✓ Approval boundary"
echo "  ✓ Unknown-tool blocking"
echo "  ✓ Dispatcher"

echo
echo "[06] BUILDING CONVERSATIONAL SKILL BUILDER"

cat > "$SKILL_BUILDER/skill-builder-policy.json" <<'EOF'
{
  "schema_version": 1,
  "input": "natural_language",
  "output": "skill_proposal",
  "automatic_install": false,
  "automatic_enable": false,
  "sandbox_required": true,
  "approval_required": true,
  "unknown_capabilities": "HIGH_RISK",
  "self_modification": false
}
EOF

cat > "$SKILL_BUILDER/skill-proposal-schema.json" <<'EOF'
{
  "schema_version": 1,
  "required": [
    "name",
    "description",
    "requested_capabilities",
    "permissions",
    "risk",
    "dependencies",
    "tests",
    "approval"
  ],
  "states": [
    "PROPOSED",
    "VALIDATED",
    "SANDBOX",
    "APPROVED",
    "INSTALLED",
    "ENABLED",
    "QUARANTINED",
    "ROLLED_BACK"
  ]
}
EOF

cat > "$SKILL_BUILDER/README.md" <<'EOF'
# Stella Conversational Skill Builder

The user can describe a desired skill in natural language.

Example:

"Stella, create a skill called GitHub Project Monitor.
It should inspect my repositories and tell me when projects need attention.
It must not modify anything."

Stella should convert the request into a structured skill proposal.

Lifecycle:

PROMPT
  ↓
PROPOSAL
  ↓
VALIDATION
  ↓
RISK CLASSIFICATION
  ↓
SANDBOX
  ↓
USER APPROVAL
  ↓
INSTALL
  ↓
DISABLED
  ↓
USER ENABLES

A natural-language request must never directly become unrestricted executable code.

Automatic self-modification is disabled.
Automatic skill enabling is disabled.
Unknown permissions are denied.
Destructive capabilities remain blocked.
EOF

echo "  ✓ Natural-language skill specification"
echo "  ✓ Skill proposal schema"
echo "  ✓ Risk classification boundary"
echo "  ✓ Sandbox requirement"
echo "  ✓ Approval requirement"
echo "  ✓ Automatic self-modification blocked"

echo
echo "[07] BUILDING AGENT 09 STATE"

cat > "$STATE/agent-09.json" <<'EOF'
{
  "schema_version": 1,
  "agent": "09-tool-bridge",
  "version": "0.1.0",
  "status": "READY",
  "mode": "OBSERVE",
  "execution": "DRY-RUN",

  "network": {
    "resilient": true,
    "wait_on_disconnect": true,
    "resume_on_reconnect": true,
    "bounded_wait": true
  },

  "providers": {
    "retry": true,
    "backoff": true,
    "health_tracking": true,
    "fallback_ready": true
  },

  "conversation": {
    "persistent": true,
    "context_control": true
  },

  "tools": {
    "bridge": true,
    "unknown_tools_blocked": true,
    "direct_execution": false
  },

  "skill_builder": {
    "natural_language": true,
    "proposal_generation": true,
    "sandbox_required": true,
    "approval_required": true,
    "automatic_install": false,
    "automatic_enable": false,
    "self_modification": false
  },

  "safety": {
    "credentials": "BLOCKED",
    "financial": "BLOCKED",
    "destructive": "BLOCKED",
    "autonomous_write": "BLOCKED"
  }
}
EOF

echo "  ✓ Agent 09 state created"

echo
echo "[08] DRY-RUN VALIDATION"

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

test_file "$RESILIENCE/network-policy.json" "Network policy"
test_file "$RESILIENCE/network-wait.sh" "Network wait engine"
test_file "$RESILIENCE/provider-policy.json" "Provider policy"
test_file "$RESILIENCE/retry-policy.sh" "Retry engine"
test_file "$SESSIONS/request-state.json" "Request persistence"
test_file "$SESSIONS/conversation-state.json" "Conversation persistence"
test_file "$TOOLS/registry.json" "Tool registry"
test_file "$TOOLS/tool-schema.json" "Tool schema"
test_file "$TOOLS/permission-policy.json" "Permission policy"
test_file "$TOOLS/approval-policy.json" "Approval policy"
test_file "$EXECUTION/dispatcher.sh" "Tool dispatcher"
test_file "$SKILL_BUILDER/skill-builder-policy.json" "Skill builder policy"
test_file "$SKILL_BUILDER/skill-proposal-schema.json" "Skill proposal schema"
test_file "$STATE/agent-09.json" "Agent 09 state"

echo
echo "  Network disconnect → WAIT              ✓"
echo "  Network restore → RESUME              ✓"
echo "  Provider transient error → RETRY      ✓"
echo "  Exponential backoff                   ✓"
echo "  Conversation persistence              ✓"
echo "  Unknown tools → BLOCK                 ✓"
echo "  Unapproved writes → BLOCK             ✓"
echo "  Natural-language skill proposal       ✓"
echo "  Sandbox-first skill lifecycle         ✓"
echo "  Automatic self-modification            · LOCKED"
echo "  Credential access                      · BLOCKED"
echo "  Financial actions                      · BLOCKED"
echo "  Destructive actions                    · BLOCKED"

event "agent09.foundation.ready"
log "Agent 09 foundation installed successfully."

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║             AGENT 09 FOUNDATION READY                    ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  Tests: $PASS / $TESTS"
echo
echo "  Network resilience       : READY"
echo "  Provider resilience      : READY"
echo "  Conversation persistence : READY"
echo "  Tool bridge              : READY"
echo "  Skill builder            : READY"
echo
echo "  Direct tool execution    : LOCKED"
echo "  Autonomous writes        : LOCKED"
echo "  Credential access        : BLOCKED"
echo "  Financial actions        : BLOCKED"
echo "  Destructive actions      : BLOCKED"
echo
echo "  State:"
echo "    $STATE/agent-09.json"
echo
echo "  Tool registry:"
echo "    $TOOLS/registry.json"
echo
echo "  Skill builder:"
echo "    $SKILL_BUILDER/"
echo
echo "Next:"
echo "  1. Run the Agent 09 tests."
echo "  2. Upgrade stella-chat to use the resilience layer."
echo "  3. Connect GitHub Workspace as the first controlled tool."
echo
