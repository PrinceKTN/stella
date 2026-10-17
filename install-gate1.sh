#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX_DIR="${PREFIX:-$HOME/.local}/bin"
GLOBAL_LAUNCHER="$PREFIX_DIR/stella"
BACKUP_DIR="$ROOT/tmp/gate1-backup-$(date '+%Y%m%d-%H%M%S')"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 STELLA — GATE 1 INSTALLER                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "Stella root:"
echo "  $ROOT"
echo

# ------------------------------------------------------------
# PREFLIGHT
# ------------------------------------------------------------

[ -d "$ROOT/core" ] || {
    echo "✗ Invalid Stella installation: core/ missing."
    exit 1
}

[ -f "$ROOT/core/interfaces/terminal/stella-chat.sh" ] || {
    echo "✗ Terminal runtime not found."
    exit 1
}

[ -f "$ROOT/config/providers.env" ] || {
    echo "✗ Provider configuration not found."
    exit 1
}

mkdir -p "$ROOT/tmp"
mkdir -p "$PREFIX_DIR"

echo "✓ Stella installation detected."

# ------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------

mkdir -p "$BACKUP_DIR"

cp -p \
    "$ROOT/core/interfaces/terminal/stella-chat.sh" \
    "$BACKUP_DIR/stella-chat.sh"

echo "✓ Runtime backup created:"
echo "  $BACKUP_DIR"
echo

# ------------------------------------------------------------
# BRAIN RESOLVER
# ------------------------------------------------------------

mkdir -p "$ROOT/core/brain"

cat > "$ROOT/core/brain/resolve.sh" <<'RESOLVER'
#!/data/data/com.termux/files/usr/bin/bash

set -u

BRAIN_ROOT="$(cd "$(dirname "$0")" && pwd)"
STELLA_ROOT="$(cd "$BRAIN_ROOT/../.." && pwd)"

CONFIG="$STELLA_ROOT/config/providers.env"

# Default Stella brain.
#
# This is deliberately configuration-driven.
# Agents should not need to know which provider is underneath.

STELLA_BRAIN_PROVIDER="${STELLA_BRAIN_PROVIDER:-gemini}"
STELLA_BRAIN_MODEL="${STELLA_BRAIN_MODEL:-}"

if [ -f "$CONFIG" ]; then
    set -a
    . "$CONFIG"
    set +a
fi

case "$STELLA_BRAIN_PROVIDER" in

    gemini)
        PROVIDER="gemini"
        MODEL="${STELLA_BRAIN_MODEL:-${STELLA_GEMINI_MODEL:-gemini-2.5-flash}}"
        CREDENTIAL_ENV="STELLA_GEMINI_API_KEY"
        ;;

    groq)
        PROVIDER="groq"
        MODEL="${STELLA_BRAIN_MODEL:-${STELLA_GROQ_MODEL:-}}"
        CREDENTIAL_ENV="STELLA_GROQ_API_KEY"
        ;;

    openrouter)
        PROVIDER="openrouter"
        MODEL="${STELLA_BRAIN_MODEL:-${STELLA_OPENROUTER_MODEL:-}}"
        CREDENTIAL_ENV="STELLA_OPENROUTER_API_KEY"
        ;;

    ollama)
        PROVIDER="ollama"
        MODEL="${STELLA_BRAIN_MODEL:-${STELLA_OLLAMA_MODEL:-}}"
        CREDENTIAL_ENV=""
        ;;

    *)
        echo "ERROR: Unsupported Stella brain provider: $STELLA_BRAIN_PROVIDER" >&2
        exit 1
        ;;
esac

export STELLA_BRAIN_PROVIDER="$PROVIDER"
export STELLA_BRAIN_MODEL="$MODEL"
export STELLA_BRAIN_CREDENTIAL_ENV="$CREDENTIAL_ENV"

# Compatibility aliases.
#
# Existing Gemini runtime can continue using its current
# credential without exposing the secret to this resolver.

if [ "$PROVIDER" = "gemini" ]; then
    export STELLA_GEMINI_MODEL="$MODEL"
fi
RESOLVER

chmod 700 "$ROOT/core/brain/resolve.sh"

echo "✓ Brain resolver installed."

# ------------------------------------------------------------
# BRAIN PROFILE
# ------------------------------------------------------------

cat > "$ROOT/config/brain.env.example" <<'PROFILE'
# Stella Brain Profile
#
# Leave these commented for the default Stella brain.
#
# Provider:
# STELLA_BRAIN_PROVIDER=gemini
#
# Optional model override:
# STELLA_BRAIN_MODEL=gemini-2.5-flash
#
# Supported foundation providers:
# gemini
# groq
# openrouter
# ollama
PROFILE

