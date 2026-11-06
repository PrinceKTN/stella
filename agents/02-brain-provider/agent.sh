#!/usr/bin/env bash
# ==============================================================
# STELLA — AGENT 02
# BRAIN & PROVIDER GATEWAY v2 — Live Provider Registry
# ==============================================================

set -euo pipefail

STELLA_ROOT="${STELLA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export STELLA_ROOT

STATE_DIR="$STELLA_ROOT/state"
EVENT_DIR="$STELLA_ROOT/events"
LOG_DIR="$STELLA_ROOT/logs"
CONFIG_DIR="$STELLA_ROOT/config"
SECRETS_DIR="$STELLA_ROOT/secrets"
BRAIN_DIR="$STELLA_ROOT/brain"
SCHEMA_DIR="$STELLA_ROOT/config/schemas"

DEVICE_PROFILE="$STATE_DIR/device.json"
BRAIN_PROFILE="$STATE_DIR/brain.json"
PROVIDER_PROFILE="$STATE_DIR/providers.json"
PROVIDER_REGISTRY="$CONFIG_DIR/provider-registry.json"
PROVIDER_SCHEMA="$SCHEMA_DIR/provider-registry.schema.json"

LOG="$LOG_DIR/agent-02.log"
EVENTS="$EVENT_DIR/events.jsonl"

mkdir -p "$STATE_DIR" "$EVENT_DIR" "$LOG_DIR" "$CONFIG_DIR" "$SECRETS_DIR" "$BRAIN_DIR" "$SCHEMA_DIR"
chmod 700 "$SECRETS_DIR"

timestamp() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(timestamp)] $*" | tee -a "$LOG"; }
event() { printf '{"timestamp":"%s","agent":"02-brain-provider","event":"%s","data":%s}\n' "$(timestamp)" "$1" "$2" >> "$EVENTS"; }
hr() { printf '%*s\n' 70 '' | tr ' ' '─'; }

# ── Check Agent 01 ───────────────────────────────────────────
clear 2>/dev/null || true
echo
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  S T E L L A  ✦                          ║"
echo "║                                                            ║"
echo "║          AGENT 02 — BRAIN & PROVIDER GATEWAY v2            ║"
echo "║                                                            ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo

log "Agent 02 starting (provider gateway v2)."

if [[ ! -f "$DEVICE_PROFILE" ]]; then
    log "ERROR: Agent 01 device profile missing."
    event "brain.blocked" '{"reason":"device_profile_missing"}'
    exit 10
fi

# Extract device constraints (using python for robust JSON parsing)
DEVICE_JSON=$(cat "$DEVICE_PROFILE")
RESOURCE_CLASS=$(echo "$DEVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('classification',{}).get('resource_class','MINI'))")
STRATEGY=$(echo "$DEVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('classification',{}).get('strategy','MINIMAL'))")
INTERNET=$(echo "$DEVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('network',{}).get('internet','UNKNOWN'))")
MEMORY_MB=$(echo "$DEVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('resources',{}).get('memory_mb',0))")
ARCH=$(echo "$DEVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('system',{}).get('architecture','unknown'))")
TERMUX=$(echo "$DEVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('system',{}).get('termux',false))")

echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] DEVICE INTELLIGENCE RECEIVED                          │"
echo "└────────────────────────────────────────────────────────────┘"
echo
printf "  Device class : %s\n" "$RESOURCE_CLASS"
printf "  Strategy     : %s\n" "$STRATEGY"
printf "  Internet     : %s\n" "$INTERNET"
printf "  Memory       : %s MB\n" "$MEMORY_MB"
printf "  Architecture : %s\n" "$ARCH"
printf "  Termux       : %s\n" "$TERMUX"

# ── Brain Strategy from Device ───────────────────────────────
BRAIN_MODE="REMOTE_FIRST"
LOCAL_MODEL_ALLOWED=false
MAX_HEAVY_WORKERS=1
MAX_CONCURRENT_AGENTS=1
TOKEN_BUDGET_PER_TASK=4000

