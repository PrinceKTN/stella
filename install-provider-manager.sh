#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
SKILL="$ROOT/core/skills/provider-manager"
BIN="$ROOT/bin"
CONFIG="$ROOT/config"
STATE="$ROOT/state"
SECRETS="$ROOT/secrets"

mkdir -p \
  "$SKILL/bin" \
  "$SKILL/config" \
  "$BIN" \
  "$CONFIG" \
  "$STATE" \
  "$SECRETS"

chmod 700 "$SECRETS"

# ------------------------------------------------------------
# Provider Manager registry
# ------------------------------------------------------------

cat > "$SKILL/config/providers.json" <<'JSON'
{
  "schema_version": 1,
  "skill": "provider-manager",
  "providers": {
    "groq": {
      "display_name": "Groq",
      "credential_env": "STELLA_GROQ_API_KEY",
      "type": "remote",
      "credential_required": true
    },
    "gemini": {
      "display_name": "Google Gemini",
      "credential_env": "STELLA_GEMINI_API_KEY",
      "type": "remote",
      "credential_required": true
    },
    "openrouter": {
      "display_name": "OpenRouter",
      "credential_env": "STELLA_OPENROUTER_API_KEY",
      "type": "gateway",
      "credential_required": true
    },
    "ollama": {
      "display_name": "Ollama",
      "credential_env": null,
      "type": "local",
      "credential_required": false
    }
  }
}
JSON

# ------------------------------------------------------------
# Secure provider manager
# ------------------------------------------------------------

cat > "$SKILL/bin/provider-manager.sh" <<'BASH'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
ENV_FILE="$ROOT/config/providers.env"
STATE_FILE="$ROOT/state/providers.json"
REGISTRY="$ROOT/core/skills/provider-manager/config/providers.json"

umask 077

mkdir -p "$ROOT/config" "$ROOT/state"

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

provider_valid() {
    case "$1" in
        groq|gemini|openrouter|ollama) return 0 ;;
        *) return 1 ;;
    esac
}

env_name() {
    case "$1" in
        groq) echo "STELLA_GROQ_API_KEY" ;;
        gemini) echo "STELLA_GEMINI_API_KEY" ;;
        openrouter) echo "STELLA_OPENROUTER_API_KEY" ;;
        ollama) echo "" ;;
        *) return 1 ;;
    esac
}

display_name() {
    case "$1" in
        groq) echo "Groq" ;;
        gemini) echo "Google Gemini" ;;
        openrouter) echo "OpenRouter" ;;
        ollama) echo "Ollama" ;;
        *) echo "$1" ;;
    esac
}

