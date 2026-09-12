#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")" && pwd)"

SKILL_ROOT="$STELLA_ROOT/core/skills/github-workspace"
STATE="$STELLA_ROOT/state"
LOGS="$STELLA_ROOT/logs"
EVENT_DIR="$STELLA_ROOT/events"
EVENTS="$EVENT_DIR/events.jsonl"

mkdir -p \
    "$SKILL_ROOT/bin" \
    "$SKILL_ROOT/config" \
    "$SKILL_ROOT/workspace" \
    "$SKILL_ROOT/logs" \
    "$STATE" \
    "$LOGS" \
    "$EVENT_DIR"

NOW() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(NOW)] $*" | tee -a "$LOGS/github-workspace.log"
}

event() {
    local name="$1"
    local data="${2:-{}}"

    printf '{"timestamp":"%s","agent":"07-learning-skills","skill":"github-workspace","event":"%s","data":%s}\n' \
        "$(NOW)" \
        "$name" \
        "$data" >> "$EVENTS"
}

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  S T E L L A  ✦                         ║"
echo "║                                                            ║"
echo "║          GITHUB WORKSPACE SKILL — v0.1                    ║"
echo "║                                                            ║"
echo "║          AUTHENTICATION & WORKSPACE FOUNDATION             ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

log "GitHub Workspace Skill installation started."

echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] VERIFYING STELLA FOUNDATION                         │"
echo "└────────────────────────────────────────────────────────────┘"

[ -f "$STATE/learning-skills.json" ] \
    && echo "  ✓ Agent 07 learning/skills foundation" \
    || echo "  ⚠ Agent 07 state file not found — continuing safely"

[ -f "$STATE/orchestrator.json" ] \
    && echo "  ✓ Agent 05 core foundation" \
    || echo "  ⚠ Agent 05 state file not found — continuing safely"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] CREATING GITHUB WORKSPACE                           │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILL_ROOT/config/skill.json" <<EOF
{
  "schema_version": 1,
  "skill_id": "github-workspace",
  "name": "GitHub Workspace",
  "version": "0.1.0",
  "agent": "07-learning-skills",
  "status": "INSTALLED",

  "capabilities": {
    "detect_cli": true,
    "detect_authentication": true,
    "guided_login": true,
    "detect_account": true,
    "detect_git_identity": true,
    "inspect_repositories": true,
    "workspace_registry": true,

    "clone": false,
    "create_repository": false,
    "commit": false,
    "push": false,
    "pull": false,
    "branch": false,
    "issues": false,
    "pull_requests": false,
    "releases": false,
    "actions": false,
    "deployment": false
  },

  "safety": {
    "default_mode": "OBSERVE",
    "execution": "DRY-RUN",
    "unknown_risk": "HIGH",
    "native_execution": false,
    "autonomous_execution": false,
    "write_operations": false,
    "destructive_operations": false,
    "credential_storage_by_stella": false,
    "approval_required_for_future_write_operations": true
  },

  "resource_policy": {
    "resource_class": "MICRO",
    "max_workers": 1,
    "sequential": true
  }
}
EOF

cat > "$SKILL_ROOT/config/permissions.json" <<'EOF'
{
  "schema_version": 1,
  "skill": "github-workspace",

  "permissions": {
    "read_github_auth_status": true,
    "read_github_account": true,
    "read_git_config": true,
    "read_repository_metadata": true,
    "read_local_git_status": true,

    "write_repository": false,
    "push_repository": false,
    "delete_repository": false,
    "modify_github_settings": false,
    "manage_credentials": false
  },

  "approval": {
    "required_for_write": true,
    "required_for_push": true,
    "required_for_delete": true,
    "required_for_settings_change": true
  }
}
EOF

cat > "$SKILL_ROOT/config/operations.json" <<'EOF'
{
  "schema_version": 1,

  "phase_01": [
    "detect_cli",
    "detect_auth",
    "guided_login",
    "detect_account",
    "detect_git_identity"
  ],

  "phase_02": [
    "list_repositories",
    "inspect_repository",
    "inspect_local_repository",
    "workspace_registry"
  ],

  "phase_03_locked": [
    "clone",
    "create_repository",
    "branch",
    "commit",
    "push",
    "pull",
    "issues",
    "pull_requests",
    "releases",
    "actions",
    "deployment"
  ]
}
EOF