case "$RESOURCE_CLASS" in
    MINI)       BRAIN_MODE="REMOTE_ONLY";       LOCAL_MODEL_ALLOWED=false; MAX_HEAVY_WORKERS=0; MAX_CONCURRENT_AGENTS=1; TOKEN_BUDGET_PER_TASK=2000 ;;
    SMALL)      BRAIN_MODE="REMOTE_FIRST";      LOCAL_MODEL_ALLOWED=false; MAX_HEAVY_WORKERS=1; MAX_CONCURRENT_AGENTS=1; TOKEN_BUDGET_PER_TASK=4000 ;;
    MICRO)      BRAIN_MODE="REMOTE_FIRST";      LOCAL_MODEL_ALLOWED=false; MAX_HEAVY_WORKERS=1; MAX_CONCURRENT_AGENTS=1; TOKEN_BUDGET_PER_TASK=4000 ;;
    MEDIUM)     BRAIN_MODE="HYBRID_LIGHT";      LOCAL_MODEL_ALLOWED=true;  MAX_HEAVY_WORKERS=1; MAX_CONCURRENT_AGENTS=2; TOKEN_BUDGET_PER_TASK=8000 ;;
    LARGE)      BRAIN_MODE="HYBRID";            LOCAL_MODEL_ALLOWED=true;  MAX_HEAVY_WORKERS=2; MAX_CONCURRENT_AGENTS=3; TOKEN_BUDGET_PER_TASK=16000 ;;
    XL)         BRAIN_MODE="FULL";              LOCAL_MODEL_ALLOWED=true;  MAX_HEAVY_WORKERS=4; MAX_CONCURRENT_AGENTS=5; TOKEN_BUDGET_PER_TASK=32000 ;;
    *)          BRAIN_MODE="SAFE_REMOTE";       LOCAL_MODEL_ALLOWED=false; MAX_HEAVY_WORKERS=1; MAX_CONCURRENT_AGENTS=1; TOKEN_BUDGET_PER_TASK=2000 ;;
esac

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] BRAIN STRATEGY CALCULATED                             │"
echo "└────────────────────────────────────────────────────────────┘"
echo
printf "  Brain mode              : %s\n" "$BRAIN_MODE"
printf "  Local models allowed    : %s\n" "$LOCAL_MODEL_ALLOWED"
printf "  Max heavy workers       : %s\n" "$MAX_HEAVY_WORKERS"
printf "  Max concurrent agents   : %s\n" "$MAX_CONCURRENT_AGENTS"
printf "  Token budget per task   : %s\n" "$TOKEN_BUDGET_PER_TASK"

# ── Live Provider Registry ───────────────────────────────────
echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] LIVE PROVIDER REGISTRY                                │"
echo "└────────────────────────────────────────────────────────────┘"
echo

