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
