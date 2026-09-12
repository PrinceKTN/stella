#!/data/data/com.termux/files/usr/bin/bash

set -u

STELLA_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

CONFIG="$STELLA_ROOT/config/providers.env"
AWARENESS_SCRIPT="$STELLA_ROOT/core/awareness/awareness.sh"
GOVERNOR_SCRIPT="$STELLA_ROOT/core/governor/governor.py"

AWARENESS_STATE="$STELLA_ROOT/state/awareness.json"
GOVERNOR_STATE="$STELLA_ROOT/state/governor.json"

LOG_DIR="$STELLA_ROOT/logs"
LOG="$LOG_DIR/stella-chat.log"

mkdir -p "$LOG_DIR"

MODEL="${STELLA_GEMINI_MODEL:-gemini-2.5-flash}"
API_BASE="https://generativelanguage.googleapis.com/v1beta/models"

HISTORY_FILE="$STELLA_ROOT/state/stella-live-history.json"

MAX_HISTORY_TURNS=12

if [ ! -f "$CONFIG" ]; then
    echo
    echo "✗ Stella provider configuration not found."
    echo "  $CONFIG"
    echo
    echo "Configure Gemini with:"
    echo "  ./bin/stella-provider set gemini"
    exit 1
fi

set -a
. "$CONFIG"
set +a

MODEL="${STELLA_GEMINI_MODEL:-gemini-2.5-flash}"

if [ -z "${STELLA_GEMINI_API_KEY:-}" ]; then
    echo
    echo "✗ STELLA_GEMINI_API_KEY is not configured."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "✗ curl is required."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "✗ python3 is required."
    exit 1
fi


# ============================================================
# LOGGING
# ============================================================

log_event() {
    printf '[%s] %s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
        "$1" >> "$LOG"
}


# ============================================================
# LIVE SYSTEM REFRESH
# ============================================================

refresh_system_state() {

    echo
    echo "Stella › Checking live device awareness..."

    "$AWARENESS_SCRIPT"
    AWARENESS_RC=$?

    if [ "$AWARENESS_RC" -ne 0 ]; then
        echo
        echo "Stella › Awareness refresh failed."
        log_event "Awareness refresh failed"
        return 1
    fi

    echo
    echo "Stella › Checking resource governor..."

    python3 "$GOVERNOR_SCRIPT"
    GOVERNOR_RC=$?

    if [ "$GOVERNOR_RC" -ne 0 ]; then
        echo
        echo "Stella › Governor refresh failed."
        log_event "Governor refresh failed"
        return 1
    fi

    echo
    echo "Stella › Live system state refreshed."
    log_event "Live awareness and governor refresh completed"

    return 0
}


# ============================================================
# SYSTEM STATUS
# ============================================================

show_status() {

    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                   STELLA LIVE STATUS                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"

    python3 - \
        "$AWARENESS_STATE" \
        "$GOVERNOR_STATE" \
        "$MODEL" <<'PY'
import json
import sys
from pathlib import Path

awareness_path = Path(sys.argv[1])
governor_path = Path(sys.argv[2])
model = sys.argv[3]

print()

print(f"  Brain    : Gemini")
print(f"  Model    : {model}")
print(f"  Provider : CONFIGURED")
print()

if awareness_path.exists():
    try:
        awareness = json.loads(awareness_path.read_text())

        assessment = awareness.get("assessment", {})
        load = awareness.get("load", {})
        memory = awareness.get("memory", {})
        storage = awareness.get("storage", {})

        print("  LIVE AWARENESS")

        print(
            "  Condition :",
            assessment.get("condition", "UNKNOWN")
        )

        print(
            "  Load      :",
            load.get("pressure", "UNKNOWN")
        )

        print(
            "  Memory    :",
            str(memory.get("available_percent", "UNKNOWN")) + "%"
        )

        print(
            "  Storage   :",
            str(storage.get("used_percent", "UNKNOWN")) + "%"
        )

    except Exception:
        print("  Awareness : INVALID STATE")

else:
    print("  Awareness : NOT YET GENERATED")

print()

if governor_path.exists():
    try:
        governor = json.loads(governor_path.read_text())

        freshness = (
            governor
            .get("input", {})
            .get("freshness", {})
        )

        decision = governor.get("decision", {})
        limits = governor.get("limits", {})

        print("  GOVERNOR")

        print(
            "  Freshness :",
            freshness.get("status", "UNKNOWN")
        )

        print(
            "  Action    :",
            decision.get("action", "UNKNOWN")
        )

        print(
            "  Workers   :",
            limits.get("max_workers", "UNKNOWN")
        )

        print(
            "  AI limit  :",
            limits.get("max_concurrent_ai", "UNKNOWN")
        )

    except Exception:
        print("  Governor  : INVALID STATE")

else:
    print("  Governor  : NOT YET GENERATED")

print()
print("  Execution : SAFETY-LOCKED")
print("  Autonomy  : NOT YET ENABLED")
print()
PY
}


