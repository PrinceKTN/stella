#!/usr/bin/env python3
"""
body.py - Stella's shared "nervous system".

Every face (terminal, later Telegram, web, voice) talks to the person.
Every hand (a skill) does a job. This file connects them to Stella's OWN rules
without editing any existing Stella file:

  * finds hands in            core/skills/<skill_id>/config/skill.json
  * loads a hand's tools only if Stella's registry (core/skills/registry.json)
    says it is ENABLED  (unregistered or switched-off hands stay unloaded)
  * enabling / disabling edits the registry ONLY after a typed "yes",
    and always saves a backup copy first
  * gives every tool the same safe helpers (sandbox folder, diary events)
  * asks before anything that changes files, shows your data to the cloud brain,
    or is heavy while Stella's governor says the device is under pressure

Standard library only. Works on Termux, WSL/Linux, macOS and Windows.
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(os.environ.get("STELLA_HOME") or Path(__file__).resolve().parents[2]).resolve()
SKILLS = ROOT / "core" / "skills"
REGISTRY = SKILLS / "registry.json"
DATA = ROOT / "data"                       # the sandbox: hands may only write in here
EVENTS = ROOT / "events" / "events.jsonl"  # Stella's diary (append-only)
GOVERNOR_STATE = ROOT / "state" / "governor.json"

REQUIRED = ("skill_id", "name", "version", "description", "category",
            "risk", "permissions", "execution", "status")
RISKS = ("LOW", "MEDIUM", "HIGH", "CRITICAL")
TOOL_NAME = re.compile(r"^[a-z][a-z0-9_]{2,40}$")
PARAM_TYPES = ("string", "integer", "number", "boolean")


# ------------------------------------------------------------------ basics

def now_iso():
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def event(agent, name, data=None):
    """Add one line to Stella's diary (same shape as her other agents). Never raises."""
    try:
        EVENTS.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps({"timestamp": now_iso(), "agent": agent, "event": name,
                           "data": data or {}}, ensure_ascii=False)
        with open(EVENTS, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def atomic_write_json(path, data):
    path = Path(path)
    tmp = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        with open(tmp, "r", encoding="utf-8") as f:
            json.load(f)                      # must re-read as valid JSON before it replaces anything
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


# ----------------------------------------------------------------- governor

def governor_action():
    """Stella's resource governor decision: ALLOW / LIMIT / BLOCK_HEAVY / PROTECT, or UNKNOWN."""
    d = read_json(GOVERNOR_STATE)
    if not isinstance(d, dict):
        return "UNKNOWN"
    try:
        age = datetime.now().timestamp() - GOVERNOR_STATE.stat().st_mtime
    except OSError:
        return "UNKNOWN"
    if age > 600:                              # an old reading is not a reading
        return "UNKNOWN"
    return str((d.get("decision") or {}).get("action") or "UNKNOWN")


# ---------------------------------------------------------------- sandbox

def git_would_track(path):
    """True only if `path` is inside a git repo and is NOT git-ignored (private data could be pushed)."""
    probe = Path(path)
    while not probe.exists():
        if probe.parent == probe:
            return False
        probe = probe.parent
    try:
        r = subprocess.run(["git", "-C", str(probe), "check-ignore", "-q", str(path)],
                           capture_output=True, timeout=15)
        return r.returncode == 1               # 0 = ignored, 1 = tracked-able, 128 = not a repo
    except (OSError, subprocess.SubprocessError):
        return False


def confine(path):
    """Return the resolved path, but only if it is inside the sandbox folder (data/)."""
    p = Path(path).expanduser().resolve()
    root = DATA.resolve()
    if p != root and root not in p.parents:
        raise PermissionError(f"Not allowed: {p} is outside Stella's sandbox folder ({root}).")
    return p


def private_dir(path):
    """Create (if needed) a folder inside the sandbox, refusing if Git could publish it."""
    p = confine(path)
    if git_would_track(p):
        raise PermissionError(f"{p} is inside a git repo and is not git-ignored. "
                              "Add a line '/data/' to .gitignore first so private data cannot be pushed.")
    p.mkdir(parents=True, exist_ok=True)
    return p


def make_ctx(skill_id):
    return SimpleNamespace(
        root=ROOT, data=DATA, skill_id=skill_id,
        confine=confine, private_dir=private_dir,
        event=lambda name, data=None: event(skill_id, name, data),
    )


# ----------------------------------------------------------- finding hands

def validate(folder, m):
    """Stella's rule: an invalid skill is BLOCKED. Returns a list of problems (empty = fine)."""
    p = []
    for k in REQUIRED:
        if k not in m:
            p.append(f"missing '{k}'")
    if m.get("skill_id") != folder.name:
        p.append("skill_id must match its folder name")
    risk = m.get("risk")
    level = risk.get("level") if isinstance(risk, dict) else risk
    if level not in RISKS:
        p.append("unknown risk level")
    ex = m.get("execution") if isinstance(m.get("execution"), dict) else {}
    if ex.get("native_allowed") or ex.get("autonomous_allowed"):
        p.append("native or autonomous execution is not allowed for body parts")
    if level in ("MEDIUM", "HIGH", "CRITICAL") and not (ex.get("requires_approval") and ex.get("sandbox_required")):
        p.append(f"{level} risk must require approval and sandbox (Stella's risk-policy)")
    entry = m.get("agent_tools")
    if not isinstance(entry, str) or not entry:
        p.append("missing 'agent_tools' entry file")
    else:
        full = (folder / entry).resolve()
        if folder.resolve() not in full.parents:
            p.append("agent_tools must stay inside the skill folder")
        elif not full.is_file():
            p.append(f"tools file not found: {entry}")
    if not (folder / "config" / "permissions.json").is_file():
        p.append("missing config/permissions.json")
    return p


def find_skills():
    """Hands built for the agent (they declare 'agent_tools'). Stella's own older skills are left alone."""
    out = []
    if not SKILLS.is_dir():
        return out
    for d in sorted(SKILLS.iterdir()):
        mf = d / "config" / "skill.json"
        if not d.is_dir() or not mf.is_file():
            continue
        m = read_json(mf)
        if m is None:
            out.append({"id": d.name, "dir": d, "manifest": {}, "problems": ["skill.json is unreadable"]})
            continue
        if not isinstance(m, dict) or not m.get("agent_tools"):
            continue
        out.append({"id": d.name, "dir": d, "manifest": m, "problems": validate(d, m)})
    return out


# ---------------------------------------------------------------- registry

def read_registry():
    d = read_json(REGISTRY)
    return d if isinstance(d, dict) and isinstance(d.get("skills"), list) else None


def registry_entry(data, skill_id):
    for e in (data or {}).get("skills", []):
        if isinstance(e, dict) and e.get("skill_id") == skill_id:
            return e
    return None


def _risk_level(m):
    r = m.get("risk")
    return r.get("level") if isinstance(r, dict) else r


def _entry_from(m, status, enabled):
    # exactly the nine fields Stella's own installers write, nothing extra
    return {"skill_id": m["skill_id"], "name": m["name"], "version": m["version"],
            "status": status, "enabled": enabled, "risk": _risk_level(m),
            "execution": "SANDBOX", "native": False, "autonomous": False}


def set_enabled(skill_id, enable, confirm):
    """Switch a hand on/off in Stella's registry. `confirm(lines)` must return True (a typed yes).
    Returns (ok, message). Saves a backup copy first. Touches nothing else in the file."""
    sk = next((s for s in find_skills() if s["id"] == skill_id), None)
    if not sk:
        return False, f"I don't know a skill called '{skill_id}'. Type /skills to see them."
    if sk["problems"]:
        return False, "Stella's rules block that skill: " + "; ".join(sk["problems"])
    m = sk["manifest"]
    data = read_registry()
    if data is None:
        return False, "Stella's skill registry is missing or unreadable, so I changed nothing."
    existing = registry_entry(data, skill_id)
    new = _entry_from(m, "ENABLED" if enable else "DISABLED", bool(enable))
    if existing and existing.get("enabled") == new["enabled"] and existing.get("status") == new["status"]:
        return True, "Already like that. Nothing changed."
    if not enable and existing is None:
        return True, "That skill was never switched on. Nothing to do."
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = REGISTRY.with_name(f"{REGISTRY.name}.backup-{stamp}")
    perms = m.get("permissions") or {}
    allowed = ", ".join(k.replace("_", " ") for k, v in perms.items() if v) or "nothing special"
    lines = [
        ("Switch ON" if enable else "Switch OFF") + f": {m['name']} (v{m['version']}, risk {_risk_level(m)})",
        f"What it is: {m.get('description', '')}",
        f"What it may do: {allowed}. It may only write inside the data/ folder.",
        "What changes: one entry in Stella's skill registry file. Nothing else in that file.",
        f"Backup first: {backup.name}",
        "Enabling a skill means trusting its code. It is plain text you can read first.",
        "Undo any time: /disable " + skill_id + "  (or copy the backup file back).",
    ]
    if not confirm(lines):
        return False, "Cancelled. Nothing was changed."
    shutil.copy2(REGISTRY, backup)
    if existing is not None:
        existing.update(new)
    else:
        data["skills"].append(new)
    data["updated_at"] = datetime.now(timezone.utc).isoformat()
    atomic_write_json(REGISTRY, data)
    event("body", "skill_enabled" if enable else "skill_disabled",
          {"skill_id": skill_id, "version": m["version"], "backup": backup.name})
    return True, f"Done. {m['name']} is now {new['status']}. (Backup saved: {backup.name})"


# ------------------------------------------------------------ loading tools

def _check_tool(name, t, reserved, seen):
    if not TOOL_NAME.match(name or ""):
        return None, "bad tool name"
    if name in reserved or name in seen:
        return None, "name already used (no duplicates allowed)"
    if not isinstance(t, dict) or not callable(t.get("fn")):
        return None, "tool has no function"
    if not isinstance(t.get("label"), str) or not isinstance(t.get("description"), str):
        return None, "tool needs a label and a description"
    params = t.get("params") or {}
    if not isinstance(params, dict):
        return None, "params must be a dict"
    for pn, spec in params.items():
        if not (isinstance(spec, (tuple, list)) and len(spec) == 2 and spec[0] in PARAM_TYPES):
            return None, f"bad parameter spec for '{pn}'"
    t = dict(t)
    t["params"] = {k: (v[0], v[1]) for k, v in params.items()}
    t["egress"] = bool(t.get("egress"))
    t["heavy"] = bool(t.get("heavy"))
    t["approve"] = bool(t.get("approve") or t["egress"] or t["heavy"])   # these always ask first
    return t, ""


def load_tools(reserved=()):
    """Load tools from ENABLED hands only. Returns (tools, report).
    report rows: {id, name, version, state, detail, tools}. state: ON / OFF / NOT_REGISTERED / BLOCKED."""
    reg = read_registry()
    tools, report, seen = {}, [], set()
    for sk in find_skills():
        m = sk["manifest"]
        row = {"id": sk["id"], "name": m.get("name", sk["id"]), "version": m.get("version", "?"),
               "state": "", "detail": "", "tools": []}
        report.append(row)
        if sk["problems"]:
            row["state"], row["detail"] = "BLOCKED", "; ".join(sk["problems"])
            continue
        entry = registry_entry(reg, sk["id"])
        if entry is None:
            row["state"], row["detail"] = "NOT_REGISTERED", f"installed but not switched on. Type /enable {sk['id']}"
            continue
        if not entry.get("enabled"):
            row["state"], row["detail"] = "OFF", f"switched off. Type /enable {sk['id']}"
            continue
        try:
            path = (sk["dir"] / m["agent_tools"]).resolve()
            spec = importlib.util.spec_from_file_location("stella_skill_" + re.sub(r"\W", "_", sk["id"]), path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            offered = mod.tools(make_ctx(sk["id"]))
        except Exception as e:                 # a broken hand must never stop Stella starting
            row["state"], row["detail"] = "BLOCKED", f"could not load: {type(e).__name__}: {e}"
            continue
        bad = []
        for name, t in (offered or {}).items():
            ok, why = _check_tool(name, t, reserved, seen)
            if ok is None:
                bad.append(f"{name}: {why}")
                continue
            seen.add(name)
            tools[name] = ok
            row["tools"].append(name)
        row["state"] = "ON"
        row["detail"] = f"{len(row['tools'])} tools" + (f"; refused: {'; '.join(bad)}" if bad else "")
    return tools, report


# ---------------------------------------------------------------- approvals

def flush_input():
    """Drop keys typed while Stella was busy, so a stray Enter cannot answer a question."""
    try:
        if os.name == "nt":
            import msvcrt
            while msvcrt.kbhit():
                msvcrt.getwch()
        else:
            import termios
            termios.tcflush(sys.stdin.fileno(), termios.TCIFLUSH)
    except Exception:
        pass


def ask_choice(prompt, valid):
    flush_input()
    while True:
        try:
            a = input(prompt).strip().lower()
        except EOFError:
            return "n"
        if a in valid:
            return a
        print("  Please type one of: " + ", ".join(sorted(v for v in valid if v)))


def make_approver(agent):
    """Build the approval function a face plugs into stella_agent. Rules:
       - anything that changes files asks first (y/N)
       - anything that shows your data to Gemini asks first (y / a = whole session / N)
       - heavy work while the governor says PROTECT/BLOCK_HEAVY needs a typed 'yes'"""
    session = {"egress_ok": False}

    def approve(name, args):
        t = agent.TOOLS[name]
        print(f"\n  Stella wants to: {t['label']}")
        for k, v in (args or {}).items():
            print(f"    {k}: {v}")
        if t.get("heavy"):
            gov = governor_action()
            if hasattr(agent, "heads_up"):
                note = agent.heads_up()
                if note:
                    print(note, end="")
            if gov in ("PROTECT", "BLOCK_HEAVY"):
                print(f"  Stella's governor says {gov}: heavy jobs should wait.")
                print("  Better: do this on your laptop (WSL) and copy the finished library over.")
                return ask_choice("  Type yes to run it here anyway (anything else cancels): ", {"yes", "n", "no"}) == "yes"
            if gov == "LIMIT":
                print("  Stella's governor says LIMIT: only light, one-at-a-time work. This job is heavy.")
        if t.get("egress"):
            if session["egress_ok"]:
                print("  (Gemini will see the result. You allowed this for the whole session.)")
                return True
            print("  Privacy: the result goes to Gemini (Google). On the free plan, Google's terms say")
            print("  people may read it and it may be used to improve their products.")
            a = ask_choice("  Allow? [y = this time / a = whole session / n = no] ", {"y", "yes", "a", "n", "no"})
            if a == "a":
                session["egress_ok"] = True
            return a in ("y", "yes", "a")
        return ask_choice("  Allow? [y/N] ", {"y", "yes", "n", "no"}) in ("y", "yes")

    return approve