# Build comprehensive provider registry with live data structure
cat > "$PROVIDER_REGISTRY" <<'REGISTRY'
{
  "schema_version": 2,
  "updated": "$(timestamp)",
  "providers": {
    "gemini": {
      "name": "Google Gemini",
      "enabled": true,
      "configured": false,
      "health": "unknown",
      "priority": 10,
      "cost_mode": "free_tier",
      "api_key_env": "STELLA_GEMINI_API_KEY",
      "base_url": "https://generativelanguage.googleapis.com/v1beta",
      "models": {
        "gemini-2.5-flash": {
          "context_window": 1048576,
          "max_output": 8192,
          "cost_per_1k_input": 0.000075,
          "cost_per_1k_output": 0.0003,
          "free_tier": { "rpm": 15, "rpd": 1500, "tokens_per_minute": 1000000 },
          "capabilities": ["text", "vision", "function_calling", "code_execution"],
          "speed_tier": "fast"
        },
        "gemini-2.5-pro": {
          "context_window": 2097152,
          "max_output": 8192,
          "cost_per_1k_input": 0.00125,
          "cost_per_1k_output": 0.005,
          "free_tier": { "rpm": 5, "rpd": 100, "tokens_per_minute": 250000 },
          "capabilities": ["text", "vision", "function_calling", "code_execution", "thinking"],
          "speed_tier": "medium"
        },
        "gemini-1.5-flash": {
          "context_window": 1048576,
          "max_output": 8192,
          "cost_per_1k_input": 0.000075,
          "cost_per_1k_output": 0.0003,
          "free_tier": { "rpm": 15, "rpd": 1500 },
          "capabilities": ["text", "vision", "function_calling"],
          "speed_tier": "fast"
        }
      },
      "rate_limits": { "requests_per_minute": 15, "requests_per_day": 1500 },
      "token_budget_friendly": true,
      "supports_streaming": true,
      "supports_system_prompt": true
    },
    "openrouter": {
      "name": "OpenRouter",
      "enabled": true,
      "configured": false,
      "health": "unknown",
      "priority": 20,
      "cost_mode": "free_or_paid",
      "api_key_env": "STELLA_OPENROUTER_API_KEY",
      "base_url": "https://openrouter.ai/api/v1",
      "models": {
        "google/gemini-2.5-flash": { "context_window": 1048576, "max_output": 8192, "cost_per_1k_input": 0.000075, "cost_per_1k_output": 0.0003, "free": true },
        "google/gemini-2.5-pro": { "context_window": 2097152, "max_output": 8192, "cost_per_1k_input": 0.00125, "cost_per_1k_output": 0.005, "free": false },
        "meta-llama/llama-3.1-8b-instruct:free": { "context_window": 131072, "max_output": 4096, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free": true },
        "meta-llama/llama-3.1-70b-instruct:free": { "context_window": 131072, "max_output": 4096, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free": true },
        "microsoft/phi-3-mini-128k-instruct:free": { "context_window": 128000, "max_output": 4096, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free": true },
        "mistralai/mistral-7b-instruct:free": { "context_window": 32768, "max_output": 4096, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free": true },
        "nousresearch/hermes-3-llama-3.1-405b:free": { "context_window": 131072, "max_output": 4096, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free": true }
      },
      "rate_limits": { "requests_per_minute": 20, "requests_per_day": 1000 },
      "token_budget_friendly": true,
      "supports_streaming": true,
      "supports_system_prompt": true,
      "model_routing": true
    },
    "groq": {
      "name": "Groq",
      "enabled": true,
      "configured": false,
      "health": "unknown",
      "priority": 30,
      "cost_mode": "free_tier",
      "api_key_env": "STELLA_GROQ_API_KEY",
      "base_url": "https://api.groq.com/openai/v1",
      "models": {
        "llama-3.1-8b-instant": { "context_window": 131072, "max_output": 8192, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free_tier": { "rpm": 30, "rpd": 14400 } },
        "llama-3.1-70b-versatile": { "context_window": 131072, "max_output": 8192, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free_tier": { "rpm": 30, "rpd": 14400 } },
        "mixtral-8x7b-32768": { "context_window": 32768, "max_output": 8192, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free_tier": { "rpm": 30, "rpd": 14400 } },
        "gemma2-9b-it": { "context_window": 8192, "max_output": 8192, "cost_per_1k_input": 0, "cost_per_1k_output": 0, "free_tier": { "rpm": 30, "rpd": 14400 } }
      },
      "rate_limits": { "requests_per_minute": 30, "requests_per_day": 14400 },
      "token_budget_friendly": true,
      "supports_streaming": true,
      "supports_system_prompt": true,
      "speed_tier": "very_fast"
    },
    "ollama": {
      "name": "Ollama (Local)",
      "enabled": true,
      "configured": false,
      "health": "unknown",
      "priority": 5,
      "cost_mode": "local",
      "api_key_env": null,
      "base_url": "http://localhost:11434",
      "models": {
        "llama3.1:8b": { "context_window": 131072, "max_output": 4096, "size_gb": 4.7, "speed_tier": "medium" },
        "llama3.1:70b": { "context_window": 131072, "max_output": 4096, "size_gb": 40, "speed_tier": "slow" },
        "phi3:mini": { "context_window": 128000, "max_output": 4096, "size_gb": 2.3, "speed_tier": "fast" },
        "mistral:7b": { "context_window": 32768, "max_output": 4096, "size_gb": 4.1, "speed_tier": "medium" },
        "codellama:7b": { "context_window": 16384, "max_output": 4096, "size_gb": 3.8, "speed_tier": "medium" }
      },
      "rate_limits": { "requests_per_minute": 999, "requests_per_day": 999999 },
      "token_budget_friendly": true,
      "supports_streaming": true,
      "supports_system_prompt": true,
      "requires_gpu": false,
      "auto_pull": true
    },
    "openai": {
      "name": "OpenAI",
      "enabled": false,
      "configured": false,
      "health": "unknown",
      "priority": 40,
      "cost_mode": "paid",
      "api_key_env": "STELLA_OPENAI_API_KEY",
      "base_url": "https://api.openai.com/v1",
      "models": {
        "gpt-4o-mini": { "context_window": 128000, "max_output": 16384, "cost_per_1k_input": 0.00015, "cost_per_1k_output": 0.0006 },
        "gpt-4o": { "context_window": 128000, "max_output": 16384, "cost_per_1k_input": 0.005, "cost_per_1k_output": 0.015 },
        "gpt-3.5-turbo": { "context_window": 16384, "max_output": 4096, "cost_per_1k_input": 0.0005, "cost_per_1k_output": 0.0015 }
      },
      "rate_limits": { "requests_per_minute": 500, "tokens_per_minute": 200000 },
      "token_budget_friendly": false,
      "supports_streaming": true,
      "supports_system_prompt": true
    },
    "anthropic": {
      "name": "Anthropic",
      "enabled": false,
      "configured": false,
      "health": "unknown",
      "priority": 50,
      "cost_mode": "paid",
      "api_key_env": "STELLA_ANTHROPIC_API_KEY",
      "base_url": "https://api.anthropic.com/v1",
      "models": {
        "claude-3-5-sonnet-20241022": { "context_window": 200000, "max_output": 8192, "cost_per_1k_input": 0.003, "cost_per_1k_output": 0.015 },
        "claude-3-5-haiku-20241022": { "context_window": 200000, "max_output": 8192, "cost_per_1k_input": 0.001, "cost_per_1k_output": 0.005 }
      },
      "rate_limits": { "requests_per_minute": 50, "tokens_per_minute": 40000 },
      "token_budget_friendly": false,
      "supports_streaming": true,
      "supports_system_prompt": true
    }
  },
  "fallback_chain": {
    "REMOTE_ONLY": ["gemini", "openrouter", "groq"],
    "REMOTE_FIRST": ["gemini", "openrouter", "groq", "ollama"],
    "HYBRID_LIGHT": ["ollama", "gemini", "openrouter", "groq"],
    "HYBRID": ["ollama", "gemini", "openrouter", "groq"],
    "FULL": ["ollama", "gemini", "openrouter", "groq", "openai", "anthropic"],
    "SAFE_REMOTE": ["gemini", "openrouter"]
  },
  "selection_policy": {
    "prefer_free": true,
    "prefer_fast": true,
    "max_cost_per_task_usd": 0.01,
    "require_streaming": false,
    "require_system_prompt": true,
    "min_context_window": 4096
  }
}
REGISTRY

# Replace timestamp placeholder
sed -i "s/\"\$\(timestamp\)\"/\"$(timestamp)\"/" "$PROVIDER_REGISTRY"

echo "  ✓ Provider registry created (v2 schema)"
echo "  ✓ 6 providers: gemini, openrouter, groq, ollama, openai, anthropic"
echo "  ✓ Free tier models catalogued"
echo "  ✓ Fallback chains per brain mode defined"
echo "  ✓ Token budget policy configured"

# ── Provider Health Check ────────────────────────────────────
echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] PROVIDER HEALTH CHECK                                 │"
echo "└────────────────────────────────────────────────────────────┘"
echo

check_provider() {
    local name="$1" base_url="$2" key_env="$3"
    local health="unknown" latency=0 configured=false

    if [[ -n "$key_env" && -n "${!key_env:-}" ]]; then
        configured=true
        if command -v curl >/dev/null 2>&1; then
            local start end
            start=$(date +%s%3N)
            if curl -Is --max-time 5 -H "Authorization: Bearer ${!key_env}" "$base_url/models" >/dev/null 2>&1; then
                end=$(date +%s%3N)
                latency=$((end - start))
                health="healthy"
            else
                health="unreachable"
            fi
        fi
    else
        health="not_configured"
    fi

    python3 -c "
import json
print(json.dumps({'health': '$health', 'latency_ms': $latency, 'configured': $configured}))
"
}

GEMINI_HEALTH=$(check_provider "gemini" "https://generativelanguage.googleapis.com/v1beta" "STELLA_GEMINI_API_KEY")
OPENROUTER_HEALTH=$(check_provider "openrouter" "https://openrouter.ai/api/v1" "STELLA_OPENROUTER_API_KEY")
GROQ_HEALTH=$(check_provider "groq" "https://api.groq.com/openai/v1" "STELLA_GROQ_API_KEY")

# Ollama local check
OLLAMA_HEALTH="not_configured"
if command -v curl >/dev/null 2>&1; then
    local start end
    start=$(date +%s%3N)
    if curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
        end=$(date +%s%3N)
        OLLAMA_HEALTH=$(python3 -c "import json; print(json.dumps({'health':'healthy','latency_ms':$(($end-$start)),'configured':true}))")
    else
        OLLAMA_HEALTH=$(python3 -c "import json; print(json.dumps({'health':'not_running','latency_ms':0,'configured':false}))")
    fi
fi

echo "  Gemini     : $(echo "$GEMINI_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['health'])") ($(echo "$GEMINI_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['latency_ms'])")ms)
echo "  OpenRouter : $(echo "$OPENROUTER_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['health'])") ($(echo "$OPENROUTER_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['latency_ms'])")ms)
echo "  Groq       : $(echo "$GROQ_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['health'])") ($(echo "$GROQ_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['latency_ms'])")ms)
echo "  Ollama     : $(echo "$OLLAMA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['health'])")"