if [ ! -f "$ROOT/config/brain.env" ]; then
    cat > "$ROOT/config/brain.env" <<'PROFILE'
# Stella Brain Profile
#
# Default:
# Gemini using the credential already configured in providers.env.
#
# This file contains configuration only.
# API credentials remain in providers.env.

STELLA_BRAIN_PROVIDER=gemini
STELLA_BRAIN_MODEL=gemini-2.5-flash
PROFILE

    chmod 600 "$ROOT/config/brain.env"
fi

echo "✓ Brain profile installed."

# ------------------------------------------------------------
# BRAIN STATUS
# ------------------------------------------------------------

cat > "$ROOT/bin/stella-brain" <<'BRAIN'
#!/data/data/com.termux/files/usr/bin/bash

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/brain.env"
RESOLVER="$ROOT/core/brain/resolve.sh"

if [ -f "$CONFIG" ]; then
    set -a
    . "$CONFIG"
    set +a
fi

if ! "$RESOLVER"; then
    exit 1
fi

echo
echo "╔══════════════════════════════════════════════════════╗"
echo "║                 STELLA BRAIN                       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo
echo "  Provider : ${STELLA_BRAIN_PROVIDER:-UNKNOWN}"
echo "  Model    : ${STELLA_BRAIN_MODEL:-UNKNOWN}"
echo "  Credential: ${STELLA_BRAIN_CREDENTIAL_ENV:-LOCAL/NONE}"
echo
BRAIN

chmod 700 "$ROOT/bin/stella-brain"

echo "✓ Brain status command installed."

# ------------------------------------------------------------
# GLOBAL LAUNCHER
# ------------------------------------------------------------

cat > "$GLOBAL_LAUNCHER" <<LAUNCHER
#!/data/data/com.termux/files/usr/bin/bash

set -u

STELLA_ROOT="$ROOT"
RUNTIME="\$STELLA_ROOT/core/interfaces/terminal/stella-chat.sh"

if [ ! -d "\$STELLA_ROOT" ]; then
    echo
    echo "✗ Stella installation is missing."
    echo "  Expected:"
    echo "  \$STELLA_ROOT"
    echo
    echo "Run the Stella installer/repair process."
    exit 1
fi

if [ ! -x "\$RUNTIME" ]; then
    echo
    echo "✗ Stella installation appears broken."
    echo "  Runtime missing:"
    echo "  \$RUNTIME"
    echo
    echo "Run the Stella installer/repair process."
    exit 1
fi

exec "\$RUNTIME" "\$@"
LAUNCHER

chmod 700 "$GLOBAL_LAUNCHER"

echo "✓ Global launcher installed:"
echo "  $GLOBAL_LAUNCHER"

# ------------------------------------------------------------
# PATH DETECTION
# ------------------------------------------------------------

case ":${PATH:-}:" in
    *":$PREFIX_DIR:"*)
        PATH_READY=1
        ;;
    *)
        PATH_READY=0
        ;;
esac

if [ "$PATH_READY" -eq 0 ]; then
    echo
    echo "⚠ $PREFIX_DIR is not currently in PATH."
    echo
    echo "Add it with:"
    echo
    echo "  export PATH=\"$PREFIX_DIR:\$PATH\""
    echo
    echo "For a permanent Termux setup, add that line to:"
    echo "  ~/.bashrc"
    echo
else
    echo "✓ Global launcher directory is already in PATH."
fi

# ------------------------------------------------------------
# VERIFICATION
# ------------------------------------------------------------

echo
echo "===== GATE 1 VERIFICATION ====="
echo

FAIL=0

if [ -x "$GLOBAL_LAUNCHER" ]; then
    echo "✓ Global launcher"
else
    echo "✗ Global launcher"
    FAIL=1
fi

if [ -x "$ROOT/core/brain/resolve.sh" ]; then
    echo "✓ Brain resolver"
else
    echo "✗ Brain resolver"
    FAIL=1
fi

if [ -x "$ROOT/bin/stella-brain" ]; then
    echo "✓ Brain status command"
else
    echo "✗ Brain status command"
    FAIL=1
fi

if "$ROOT/bin/stella-brain" >/dev/null 2>&1; then
    echo "✓ Brain resolution"
else
    echo "✗ Brain resolution"
    FAIL=1
fi

echo

if [ "$FAIL" -ne 0 ]; then
    echo "✗ Gate 1 installation failed."
    echo
    echo "Runtime backup remains at:"
    echo "  $BACKUP_DIR"
    exit 1
fi

echo "✓ Gate 1 installation completed."
echo
echo "Next taste commands:"
echo
echo "  export PATH=\"$PREFIX_DIR:\$PATH\""
echo "  stella-brain"
echo "  stella"
echo
echo "No Git commit was created."
echo "No Git push was performed."
echo
