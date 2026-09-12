#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

ROOT="$HOME/stella"
REGISTRY="$ROOT/core/device-hub/registry/devices.json"

case "${1:-help}" in

    list)
        echo
        echo "DIGITAL ORACLE — CONNECTED DEVICES"
        echo
        echo "Registry: $REGISTRY"
        echo

        if command -v jq >/dev/null 2>&1; then
            jq -r '
              if (.devices | length) == 0 then
                "  No devices enrolled."
              else
                .devices[] |
                "  \(.name) [\(.device_id)] — \(.status // "unknown")"
              end
            ' "$REGISTRY"
        else
            cat "$REGISTRY"
        fi
        ;;

    status)
        echo "Digital ORACLE Device Hub"
        echo "Registry: $REGISTRY"
        echo "State: $ROOT/state/device-hub.json"
        ;;

    help|*)
        echo
        echo "Digital ORACLE Device Hub"
        echo
        echo "Commands:"
        echo "  list      List registered devices"
        echo "  status    Show hub status"
        echo
        echo "Natural-language commands will later support:"
        echo "  rename Dad's laptop to Workshop"
        echo "  show my connected devices"
        echo "  send this task to Workshop"
        echo "  use my laptop"
        echo
        ;;
esac