# ============================================================
# CONVERSATION HISTORY
# ============================================================

initialize_history() {

    if [ ! -f "$HISTORY_FILE" ]; then
        printf '[]\n' > "$HISTORY_FILE"
    fi
}


clear_history() {

    printf '[]\n' > "$HISTORY_FILE"

    echo
    echo "Stella › Conversation memory cleared."

    log_event "Conversation history cleared"
}


# ============================================================
# GEMINI REQUEST
# ============================================================

ask_stella() {

    local USER_TEXT="$1"

    initialize_history

    local SYSTEM_CONTEXT

    SYSTEM_CONTEXT=$(python3 - \
        "$AWARENESS_STATE" \
        "$GOVERNOR_STATE" <<'PY'
import json
import sys
from pathlib import Path

awareness_path = Path(sys.argv[1])
governor_path = Path(sys.argv[2])

context = {
    "stella_runtime": "LIVE_CONVERSATION",
    "execution": "SAFETY_LOCKED"
}

if awareness_path.exists():
    try:
        awareness = json.loads(awareness_path.read_text())

        context["device_condition"] = (
            awareness
            .get("assessment", {})
            .get("condition", "UNKNOWN")
        )

    except Exception:
        context["device_condition"] = "UNKNOWN"

if governor_path.exists():
    try:
        governor = json.loads(governor_path.read_text())

        context["governor_action"] = (
            governor
            .get("decision", {})
            .get("action", "UNKNOWN")
        )

        context["awareness_freshness"] = (
            governor
            .get("input", {})
            .get("freshness", {})
            .get("status", "UNKNOWN")
        )

    except Exception:
        context["governor_action"] = "UNKNOWN"

print(json.dumps(context))
PY
)

    local SYSTEM_PROMPT

    SYSTEM_PROMPT="You are Stella, an AI assistant running inside the Stella development system.

Your current runtime mode is LIVE_CONVERSATION.

You are conversational, helpful, precise, and honest.

Current Stella system context:
$SYSTEM_CONTEXT

IMPORTANT SAFETY RULES:

- You can reason, explain, plan, analyze, and discuss the Stella system.
- You do NOT currently have permission to execute arbitrary system actions.
- Never claim that you changed files, ran commands, modified GitHub, installed software, or controlled the device unless Stella's execution layer explicitly reports success.
- Execution is currently SAFETY-LOCKED.
- Autonomous operation is NOT enabled.
- You may propose plans for future execution.
- Be honest about what you can and cannot currently do.
- Treat the user as the owner and founder of Stella."

    local PAYLOAD

    PAYLOAD=$(python3 - \
        "$HISTORY_FILE" \
        "$USER_TEXT" \
        "$SYSTEM_PROMPT" \
        "$MAX_HISTORY_TURNS" <<'PY'
import json
import sys
from pathlib import Path

history_path = Path(sys.argv[1])
user_text = sys.argv[2]
system_prompt = sys.argv[3]
max_turns = int(sys.argv[4])

try:
    history = json.loads(history_path.read_text())
except Exception:
    history = []

if not isinstance(history, list):
    history = []

history = history[-max_turns:]

contents = []

for item in history:
    if not isinstance(item, dict):
        continue

    role = item.get("role")
    text = item.get("text")

    if role not in ("user", "model"):
        continue

    if not isinstance(text, str) or not text.strip():
        continue

    contents.append({
        "role": role,
        "parts": [
            {
                "text": text
            }
        ]
    })

contents.append({
    "role": "user",
    "parts": [
        {
            "text": user_text
        }
    ]
})

payload = {
    "system_instruction": {
        "parts": [
            {
                "text": system_prompt
            }
        ]
    },
    "contents": contents,
    "generationConfig": {
        "temperature": 0.7,
        "maxOutputTokens": 1024
    }
}

print(json.dumps(payload))
PY
)

    local RESPONSE_FILE

    RESPONSE_FILE="$(mktemp "$STELLA_ROOT/state/.stella-response.XXXXXX")"

    local HTTP_CODE

    HTTP_CODE=$(
        curl -sS \
            --connect-timeout 20 \
            --max-time 90 \
            -o "$RESPONSE_FILE" \
            -w "%{http_code}" \
            -X POST \
            "$API_BASE/${MODEL}:generateContent" \
            -H "Content-Type: application/json" \
            -H "x-goog-api-key: ${STELLA_GEMINI_API_KEY}" \
            -d "$PAYLOAD"
    )

    local CURL_RC=$?

    if [ "$CURL_RC" -ne 0 ]; then
        echo "✗ Network request failed."
        rm -f "$RESPONSE_FILE"
        log_event "Gemini network request failed"
        return 1
    fi

    local RESULT

    RESULT=$(python3 - \
        "$RESPONSE_FILE" \
        "$HISTORY_FILE" \
        "$USER_TEXT" \
        "$MAX_HISTORY_TURNS" <<'PY'
import json
import sys
from pathlib import Path

response_path = Path(sys.argv[1])
history_path = Path(sys.argv[2])
user_text = sys.argv[3]
max_turns = int(sys.argv[4])

try:
    data = json.loads(response_path.read_text())

    if "error" in data:
        error = data["error"]

        print(
            "ERROR:API "
            + str(error.get("code", "UNKNOWN"))
            + ": "
            + str(error.get("message", "Unknown API error"))
        )

        raise SystemExit(2)

    candidates = data.get("candidates", [])

    if not candidates:
        print("ERROR:No response candidate returned")
        raise SystemExit(3)

    candidate = candidates[0]

    parts = (
        candidate
        .get("content", {})
        .get("parts", [])
    )

    text = "".join(
        part.get("text", "")
        for part in parts
        if isinstance(part, dict)
    ).strip()

    if not text:
        finish = candidate.get("finishReason", "UNKNOWN")

        print(
            "ERROR:Model returned no text "
            f"(finish reason: {finish})"
        )

        raise SystemExit(4)

    try:
        history = json.loads(history_path.read_text())
    except Exception:
        history = []

    if not isinstance(history, list):
        history = []

    history.append({
        "role": "user",
        "text": user_text
    })

    history.append({
        "role": "model",
        "text": text
    })

    history = history[-max_turns:]

    tmp = history_path.with_suffix(".tmp")

    tmp.write_text(
        json.dumps(history, indent=2) + "\n"
    )

    json.loads(tmp.read_text())

    tmp.replace(history_path)

    print(text)

except Exception as e:

    if not str(e).startswith("ERROR:"):
        print("ERROR:" + str(e))

    raise SystemExit(1)
PY
)

    local PARSE_RC=$?

    rm -f "$RESPONSE_FILE"

    if [ "$PARSE_RC" -ne 0 ]; then

        echo "✗ $RESULT"

        log_event "Gemini response failed: HTTP $HTTP_CODE"

        return 1
    fi

    printf '%s\n' "$RESULT"

    log_event "Conversation exchange completed"

    return 0
}