echo "  ✓ Skill configuration created"
echo "  ✓ Permission boundary created"
echo "  ✓ Operation phases created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] BUILDING WORKSPACE REGISTRY                         │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILL_ROOT/workspace/projects.json" <<'EOF'
{
  "schema_version": 1,
  "workspace": "stella-github-workspace",
  "created_at": "",
  "projects": []
}
EOF

cat > "$SKILL_ROOT/workspace/account.json" <<'EOF'
{
  "schema_version": 1,
  "authenticated": false,
  "username": "",
  "name": "",
  "host": "github.com",
  "checked_at": ""
}
EOF

echo "  ✓ Project registry created"
echo "  ✓ Account state created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] BUILDING GITHUB DETECTION ENGINE                    │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$SKILL_ROOT/bin/github-status.sh" <<'STATUS_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SKILL_ROOT="$STELLA_ROOT/core/skills/github-workspace"
STATE="$STELLA_ROOT/state"
LOG="$STELLA_ROOT/logs/github-workspace.log"
ACCOUNT="$SKILL_ROOT/workspace/account.json"

NOW() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              STELLA — GITHUB WORKSPACE                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] GITHUB CLI                                           │"
echo "└────────────────────────────────────────────────────────────┘"

if command -v gh >/dev/null 2>&1; then
    echo "  ✓ GitHub CLI detected"
    GH_PATH="$(command -v gh)"
    GH_VERSION="$(gh --version 2>/dev/null | head -n 1)"
    echo "  Path    : $GH_PATH"
    echo "  Version : $GH_VERSION"
else
    echo "  ✗ GitHub CLI is not installed"
    echo
    echo "  Stella needs GitHub CLI for the GitHub Workspace skill."
    echo
    echo "  Install it with:"
    echo
    echo "      pkg install gh"
    echo
    echo "  Then run this command again:"
    echo
    echo "      $SKILL_ROOT/bin/github-status.sh"
    exit 10
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] AUTHENTICATION                                       │"
echo "└────────────────────────────────────────────────────────────┘"

if gh auth status >/dev/null 2>&1; then

    echo "  ✓ GitHub authentication detected"

    ACCOUNT_INFO="$(gh api user 2>/dev/null || true)"

    if command -v python3 >/dev/null 2>&1 && [ -n "$ACCOUNT_INFO" ]; then

        USERNAME="$(printf '%s' "$ACCOUNT_INFO" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("login",""))' 2>/dev/null || true)"
        NAME="$(printf '%s' "$ACCOUNT_INFO" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name","") or "")' 2>/dev/null || true)"

    else
        USERNAME=""
        NAME=""
    fi

    echo "  Account : ${USERNAME:-detected}"
    [ -n "$NAME" ] && echo "  Name    : $NAME"

    cat > "$ACCOUNT" <<EOF
{
  "schema_version": 1,
  "authenticated": true,
  "username": "$USERNAME",
  "name": "$NAME",
  "host": "github.com",
  "checked_at": "$(NOW)"
}
EOF

else

    echo "  ✗ GitHub authentication not detected"

    cat > "$ACCOUNT" <<EOF
{
  "schema_version": 1,
  "authenticated": false,
  "username": "",
  "name": "",
  "host": "github.com",
  "checked_at": "$(NOW)"
}
EOF

    echo
    echo "  Stella needs you to authenticate with GitHub."
    echo
    echo "  Starting GitHub login..."
    echo

    gh auth login

    echo
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│ [03] VERIFYING LOGIN                                     │"
    echo "└────────────────────────────────────────────────────────────┘"

    if gh auth status >/dev/null 2>&1; then
        echo "  ✓ GitHub authentication successful"
    else
        echo "  ✗ GitHub authentication was not completed"
        exit 20
    fi
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] GIT IDENTITY                                        │"
echo "└────────────────────────────────────────────────────────────┘"

GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [ -n "$GIT_NAME" ]; then
    echo "  ✓ Git name detected : $GIT_NAME"
else
    echo "  ⚠ Git name not configured"
fi

if [ -n "$GIT_EMAIL" ]; then
    echo "  ✓ Git email detected"
else
    echo "  ⚠ Git email not configured"
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] WORKSPACE STATUS                                    │"
echo "└────────────────────────────────────────────────────────────┘"

echo "  Workspace : $SKILL_ROOT/workspace"
echo "  Account   : $ACCOUNT"
echo "  Mode      : OBSERVE"
echo "  Execution : DRY-RUN"

