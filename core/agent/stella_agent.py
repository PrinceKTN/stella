#!/usr/bin/env python3
"""
Stella agent: talk to her normally and she does the steps with tools.

  * Reads (checking the device, looking for files) run on their own.
  * Anything that changes files asks you first: Allow? [y/N]
  * Standard library only, so it is light enough for a low-RAM phone and
    runs the same on Termux, WSL, macOS and Windows.
  * The Gemini key is read from config/providers.env (or the environment)
    and is never printed.
"""
import argparse
import contextlib
import importlib.util
import io
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(os.environ.get("STELLA_HOME") or Path(__file__).resolve().parents[2]).resolve()
API = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
MAX_ROUNDS = 6        # tool steps allowed for one request
KEEP_TURNS = 8        # past requests kept in the conversation (keeps RAM and tokens low)
DEBUG = bool(os.environ.get("STELLA_DEBUG"))


# ------------------------------------------------------------------ config

def load_env(path):
    out = {}
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return out
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[7:]
        k, v = line.split("=", 1)
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
            v = v[1:-1]
        out[k.strip()] = v
    return out


def get_config():
    env = load_env(ROOT / "config" / "providers.env")
    key = os.environ.get("STELLA_GEMINI_API_KEY") or env.get("STELLA_GEMINI_API_KEY", "")
    model = os.environ.get("STELLA_GEMINI_MODEL") or env.get("STELLA_GEMINI_MODEL") or "gemini-2.5-flash"
    return key, model


def detect_env():
    if os.name == "nt":
        return "Windows"
    if "com.termux" in os.environ.get("PREFIX", ""):
        return "Termux (Android)"
    try:
        if "microsoft" in Path("/proc/version").read_text().lower():
            return "WSL"
    except OSError:
        pass
    return platform.system() or "Linux"


# ------------------------------------------------------------------- tools

