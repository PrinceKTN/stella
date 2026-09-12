#!/usr/bin/env python3

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

AWARENESS_PATH = ROOT / "state" / "awareness.json"
RESOURCE_POLICY_PATH = ROOT / "core" / "scheduler" / "resource-policy.json"
RISK_POLICY_PATH = ROOT / "core" / "safety" / "risk-policy.json"
GOVERNOR_POLICY_PATH = ROOT / "core" / "governor" / "governor-policy.json"

STATE_DIR = ROOT / "state"
STATE_PATH = STATE_DIR / "governor.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def atomic_write_json(path: Path, data):
    tmp_path = path.with_name(f".{path.name}.tmp.{os.getpid()}")

    try:
        with tmp_path.open("w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")

        # Validate before publication.
        with tmp_path.open("r", encoding="utf-8") as f:
            json.load(f)

        os.replace(tmp_path, path)

    finally:
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass


def main():
    print()
    print("╔════════════════════════════════════════════════════════════╗")
    print("║              STELLA RESOURCE GOVERNOR                     ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print()

    required = {
        "awareness": AWARENESS_PATH,
        "resource policy": RESOURCE_POLICY_PATH,
        "risk policy": RISK_POLICY_PATH,
        "governor policy": GOVERNOR_POLICY_PATH,
    }

    for name, path in required.items():
        if not path.exists():
            print(f"ERROR: Missing {name}: {path}", file=sys.stderr)
            return 1

    try:
        awareness = load_json(AWARENESS_PATH)
        resource_policy = load_json(RESOURCE_POLICY_PATH)
        risk_policy = load_json(RISK_POLICY_PATH)
        governor_policy = load_json(GOVERNOR_POLICY_PATH)

    except Exception as exc:
        print(f"ERROR: Failed to load governor input: {exc}", file=sys.stderr)
        return 1

    condition = (
        awareness.get("assessment", {})
        .get("condition", "UNKNOWN")
    )

    condition_mapping = governor_policy.get("condition_mapping", {})

    decision = condition_mapping.get(
        condition,
        condition_mapping.get("UNKNOWN", "PROTECT")
    )

    # --------------------------------------------------------
    # Awareness freshness guard
    # --------------------------------------------------------

    freshness_policy = governor_policy.get("freshness", {})

    freshness_enabled = freshness_policy.get("enabled", True)
    max_awareness_age_seconds = int(
        freshness_policy.get("max_awareness_age_seconds", 300)
    )

    stale_action = freshness_policy.get(
        "stale_action",
        "PROTECT"
    )

    invalid_timestamp_action = freshness_policy.get(
        "invalid_timestamp_action",
        "PROTECT"
    )

    awareness_timestamp = awareness.get("timestamp")

    awareness_age_seconds = None
    awareness_fresh = False
    freshness_status = "UNKNOWN"

    if not freshness_enabled:
        awareness_fresh = True
        freshness_status = "DISABLED"

    elif isinstance(awareness_timestamp, str):
        try:
            awareness_time = datetime.strptime(
                awareness_timestamp,
                "%Y-%m-%dT%H:%M:%S%z"
            )

            now = datetime.now(timezone.utc)

            awareness_age_seconds = max(
                0,
                int((now - awareness_time).total_seconds())
            )

            awareness_fresh = (
                awareness_age_seconds
                <= max_awareness_age_seconds
            )

            freshness_status = (
                "FRESH"
                if awareness_fresh
                else "STALE"
            )

            if not awareness_fresh:
                decision = stale_action

        except (ValueError, TypeError, OverflowError):
            freshness_status = "INVALID_TIMESTAMP"
            decision = invalid_timestamp_action

    else:
        freshness_status = "INVALID_TIMESTAMP"
        decision = invalid_timestamp_action

    load_data = awareness.get("load", {})
    memory_data = awareness.get("memory", {})
    storage_data = awareness.get("storage", {})
    battery_data = awareness.get("battery", {})

    limits = resource_policy.get("limits", {})

    timestamp = datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")

    report = {
        "schema_version": 1,
        "component": "stella-resource-governor",
        "timestamp": timestamp,

        "mode": governor_policy.get(
            "mode",
            "READ_ONLY_DECISION"
        ),

        "input": {
            "awareness_timestamp": awareness_timestamp,
            "device_condition": condition,

            "freshness": {
                "enabled": freshness_enabled,
                "status": freshness_status,
                "fresh": awareness_fresh,
                "age_seconds": awareness_age_seconds,
                "max_age_seconds": max_awareness_age_seconds
            }
        },

        "decision": {
            "action": decision,
            "reason": (
                f"Awareness condition is {condition}; "
                f"freshness is {freshness_status}"
            )
        },

        "resource_snapshot": {
            "load_pressure": load_data.get("pressure", "UNKNOWN"),
            "memory_available_percent": memory_data.get(
                "available_percent"
            ),
            "storage_used_percent": storage_data.get(
                "used_percent"
            ),
            "battery_percentage": battery_data.get(
                "percentage"
            )
        },

        "limits": {
            "resource_class": resource_policy.get(
                "resource_class",
                "UNKNOWN"
            ),
            "max_workers": limits.get("max_workers"),
            "max_heavy_workers": limits.get(
                "max_heavy_workers"
            ),
            "max_concurrent_ai": limits.get(
                "max_concurrent_ai"
            ),
            "scheduler_parallelism": limits.get(
                "scheduler_parallelism"
            )
        },

        "safety": governor_policy.get("safety", {}),

        "execution": {
            "actions_performed": [],
            "read_only": True
        }
    }

    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        atomic_write_json(STATE_PATH, report)

    except Exception as exc:
        print(
            f"ERROR: Governor state publication failed: {exc}",
            file=sys.stderr
        )
        return 1

    print(f"  Device condition : {condition}")
    print(f"  Awareness status : {freshness_status}")

    if awareness_age_seconds is not None:
        print(
            f"  Awareness age    : "
            f"{awareness_age_seconds} seconds"
        )

    print(f"  Governor action  : {decision}")
    print()
    print(
        "  Resource class   : "
        f"{report['limits']['resource_class']}"
    )
    print(
        "  Max workers      : "
        f"{report['limits']['max_workers']}"
    )
    print(
        "  Max AI workers   : "
        f"{report['limits']['max_concurrent_ai']}"
    )
    print()
    print(f"  State: {STATE_PATH}")
    print("  Mode : READ-ONLY / DECISION-ONLY")
    print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