ensure_env_file() {
    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

configured() {
    local provider="$1"
    local env
    env="$(env_name "$provider")"

    [ -n "$env" ] || {
        [ "$provider" = "ollama" ] && return 1
    }

    grep -q "^${env}=" "$ENV_FILE" 2>/dev/null
}

write_credential() {
    local provider="$1"
    local env="$2"
    local value="$3"
    local tmp

    ensure_env_file

    tmp="$(mktemp "$ENV_FILE.tmp.XXXXXX")"
    chmod 600 "$tmp"

    if [ -f "$ENV_FILE" ]; then
        grep -v "^${env}=" "$ENV_FILE" > "$tmp" || true
    fi

    printf '%s="%s"\n' "$env" "$value" >> "$tmp"

    chmod 600 "$tmp"
    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    unset value
}

remove_credential() {
    local env="$1"
    local tmp

    ensure_env_file

    tmp="$(mktemp "$ENV_FILE.tmp.XXXXXX")"
    chmod 600 "$tmp"

    grep -v "^${env}=" "$ENV_FILE" > "$tmp" || true

    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

sync_state() {
    python - "$STATE_FILE" "$ENV_FILE" <<'PY'
import json
import os
import stat
import sys
from pathlib import Path

state_file = Path(sys.argv[1])
env_file = Path(sys.argv[2])

providers = ["groq", "gemini", "openrouter", "ollama"]

env_map = {
    "groq": "STELLA_GROQ_API_KEY",
    "gemini": "STELLA_GEMINI_API_KEY",
    "openrouter": "STELLA_OPENROUTER_API_KEY"
}

configured = {}

text = env_file.read_text(errors="ignore") if env_file.exists() else ""

for provider in providers:
    if provider == "ollama":
        configured[provider] = False
    else:
        key = env_map[provider]
        configured[provider] = any(
            line.startswith(key + "=") and len(line.split("=", 1)[1].strip().strip('"').strip("'")) > 0
            for line in text.splitlines()
        )

if state_file.exists():
    try:
        data = json.loads(state_file.read_text())
    except Exception:
        data = {}
else:
    data = {}

data.setdefault("schema_version", 1)
data.setdefault("providers", {})

for provider in providers:
    item = data["providers"].setdefault(provider, {})

    if provider in env_map:
        item["api_key_env"] = env_map[provider]

    item["configured"] = configured[provider]

    if not configured[provider]:
        item["health"] = "unknown"

data["provider_manager"] = {
    "configured": [p for p in providers if configured[p]]
}

state_file.write_text(json.dumps(data, indent=2) + "\n")

try:
    os.chmod(env_file, stat.S_IRUSR | stat.S_IWUSR)
except Exception:
    pass
PY
}

status() {
    echo
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              STELLA PROVIDER MANAGER                ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo

    for provider in groq gemini openrouter ollama; do
        if configured "$provider"; then
            echo "● $(display_name "$provider"): CONFIGURED"
        else
            echo "○ $(display_name "$provider"): NOT CONFIGURED"
        fi
    done

    echo
    echo "Credential file: $ENV_FILE"

    perms="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || echo unknown)"
    echo "Credential permissions: $perms"

    if [ "$perms" != "600" ]; then
        echo "WARNING: credential file permissions should be 600"
    fi

    echo
}

set_provider() {
    local provider="$1"

    provider_valid "$provider" || die "Unsupported provider: $provider"

    if [ "$provider" = "ollama" ]; then
        echo "Ollama does not require an API key."
        sync_state
        return 0
    fi

    local env
    env="$(env_name "$provider")"

    echo
    echo "STELLA PROVIDER MANAGER"
    echo "Provider: $(display_name "$provider")"
    echo
    echo "Enter the new API key."
    echo "Input is hidden and will not be displayed."
    echo

    local value
    read -r -s -p "API key: " value
    echo

    [ -n "$value" ] || die "No key supplied."

    write_credential "$provider" "$env" "$value"

    unset value

    sync_state

    echo
    echo "Credential updated for $(display_name "$provider")."
    echo "Secret value was not displayed or logged."
    echo
    echo "Next: run:"
    echo "  stella provider test $provider"
    echo
}

remove_provider() {
    local provider="$1"

    provider_valid "$provider" || die "Unsupported provider: $provider"

    local env
    env="$(env_name "$provider")"

    if [ -z "$env" ]; then
        echo "$(display_name "$provider") has no API credential."
        return 0
    fi

    remove_credential "$env"
    sync_state

    echo "Credential removed for $(display_name "$provider")."
}

test_provider() {
    local provider="$1"

    provider_valid "$provider" || die "Unsupported provider: $provider"

    case "$provider" in
        ollama)
            if command -v ollama >/dev/null 2>&1; then
                echo "Ollama executable: FOUND"
                if ollama list >/dev/null 2>&1; then
                    echo "Ollama: RESPONDING"
                else
                    echo "Ollama: NOT RESPONDING"
                fi
            else
                echo "Ollama: NOT INSTALLED"
            fi
            ;;

        *)
            if configured "$provider"; then
                echo "$(display_name "$provider"): credential is configured."
                echo "Network/API authentication testing will be added to the provider adapters."
                echo "No secret was displayed."
            else
                echo "$(display_name "$provider"): NOT CONFIGURED"
                return 1
            fi
            ;;
    esac
}

