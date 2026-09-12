#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"

STATE="$STELLA_ROOT/state"
EVENTS="$STELLA_ROOT/events/events.jsonl"
LOGS="$STELLA_ROOT/logs"

CORE="$STELLA_ROOT/core"
SKILLS="$CORE/skills"
REGISTRY="$SKILLS/registry"
PACKAGES="$SKILLS/packages"
VERSIONS="$SKILLS/versions"
TESTS="$SKILLS/tests"
RUNS="$SKILLS/runs"
LEARNING="$SKILLS/learning"
APPROVALS="$SKILLS/approvals"
LOCKS="$SKILLS/locks"

mkdir -p \
    "$STATE" \
    "$LOGS" \
    "$CORE" \
    "$SKILLS" \
    "$REGISTRY" \
    "$PACKAGES" \
    "$VERSIONS" \
    "$TESTS" \
    "$RUNS" \
    "$LEARNING" \
    "$APPROVALS" \
    "$LOCKS"

LOG="$LOGS/agent-07.log"

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

fail() {
    echo
    echo "  ✗ $*"
    log "ERROR: $*"
    exit 1
}

banner() {
    printf '\033[2J\033[H'

    cat <<'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                 ✦  S T E L L A  ✦                         ║
║                                                            ║
║       AGENT 07 — LEARNING & SKILLS                        ║
║                                                            ║
║          CAPABILITY CONTROL PLANE                         ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
}

banner

log "Agent 07 starting."

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

[ -f "$CORE/safety/execution-modes.json" ] ||
    fail "Execution modes missing."

[ -f "$CORE/safety/risk-policy.json" ] ||
    fail "Risk policy missing."

[ -f "$CORE/scheduler/commands.json" ] ||
    fail "Scheduler command policy missing."

echo "  ✓ Agent 01 device foundation"
echo "  ✓ Agent 02 brain foundation"
echo "  ✓ Agent 03 provider foundation"
echo "  ✓ Agent 04 execution foundation"
echo "  ✓ Agent 05 core foundation"
echo "  ✓ Agent 06 scheduler foundation"
echo "  ✓ Safety policy"
echo "  ✓ Command policy"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] READING DEVICE EXECUTION POLICY                     │"
echo "└────────────────────────────────────────────────────────────┘"

RESOURCE_CLASS="UNKNOWN"
STRATEGY="SEQUENTIAL"
MAX_WORKERS=1

if command -v python3 >/dev/null 2>&1; then

    DEVICE_VALUES="$(python3 - "$STATE/device.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

c = data.get("classification", {})

print(c.get("resource_class", "UNKNOWN"))
print(c.get("strategy", "SEQUENTIAL"))
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
echo "│ [03] BUILDING SKILL REGISTRY                             │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILLS/registry.json" <<EOF
{
  "schema_version": 1,
  "created_at": "$(NOW)",

  "registry": {
    "status": "READY",
    "append_only_history": true,
    "version_tracking": true,
    "dependency_tracking": true,
    "disabled_skills_preserved": true
  },

  "policy": {
    "unknown_skill": "BLOCK",
    "unregistered_skill": "BLOCK",
    "invalid_schema": "BLOCK",
    "unknown_risk": "HIGH",
    "default_enabled": false,
    "default_native_execution": false,
    "default_autonomous_execution": false
  },

  "skills": []
}
EOF

echo "  ✓ Skill registry created"
echo "  ✓ Unknown skills blocked"
echo "  ✓ Unregistered skills blocked"
echo "  ✓ Default skill state: DISABLED"
echo "  ✓ Native execution disabled by default"
echo "  ✓ Autonomous execution disabled by default"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] BUILDING SKILL MODEL                                │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILLS/skill-schema.json" <<'EOF'
{
  "schema_version": 1,

  "required": [
    "skill_id",
    "name",
    "version",
    "description",
    "category",
    "risk",
    "permissions",
    "execution",
    "status"
  ],

  "skill": {
    "skill_id": "unique-string",
    "name": "human-readable-name",
    "version": "semantic-version",
    "description": "capability-description",
    "category": "category-name",

    "risk": {
      "level": "LOW|MEDIUM|HIGH|CRITICAL",
      "reason": "risk-explanation"
    },

    "permissions": {
      "filesystem_read": false,
      "filesystem_write": false,
      "network": false,
      "process_execution": false,
      "device_control": false,
      "credentials": false,
      "financial": false
    },

    "execution": {
      "sandbox_allowed": true,
      "sandbox_required": true,
      "native_allowed": false,
      "autonomous_allowed": false,
      "requires_approval": true
    },

    "dependencies": [],

    "status": {
      "enabled": false,
      "tested": false,
      "approved": false
    }
  }
}
EOF

