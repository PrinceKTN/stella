#!/data/data/com.termux/files/usr/bin/bash

set -u

echo "================================================"
echo " STELLA GEMINI LIVE API TEST"
echo "================================================"

CONFIG="$HOME/stella/config/providers.env"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: providers.env not found"
    exit 1
fi

set -a
. "$CONFIG"
set +a

if [ -z "${STELLA_GEMINI_API_KEY:-}" ]; then
    echo "ERROR: Gemini API key is not loaded"
    exit 1
fi

MODEL="${STELLA_GEMINI_MODEL:-gemini-2.5-flash}"
RESPONSE_FILE="$HOME/stella/state/gemini-test-response.json"

echo
echo "API KEY: LOADED"
echo "KEY LENGTH: ${#STELLA_GEMINI_API_KEY}"
echo "MODEL: $MODEL"
echo
echo "Sending safe test request..."
echo

HTTP_CODE=$(
    curl -sS \
        --connect-timeout 20 \
        --max-time 60 \
        -o "$RESPONSE_FILE" \
        -w "%{http_code}" \
        -X POST \
        "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: ${STELLA_GEMINI_API_KEY}" \
        -d '{
          "contents": [
            {
              "role": "user",
              "parts": [
                {
                  "text": "Reply with exactly: STELLA ONLINE"
                }
              ]
            }
          ],
          "generationConfig": {
            "temperature": 0,
            "maxOutputTokens": 128
          }
        }'
)

CURL_RC=$?

echo "CURL EXIT CODE: $CURL_RC"
echo "HTTP STATUS: $HTTP_CODE"

echo
echo "===== GEMINI RESPONSE DIAGNOSTIC ====="

python3 - "$RESPONSE_FILE" <<'PY'
import json
import sys

path = sys.argv[1]

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "error" in data:
        error = data["error"]

        print("RESULT: API ERROR")
        print("CODE:", error.get("code"))
        print("STATUS:", error.get("status"))
        print("MESSAGE:", error.get("message"))
        raise SystemExit(1)

    candidates = data.get("candidates", [])

    print("CANDIDATES:", len(candidates))

    if not candidates:
        print("RESULT: NO CANDIDATES")

        feedback = data.get("promptFeedback")
        if feedback:
            print("PROMPT FEEDBACK:")
            print(json.dumps(feedback, indent=2))

        raise SystemExit(1)

    candidate = candidates[0]

    print("FINISH REASON:", candidate.get("finishReason", "UNKNOWN"))

    content = candidate.get("content", {})
    parts = content.get("parts", [])

    print("PART COUNT:", len(parts))

    text_parts = []

    for index, part in enumerate(parts):
        print(f"PART {index} KEYS:", ", ".join(part.keys()))

        text = part.get("text")

        if text:
            text_parts.append(text)

    text = "".join(text_parts).strip()

    if text:
        print()
        print("RESULT: SUCCESS")
        print("STELLA RESPONSE:", text)
        raise SystemExit(0)

    print()
    print("RESULT: NO TEXT PART")

    print()
    print("SAFE RESPONSE STRUCTURE:")

    safe = {
        "candidate_count": len(candidates),
        "finish_reason": candidate.get("finishReason"),
        "part_count": len(parts),
        "part_keys": [list(part.keys()) for part in parts],
        "prompt_feedback": data.get("promptFeedback"),
        "model_version": data.get("modelVersion"),
        "response_id": data.get("responseId")
    }

    print(json.dumps(safe, indent=2))

    raise SystemExit(1)

except json.JSONDecodeError:
    print("RESULT: INVALID JSON RESPONSE")
    print("RAW RESPONSE:")
    print(open(path, "r", encoding="utf-8").read())
    raise SystemExit(1)

finally:
    pass
PY

RC=$?

rm -f "$RESPONSE_FILE"

unset STELLA_GEMINI_API_KEY

echo
echo "================================================"
echo " TEST COMPLETE"
echo " EXIT CODE: $RC"
echo "================================================"

exit "$RC"
