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
