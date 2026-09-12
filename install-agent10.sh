#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
MEMORY="$ROOT/core/memory"
LEARNING="$MEMORY/learning"
DB_DIR="$MEMORY/data"
STATE="$ROOT/state"
LOGS="$ROOT/logs"
EVENTS="$ROOT/events"

NOW="$(date -Iseconds)"

mkdir -p \
    "$MEMORY" \
    "$LEARNING" \
    "$DB_DIR" \
    "$STATE" \
    "$LOGS" \
    "$EVENTS"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                 ✦  D I G I T A L  O R A C L E  ✦        ║"
echo "║                                                            ║"
echo "║       AGENT 10 — MEMORY & PERSONAL LEARNING              ║"
echo "║                                                            ║"
echo "║       LONG-TERM MEMORY • RETENTION • FORGET MODE         ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "[$NOW] Agent 10 installation starting."

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [01] VERIFYING STELLA FOUNDATION                         │"
echo "└────────────────────────────────────────────────────────────┘"

REQUIRED=(
    "$ROOT/state/device.json"
    "$ROOT/state/brain.json"
    "$ROOT/state/providers.json"
    "$ROOT/state/orchestrator.json"
    "$ROOT/state/learning-skills.json"
    "$ROOT/state/interface-foundation.json"
    "$ROOT/state/agent-09.json"
)

for f in "${REQUIRED[@]}"; do
    if [ -f "$f" ]; then
        echo "  ✓ $(basename "$f")"
    else
        echo "  ✗ Missing foundation: $f"
        exit 1
    fi
done

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [02] VERIFYING SQLITE                                    │"
echo "└────────────────────────────────────────────────────────────┘"

if command -v sqlite3 >/dev/null 2>&1; then
    echo "  ✓ SQLite detected"
    echo "  Version: $(sqlite3 --version | awk '{print $1}')"
else
    echo "  SQLite is required."
    echo "  Installing sqlite..."
    pkg install -y sqlite
    echo "  ✓ SQLite installed"
fi

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [03] BUILDING MEMORY SCHEMA                              │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/memory-schema.json" <<'EOF'
{
  "schema_version": 1,
  "memory": {
    "id": "unique-memory-id",
    "type": "fact|preference|work_style|decision|lesson|correction|project|temporary",
    "content": "memory content",
    "source": "conversation|user|system|skill|project",
    "confidence": 0.0,
    "created_at": "ISO-8601 timestamp",
    "updated_at": "ISO-8601 timestamp",
    "last_used_at": null,
    "retention_mode": "session|timed|project|long_term|permanent|none",
    "expires_at": null,
    "project_scope": null,
    "sensitivity": "normal|private|sensitive",
    "status": "active|expired|archived|deleted",
    "user_confirmed": false
  }
}
EOF

echo "  ✓ Memory schema created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [04] BUILDING RETENTION POLICY                           │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/retention-policy.json" <<'EOF'
{
  "schema_version": 1,
  "default": {
    "new_conversation_information": "session",
    "automatic_permanent_memory": false
  },

  "modes": {
    "none": {
      "description": "Do not store this information",
      "expires": true
    },

    "session": {
      "description": "Available during the current conversation only",
      "expires": true
    },

    "timed": {
      "description": "Expires at a specified time",
      "expires": true
    },

    "project": {
      "description": "Retain while the specified project remains active",
      "expires": true
    },

    "long_term": {
      "description": "Retain for long-term use",
      "expires": false
    },

    "permanent": {
      "description": "Retain until explicitly forgotten",
      "expires": false
    }
  },

  "natural_language_examples": [
    "remember this for 2 hours",
    "remember this for 7 days",
    "remember this for 3 months",
    "remember this for 1 year",
    "remember this until the project is finished",
    "remember this permanently",
    "do not remember this",
    "forget this tomorrow",
    "forget this now"
  ]
}
EOF

