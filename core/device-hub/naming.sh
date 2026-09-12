#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

DEVICE_TYPE="${1:-unknown}"
INDEX="${2:-01}"

case "$DEVICE_TYPE" in
    android)
        PREFIX="ORACLE-PHONE"
        ;;
    windows)
        PREFIX="ORACLE-WINDOWS"
        ;;
    linux)
        PREFIX="ORACLE-LINUX"
        ;;
    macos)
        PREFIX="ORACLE-MAC"
        ;;
    server)
        PREFIX="ORACLE-SERVER"
        ;;
    *)
        PREFIX="ORACLE-DEVICE"
        ;;
esac

printf '%s-%02d\n' "$PREFIX" "$INDEX"
