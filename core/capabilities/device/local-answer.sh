#!/data/data/com.termux/files/usr/bin/bash

STELLA_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
AWARENESS="$STELLA_ROOT/state/awareness.json"

question="$*"

[ -f "$AWARENESS" ] || exit 1

python3 - "$AWARENESS" "$question" <<'PY'
import json
import sys

path = sys.argv[1]
question = " ".join(sys.argv[2:]).lower()

with open(path, "r") as f:
    d = json.load(f)

storage = d.get("storage", {})
memory = d.get("memory", {})
battery = d.get("battery", {})
network = d.get("network", {})
device = d.get("device", {})
load = d.get("load", {})
swap = d.get("swap", {})
assessment = d.get("assessment", {})

def mb_to_gb(mb):
    return mb / 1024

# STORAGE
if any(x in question for x in [
    "storage", "disk space", "disk", "space left",
    "free space", "storage space"
]):
    total = mb_to_gb(storage.get("total_mb", 0))
    available = mb_to_gb(storage.get("available_mb", 0))
    used = storage.get("used_percent", 0)

    print(
        f"Your device has about {available:.1f} GB available "
        f"out of {total:.1f} GB, with {used}% used."
    )
    raise SystemExit(0)

# RAM / MEMORY
if any(x in question for x in [
    "ram", "memory", "available memory", "free memory"
]):
    total = memory.get("total_mb", 0)
    available = memory.get("available_mb", 0)
    percent = memory.get("available_percent", 0)

    print(
        f"You have about {available} MB of RAM available "
        f"out of {total} MB ({percent}% available)."
    )
    raise SystemExit(0)

# BATTERY
if any(x in question for x in [
    "battery", "charge", "battery level"
]):
    percentage = battery.get("percentage", 0)
    status = battery.get("status", "UNKNOWN").lower()

    print(f"Battery is at {percentage}% and currently {status}.")
    raise SystemExit(0)

# NETWORK
if any(x in question for x in [
    "internet", "network", "online", "offline", "connection"
]):
    print(f"Network status: {network.get('status', 'UNKNOWN')}.")
    raise SystemExit(0)

# CPU
if any(x in question for x in [
    "cpu", "processor", "cores", "core count"
]):
    print(f"Your device has {device.get('cpu_count', 'unknown')} CPU cores.")
    raise SystemExit(0)

# LOAD
if any(x in question for x in [
    "load", "system load", "cpu load"
]):
    print(
        f"Current system load is {load.get('average_1m', 'unknown')} "
        f"(1-minute average), with pressure marked "
        f"{load.get('pressure', 'UNKNOWN')}."
    )
    raise SystemExit(0)

# SWAP
if any(x in question for x in [
    "swap"
]):
    used = swap.get("used_mb", 0)
    total = swap.get("total_mb", 0)

    print(f"Swap usage is {used} MB used out of {total} MB.")
    raise SystemExit(0)

# DEVICE CONDITION
if any(x in question for x in [
    "device condition", "device health", "device state",
    "system condition"
]):
    print(f"Stella currently reports the device condition as {assessment.get('condition', 'UNKNOWN')}.")
    raise SystemExit(0)

# No local answer
exit(2)
PY