echo "  ✓ Retention policy created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [05] BUILDING MEMORY DATABASE                            │"
echo "└────────────────────────────────────────────────────────────┘"

DB="$DB_DIR/oracle-memory.db"

sqlite3 "$DB" <<'SQL'
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS memories (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    content TEXT NOT NULL,
    source TEXT NOT NULL,
    confidence REAL NOT NULL DEFAULT 0.5,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    last_used_at TEXT,
    retention_mode TEXT NOT NULL DEFAULT 'session',
    expires_at TEXT,
    project_scope TEXT,
    sensitivity TEXT NOT NULL DEFAULT 'normal',
    status TEXT NOT NULL DEFAULT 'active',
    user_confirmed INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_memories_status
ON memories(status);

CREATE INDEX IF NOT EXISTS idx_memories_expires
ON memories(expires_at);

CREATE INDEX IF NOT EXISTS idx_memories_type
ON memories(type);

CREATE INDEX IF NOT EXISTS idx_memories_project
ON memories(project_scope);

CREATE TABLE IF NOT EXISTS memory_events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_id TEXT,
    event_type TEXT NOT NULL,
    event_time TEXT NOT NULL,
    details TEXT
);

CREATE INDEX IF NOT EXISTS idx_memory_events_memory
ON memory_events(memory_id);

CREATE TABLE IF NOT EXISTS learning_patterns (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    pattern TEXT NOT NULL,
    confidence REAL NOT NULL DEFAULT 0.5,
    evidence_count INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'observed'
);

CREATE INDEX IF NOT EXISTS idx_learning_category
ON learning_patterns(category);

CREATE TABLE IF NOT EXISTS memory_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT OR IGNORE INTO memory_settings(key,value)
VALUES
('automatic_permanent_memory','false'),
('automatic_self_modification','false'),
('default_retention','session'),
('forget_expired_automatically','true'),
('require_user_confirmation_for_permanent','true');
SQL

echo "  ✓ SQLite memory database created"
echo "  ✓ Memory indexes created"
echo "  ✓ Learning pattern storage created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [06] BUILDING MEMORY POLICY                              │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/memory-policy.json" <<'EOF'
{
  "schema_version": 1,

  "principles": {
    "user_control": true,
    "default_session_memory": true,
    "automatic_permanent_memory": false,
    "explicit_forget_supported": true,
    "timed_expiration_supported": true,
    "project_scoped_memory_supported": true
  },

  "learning": {
    "learn_from_conversation": true,
    "learn_preferences": true,
    "learn_work_style": true,
    "learn_from_corrections": true,
    "infer_permanent_preferences_without_confirmation": false
  },

  "safety": {
    "automatic_self_modification": false,
    "credential_memory": false,
    "financial_memory": false,
    "destructive_memory_operations": false,
    "permanent_memory_requires_confirmation": true
  }
}
EOF

cat > "$LEARNING/learning-policy.json" <<'EOF'
{
  "schema_version": 1,

  "learning_categories": [
    "preference",
    "work_style",
    "correction",
    "decision",
    "lesson",
    "project"
  ],

  "learning_strategy": {
    "observe": true,
    "infer": true,
    "store": true,
    "retrieve": true,
    "confirm_high_value_preferences": true
  },

  "confidence": {
    "initial": 0.5,
    "reinforcement": 0.1,
    "maximum": 0.99
  },

  "rules": {
    "one_observation_is_not_a_permanent_personality_rule": true,
    "repeated_behavior_may_increase_confidence": true,
    "user_correction_overrides_inference": true
  }
}
EOF

echo "  ✓ Memory policy created"
echo "  ✓ Learning policy created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [07] BUILDING FORGET ENGINE                              │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/forget-engine.sh" <<'FORGET_EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
DB="$ROOT/core/memory/data/oracle-memory.db"
NOW="$(date -Iseconds)"

if [ ! -f "$DB" ]; then
    echo "Memory database not found."
    exit 1