def load_files_skill():
    path = ROOT / "core" / "capabilities" / "files" / "stella_files.py"
    spec = importlib.util.spec_from_file_location("stella_files", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def quick_awareness():
    try:
        return json.loads((ROOT / "state" / "awareness.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def tool_device_status(args):
    script = ROOT / "core" / "awareness" / "awareness.sh"
    if script.is_file() and shutil.which("bash"):
        try:
            subprocess.run(["bash", str(script)], capture_output=True, timeout=45,
                           stdin=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            pass
    d = quick_awareness()
    if d:
        mem, sto, bat = d.get("memory", {}), d.get("storage", {}), d.get("battery", {})
        return {
            "condition": d.get("assessment", {}).get("condition"),
            "memory_available_mb": mem.get("available_mb"),
            "memory_total_mb": mem.get("total_mb"),
            "storage_available_gb": round(sto.get("available_mb", 0) / 1024, 1),
            "storage_used_percent": sto.get("used_percent"),
            "battery_percent": bat.get("percentage"),
            "battery_status": bat.get("status"),
            "network": d.get("network", {}).get("status"),
            "load_pressure": d.get("load", {}).get("pressure"),
            "cpu_cores": d.get("device", {}).get("cpu_count"),
        }
    du = shutil.disk_usage(ROOT)
    return {"note": "basic info only (no device scanner on this system)",
            "storage_available_gb": round(du.free / 1024 ** 3, 1),
            "os": platform.platform(), "python": platform.python_version()}


def tool_find_export(args):
    sk = load_files_skill()
    found, seen = [], set()
    for root in sk.default_roots():
        for z in sk.iter_zips(root):
            rz = z.resolve()
            if rz in seen:
                continue
            seen.add(rz)
            if sk.is_chatgpt_export(rz):
                st = rz.stat()
                found.append({
                    "path": str(rz),
                    "size_mb": round(st.st_size / 1048576, 1),
                    "modified": datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M"),
                })
    found.sort(key=lambda f: f["modified"], reverse=True)
    return {"found": found, "count": len(found)}


def tool_archive_export(args):
    path = str(args.get("path", "")).strip()
    if not path:
        return {"ok": False, "error": "no path given"}
    sk = load_files_skill()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        rc = sk.cmd_archive(argparse.Namespace(zip=path, dest=None, yes=True))
    return {"ok": rc == 0, "report": buf.getvalue()[-2500:]}


def tool_list_archives(args):
    d = ROOT / "data" / "archive"
    items = []
    for m in sorted(d.glob("*_manifest.json")) if d.is_dir() else []:
        try:
            j = json.loads(m.read_text(encoding="utf-8"))
            items.append({"name": m.name, "archived_at": j.get("archived_at"),
                          "files_extracted": j.get("files_extracted"),
                          "chat_files": j.get("conversation_files"),
                          "extracted_dir": j.get("extracted_dir")})
        except (OSError, ValueError):
            continue
    return {"archives": items, "count": len(items)}


TOOLS = {
    "device_status": {
        "fn": tool_device_status, "approve": False,
        "label": "checking how your device is doing",
        "description": "Check the device: battery, free memory, storage, network, and overall condition.",
    },
    "find_chatgpt_export": {
        "fn": tool_find_export, "approve": False,
        "label": "looking for your ChatGPT export zip",
        "description": "Search the phone/computer's usual folders for ChatGPT data-export zip files. Read-only.",
    },
    "archive_chatgpt_export": {
        "fn": tool_archive_export, "approve": True,
        "label": "copying and unzipping your ChatGPT export (original untouched)",
        "description": ("Copy a ChatGPT export zip into Stella's archive folder with a clear name, unzip the COPY, "
                        "and write a manifest. The original is never changed. Needs the user's approval."),
        "params": {"path": ("string", "Full path of the export zip, exactly as returned by find_chatgpt_export")},
    },
    "list_archives": {
        "fn": tool_list_archives, "approve": False,
        "label": "looking at what is already archived",
        "description": "List ChatGPT exports Stella has already archived. Read-only.",
    },
}


def declarations():
    out = []
    for name, t in TOOLS.items():
        d = {"name": name, "description": t["description"]}
        params = t.get("params")
        if params:  # Gemini rejects empty parameter objects, so only add when there are some
            d["parameters"] = {
                "type": "object",
                "properties": {k: {"type": typ, "description": desc} for k, (typ, desc) in params.items()},
                "required": list(params),
            }
        out.append(d)
    return out


# ------------------------------------------------------------------ Gemini

class GeminiError(Exception):
    pass


def gemini(key, model, contents, system):
    body = {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": contents,
        "tools": [{"functionDeclarations": declarations()}],
    }
    req = urllib.request.Request(
        API.format(model=model), data=json.dumps(body).encode("utf-8"), method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            try:
                msg = json.loads(e.read().decode("utf-8", "replace")).get("error", {}).get("message", "")
            except (ValueError, OSError):
                msg = ""
            if e.code in (429, 500, 503) and attempt < 2:
                time.sleep(8 if e.code == 429 else 3)
                continue
            if e.code == 429:
                raise GeminiError("Gemini says I'm asking too often (free-plan limit). Wait a minute and try again.")
            if e.code in (400, 403) and "API key" in msg:
                raise GeminiError("Gemini does not accept my key. Re-set it with: ./bin/stella-provider set gemini")
            raise GeminiError(f"Gemini error {e.code}" + (f": {msg}" if (DEBUG or e.code == 400) else ""))
        except (urllib.error.URLError, TimeoutError, OSError):
            if attempt < 2:
                time.sleep(3)
                continue
            raise GeminiError("I can't reach Gemini. Check your internet (on Termux, flight mode on then off often fixes it).")
    raise GeminiError("Gemini did not answer.")


def parse(resp):
    cands = resp.get("candidates") or []
    if not cands:
        why = (resp.get("promptFeedback") or {}).get("blockReason")
        return None, [], "", (f"Gemini blocked that request ({why})." if why else "Gemini sent no answer.")
    content = cands[0].get("content") or {}
    parts = content.get("parts") or []
    text = "".join(p.get("text", "") for p in parts if isinstance(p, dict) and not p.get("thought"))
    calls = [p["functionCall"] for p in parts if isinstance(p, dict) and "functionCall" in p]
    if not parts:
        why = cands[0].get("finishReason") or "unknown reason"
        return None, [], "", f"Gemini sent an empty answer ({why}). Please try asking again."
    return {"role": "model", "parts": parts}, calls, text.strip(), ""


# ------------------------------------------------------------ conversation

def system_prompt():
    return (
        "You are Stella, the user's personal assistant. You live in their terminal (right now: "
        f"{detect_env()}), often on a low-power phone. Today is {datetime.now().strftime('%A, %d %B %Y')}.\n"
        "How to talk: warm, direct, simple everyday words, short sentences. Plain text only: no markdown, "
        "no asterisks, no tables. Never show internal field names; say things naturally.\n"
        "How to work: do the job yourself with your tools instead of telling the user to run commands. "
        "For a multi-step job, say in one short line what you are about to do, use the tools, then say what "
        "happened and what the next step is. Anything that changes files needs the user's approval; the system "
        "asks them, and if they decline, accept it and offer another way.\n"
        "Honesty: never invent results. If a tool fails or you have no tool for something, say so plainly and "
        "offer the closest thing. Never ask for or repeat API keys or passwords.\n"
        "Your tools today: check the device, find a ChatGPT export zip, archive it (copy + unzip the copy), and "
        "list archives. Coming later: importing the chats into long-term memory, and chat apps like Telegram."
    )


def heads_up():
    d = quick_awareness()
    if not d:
        return ""
    cond = (d.get("assessment") or {}).get("condition")
    if cond in ("CRITICAL", "PRESSURED"):
        bat = (d.get("battery") or {}).get("percentage")
        mem = (d.get("memory") or {}).get("available_mb")
        return f"  Heads-up: the device is {cond} (battery {bat}%, {mem} MB memory free). A big job may be slow.\n"
    return ""


def flush_input():
    """Throw away keys pressed while Stella was busy (a stray Enter must not answer a question)."""
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


def ask_yes_no(prompt):
    flush_input()
    while True:
        try:
            ans = input(prompt).strip().lower()
        except EOFError:
            return False
        if ans in ("y", "yes"):
            return True
        if ans in ("n", "no"):
            return False
        print("  Please type y or n.")


def approve(name, args):
    t = TOOLS[name]
    print(f"\n  Stella wants to: {t['label']}")
    for k, v in (args or {}).items():
        print(f"    {k}: {v}")
    warn = heads_up()
    if warn:
        print(warn, end="")
    return ask_yes_no("  Allow? [y/N] ")


def execute(call):
    name, args = call.get("name"), call.get("args") or {}
    tool = TOOLS.get(name)
    if not tool:
        return {"error": f"unknown tool {name}"}
    if tool["approve"] and not approve(name, args):
        print("  (Not allowed. Nothing was changed.)")
        return {"declined": True, "message": "The user said no. Nothing was changed."}
    print(f"  -> {tool['label']}...")
    try:
        return tool["fn"](args)
    except Exception as e:  # a broken tool must not kill the conversation
        return {"error": f"{type(e).__name__}: {e}"}


class Session:
    def __init__(self, key, model):
        self.key, self.model, self.turns = key, model, []
        self.system = system_prompt()

    def history(self):
        return [c for turn in self.turns[-KEEP_TURNS:] for c in turn]

    def ask(self, text):
        user = {"role": "user", "parts": [{"text": text}]}
        turn, contents = [user], self.history() + [user]
        for _ in range(MAX_ROUNDS):
            resp = gemini(self.key, self.model, contents, self.system)
            model_content, calls, reply, problem = parse(resp)
            if model_content is None:
                print(f"\nStella > {problem}")
                return
            turn.append(model_content)
            contents.append(model_content)
            if reply:
                print(f"\nStella > {reply}")
            if not calls:
                break
            results = [{"functionResponse": {"name": c.get("name"), "response": {"result": execute(c)}}}
                       for c in calls]
            back = {"role": "user", "parts": results}
            turn.append(back)
            contents.append(back)
        else:
            print("\nStella > I did several steps and I'm pausing here. Tell me to continue if you want more.")
        self.turns.append(turn)


HELP = """
  Just tell me what you want, like talking to a person. For example:
    find my ChatGPT export and save a safe copy
    how is my phone doing?
  Commands:  help   status   clear (new conversation)   exit
"""


def main():
    key, model = get_config()
    print(f"\n* Stella  ({model})")
    if not key:
        print("\nI have no Gemini key yet. Set it once with:\n  ./bin/stella-provider set gemini")
        return 1
    print(HELP)
    sess = Session(key, model)
    while True:
        try:
            line = input("\nYou > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nStella > Going offline. Talk to you later.")
            return 0
        cmd = line.lower().lstrip("/")
        if not line:
            continue
        if cmd in ("exit", "quit", "bye"):
            print("Stella > Going offline. Talk to you later.")
            return 0
        if cmd in ("clear", "reset", "new"):
            sess.turns = []
            print("Stella > Fresh start. What shall we do?")
            continue
        if cmd == "help":
            print(HELP)
            continue
        if cmd == "status":
            print(json.dumps(tool_device_status({}), indent=2))
            continue
        try:
            sess.ask(line)
        except GeminiError as e:
            print(f"\nStella > {e}")
        except KeyboardInterrupt:
            print("\n(stopped)")


if __name__ == "__main__":
    sys.exit(main())