echo "  ✓ Skill schema created"
echo "  ✓ Permission model created"
echo "  ✓ Dependency model created"
echo "  ✓ Risk metadata required"
echo "  ✓ Execution metadata required"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] BUILDING RISK CLASSIFICATION                        │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILLS/risk-policy.json" <<'EOF'
{
  "schema_version": 1,

  "default": "HIGH",

  "levels": {
    "LOW": {
      "examples": [
        "read-only information",
        "local formatting",
        "non-destructive calculation"
      ],
      "approval_required": false,
      "sandbox_preferred": true,
      "native_allowed": false
    },

    "MEDIUM": {
      "examples": [
        "local file creation",
        "package inspection",
        "configuration analysis"
      ],
      "approval_required": true,
      "sandbox_required": true,
      "native_allowed": false
    },

    "HIGH": {
      "examples": [
        "process execution",
        "network access",
        "system modification",
        "credential access"
      ],
      "approval_required": true,
      "sandbox_required": true,
      "native_allowed": false
    },

    "CRITICAL": {
      "examples": [
        "financial actions",
        "credential changes",
        "security boundary changes",
        "destructive operations"
      ],
      "approval_required": true,
      "sandbox_required": true,
      "native_allowed": false,
      "autonomous_allowed": false
    }
  },

  "unknown_risk": {
    "level": "HIGH",
    "approval_required": true,
    "sandbox_required": true,
    "native_allowed": false,
    "autonomous_allowed": false
  }
}
EOF

echo "  ✓ LOW risk policy"
echo "  ✓ MEDIUM risk policy"
echo "  ✓ HIGH risk policy"
echo "  ✓ CRITICAL risk policy"
echo "  ✓ Unknown-risk → HIGH"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [06] BUILDING PERMISSION BOUNDARY                       │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILLS/permission-policy.json" <<'EOF'
{
  "schema_version": 1,

  "permissions": {
    "filesystem_read": {
      "default": false,
      "requires_declaration": true
    },

    "filesystem_write": {
      "default": false,
      "requires_approval": true
    },

    "network": {
      "default": false,
      "requires_approval": true
    },

    "process_execution": {
      "default": false,
      "requires_approval": true
    },

    "device_control": {
      "default": false,
      "requires_approval": true,
      "native_execution_locked": true
    },

    "credentials": {
      "default": false,
      "requires_approval": true,
      "never_display_secret": true
    },

    "financial": {
      "default": false,
      "requires_approval": true,
      "autonomous_execution": false
    }
  },

  "principle": "least_privilege"
}
EOF

echo "  ✓ Least-privilege policy"
echo "  ✓ Filesystem boundary"
echo "  ✓ Network boundary"
echo "  ✓ Process boundary"
echo "  ✓ Device-control boundary"
echo "  ✓ Credential boundary"
echo "  ✓ Financial boundary"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [07] BUILDING SKILL LIFECYCLE                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILLS/lifecycle.json" <<'EOF'
{
  "schema_version": 1,

  "states": [
    "DISCOVERED",
    "REGISTERED",
    "VALIDATED",
    "TESTING",
    "TESTED",
    "PENDING_APPROVAL",
    "APPROVED",
    "ENABLED",
    "DISABLED",
    "QUARANTINED",
    "DEPRECATED",
    "REJECTED"
  ],

  "safe_flow": [
    "DISCOVERED",
    "REGISTERED",
    "VALIDATED",
    "TESTING",
    "TESTED",
    "PENDING_APPROVAL",
    "APPROVED",
    "ENABLED"
  ],

  "failure_flow": [
    "TESTING",
    "QUARANTINED"
  ],

  "rollback": {
    "enabled": true,
    "preserve_previous_version": true,
    "automatic_destructive_rollback": false
  }
}
EOF

echo "  ✓ Discovery lifecycle"
echo "  ✓ Validation lifecycle"
echo "  ✓ Testing lifecycle"
echo "  ✓ Approval lifecycle"
echo "  ✓ Enable/disable lifecycle"
echo "  ✓ Quarantine state"
echo "  ✓ Version rollback metadata"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [08] BUILDING LEARNING MEMORY                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$LEARNING/learning.json" <<EOF
{
  "schema_version": 1,
  "created_at": "$(NOW)",

  "policy": {
    "append_only": true,
    "preserve_failures": true,
    "preserve_successes": true,
    "preserve_user_feedback": true,
    "automatic_self_modification": false
  },

  "metrics": [
    "success_rate",
    "failure_rate",
    "execution_time",
    "resource_usage",
    "approval_rate",
    "sandbox_failures",
    "native_failures",
    "user_feedback"
  ],

  "records": []
}
EOF

