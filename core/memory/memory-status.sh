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
