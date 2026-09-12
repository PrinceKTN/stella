#!/data/data/com.termux/files/usr/bin/bash
set -u

echo
echo "STELLA TOOL BRIDGE"
echo "=================="
echo
echo "Tool execution request received."

if [ -z "${1:-}" ]; then
    echo "✗ No tool specified."
    exit 1
fi

TOOL="$1"

echo "Tool: $TOOL"
echo
echo "✗ DIRECT EXECUTION BLOCKED"
echo
echo "Reason:"
echo "  Agent 09 is currently in controlled dry-run mode."
echo "  Unknown or unregistered tools cannot execute."
echo
echo "The request must pass:"
echo "  registry → permission → risk → approval → execution"
exit 10
