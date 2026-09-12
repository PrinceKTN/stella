#!/data/data/com.termux/files/usr/bin/bash
set -u

STELLA_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILL_ROOT="$STELLA_ROOT/core/skills/github-workspace"

STATE="$STELLA_ROOT/state"
WORKSPACE="$SKILL_ROOT/workspace"
LOGS="$STELLA_ROOT/logs"

ACCOUNT="$WORKSPACE/account.json"
LOG="$LOGS/github-workspace.log"

mkdir -p "$WORKSPACE" "$LOGS"

NOW() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    echo "[$(NOW)] $*" >> "$LOG"
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
    GH_PATH="$(command -v gh)"
    GH_VERSION="$(gh --version | head -n 1)"

    echo "  ✓ GitHub CLI detected"
    echo "  Path    : $GH_PATH"
    echo "  Version : $GH_VERSION"
else
    echo "  ✗ GitHub CLI not detected"
    echo
    echo "  Install GitHub CLI before continuing."
    exit 1
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] AUTHENTICATION                                       │"
echo "└────────────────────────────────────────────────────────────┘"

ACCOUNT_NAME=""

if GH_ACCOUNT="$(gh api user --jq '.login' 2>/dev/null)"; then
    ACCOUNT_NAME="$GH_ACCOUNT"

    echo "  ✓ GitHub authentication detected"
    echo "  Account : $ACCOUNT_NAME"
else
    echo "  ! GitHub authentication not detected"
    echo
    echo "  Stella needs you to authenticate with GitHub."
    echo "  Run:"
    echo
    echo "    gh auth login"
    echo
    echo "  Then run this detector again."
    exit 2
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] SAVING ACCOUNT STATE                                │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$ACCOUNT" <<EOF
{
  "schema_version": 1,
  "provider": "github",
  "account": "$ACCOUNT_NAME",
  "authenticated": true,
  "detected_at": "$(NOW)",
  "read_access": true,
  "write_access": false,
  "repository_creation": false,
  "push": false,
  "commit": false,
  "delete": false,
  "autonomous": false
}
EOF

echo "  ✓ Account state saved"
echo "  Account : $ACCOUNT"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] GIT IDENTITY                                        │"
echo "└────────────────────────────────────────────────────────────┘"

GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [ -n "$GIT_NAME" ]; then
    echo "  ✓ Git name detected : $GIT_NAME"
else
    echo "  ! Git name not configured"
fi

if [ -n "$GIT_EMAIL" ]; then
    echo "  ✓ Git email detected"
else
    echo "  ! Git email not configured"
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] WORKSPACE STATUS                                    │"
echo "└────────────────────────────────────────────────────────────┘"

echo "  Workspace : $WORKSPACE"
echo "  Account   : $ACCOUNT"
echo "  Mode      : OBSERVE"
echo "  Execution : DRY-RUN"
echo
echo "  Repository creation : LOCKED"
echo "  Push                 : LOCKED"
echo "  Commit               : LOCKED"
echo "  Delete               : LOCKED"
echo "  Autonomous GitHub    : LOCKED"

log "GitHub status check successful. Account=$ACCOUNT_NAME"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             GITHUB WORKSPACE READY                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  Authentication : READY"
echo "  Account        : $ACCOUNT_NAME"
echo "  Read access    : READY"
echo "  Write access   : LOCKED"
echo "  Safety         : ENABLED"
echo
echo "  Workspace:"
echo "    $WORKSPACE"
echo
echo "  Account state:"
echo "    $ACCOUNT"
echo
echo "  Log:"
echo "    $LOG"
echo

exit 0
