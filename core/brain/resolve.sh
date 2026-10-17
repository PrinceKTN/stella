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