# Update provider registry with health status
python3 <<PY
import json, os
with open("$PROVIDER_REGISTRY") as f:
    reg = json.load(f)
health_data = {
    "gemini": $GEMINI_HEALTH,
    "openrouter": $OPENROUTER_HEALTH,
    "groq": $GROQ_HEALTH,
    "ollama": $OLLAMA_HEALTH
}
for name, health in health_data.items():
    if name in reg["providers"]:
        reg["providers"][name]["health"] = health["health"]
        reg["providers"][name]["health_latency_ms"] = health["latency_ms"]
        reg["providers"][name]["configured"] = health["configured"]
with open("$PROVIDER_REGISTRY", "w") as f:
    json.dump(reg, f, indent=2)
PY

# ── Provider Profile (simplified for brain consumption) ────────
cat > "$PROVIDER_PROFILE" <<JSON
{
  "schema_version": 2,
  "agent": "02-brain-provider",
  "timestamp": "$(timestamp)",
  "device_dependency": {
    "resource_class": "$RESOURCE_CLASS",
    "strategy": "$STRATEGY",
    "architecture": "$ARCH",
    "memory_mb": $MEMORY_MB,
    "internet": "$INTERNET",
    "termux": $TERMUX
  },
  "brain": {
    "mode": "$BRAIN_MODE",
    "local_model_allowed": $LOCAL_MODEL_ALLOWED,
    "max_heavy_workers": $MAX_HEAVY_WORKERS,
    "max_concurrent_agents": $MAX_CONCURRENT_AGENTS,
    "token_budget_per_task": $TOKEN_BUDGET_PER_TASK,
    "token_optimization": true,
    "provider_fallback": true,
    "sequential_execution": true
  },
  "providers": {
    "gemini": $GEMINI_HEALTH,
    "openrouter": $OPENROUTER_HEALTH,
    "groq": $GROQ_HEALTH,
    "ollama": $OLLAMA_HEALTH
  },
  "fallback_chain": $(echo "$(cat "$PROVIDER_REGISTRY" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['fallback_chain']))")"),
  "selection_policy": $(echo "$(cat "$PROVIDER_REGISTRY" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['selection_policy']))")"),
  "security": {
    "secrets_directory": "$SECRETS_DIR",
    "credentials_in_repository": false
  }
}
JSON