echo
echo "  Repository creation : LOCKED"
echo "  Push                 : LOCKED"
echo "  Commit               : LOCKED"
echo "  Delete               : LOCKED"
echo "  Autonomous GitHub    : LOCKED"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             GITHUB WORKSPACE READY                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "  Authentication : READY"
echo "  Account        : ${USERNAME:-detected}"
echo "  Read access    : READY"
echo "  Write access   : LOCKED"
echo "  Safety         : ENABLED"
echo

printf '[%s] GitHub Workspace status check completed.\n' "$(NOW)" >> "$LOG"

STATUS_EOF

chmod +x "$SKILL_ROOT/bin/github-status.sh"

echo "  ✓ GitHub detection engine created"
echo "  ✓ Authentication detection created"
echo "  ✓ Account detection created"
echo "  ✓ Git identity detection created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] REGISTERING SKILL WITH AGENT 07                    │"
echo "└────────────────────────────────────────────────────────────┘"

REGISTRY="$STELLA_ROOT/core/skills/registry.json"

if [ -f "$REGISTRY" ]; then

    cp "$REGISTRY" "$REGISTRY.backup-$(date '+%Y%m%d-%H%M%S')"

    if command -v python3 >/dev/null 2>&1; then

        python3 - "$REGISTRY" <<'PY'
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {
        "schema_version": 1,
        "skills": []
    }

if not isinstance(data.get("skills"), list):
    data["skills"] = []

skill = {
    "skill_id": "github-workspace",
    "name": "GitHub Workspace",
    "version": "0.1.0",
    "status": "INSTALLED",
    "enabled": False,
    "risk": "HIGH",
    "execution": "DRY-RUN",
    "native": False,
    "autonomous": False
}

existing = None

for item in data["skills"]:
    if isinstance(item, dict) and item.get("skill_id") == "github-workspace":
        existing = item
        break

if existing is None:
    data["skills"].append(skill)
else:
    existing.update(skill)

data["updated_at"] = datetime.now(timezone.utc).isoformat()

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

        echo "  ✓ GitHub Workspace registered with Agent 07"

    else
        echo "  ⚠ Python unavailable — registry registration deferred"
    fi

else

    cat > "$REGISTRY" <<'EOF'
{
  "schema_version": 1,
  "skills": [
    {
      "skill_id": "github-workspace",
      "name": "GitHub Workspace",
      "version": "0.1.0",
      "status": "INSTALLED",
      "enabled": false,
      "risk": "HIGH",
      "execution": "DRY-RUN",
      "native": false,
      "autonomous": false
    }
  ]
}
EOF

    echo "  ✓ New skill registry created"
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [06] CREATING SKILL STATE                                │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$STATE/github-workspace.json" <<EOF
{
  "schema_version": 1,
  "skill": "github-workspace",
  "version": "0.1.0",
  "status": "INSTALLED",
  "mode": "OBSERVE",
  "execution": "DRY-RUN",

  "authentication": {
    "checked": false,
    "authenticated": false
  },

  "capabilities": {
    "authentication": true,
    "account_detection": true,
    "repository_read": true,
    "repository_write": false,
    "push": false,
    "delete": false,
    "autonomous": false
  },

  "safety": {
    "approval_required": true,
    "unknown_risk": "HIGH",
    "native_locked": true
  }
}
EOF

echo "  ✓ Skill state created"

event \
    "github-workspace.installed" \
    "{\"version\":\"0.1.0\",\"mode\":\"OBSERVE\",\"execution\":\"DRY-RUN\",\"write_enabled\":false}"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           GITHUB WORKSPACE SKILL INSTALLED               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  Skill       : github-workspace"
echo "  Version     : 0.1.0"
echo "  Status      : INSTALLED"
echo "  Safety      : ENABLED"
echo "  Mode        : OBSERVE / DRY-RUN"
echo
echo "  Authentication : READY TO CHECK"
echo "  Repository     : READ-ONLY"
echo "  Push           : LOCKED"
echo "  Commit         : LOCKED"
echo "  Delete         : LOCKED"
echo "  Autonomous     : LOCKED"
echo
echo "Next:"
echo
echo "  $SKILL_ROOT/bin/github-status.sh"
echo
echo "Run that command to let Stella detect your GitHub installation"
echo "and determine whether this terminal is already authenticated."
echo

log "GitHub Workspace Skill v0.1 installed successfully."