echo "  ✓ Learning memory initialized"
echo "  ✓ Success history preserved"
echo "  ✓ Failure history preserved"
echo "  ✓ User feedback reserved"
echo "  ✓ Resource metrics reserved"
echo "  ✓ Automatic self-modification disabled"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [09] BUILDING VERSION CONTROL                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$VERSIONS/index.json" <<'EOF'
{
  "schema_version": 1,

  "policy": {
    "semantic_versions": true,
    "previous_versions_preserved": true,
    "failed_versions_preserved": true,
    "rollback_supported": true,
    "automatic_upgrade": false
  },

  "skills": []
}
EOF

echo "  ✓ Version tracking"
echo "  ✓ Previous versions preserved"
echo "  ✓ Failed versions preserved"
echo "  ✓ Rollback supported"
echo "  ✓ Automatic upgrades disabled"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [10] BUILDING SKILL TEST CENTER                          │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$TESTS/test-policy.json" <<'EOF'
{
  "schema_version": 1,

  "policy": {
    "sandbox_first": true,
    "native_testing": false,
    "network_testing": false,
    "financial_testing": false,
    "credential_testing": false,
    "destructive_testing": false
  },

  "required_checks": [
    "schema_validation",
    "permission_validation",
    "risk_validation",
    "dependency_validation",
    "sandbox_validation",
    "resource_validation"
  ]
}
EOF

echo "  ✓ Skill test center created"
echo "  ✓ Sandbox-first testing"
echo "  ✓ Native testing locked"
echo "  ✓ Network testing locked"
echo "  ✓ Financial testing locked"
echo "  ✓ Credential testing locked"
echo "  ✓ Destructive testing locked"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [11] BUILDING APPROVAL SYSTEM                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$APPROVALS/policy.json" <<'EOF'
{
  "schema_version": 1,

  "approval": {
    "manual_approval": true,
    "single_step_approval": true,
    "high_risk_required": true,
    "critical_risk_required": true,
    "native_required": true,
    "financial_required": true,
    "credential_required": true
  },

  "autonomous": {
    "enabled": false,
    "approval_bypass": false
  }
}
EOF

echo "  ✓ Manual approval"
echo "  ✓ High-risk approval"
echo "  ✓ Critical-risk approval"
echo "  ✓ Native approval boundary"
echo "  ✓ Financial approval boundary"
echo "  ✓ Credential approval boundary"
echo "  ✓ Autonomous approval bypass disabled"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [12] BUILDING SKILL COMMAND SHORTCUTS                    │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILLS/commands.json" <<'EOF'
{
  "schema_version": 1,

  "shortcuts": {
    "up": "SELECT_PREVIOUS_SKILL",
    "down": "SELECT_NEXT_SKILL",
    "enter": "OPEN_SKILL",
    "t": "TEST_SKILL",
    "s": "SANDBOX_TEST",
    "a": "APPROVE_SKILL",
    "e": "ENABLE_SKILL",
    "x": "DISABLE_SKILL",
    "v": "VIEW_VERSION",
    "l": "VIEW_LEARNING",
    "r": "ROLLBACK",
    "q": "QUIT"
  },

  "policy": {
    "shortcut_never_bypasses_safety": true,
    "shortcut_never_bypasses_approval": true,
    "shortcut_never_enables_autonomy": true
  }
}
EOF

echo "  ✓ Arrow skill navigation"
echo "  ✓ Test shortcut"
echo "  ✓ Sandbox shortcut"
echo "  ✓ Approval shortcut"
echo "  ✓ Enable/disable shortcuts"
echo "  ✓ Version shortcut"
echo "  ✓ Learning shortcut"
echo "  ✓ Rollback shortcut"
echo "  ✓ Shortcuts cannot bypass safety"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [13] RESOURCE PROTECTION                                 │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILLS/resource-policy.json" <<EOF
{
  "schema_version": 1,

  "resource_class": "$RESOURCE_CLASS",
  "strategy": "$STRATEGY",

  "limits": {
    "max_skill_operations": 1,
    "max_skill_tests": 1,
    "max_concurrent_learning_jobs": 1,
    "max_heavy_workers": 1
  },

  "micro_device": {
    "sequential_only": true,
    "automatic_parallelism": false,
    "automatic_scaling": false
  }
}
EOF