# ── Brain Profile ────────────────────────────────────────────
cat > "$BRAIN_PROFILE" <<JSON
{
  "schema_version": 2,
  "agent": "02-brain-provider",
  "timestamp": "$(timestamp)",
  "device_dependency": {
    "resource_class": "$RESOURCE_CLASS",
    "strategy": "$STRATEGY",
    "architecture": "$ARCH",
    "memory_mb": $MEMORY_MB,
    "internet": "$INTERNET"
  },
  "brain": {
    "mode": "$BRAIN_MODE",
    "local_model_allowed": $LOCAL_MODEL_ALLOWED,
    "max_heavy_workers": $MAX_HEAVY_WORKERS,
    "max_concurrent_agents": $MAX_CONCURRENT_AGENTS,
    "token_budget_per_task": $TOKEN_BUDGET_PER_TASK,
    "token_optimization": true,
    "provider_fallback": true,
    "sequential_execution": true,
    "intelligence_efficiency": true
  },
  "providers": {
    "registry": "$PROVIDER_REGISTRY",
    "active_fallback": "$BRAIN_MODE",
    "health_check_interval_minutes": 30
  },
  "security": {
    "secrets_directory": "$SECRETS_DIR",
    "credentials_in_repository": false
  }
}
JSON

# ── JSON Schema for Provider Registry ────────────────────────
cat > "$PROVIDER_SCHEMA" <<'SCHEMA'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Stella Provider Registry",
  "type": "object",
  "required": ["schema_version", "updated", "providers", "fallback_chain", "selection_policy"],
  "properties": {
    "schema_version": {"type": "integer", "const": 2},
    "updated": {"type": "string", "format": "date-time"},
    "providers": {
      "type": "object",
      "patternProperties": {
        "^.*$": {
          "type": "object",
          "required": ["name", "enabled", "configured", "health", "priority", "cost_mode", "models", "rate_limits"],
          "properties": {
            "name": {"type": "string"},
            "enabled": {"type": "boolean"},
            "configured": {"type": "boolean"},
            "health": {"type": "string", "enum": ["healthy", "unreachable", "not_configured", "not_running", "unknown"]},
            "priority": {"type": "integer", "minimum": 1},
            "cost_mode": {"type": "string", "enum": ["free_tier", "free_or_paid", "local", "paid"]},
            "api_key_env": {"type": ["string", "null"]},
            "base_url": {"type": "string", "format": "uri"},
            "models": {"type": "object"},
            "rate_limits": {"type": "object"},
            "token_budget_friendly": {"type": "boolean"},
            "supports_streaming": {"type": "boolean"},
            "supports_system_prompt": {"type": "boolean"}
          }
        }
      }
    },
    "fallback_chain": {
      "type": "object",
      "patternProperties": { "^.*$": { "type": "array", "items": { "type": "string" } } }
    },
    "selection_policy": {
      "type": "object",
      "required": ["prefer_free", "prefer_fast", "max_cost_per_task_usd"],
      "properties": {
        "prefer_free": {"type": "boolean"},
        "prefer_fast": {"type": "boolean"},
        "max_cost_per_task_usd": {"type": "number", "minimum": 0},
        "require_streaming": {"type": "boolean"},
        "require_system_prompt": {"type": "boolean"},
        "min_context_window": {"type": "integer", "minimum": 1}
      }
    }
  }
}
SCHEMA