# ============================================================
# HELP
# ============================================================

show_help() {

    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    STELLA HELP BOOK                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo
    echo "  /help"
    echo "      Show this help book."
    echo
    echo "  /status"
    echo "      Show the latest known Stella awareness and governor state."
    echo
    echo "  /refresh"
    echo "      Run live Awareness and Governor checks."
    echo
    echo "  /clear"
    echo "      Clear this terminal conversation history."
    echo
    echo "  /exit"
    echo "      Leave Stella."
    echo
    echo "  Any normal message"
    echo "      Talk with Stella through the live Gemini brain."
    echo
    echo "  SAFETY"
    echo "      Conversation is live."
    echo "      System execution remains locked."
    echo "      Autonomous control is not enabled."
    echo
}


# ============================================================
# STARTUP
# ============================================================

initialize_history

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  S T E L L A  ✦                         ║"
echo "║                                                            ║"
echo "║                    LIVE RUNTIME                            ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"

echo
echo "  Brain     : Gemini"
echo "  Model     : $MODEL"
echo "  Interface : Terminal"
echo "  Execution : SAFETY-LOCKED"
echo

echo "  Stella Live Runtime is starting..."
echo

refresh_system_state

echo
echo "  Commands:"
echo "    /help"
echo "    /status"
echo "    /refresh"
echo "    /clear"
echo "    /exit"
echo

log_event "Stella Live Runtime started"


# ============================================================
# MAIN LOOP
# ============================================================

while true; do

    printf '\nYou › '

    IFS= read -r INPUT || break

    case "$INPUT" in

        "")
            continue
            ;;

        /exit|/quit)
            echo
            echo "Stella › Going offline. Talk to you later."
            echo

            log_event "Stella Live Runtime stopped"

            break
            ;;

        /help)
            show_help
            ;;

        /status)
            show_status
            ;;

        /refresh)
            refresh_system_state
            ;;

        /clear)
            clear_history
            ;;

        /*)
            echo
            echo "Stella › Unknown command."
            echo "Type /help to see available commands."
            ;;

        *)
            echo
            printf 'Stella › '

            ask_stella "$INPUT"
            ;;
    esac

done

unset STELLA_GEMINI_API_KEY