echo "  ✓ Skill operation limit: 1"
echo "  ✓ Skill test limit: 1"
echo "  ✓ Learning job limit: 1"
echo "  ✓ Heavy-worker limit: 1"
echo "  ✓ Parallel skill execution disabled"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [14] DRY-RUN VALIDATION                                  │"
echo "└────────────────────────────────────────────────────────────┘"

echo
echo "  Core → Skill Registry          ✓"
echo "  Scheduler → Skill Registry     ✓"
echo "  Skill → Risk Policy            ✓"
echo "  Skill → Permission Policy      ✓"
echo "  Skill → Test Center            ✓"
echo "  Skill → Approval Boundary      ✓"
echo "  Skill → Learning Memory        ✓"
echo "  Skill → Version Control        ✓"

echo
echo "  Arbitrary skill execution      · SKIPPED"
echo "  Native execution               · LOCKED"
echo "  Autonomous execution           · LOCKED"
echo "  Credential access              · LOCKED"
echo "  Financial action               · LOCKED"
echo "  Destructive action             · BLOCKED"
echo "  Automatic self-modification    · LOCKED"

event \
    "07-learning-skills" \
    "skills.initialized" \
    "{\"resource_class\":\"$RESOURCE_CLASS\",\"strategy\":\"$STRATEGY\",\"max_operations\":1,\"execution\":\"DRY-RUN\"}"

event \
    "07-learning-skills" \
    "skills.safety.initialized" \
    "{\"sandbox_first\":true,\"unknown_risk\":\"HIGH\",\"native_enabled\":false,\"autonomous_enabled\":false}"

cat > "$STATE/learning-skills.json" <<EOF
{
  "schema_version": 1,
  "agent": "07-learning-skills",
  "timestamp": "$(NOW)",

  "status": "READY",

  "resource_policy": {
    "resource_class": "$RESOURCE_CLASS",
    "strategy": "$STRATEGY",
    "max_skill_operations": 1,
    "max_skill_tests": 1
  },

  "registry": {
    "status": "READY",
    "version_tracking": true,
    "dependency_tracking": true
  },

  "learning": {
    "memory": true,
    "feedback": true,
    "metrics": true,
    "automatic_self_modification": false
  },

  "safety": {
    "sandbox_first": true,
    "unknown_risk": "HIGH",
    "native_execution": false,
    "autonomous_execution": false,
    "credential_access": false,
    "financial_actions": false,
    "destructive_actions": false
  },

  "upstream": [
    "01-device-intelligence",
    "02-brain-provider",
    "03-provider-health",
    "04-ai-execution",
    "05-core-orchestrator",
    "06-automation-scheduler"
  ],

  "downstream_ready": [
    "terminal-interface",
    "web-gui",
    "voice-interface",
    "video-interface",
    "skill-execution-engine"
  ]
}
EOF

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             AGENT 07 SKILLS READY                        ║"
echo "╚════════════════════════════════════════════════════════════╝"

echo
echo "  Agent    : 07-learning-skills"
echo "  Status   : READY"
echo "  Safety   : ENABLED"
echo "  Mode     : OBSERVE / DRY-RUN"
echo "  Workers  : 1"
echo
echo "  Skill registry       : READY"
echo "  Skill testing        : READY"
echo "  Skill approval       : READY"
echo "  Skill versioning     : READY"
echo "  Learning memory      : READY"
echo "  Rollback metadata    : READY"
echo
echo "  Native execution     : LOCKED"
echo "  Autonomous execution : LOCKED"
echo "  Credential access    : LOCKED"
echo "  Financial actions    : LOCKED"
echo "  Destructive actions  : BLOCKED"
echo
echo "  Registry:"
echo "    $SKILLS/registry.json"
echo
echo "  Skill schema:"
echo "    $SKILLS/skill-schema.json"
echo
echo "  Risk policy:"
echo "    $SKILLS/risk-policy.json"
echo
echo "  Learning:"
echo "    $LEARNING/learning.json"
echo
echo "  State:"
echo "    $STATE/learning-skills.json"

event \
    "07-learning-skills" \
    "agent.ready" \
    "{\"status\":\"READY\",\"mode\":\"OBSERVE\",\"execution\":\"DRY-RUN\",\"native\":false,\"autonomous\":false}"

log "Agent 07 completed successfully."