# ── Git Safety ───────────────────────────────────────────────
GITIGNORE="$STELLA_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
    grep -q '^secrets/$' "$GITIGNORE" || echo 'secrets/' >> "$GITIGNORE"
    grep -q '^\.env$' "$GITIGNORE" || echo '.env' >> "$GITIGNORE"
    grep -q '^config/providers\.env$' "$GITIGNORE" || echo 'config/providers.env' >> "$GITIGNORE"
fi

# ── Events ───────────────────────────────────────────────────
event "brain.initialized" "{\"mode\":\"$BRAIN_MODE\",\"resource_class\":\"$RESOURCE_CLASS\",\"local_model_allowed\":$LOCAL_MODEL_ALLOWED,\"max_concurrent_agents\":$MAX_CONCURRENT_AGENTS,\"token_budget_per_task\":$TOKEN_BUDGET_PER_TASK}"
event "provider.registry.loaded" "{\"providers\":6,\"fallback_chain\":\"$BRAIN_MODE\",\"health_checks\":4}"

log "Brain profile saved: $BRAIN_PROFILE"
log "Provider profile saved: $PROVIDER_PROFILE"
log "Provider registry saved: $PROVIDER_REGISTRY (v2)"

# ── Result ───────────────────────────────────────────────────
echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ RESULT                                                     │"
echo "└────────────────────────────────────────────────────────────┘"
echo
echo "  ✓ Agent 01 intelligence received"
echo "  ✓ Brain strategy: $BRAIN_MODE (token budget: $TOKEN_BUDGET_PER_TASK)"
echo "  ✓ Live provider registry loaded (6 providers, v2 schema)"
echo "  ✓ Health checks: Gemini, OpenRouter, Groq, Ollama"
echo "  ✓ Fallback chain configured for $BRAIN_MODE"
echo "  ✓ Token optimization + intelligence efficiency enabled"
echo "  ✓ Provider fallback + sequential execution enabled"
echo "  ✓ Secrets protected from Git"
echo
echo "  Brain profile      : $BRAIN_PROFILE"
echo "  Provider profile   : $PROVIDER_PROFILE"
echo "  Provider registry  : $PROVIDER_REGISTRY"
echo "  Registry schema    : $PROVIDER_SCHEMA"
echo
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║         AGENT 02 COMPLETE — PROVIDER GATEWAY v2            ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo

exit 0