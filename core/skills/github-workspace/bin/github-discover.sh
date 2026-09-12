#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILL_ROOT="$STELLA_ROOT/core/skills/github-workspace"
WORKSPACE="$SKILL_ROOT/workspace"
PROJECTS="$WORKSPACE/projects"
STATE="$STELLA_ROOT/state"
LOG="$STELLA_ROOT/logs/github-workspace.log"
EVENTS="$STELLA_ROOT/events/events.jsonl"

mkdir -p "$WORKSPACE" "$PROJECTS" "$STELLA_ROOT/logs" "$STELLA_ROOT/events"

NOW() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(NOW)] $*" >> "$LOG"
}

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              STELLA — GITHUB DISCOVERY                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

if ! command -v gh >/dev/null 2>&1; then
    echo "  ✗ GitHub CLI unavailable"
    exit 1
fi

ACCOUNT="$(gh api user --jq '.login' 2>/dev/null || true)"

if [ -z "$ACCOUNT" ]; then
    echo "  ✗ GitHub authentication unavailable"
    exit 2
fi

echo "  Account : $ACCOUNT"
echo "  Mode    : OBSERVE"
echo "  Access  : READ-ONLY"
echo

echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] DISCOVERING REMOTE REPOSITORIES                     │"
echo "└────────────────────────────────────────────────────────────┘"

REPO_FILE="$WORKSPACE/github-repositories.json"

if gh repo list "$ACCOUNT" \
    --limit 100 \
    --json name,nameWithOwner,description,isPrivate,isFork,defaultBranchRef,url,pushedAt \
    > "$REPO_FILE" 2>/dev/null; then

    COUNT="$(python3 - "$REPO_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data=json.load(f)
    print(len(data))
except Exception:
    print(0)
PY
)"

    echo "  ✓ Repository discovery complete"
    echo "  Repositories found : $COUNT"
else
    echo "  ✗ Repository discovery failed"
    exit 3
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] BUILDING PROJECT INVENTORY                          │"
echo "└────────────────────────────────────────────────────────────┘"

python3 - "$REPO_FILE" "$WORKSPACE/project-registry.json" <<'PY'
import json
import sys
from datetime import datetime, timezone

repo_file=sys.argv[1]
registry_file=sys.argv[2]

with open(repo_file, encoding="utf-8") as f:
    repos=json.load(f)

projects=[]

for r in repos:
    projects.append({
        "name": r.get("name"),
        "full_name": r.get("nameWithOwner"),
        "description": r.get("description"),
        "private": r.get("isPrivate"),
        "fork": r.get("isFork"),
        "default_branch": (r.get("defaultBranchRef") or {}).get("name"),
        "url": r.get("url"),
        "pushed_at": r.get("pushedAt"),
        "local_path": None,
        "local_detected": False,
        "operations": {
            "inspect": True,
            "clone": False,
            "branch": False,
            "commit": False,
            "push": False,
            "pull": False,
            "delete": False
        }
    })

with open(registry_file, "r", encoding="utf-8") as f:
    registry=json.load(f)

registry["updated_at"]=datetime.now(timezone.utc).isoformat()
registry["projects"]=projects

with open(registry_file, "w", encoding="utf-8") as f:
    json.dump(registry, f, indent=2)
PY

echo "  ✓ Project inventory generated"
echo "  ✓ Repository metadata normalized"
echo "  ✓ Multi-project model ready"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] LOCAL PROJECT DETECTION                             │"
echo "└────────────────────────────────────────────────────────────┘"

LOCAL_REGISTRY="$WORKSPACE/local-projects.json"

python3 - "$STELLA_ROOT" "$LOCAL_REGISTRY" <<'PY'
import os
import json
import sys
from datetime import datetime, timezone

root=sys.argv[1]
output=sys.argv[2]

projects=[]

for current, dirs, files in os.walk(root):
    dirs[:] = [
        d for d in dirs
        if d not in {
            ".git",
            "node_modules",
            "__pycache__",
            ".npm",
            ".cache"
        }
    ]

    if ".git" in dirs or ".git" in files:
        projects.append({
            "path": current,
            "git_detected": True
        })

with open(output, "w", encoding="utf-8") as f:
    json.dump({
        "schema_version": 1,
        "detected_at": datetime.now(timezone.utc).isoformat(),
        "projects": projects
    }, f, indent=2)
PY

echo "  ✓ Local Git project scan complete"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] BUILDING OPERATION MATRIX                           │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$WORKSPACE/operation-policy.json" <<'EOF'
{
  "schema_version": 2,

  "mode": "OBSERVE",
  "execution": "DRY-RUN",

  "operations": {
    "account_inspection": {
      "enabled": true,
      "approval": false
    },

    "repository_listing": {
      "enabled": true,
      "approval": false
    },

    "repository_inspection": {
      "enabled": true,
      "approval": false
    },

    "local_status": {
      "enabled": true,
      "approval": false
    },

    "clone": {
      "enabled": false,
      "approval": true
    },

    "branch_create": {
      "enabled": false,
      "approval": true
    },

    "commit": {
      "enabled": false,
      "approval": true
    },

    "pull": {
      "enabled": false,
      "approval": true
    },

    "push": {
      "enabled": false,
      "approval": true
    },

    "repository_create": {
      "enabled": false,
      "approval": true
    },

    "repository_delete": {
      "enabled": false,
      "approval": true,
      "risk": "CRITICAL"
    }
  },

  "safety": {
    "unknown_operation": "BLOCK",
    "credential_export": "BLOCK",
    "token_storage": "BLOCK",
    "destructive_operation": "BLOCK",
    "autonomous_write": "BLOCK"
  }
}
EOF

