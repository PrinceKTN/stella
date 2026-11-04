"""
device_profile.py - Stella looks at the device she is running on and picks sensible limits.

Plain words: this is Stella's "how strong is this machine?" check. A weak phone gets small, light settings.
A strong laptop gets bigger ones. Nothing here installs anything or changes any file: it only reads.

Tiers:  tiny (under ~2.2 GB RAM)   small (under ~4.5 GB)   medium (under ~12 GB)   large (more)

Used by stella-ui.py (to choose defaults) and by the /device command.
"""
import os
import platform
import shutil
import sys

TIERS = ("tiny", "small", "medium", "large")


def kind():
    """windows / termux / wsl / mac / linux"""
    if os.name == "nt":
        return "windows"
    if "com.termux" in os.environ.get("PREFIX", ""):
        return "termux"
    if "microsoft" in platform.release().lower():
        return "wsl"
    if sys.platform == "darwin":
        return "mac"
    return "linux"


def ram_mb():
    """(total_mb, available_mb); a value is None when it cannot be read."""
    try:
        if os.name == "nt":
            import ctypes

            class MEM(ctypes.Structure):
                _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong),
                            ("total", ctypes.c_ulonglong), ("avail", ctypes.c_ulonglong),
                            ("tpage", ctypes.c_ulonglong), ("apage", ctypes.c_ulonglong),
                            ("tvirt", ctypes.c_ulonglong), ("avirt", ctypes.c_ulonglong),
                            ("ext", ctypes.c_ulonglong)]
            m = MEM()
            m.length = ctypes.sizeof(MEM)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m)):
                return int(m.total / 1048576), int(m.avail / 1048576)
            return None, None
        vals = {}
        with open("/proc/meminfo", encoding="utf-8") as f:
            for line in f:
                k, _, v = line.partition(":")
                if k in ("MemTotal", "MemAvailable"):
                    vals[k] = int(v.split()[0]) // 1024
        return vals.get("MemTotal"), vals.get("MemAvailable")
    except (OSError, ValueError, AttributeError):
        return None, None


def tier_for(total_mb):
    if total_mb is None:
        return "small"                    # unknown machine: be careful, not wasteful
    if total_mb < 2200:
        return "tiny"
    if total_mb < 4500:
        return "small"
    if total_mb < 12000:
        return "medium"
    return "large"


def _has(module):
    try:
        __import__(module)
        return True
    except ImportError:
        return False


def detect(path="."):
    total, avail = ram_mb()
    try:
        disk_free = int(shutil.disk_usage(path).free / 1048576)
    except OSError:
        disk_free = None
    return {
        "kind": kind(),
        "python": platform.python_version(),
        "cpus": os.cpu_count() or 1,
        "ram_total_mb": total,
        "ram_free_mb": avail,
        "disk_free_mb": disk_free,
        "tier": tier_for(total),
        "live_menu_ready": _has("prompt_toolkit"),
    }


def hint(tier):
    """One sentence for the brain about the device, so she keeps answers sensible."""
    if tier == "tiny":
        return "This is a very small device: keep answers short and avoid suggesting heavy jobs."
    if tier == "small":
        return "This is a small device: keep answers compact."
    return ""


def describe(p):
    """Plain lines for /device."""
    gb = lambda mb: "unknown" if mb is None else (f"{mb / 1024:.1f} GB" if mb >= 1024 else f"{mb} MB")
    lines = [
        f"Where I run : {p['kind']}  (Python {p['python']}, {p['cpus']} CPU core{'s' if p['cpus'] != 1 else ''})",
        f"Memory      : {gb(p['ram_total_mb'])} total, {gb(p['ram_free_mb'])} free right now",
        f"Disk free   : {gb(p['disk_free_mb'])}",
        f"Strength    : {p['tier'].upper()}",
        f"Live menu   : {'ready' if p['live_menu_ready'] else 'not installed (optional: py -m pip install prompt_toolkit)'}",
    ]
    why = {
        "tiny": "I keep my memory of the chat short, take fewer steps per job, and hide the status bar.",
        "small": "I use compact settings so I stay quick.",
        "medium": "I use balanced settings.",
        "large": "I use roomy settings: longer memory and more steps per job.",
    }[p["tier"]]
    lines.append(f"What that means: {why}")
    lines.append("You can change any of it with /config and /set.")
    return lines