case "${1:-status}" in
    status)
        sync_state
        status
        ;;

    list)
        status
        ;;

    set)
        [ $# -ge 2 ] || die "Usage: provider-manager.sh set <provider>"
        set_provider "$2"
        ;;

    remove)
        [ $# -ge 2 ] || die "Usage: provider-manager.sh remove <provider>"
        remove_provider "$2"
        ;;

    test)
        [ $# -ge 2 ] || die "Usage: provider-manager.sh test <provider>"
        test_provider "$2"
        ;;

    *)
        cat <<'HELP'
STELLA PROVIDER MANAGER

Usage:

  provider-manager.sh status
  provider-manager.sh list
  provider-manager.sh set <provider>
  provider-manager.sh remove <provider>
  provider-manager.sh test <provider>

Providers:

  gemini
  groq
  openrouter
  ollama
HELP
        ;;
esac
BASH

chmod 700 "$SKILL/bin/provider-manager.sh"

# ------------------------------------------------------------
# Public Stella command
# ------------------------------------------------------------

cat > "$BIN/stella-provider" <<'BASH'
#!/data/data/com.termux/files/usr/bin/bash
exec "$HOME/stella/core/skills/provider-manager/bin/provider-manager.sh" "$@"
BASH

chmod 700 "$BIN/stella-provider"

# ------------------------------------------------------------
# Add convenient "stella provider ..." routing if Stella's
# existing launcher is suitable; otherwise expose aliases.
# ------------------------------------------------------------

cat > "$SKILL/README.md" <<'EOF'
# Stella Provider Manager

Secure management of external AI provider credentials.

## Providers

- Gemini
- Groq
- OpenRouter
- Ollama

## Security

Credentials are stored locally in:

config/providers.env

The file is excluded from Git and restricted to mode 600.

Raw credentials must never be:

- printed
- logged
- written to events
- placed in JSON state
- sent to an AI model
- committed to Git

## Commands

stella-provider status
stella-provider list
stella-provider set gemini
stella-provider set groq
stella-provider set openrouter
stella-provider remove gemini
stella-provider test gemini
EOF

# ------------------------------------------------------------
# Update provider example to match Stella's registry
# ------------------------------------------------------------

cat > "$CONFIG/providers.env.example" <<'EOF'
# ============================================================
# STELLA PROVIDER CONFIGURATION TEMPLATE
# ============================================================
#
# NEVER PUT REAL API KEYS IN THIS FILE.
#
# Private credentials belong in:
#
#   ~/stella/config/providers.env
#
# Stella Provider Manager can configure them securely.
#
# Supported remote providers:
#
# STELLA_GROQ_API_KEY="your-key"
# STELLA_GEMINI_API_KEY="your-key"
# STELLA_OPENROUTER_API_KEY="your-key"
#
# Local provider:
#
# Ollama does not require an API key.
EOF

chmod 644 "$CONFIG/providers.env.example"

# ------------------------------------------------------------
# Initialize private credential file without exposing content
# ------------------------------------------------------------

touch "$CONFIG/providers.env"
chmod 600 "$CONFIG/providers.env"

# ------------------------------------------------------------
# Sync provider state
# ------------------------------------------------------------

"$SKILL/bin/provider-manager.sh" status

echo
echo "============================================================"
echo " STELLA PROVIDER MANAGER INSTALLED"
echo "============================================================"
echo
echo "Try:"
echo "  ~/stella/bin/stella-provider status"
echo
echo "Configure a provider:"
echo "  ~/stella/bin/stella-provider set gemini"
echo
echo "Test configuration:"
echo "  ~/stella/bin/stella-provider test gemini"
echo
echo "The secret is never printed by the manager."
echo