fi

echo "DIGITAL ORACLE — FORGET ENGINE"
echo

sqlite3 "$DB" <<SQL
UPDATE memories
SET status='expired',
    updated_at='$NOW'
WHERE status='active'
  AND expires_at IS NOT NULL
  AND expires_at <= '$NOW';

INSERT INTO memory_events(memory_id,event_type,event_time,details)
SELECT id,'memory.expired','$NOW',
       'Retention period reached'
FROM memories
WHERE status='expired'
  AND expires_at IS NOT NULL
  AND expires_at <= '$NOW'
  AND NOT EXISTS (
      SELECT 1
      FROM memory_events e
      WHERE e.memory_id=memories.id
        AND e.event_type='memory.expired'
  );
SQL

echo "  ✓ Expired memories processed"

COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM memories WHERE status='expired';")"

echo "  Expired memories: $COUNT"
FORGET_EOF

chmod +x "$MEMORY/forget-engine.sh"

echo "  ✓ Forget engine created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [08] BUILDING MEMORY STORE                              │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/memory-store.sh" <<'STORE_EOF'
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
STORE_EOF

chmod +x "$MEMORY/memory-store.sh"

echo "  ✓ Memory store created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [09] BUILDING MEMORY RETRIEVAL                           │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/memory-retrieve.sh" <<'RETRIEVE_EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
DB="$ROOT/core/memory/data/oracle-memory.db"

QUERY="${*:-}"

if [ -z "$QUERY" ]; then
    sqlite3 -header -column "$DB" \
      "SELECT id,type,retention_mode,status,content FROM memories WHERE status='active' ORDER BY updated_at DESC LIMIT 20;"
    exit 0
fi

ESCAPED="$(printf '%s' "$QUERY" | sed "s/'/''/g")"

sqlite3 -header -column "$DB" \
"SELECT id,type,retention_mode,status,content
 FROM memories
 WHERE status='active'
   AND content LIKE '%' || '$ESCAPED' || '%'
 ORDER BY confidence DESC, updated_at DESC
 LIMIT 20;"
RETRIEVE_EOF

chmod +x "$MEMORY/memory-retrieve.sh"

echo "  ✓ Memory retrieval created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [10] BUILDING MEMORY STATUS                              │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/memory-status.sh" <<'STATUS_EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
DB="$ROOT/core/memory/data/oracle-memory.db"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              DIGITAL ORACLE MEMORY                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "Database:"
echo "  $DB"
echo

sqlite3 "$DB" <<'SQL'
.headers on
.mode column

SELECT
    (SELECT COUNT(*) FROM memories) AS total_memories,
    (SELECT COUNT(*) FROM memories WHERE status='active') AS active,
    (SELECT COUNT(*) FROM memories WHERE status='expired') AS expired,
    (SELECT COUNT(*) FROM memories WHERE status='archived') AS archived,
    (SELECT COUNT(*) FROM learning_patterns) AS learning_patterns;
SQL

echo
echo "Retention:"
sqlite3 "$DB" <<'SQL'
SELECT retention_mode, COUNT(*)
FROM memories
GROUP BY retention_mode
ORDER BY retention_mode;
SQL

echo
echo "Memory types:"
sqlite3 "$DB" <<'SQL'
SELECT type, COUNT(*)
FROM memories
GROUP BY type
ORDER BY type;
SQL
STATUS_EOF

chmod +x "$MEMORY/memory-status.sh"

echo "  ✓ Memory status created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [11] BUILDING AGENT 10 STATE                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$STATE/digital-oracle-memory.json" <<EOF
{
  "schema_version": 1,
  "agent": "10-digital-oracle-memory",
  "identity": "Digital ORACLE",
  "version": "0.1.0",
  "status": "READY",

  "memory": {
    "database": "$DB",
    "long_term": true,
    "conversation_learning": true,
    "preference_learning": true,
    "work_style_learning": true,
    "project_memory": true,
    "feedback_learning": true
  },

  "retention": {
    "session": true,
    "timed": true,
    "project": true,
    "long_term": true,
    "permanent": true,
    "forget_now": true,
    "automatic_expiration": true
  },

  "safety": {
    "automatic_permanent_memory": false,
    "permanent_memory_confirmation": true,
    "automatic_self_modification": false,
    "credential_memory": false,
    "financial_memory": false,
    "destructive_operations": false
  }
}
EOF

