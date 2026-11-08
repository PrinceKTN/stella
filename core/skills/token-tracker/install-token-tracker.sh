#!/usr/bin/env bash
# ==============================================================
# STELLA — TOKEN TRACKER SKILL INSTALLER
# ==============================================================

set -euo pipefail

STELLA_ROOT="${STELLA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
export STELLA_ROOT

SKILL_DIR="$STELLA_ROOT/core/skills/token-tracker"
SKILL_CONFIG="$STELLA_ROOT/config/skills/token-tracker"
SKILL_BIN="$STELLA_ROOT/bin"

echo "╔═════════════════════════════════════════════════════════════╗"
echo "║       INSTALLING TOKEN TRACKER SKILL                       ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo

# Create directories
mkdir -p "$SKILL_DIR/bin" "$SKILL_DIR/config" "$SKILL_DIR/templates"
mkdir -p "$STELLA_ROOT/state" "$STELLA_ROOT/events" "$STELLA_ROOT/logs"
mkdir -p "$STELLA_ROOT/config/schemas" "$STELLA_ROOT/config/skills"

# Ensure skill script is executable
chmod +x "$SKILL_DIR/bin/token-tracker.sh"

# Link to global bin
ln -sf "$SKILL_DIR/bin/token-tracker.sh" "$STELLA_ROOT/bin/token-tracker"

# Initialize config
"$SKILL_DIR/bin/token-tracker.sh" init

# Validate schema
if command -v python3 >/dev/null 2>&1; then
    STELLA_ROOT="$STELLA_ROOT" python3 <<PY
import json, sys, os
stella_root = os.environ.get('STELLA_ROOT')
try:
    schema_path = os.path.join(stella_root, 'config/schemas/token-tracker.schema.json')
    config_path = os.path.join(stella_root, 'core/skills/token-tracker/config/token-tracker.json')
    with open(schema_path) as f:
        schema = json.load(f)
    with open(config_path) as f:
        config = json.load(f)
    required = ["schema_version", "enabled", "tracking", "display"]
    for r in required:
        if r not in config:
            print(f"MISSING: {r}", file=sys.stderr)
            sys.exit(1)
    print("Configuration validation: PASSED")
except Exception as e:
    print(f"Validation error: {e}", file=sys.stderr)
    sys.exit(1)
PY
fi

# Register skill in registry
REGISTRY="$STELLA_ROOT/core/skills/registry.json"
if [[ -f "$REGISTRY" ]]; then
    REGISTRY="$REGISTRY" python3 <<PY
import json, os, sys
registry_file = os.environ.get('REGISTRY')
with open(registry_file) as f:
    reg = json.load(f)

# Ensure skills is a list
if "skills" not in reg or not isinstance(reg["skills"], list):
    reg["skills"] = []

# Check if already exists
existing = next((s for s in reg["skills"] if s.get("skill_id") == "token-tracker"), None)
if existing:
    print("Skill already registered")
    sys.exit(0)

reg["skills"].append({
    "skill_id": "token-tracker",
    "name": "Token Tracker",
    "version": "1.0.0",
    "status": "INSTALLED",
    "enabled": True,
    "risk": "LOW",
    "execution": "AUTO",
    "native": True,
    "autonomous": False,
    "description": "Live token usage monitoring across providers with smart splitting and alerting",
    "entry_point": "core/skills/token-tracker/bin/token-tracker.sh",
    "commands": ["record", "report", "split", "monitor", "alerts", "export", "cleanup", "config"],
    "hooks": ["pre_provider_call", "post_provider_call", "daily_summary"],
    "provides": ["token_monitoring", "provider_optimization", "limit_alerting", "task_splitting"]
})

with open(registry_file, 'w') as f:
    json.dump(reg, f, indent=2)
print("Skill registered in registry")
PY
fi

echo
echo "✅ Token Tracker Skill installed"
echo "   Binary: $STELLA_ROOT/bin/token-tracker"
echo "   Config: $STELLA_ROOT/core/skills/token-tracker/config/token-tracker.json"
echo "   Schema: $STELLA_ROOT/config/schemas/token-tracker.schema.json"
echo
echo "USAGE:"
echo "  token-tracker report          # Today's usage"
echo "  token-tracker split 15000     # Plan a 15k token task"
echo "  token-tracker monitor 60      # Live monitor (60s interval)"
echo "  token-tracker record gemini gemini-2.5-flash 1200 800 chat"
echo

exit 0