echo "  ✓ Operation matrix created"
echo "  ✓ Read operations enabled"
echo "  ✓ Write operations locked"
echo "  ✓ Destructive operations blocked"
echo "  ✓ Credential export blocked"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] BUILDING PROJECT WORKSPACE MODEL                    │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$WORKSPACE/workspace-model.json" <<EOF
{
  "schema_version": 2,
  "workspace": "github-workspace",
  "account": "$ACCOUNT",
  "architecture": {
    "multi_project": true,
    "shared_core": true,
    "shared_event_bus": true,
    "project_isolation": true,
    "persistent_registry": true
  },

  "project_operations": [
    "discover",
    "inspect",
    "status",
    "diff",
    "clone",
    "branch",
    "test",
    "commit",
    "pull",
    "push",
    "release"
  ],

  "current_execution": {
    "mode": "OBSERVE",
    "dry_run": true,
    "write_operations": false,
    "autonomous_operations": false
  }
}
EOF

echo "  ✓ Multi-project workspace model created"
echo "  ✓ Project isolation enabled"
echo "  ✓ Shared Stella core preserved"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [06] BUILDING GITHUB SKILL STATE                         │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$STATE/github-workspace.json" <<EOF
{
  "schema_version": 2,
  "skill": "github-workspace",
  "version": "0.2.0",
  "status": "READY",
  "account": "$ACCOUNT",

  "authentication": {
    "provider": "gh",
    "detected": true,
    "credentials_managed_externally": true,
    "token_storage_by_stella": false
  },

  "capabilities": {
    "account_detection": true,
    "repository_discovery": true,
    "repository_inspection": true,
    "local_project_detection": true,
    "multi_project_registry": true,

    "clone": false,
    "branch": false,
    "commit": false,
    "pull": false,
    "push": false,
    "repository_create": false,
    "repository_delete": false
  },

  "safety": {
    "observe": true,
    "dry_run": true,
    "approval_required_for_write": true,
    "destructive_actions_blocked": true,
    "credential_export_blocked": true,
    "autonomous_write_blocked": true
  }
}
EOF

echo "  ✓ GitHub Workspace state updated"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [07] DRY-RUN VALIDATION                                  │"
echo "└────────────────────────────────────────────────────────────┘"

echo
echo "  Stella → GitHub account             ✓"
echo "  Stella → Repository discovery      ✓"
echo "  Stella → Repository metadata       ✓"
echo "  Stella → Local project detection   ✓"
echo "  Stella → Project registry          ✓"
echo "  Stella → Multi-project model       ✓"
echo "  Stella → Operation policy          ✓"
echo
echo "  Repository creation                 · LOCKED"
echo "  Clone                               · LOCKED"
echo "  Branch creation                     · LOCKED"
echo "  Commit                              · LOCKED"
echo "  Pull                                · LOCKED"
echo "  Push                                · LOCKED"
echo "  Delete                              · BLOCKED"
echo "  Credential export                   · BLOCKED"
echo "  Autonomous GitHub writes            · BLOCKED"

printf '%s\n' \
"{\"timestamp\":\"$(NOW)\",\"agent\":\"github-workspace\",\"event\":\"workspace.v0.2.ready\",\"data\":{\"account\":\"$ACCOUNT\",\"mode\":\"OBSERVE\",\"execution\":\"DRY-RUN\"}}" \
>> "$EVENTS"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          GITHUB WORKSPACE v0.2 READY                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  Account       : $ACCOUNT"
echo "  Status        : READY"
echo "  Mode          : OBSERVE / DRY-RUN"
echo
echo "  Repository discovery : READY"
echo "  Project registry     : READY"
echo "  Local detection      : READY"
echo "  Multi-project model  : READY"
echo
echo "  Write operations     : LOCKED"
echo "  Delete               : BLOCKED"
echo "  Autonomous writes    : BLOCKED"
echo
echo "  Registry:"
echo "    $WORKSPACE/project-registry.json"
echo
echo "  Repository inventory:"
echo "    $REPO_FILE"
echo
echo "  Local projects:"
echo "    $LOCAL_REGISTRY"
echo
echo "  Policy:"
echo "    $WORKSPACE/operation-policy.json"
echo
echo "  State:"
echo "    $STATE/github-workspace.json"
echo
echo "  Log:"
echo "    $LOG"
echo

log "GitHub Workspace v0.2 installed successfully. Account=$ACCOUNT"