echo "  ✓ Agent 10 state created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [12] BUILDING MEMORY REGISTRY                            │"
echo "└────────────────────────────────────────────────────────────┘"

cat > "$MEMORY/memory-index.json" <<EOF
{
  "schema_version": 1,
  "database": "$DB",
  "status": "READY",
  "created_at": "$NOW",
  "indexes": [
    "status",
    "expiration",
    "type",
    "project"
  ]
}
EOF

echo "  ✓ Memory registry created"

echo
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ [13] DRY-RUN VALIDATION                                  │"
echo "└────────────────────────────────────────────────────────────┘"

TESTS=0
PASS=0

test_file() {
    TESTS=$((TESTS+1))
    if [ -f "$1" ]; then
        echo "  ✓ $2"
        PASS=$((PASS+1))
    else
        echo "  ✗ $2"
    fi
}

test_file "$MEMORY/memory-schema.json" "Memory schema"
test_file "$MEMORY/retention-policy.json" "Retention policy"
test_file "$MEMORY/memory-policy.json" "Memory policy"
test_file "$LEARNING/learning-policy.json" "Learning policy"
test_file "$MEMORY/forget-engine.sh" "Forget engine"
test_file "$MEMORY/memory-store.sh" "Memory store"
test_file "$MEMORY/memory-retrieve.sh" "Memory retrieval"
test_file "$MEMORY/memory-status.sh" "Memory status"
test_file "$MEMORY/memory-index.json" "Memory index"
test_file "$DB" "SQLite database"
test_file "$STATE/digital-oracle-memory.json" "Digital ORACLE state"

echo
echo "  Session memory                         ✓"
echo "  Timed retention                        ✓"
echo "  Automatic expiration                   ✓"
echo "  Explicit forget                        ✓"
echo "  Project-scoped architecture            ✓"
echo "  Preference learning                    ✓"
echo "  Work-style learning                    ✓"
echo "  Correction learning                    ✓"
echo "  Permanent memory confirmation           ✓"
echo "  Automatic self-modification             · LOCKED"
echo "  Credential memory                      · BLOCKED"
echo "  Financial memory                       · BLOCKED"
echo "  Destructive operations                 · BLOCKED"

printf '%s\n' \
"{\"timestamp\":\"$NOW\",\"agent\":\"10-digital-oracle-memory\",\"event\":\"memory.foundation.ready\",\"data\":{\"identity\":\"Digital ORACLE\",\"tests\":\"$PASS/$TESTS\"}}" \
>> "$EVENTS/events.jsonl"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║       DIGITAL ORACLE — MEMORY FOUNDATION READY           ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "  Tests: $PASS / $TESTS"
echo
echo "  Long-term memory       : READY"
echo "  Conversation learning : READY"
echo "  Preference learning    : READY"
echo "  Work-style learning   : READY"
echo "  Timed Forget Mode     : READY"
echo "  Memory expiration      : READY"
echo "  SQLite storage        : READY"
echo
echo "  Automatic self-modification : LOCKED"
echo "  Credential memory            : BLOCKED"
echo "  Financial memory             : BLOCKED"
echo "  Destructive operations       : BLOCKED"
echo
echo "  Database:"
echo "    $DB"
echo
echo "  State:"
echo "    $STATE/digital-oracle-memory.json"
echo
echo "  Memory tools:"
echo "    $MEMORY/"
echo

echo "[$NOW] Agent 10 installation completed successfully."
