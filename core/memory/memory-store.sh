#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
DB="$ROOT/core/memory/data/oracle-memory.db"

usage() {
    echo "Usage:"
    echo "  memory-store.sh add TYPE RETENTION CONTENT"
    echo
    echo "Examples:"
    echo "  memory-store.sh add preference permanent 'Prefer concise explanations'"
    echo "  memory-store.sh add lesson timed 'Learning lesson' 7d"
    exit 1
}

[ $# -ge 4 ] || usage

TYPE="$1"
RETENTION="$2"
CONTENT="$3"
EXTRA="${4:-}"

case "$RETENTION" in
    session|none|long_term|permanent)
        EXPIRES=""
        ;;
    timed)
        [ -n "$EXTRA" ] || {
            echo "Timed retention requires duration such as 7d, 3h or 30m."
            exit 1
        }

        case "$EXTRA" in
            *m) SECONDS=$(( ${EXTRA%m} * 60 )) ;;
            *h) SECONDS=$(( ${EXTRA%h} * 3600 )) ;;
            *d) SECONDS=$(( ${EXTRA%d} * 86400 )) ;;
            *w) SECONDS=$(( ${EXTRA%w} * 604800 )) ;;
            *) echo "Unsupported duration."; exit 1 ;;
        esac

        EXPIRES="$(date -d "+$SECONDS seconds" -Iseconds 2>/dev/null || date -Iseconds)"
        ;;
    *)
        echo "Unknown retention mode: $RETENTION"
        exit 1
        ;;
esac

ID="mem-$(date +%Y%m%d-%H%M%S)-$$"
NOW="$(date -Iseconds)"

CONTENT_ESCAPED="$(printf '%s' "$CONTENT" | sed "s/'/''/g")"

sqlite3 "$DB" <<SQL
INSERT INTO memories(
    id,type,content,source,confidence,
    created_at,updated_at,
    retention_mode,expires_at,
    sensitivity,status,user_confirmed
)
VALUES(
    '$ID',
    '$TYPE',
    '$CONTENT_ESCAPED',
    'user',
    1.0,
    '$NOW',
    '$NOW',
    '$RETENTION',
    '$EXPIRES',
    'normal',
    'active',
    1
);

INSERT INTO memory_events(
    memory_id,event_type,event_time,details
)
VALUES(
    '$ID',
    'memory.created',
    '$NOW',
    'Created through memory store'
);
SQL

echo "✓ Memory stored"
echo "  ID        : $ID"
echo "  Type      : $TYPE"
echo "  Retention : $RETENTION"
[ -n "$EXPIRES" ] && echo "  Expires   : $EXPIRES"
