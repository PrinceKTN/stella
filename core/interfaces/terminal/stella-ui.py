#!/usr/bin/env python3
"""
stella-ui - Stella's colorful face with saved chats and a live "/" command menu.

A NEW face that sits next to stella-live.py and stella-chat.sh. Both of those stay exactly as they are.
It reuses the same brain, hands and safety rules. It adds:
  * colors, so you and Stella are easy to tell apart (no more all-white text)
  * saved chats:  /new  /sessions  /resume  /title  /history  /delete
  * a live menu: type "/" and the commands appear and filter as you type (needs: py -m pip install prompt_toolkit)
  * settings you can change one by one: /config and /set
  * a device check: /device  (she picks light or roomy limits by how strong the machine is)

  python3 stella-ui.py             talk to Stella
  python3 stella-ui.py --continue  open the most recent chat again   (--new always starts a fresh one)
  python3 stella-ui.py --plain     no live menu (works everywhere)
"""
import importlib.util
import os
import re
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("STELLA_HOME") or HERE.parents[2]).resolve()
os.environ["STELLA_HOME"] = str(ROOT)
sys.path.insert(0, str(ROOT / "core" / "agent"))

ARGS = set(sys.argv[1:])
if {"-h", "--help"} & ARGS:
    print(__doc__)
    sys.exit(0)
if {"--install-command", "--uninstall-command"} & ARGS:
    print("This face does not create a command yet. Nothing was changed.")
    sys.exit(0)

try:
    import stella_agent as agent
    import body
    import device_profile as devprofile
    import sessions
    import settings as settings_mod
    sys.path.insert(0, str(ROOT / "core" / "onboarding"))
    try:
        import vault as vaultmod
        import connect as connectmod
    except ImportError:
        vaultmod = connectmod = None             # an older install without the setup guide still works
    spec = importlib.util.spec_from_file_location("stella_live_face", HERE / "stella-live.py")
    live = importlib.util.module_from_spec(spec)
    sys.argv = [str(HERE / "stella-live.py")]        # the older face must not see our flags
    spec.loader.exec_module(live)
except (ImportError, FileNotFoundError, AttributeError) as e:
    print(f"Stella's files are missing or too old ({e}). Nothing was changed.")
    sys.exit(1)

# ------------------------------------------------------------------ colors
PALETTE = {
    "dark": dict(you="#7ee787", accent="#c792ea", reply="#8bd5ff", think="#7d93a8", step="#7a7f8e", ask="#ffcb6b",
                 dim="#7a7f8e", err="#ff6b6b", rule="#4b5263", title="#82aaff"),
    # yellow and white, with a lighter color for her thinking-aloud lines
    "gold": dict(you="#ffffff", accent="#ffd166", reply="#f5f0e1", think="#9fb3c8", step="#8d99a6", ask="#ffb347",
                 dim="#8d99a6", err="#ff6b6b", rule="#6b5b2e", title="#ffd166"),
    "ocean": dict(you="#9be7c4", accent="#4fd1c5", reply="#cfe8ff", think="#7aa2c7", step="#6b8299", ask="#ffd479",
                  dim="#6b8299", err="#ff7b7b", rule="#335c75", title="#63b3ed"),
    "light": dict(you="#1b7f3b", accent="#8a2be2", reply="#0b3d62", think="#52667a", step="#6b7280", ask="#b45309",
                  dim="#6b7280", err="#b91c1c", rule="#9ca3af", title="#1d4ed8"),
}
ROLE_KEYS = {"you": "you", "name": "accent", "reply": "reply", "think": "think", "step": "step",
             "ask": "ask", "dim": "dim", "err": "err", "rule": "rule", "title": "title"}
RESET, BOLD = "\x1b[0m", "\x1b[1m"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def _fg(hexcolor):
    h = hexcolor.lstrip("#")
    return f"\x1b[38;2;{int(h[0:2], 16)};{int(h[2:4], 16)};{int(h[4:6], 16)}m"


class Painter:
    """Wraps what Stella prints and colors it line by line. Never changes the words, only the paint."""
    def __init__(self, real, theme="dark", show_steps=True, timestamps=False):
        self._real = real
        self.state, self.at_start, self.pending_prompt, self.think = "plain", True, False, False
        self.set_theme(theme)
        self.show_steps, self.timestamps = show_steps, timestamps

    def set_theme(self, theme, overrides=None):
        self.theme = theme
        base = PALETTE.get(theme)
        self.pal = dict(base, **(overrides or {})) if base else None

    def c(self, role):
        return _fg(self.pal[role]) if self.pal else ""

    def _classify(self, seg):
        if not seg.strip():
            return                                   # blank lines keep the current mood
        if seg.startswith(("Stella > ", "Stella › ")):
            self.state = "think" if self.think else "reply"      # thinking aloud = she is about to use a tool
            self.think = False
        elif seg.startswith(("  Stella wants", "  Allow?", "  Privacy:", "  Please type", "  Heads-up")):
            self.state = "ask"
        elif seg.startswith(("  -> ", "  (")):
            self.state = "step"

    def write(self, s):
        if self.pending_prompt:                      # the user pressed Enter after a prompt: a new line began
            self.at_start, self.pending_prompt = True, False
        out = []
        for seg in s.splitlines(keepends=True):
            if self.at_start:
                self._classify(seg)
            nl = "\n" if seg.endswith("\n") else ""
            body_ = seg[:-1] if nl else seg
            self.at_start = bool(nl)
            if self.state == "step" and not self.show_steps and body_.strip():
                continue
            out.append(self._paint(body_) + nl)
        text = "".join(out)
        if not self.pal:
            text = ANSI_RE.sub("", text)             # mono theme: no escape codes at all
        return self._real.write(text)

    def _paint(self, text):
        header = text.startswith(("Stella > ", "Stella › "))
        if header:
            text = text[len("Stella > "):]
        if not self.pal:
            return ("Stella › " + text) if header else text
        if header:
            stamp = f"{self.c('dim')}[{datetime.now().strftime('%H:%M')}]{RESET} " if self.timestamps else ""
            role = "think" if self.state == "think" else "reply"
            mark = "⋯" if role == "think" else "›"
            return (f"{stamp}{BOLD}{self.c('accent')}✦ Stella{RESET} {self.c('dim')}{mark}{RESET} "
                    f"{self.c(role)}{text}{RESET}")
        role = {"reply": "reply", "think": "think", "step": "step", "ask": "ask"}.get(self.state)
        if role and text.strip():
            return f"{self.c(role)}{text}{RESET}"
        return text

    def flush(self):
        if not self.at_start:
            self.pending_prompt = True               # input() flushes right after printing its prompt
        return self._real.flush()

    def __getattr__(self, name):
        return getattr(self._real, name)


# ---------------------------------------------------------------- commands
COMMANDS = [
    ("help", "/help [word]", "Show the commands (add a word to filter them)"),
    ("new", "/new [name]", "Start a fresh chat (the old one stays saved)"),
    ("sessions", "/sessions", "List your saved chats"),
    ("resume", "/resume <number|id|title>", "Continue a saved chat"),
    ("title", "/title <name>", "Rename this chat"),
    ("history", "/history", "Show the recent messages of this chat"),
    ("delete", "/delete <number|id>", "Delete a saved chat (asks you to type yes)"),
    ("status", "/status", "Quick device status"),
    ("device", "/device", "How strong this device is and what that changes"),
    ("config", "/config", "Show every setting"),
    ("set", "/set <setting> <value>", "Change one setting (value 'reset' restores it)"),
    ("theme", "/theme [name]", "Show or change the color theme (dark, gold, ocean, light, mono)"),
    ("colors", "/colors", "See every color. Change one: /color <part> <color>"),
    ("color", "/color <part> <color>", "Change one color, e.g. /color think yellow  (color = name or #hex, or reset)"),
    ("connect", "/connect [name]", "Guided setup for a key or bot token (gemini, telegram...)"),
    ("disconnect", "/disconnect <name>", "Forget a saved key or token (asks you to type yes)"),
    ("skills", "/skills", "See my hands (tools) and which are switched on"),
    ("enable", "/enable <skill>", "Switch a hand on (asks you to type yes)"),
    ("disable", "/disable <skill>", "Switch a hand off"),
    ("refresh", "/refresh", "Run the awareness and governor panels again"),
    ("clear", "/clear", "Clear the screen (the chat is kept)"),
    ("exit", "/exit", "Leave (your chat is already saved)"),
]
NAMES = [c[0] for c in COMMANDS]


def match_commands(word):
    word = word.lower()
    starts = [c for c in COMMANDS if c[0].startswith(word)]
    inside = [c for c in COMMANDS if word in c[0] and c not in starts]
    return starts + inside


def ago(iso):
    try:
        secs = time.time() - datetime.fromisoformat(iso).timestamp()
    except (ValueError, TypeError):
        return "?"
    if secs < 90:
        return "just now"
    if secs < 5400:
        return f"{int(secs // 60)}m ago"
    if secs < 129600:
        return f"{int(secs // 3600)}h ago"
    if secs < 14 * 86400:
        return f"{int(secs // 86400)}d ago"
    return iso[:10]


# ---------------------------------------------------------------- the app
class App:
    def __init__(self, real_out):
        self.real = real_out
        self.prof = devprofile.detect(str(ROOT))
        self.report = live.reload_hands()
        self.listing = []
        self.ctrl_c = 0
        try:
            self.store = sessions.Store(body.private_dir(body.DATA / "sessions"))
            self.saving = True
        except (PermissionError, OSError) as e:
            self.store, self.saving = sessions.Store(body.DATA / "sessions"), False
            self.save_problem = str(e)
        self.cfg = settings_mod.Settings(body.DATA / "settings.json", self.prof["tier"])
        self.painter = Painter(real_out, self.cfg.get("theme"), self.cfg.get("show_steps"),
                               self.cfg.get("timestamps"))
        _orig_parse = agent.parse

        def parse_and_note(resp):                      # lets the painter know a reply is "thinking aloud"
            out = _orig_parse(resp)
            self.painter.think = bool(out[1])
            return out
        agent.parse = parse_and_note
        sys.stdout = self.painter
        self.apply_settings()
        self.vault = None
        if vaultmod is not None:
            try:
                self.vault = vaultmod.Vault(body.private_dir(body.DATA / "vault"))
            except (PermissionError, OSError):
                self.vault = None
        key, self.model = agent.get_config()
        self.key = key or self.vault_key()
        self.sess = None
        self.meta = {}
        self.reader = None

    def opt(self, key, fallback):
        """A setting, or a safe default if an older settings.py does not know it yet."""
        try:
            return self.cfg.get(key)
        except KeyError:
            return fallback

    def vault_key(self):
        """Her Gemini key from the locked vault (kept only in memory for this run)."""
        if self.vault is None:
            return ""
        key = self.vault.get("gemini_api_key") or ""
        if key:
            os.environ["STELLA_GEMINI_API_KEY"] = key
        return key

    def first_run_key(self):
        """No key yet: walk the person through getting one. Returns True when she has a key afterwards."""
        if connectmod is None or self.vault is None or not sys.stdin.isatty():
            return False
        self.say("\n  Welcome! I am Stella. Before I can think I need a free Google Gemini key.")
        self.say("  I will guide you step by step. It takes about 2 minutes and it is free (no card).")
        connectmod.run(connectmod.load_recipes()["gemini"], self.vault)
        self.painter.state = "plain"
        self.key = self.vault_key()
        return bool(self.key)

    def maybe_resume(self):
        """Apply the 'resume' setting (last / ask / new). --continue forces it, --new blocks it."""
        if "--new" in ARGS:
            return False
        forced = "--continue" in ARGS
        mode = self.opt("resume", "last")
        last = self.store.listing(1)
        if not last or (mode == "new" and not forced):
            return False
        r = last[0]
        try:
            age_h = (time.time() - datetime.fromisoformat(r["updated"]).timestamp()) / 3600
        except (ValueError, TypeError, KeyError):
            age_h = 1e9
        if not forced and age_h > self.opt("resume_hours", 12):
            return False
        if mode == "ask" and not forced:
            ans = input(f"\n  Continue your last chat \"{r['title']}\" ({ago(r['updated'])})? [Y/n] ").strip().lower()
            if ans in ("n", "no"):
                return False
        self.listing = last
        self.cmd_resume("1")
        return True

    # -- settings plumbing ------------------------------------------------
    def apply_settings(self):
        agent.KEEP_TURNS = self.cfg.get("keep_turns")
        agent.MAX_ROUNDS = self.cfg.get("max_rounds")
        self.painter.set_theme(self.cfg.get("theme"), self.color_overrides())
        self.painter.show_steps = self.cfg.get("show_steps")
        self.painter.timestamps = self.cfg.get("timestamps")

    def color_overrides(self):
        out = {}
        for role, palkey in ROLE_KEYS.items():
            val = self.opt("color_" + role, "")
            if val:
                out[palkey] = val
        return out

    def build_system(self):
        text = live.system_text(self.report)
        extra = devprofile.hint(self.prof["tier"])
        return (text + " " + extra) if extra else text

    def start_chat(self, title=""):
        self.sess = agent.Session(self.key, self.model)
        self.sess.system = self.build_system()
        self.meta = {"id": sessions.new_id(), "title": title, "created": "", "model": self.model}

    def autosave(self):
        if not (self.cfg.get("autosave") and self.saving):
            return
        try:
            self.meta = self.store.save(self.meta, self.sess.turns)
        except OSError as e:
            self.say(f"(I could not save this chat: {e})", "err")
            self.saving = False

    # -- printing ---------------------------------------------------------
    def say(self, text="", role=None):
        self.painter.state = "plain"
        if role and self.painter.pal:
            text = f"{self.painter.c(role)}{text}{RESET}"
        print(text)

    def heading(self, text):
        self.say()
        self.say(text, "title")

    # -- the face ----------------------------------------------------------
    def banner(self):
        p, c = self.painter, self.painter.c
        box = [
            "╔════════════════════════════════════════════════════════════╗",
            "║                                                            ║",
            "║                 ✦  S T E L L A  ✦                         ║",
            "║                                                            ║",
            "║                    LIVE RUNTIME                            ║",
            "║                                                            ║",
            "╚════════════════════════════════════════════════════════════╝",
        ]
        self.say()
        for i, line in enumerate(box):
            self.say(line, "accent" if i in (2, 4) else "rule")
        self.say()
        gb = lambda mb: "?" if mb is None else f"{mb / 1024:.1f} GB"
        rows = [
            ("Brain", "Gemini"), ("Model", self.model), ("Interface", "Terminal"),
            ("Device", f"{self.prof['kind']}, {gb(self.prof['ram_total_mb'])} RAM, strength {self.prof['tier'].upper()}"),
            ("Execution", "APPROVAL-GATED (she asks before changing anything)"),
            ("Hands", live.hands_line(self.report)),
            ("Menu", "live" if self.reader_is_live() else "plain (type /help)"),
        ]
        for k, v in rows:
            self.say(f"  {c('dim')}{k:<10}:{RESET} {v}")
        self.say()

    def reader_is_live(self):
        return isinstance(self.reader, LiveReader)

    def welcome(self, resumed):
        if resumed:
            return
        last = self.store.listing(1)
        if last:
            r = last[0]
            self.say(f"  Last chat: \"{r['title']}\" ({ago(r['updated'])}).  /resume 1 continues it, "
                     "or just start talking for a new chat.", "dim")
        else:
            self.say("  Just tell me what you want, like talking to a person.  /help shows the commands.", "dim")

    # -- slash commands ----------------------------------------------------
    def resolve(self, word):
        """Expand a short or partial command name. Returns (name, message)."""
        if word in NAMES:
            return word, ""
        hits = [c[0] for c in COMMANDS if c[0].startswith(word)]
        if len(hits) == 1:
            return hits[0], ""
        if hits:
            return None, "Did you mean: " + ", ".join("/" + h for h in hits) + "?"
        return None, "Unknown command. Type /help to see what I know."

    def command(self, line):
        word, _, rest = line[1:].partition(" ")
        word, rest = word.strip().lower(), rest.strip()
        if not word:
            word = "help"
        name, msg = self.resolve(word)
        if not name:
            self.say(f"\nStella › {msg}")
            return True
        getattr(self, "cmd_" + name)(rest)
        return name != "exit"

    def cmd_help(self, rest):
        self.heading("Commands")
        rows = [c for c in COMMANDS if not rest or rest.lower() in (c[0] + c[1] + c[2]).lower()]
        if not rows:
            self.say(f"  Nothing matches '{rest}'.", "dim")
        for name, usage, desc in rows:
            self.say(f"  {self.painter.c('accent')}{usage:<28}{RESET}{desc}")
        self.say()
        self.say("  Tip: type / and the list appears. Keep typing to narrow it. Tab or Enter picks one.", "dim")

    def cmd_new(self, rest):
        self.start_chat(rest)
        self.say(f"\nStella › Fresh chat started{(' — ' + rest) if rest else ''}. The old one stays saved.")

    def cmd_sessions(self, rest):
        self.listing = self.store.listing(15)
        if not self.listing:
            self.say("\nStella › No saved chats yet. They appear after your first message.")
            return
        self.heading("Saved chats")
        self.say(f"  {'#':<3} {'Title':<34} {'Last active':<12} Turns", "dim")
        for i, r in enumerate(self.listing, 1):
            mark = "•" if r["id"] == self.meta.get("id") else " "
            self.say(f"  {i:<3} {r['title'][:33]:<34} {ago(r['updated']):<12} {r.get('count', 0)} {mark}")
        self.say("\n  /resume <number> continues one.   • = this chat.", "dim")

    def cmd_resume(self, rest):
        if not rest:
            self.cmd_sessions("")
            self.say("  Tell me which one: /resume <number>", "dim")
            return
        if not self.listing:
            self.listing = self.store.listing(15)
        sid = self.store.find(rest, self.listing)
        if not sid:
            self.say(f"\nStella › I can't find a saved chat for '{rest}'. Type /sessions.")
            return
        try:
            meta, turns = self.store.load(sid)
        except (OSError, ValueError, KeyError):
            self.say("\nStella › That chat file could not be read. Nothing was changed.", "err")
            return
        self.start_chat()
        self.meta = {**self.meta, **meta, "model": self.model}
        self.sess.turns = turns
        self.say(f"\nStella › Back in \"{meta.get('title') or 'that chat'}\" ({len(turns)} exchange{"s" if len(turns) != 1 else ""} saved).")
        self.cmd_history("recap")

    def cmd_title(self, rest):
        if not rest:
            self.say(f"\nStella › This chat is called \"{self.meta.get('title') or '(not named yet)'}\". "
                     "Rename it with /title <name>.")
            return
        self.meta["title"] = rest[:60]
        self.autosave()
        self.say(f"\nStella › Renamed to \"{self.meta['title']}\".")

    def cmd_history(self, rest):
        lines = []
        for turn in self.sess.turns[-4:]:
            for c in turn:
                text = " ".join(p.get("text", "") for p in c.get("parts", []) if isinstance(p, dict)).strip()
                if text and c.get("role") == "user":
                    lines.append(("you", text))
                elif text and c.get("role") == "model":
                    lines.append(("stella", text))
        if not lines:
            if rest != "recap":
                self.say("\nStella › Nothing said yet in this chat.")
            return
        self.heading("Recent messages")
        for who, text in lines[-8:]:
            text = text if len(text) <= 260 else text[:259] + "…"
            if who == "you":
                self.say(f"  {self.painter.c('you')}You ›{RESET} {text}")
            else:
                self.say(f"  {BOLD}{self.painter.c('accent')}✦ Stella ›{RESET} {self.painter.c('reply')}{text}{RESET}")

    def cmd_delete(self, rest):
        if not self.listing:
            self.listing = self.store.listing(15)
        sid = self.store.find(rest, self.listing)
        if not sid:
            self.say("\nStella › Tell me which chat: /delete <number>. Type /sessions first.")
            return
        title = next((r["title"] for r in self.listing if r["id"] == sid), sid)
        if live.confirm_typed([f"Delete the saved chat \"{title}\" for good?",
                               "This cannot be undone. Your other chats are not touched."]):
            self.store.delete(sid)
            self.listing = self.store.listing(15)
            self.say("\nStella › Deleted.")
        else:
            self.say("\nStella › Cancelled. Nothing was deleted.")

    def cmd_status(self, rest):
        st = agent.tool_device_status({})
        self.heading("Quick status")
        for k, v in st.items():
            self.say(f"  {k.replace('_', ' '):22}: {v}")
        self.say(f"  {'chat':22}: {self.meta.get('title') or '(new)'}  ({len(self.sess.turns)} exchanges)")

    def cmd_device(self, rest):
        self.prof = devprofile.detect(str(ROOT))
        self.heading("This device")
        for line in devprofile.describe(self.prof):
            self.say("  " + line)

    def cmd_config(self, rest):
        self.heading("Settings  (change one with /set <name> <value>)")
        for k, v, custom, desc, allowed in self.cfg.rows():
            shown = settings_mod.show(v)
            tag = "*" if custom else " "
            self.say(f"  {self.painter.c('accent')}{k:<12}{RESET} {shown:<7}{tag} {self.painter.c('dim')}[{allowed}] {desc}{RESET}")
        self.say("\n  * = you changed it.  Anything else uses the starting value chosen for this device.", "dim")

    def cmd_set(self, rest):
        parts = rest.split(None, 1)
        if len(parts) < 2:
            self.say("\nStella › Use: /set <setting> <value>.  Type /config to see them all.")
            return
        ok, msg = self.cfg.set(parts[0], parts[1])
        if ok:
            self.apply_settings()
            self.reader = make_reader(self)          # theme, menu and status bar may have changed
        self.say(f"\nStella › {msg}", None if ok else "err")

    def sample(self, pal):
        f = lambda role: _fg(pal[role])
        return (f"{f('you')}You ›{RESET} hello   {BOLD}{f('accent')}✦ Stella{RESET} {f('dim')}⋯{RESET} {f('think')}checking{RESET}   "
                f"{f('step')}-> looking...{RESET}   {BOLD}{f('accent')}✦ Stella{RESET} {f('dim')}›{RESET} {f('reply')}done{RESET}   "
                f"{f('ask')}Allow? [y/N]{RESET}")

    def cmd_theme(self, rest):
        names = list(PALETTE) + ["mono"]
        word = rest.strip().lower()
        if not word:
            self.heading("Themes  (change with /theme <name>)")
            now = self.cfg.get("theme")
            for n in names:
                mark = "•" if n == now else " "
                body_ = self.sample(PALETTE[n]) if n in PALETTE else "(no colors at all)"
                self.say(f"  {mark} {n:<6} {body_}")
            self.say("\n  Tweak any single color with /colors. Your tweaks stay when you switch theme.", "dim")
            return
        hits = [n for n in names if n.startswith(word)]
        if len(hits) != 1:
            self.say("\nStella › I do not know that theme. Type /theme to see them.")
            return
        ok, msg = self.cfg.set("theme", hits[0])
        self.apply_settings()
        self.reader = make_reader(self)
        self.say(f"\nStella › {msg}")

    def cmd_colors(self, rest):
        if rest.strip().lower() == "reset":
            for role in ROLE_KEYS:
                self.cfg.set("color_" + role, "reset")
            self.apply_settings()
            self.reader = make_reader(self)
            self.say("\nStella › All color tweaks removed. The theme's own colors are back.")
            return
        self.heading(f"Colors  (theme: {self.cfg.get('theme')})   change one: /color <part> <color>")
        if not self.painter.pal:
            self.say("  The mono theme has no colors. Pick another with /theme.", "dim")
            return
        for role, palkey in ROLE_KEYS.items():
            custom = self.opt("color_" + role, "")
            tag = f"{custom} (yours)" if custom else f"{self.painter.pal[palkey]} (theme)"
            self.say(f"  {role:<6} {_fg(self.painter.pal[palkey])}■■■ sample text{RESET}   {self.painter.c('dim')}{tag}{RESET}")
        self.say("\n  Parts: " + ", ".join(ROLE_KEYS) + ".   Colors: yellow, white, cream, gold, cyan... or #ffcc00.", "dim")
        self.say("  /colors reset removes all your tweaks.", "dim")

    def cmd_color(self, rest):
        parts = rest.split(None, 1)
        if len(parts) < 2 or parts[0].lower() not in ROLE_KEYS:
            self.say("\nStella › Use: /color <part> <color>.  Parts: " + ", ".join(ROLE_KEYS) + ".  Type /colors to see them.")
            return
        ok, msg = self.cfg.set("color_" + parts[0].lower(), parts[1])
        if ok:
            self.apply_settings()
            self.reader = make_reader(self)
        self.say(f"\nStella › {msg}" if ok else f"\nStella › {msg}", None if ok else "err")

    def cmd_connect(self, rest):
        if connectmod is None or self.vault is None:
            self.say("\nStella › The setup guide is not available here (an older install). Update with the newest bundle.")
            return
        recipes = connectmod.load_recipes()
        word = rest.strip().lower()
        if not word:
            self.heading("Connections")
            for rid, r in recipes.items():
                info = self.vault.info(r["secret_name"])
                state = f"connected  {info['masked']}" if info else "not set up"
                self.say(f"  {self.painter.c('accent')}{rid:<10}{RESET} {r['name']}")
                self.say(f"  {'':<10} {self.painter.c('dim')}{state}{RESET}")
            self.say("\n  Start one with /connect <name>, for example /connect telegram", "dim")
            return
        hits = [rid for rid in recipes if rid.startswith(word)]
        if len(hits) != 1:
            self.say("\nStella › I do not know that one. Type /connect to see the list.")
            return
        rid = hits[0]
        if self.vault.has(recipes[rid]["secret_name"]) and not live.confirm_typed(
                [f"{recipes[rid]['name']} is already connected.", "Continuing will REPLACE the saved one."]):
            self.say("\nStella › Cancelled. Nothing was changed.")
            return
        ok, msg = connectmod.run(recipes[rid], self.vault)
        self.painter.state = "plain"
        self.say(f"\nStella › {msg}", None if ok else "err")
        if ok and rid == "gemini":
            self.key = self.vault_key()
            if self.sess is not None:
                self.sess.key = self.key

    def cmd_disconnect(self, rest):
        if self.vault is None:
            return
        recipes = connectmod.load_recipes() if connectmod else {}
        word = rest.strip().lower()
        names = {r["secret_name"]: rid for rid, r in recipes.items()}
        target = next((sn for sn, rid in names.items() if rid.startswith(word) and word), None)
        if not target or not self.vault.has(target):
            self.say("\nStella › Nothing saved under that name. Type /connect to see what is set up.")
            return
        if live.confirm_typed([f"Forget the saved '{names[target]}' secret? I will have to be set up again to use it.",
                               "This deletes it from the vault. It does not change anything on the website."]):
            self.vault.delete(target)
            self.say("\nStella › Forgotten. It stops working for me the next time I start.")
        else:
            self.say("\nStella › Cancelled. Nothing was deleted.")

    def cmd_skills(self, rest):
        live.show_skills(self.report)

    def _toggle(self, cmd, rest):
        if not rest:
            self.say(f"\nStella › Tell me which one: /{cmd} <skill id>. Type /skills to see them.")
            return
        ok, msg = body.set_enabled(rest, cmd == "enable", live.confirm_typed)
        self.say(f"\nStella › {msg}")
        live.log_event(f"/{cmd} {rest}: {'ok' if ok else 'no'}")
        if ok:
            self.report = live.reload_hands()
            self.sess.system = self.build_system()

    def cmd_enable(self, rest):
        self._toggle("enable", rest)

    def cmd_disable(self, rest):
        self._toggle("disable", rest)

    def cmd_refresh(self, rest):
        live.run_panels()

    def cmd_clear(self, rest):
        self.real.write("\x1b[2J\x1b[H")
        self.real.flush()

    def cmd_exit(self, rest):
        self.say("\nStella › Going offline. Your chat is saved. Talk to you later.\n")
        live.log_event("Stella UI stopped")

    # -- talking -----------------------------------------------------------
    def ask(self, line):
        try:
            self.sess.ask(line)
        except agent.GeminiError as e:
            self.say(f"\nStella › {e}")
        except KeyboardInterrupt:
            self.say("\n(stopped)")
        self.autosave()

    def loop(self):
        while True:
            try:
                line = self.reader.read().strip()
                self.ctrl_c = 0
            except KeyboardInterrupt:
                self.ctrl_c += 1
                if self.ctrl_c >= 2:
                    self.cmd_exit("")
                    return 0
                self.say("\n(press Ctrl+C again, or type /exit, to leave)", "dim")
                continue
            except EOFError:
                self.cmd_exit("")
                return 0
            self.painter.state = "plain"
            if not line:
                continue
            bare = line.lower()
            if bare in ("exit", "quit", "bye", "help", "clear", "status"):
                line = "/" + bare
            if line.startswith("/"):
                if not self.command(line):
                    return 0
            else:
                self.ask(line)


# ----------------------------------------------------------------- input
class PlainReader:
    def __init__(self, app):
        self.app = app

    def read(self):
        p = self.app.painter
        mark = f"{BOLD}{p.c('you')}You ›{RESET} " if p.pal else "You › "
        if os.name == "nt":                      # Windows consoles can garble non-ASCII prompts in input()
            self.app.real.write("\n" + mark)
            self.app.real.flush()
            return input()
        return input("\n" + mark)


class LiveReader:
    """prompt_toolkit input: the '/' menu filters as you type and a hint line previews the command."""
    def __init__(self, app):
        from prompt_toolkit import PromptSession
        from prompt_toolkit.completion import Completer, Completion
        from prompt_toolkit.output import create_output
        from prompt_toolkit.styles import Style
        from prompt_toolkit.application.current import get_app
        self.app = app
        pal = app.painter.pal or PALETTE["dark"]

        class Slash(Completer):
            def get_completions(inner, document, event):
                text = document.text_before_cursor
                if not text.startswith("/"):
                    return
                word, space, arg = text[1:].partition(" ")
                if not space:
                    for name, usage, desc in match_commands(word):
                        needs_arg = "<" in usage or "[" in usage
                        yield Completion(name + (" " if needs_arg else ""), start_position=-len(word),
                                         display=usage, display_meta=desc)
                    return
                cmd = word.lower()
                options = []
                if cmd in ("resume", "delete"):
                    rows = app.listing or app.store.listing(15)
                    options = [(str(i), r["title"][:40]) for i, r in enumerate(rows, 1)]
                elif cmd == "set" and " " not in arg:
                    options = [(k, d[:40]) for k, _, _, d, _ in app.cfg.rows()]
                elif cmd == "set":
                    key, _, val = arg.partition(" ")
                    spec_ = settings_mod.SPEC.get(key.lower())
                    if spec_:
                        arg = val
                        options = [(o, "") for o in (spec_[1] if spec_[0] == "choice" else
                                                     ["on", "off"] if spec_[0] == "bool" else [])] + [("reset", "")]
                elif cmd == "theme":
                    options = [(n, "") for n in list(PALETTE) + ["mono"]]
                elif cmd == "color" and " " not in arg:
                    options = [(r, "part") for r in ROLE_KEYS]
                elif cmd == "color":
                    arg = arg.partition(" ")[2]
                    options = [(c, "") for c in ("white", "yellow", "gold", "cream", "cyan", "green", "pink", "reset")]
                elif cmd == "connect" and connectmod is not None:
                    options = [(rid, r["name"][:40]) for rid, r in connectmod.load_recipes().items()]
                elif cmd == "disconnect" and app.vault is not None and connectmod is not None:
                    have = {r["secret_name"]: rid for rid, r in connectmod.load_recipes().items()}
                    options = [(have[n], "saved") for n in app.vault.names() if n in have]
                elif cmd in ("enable", "disable"):
                    options = [(r["id"], r["state"].lower()) for r in app.report]
                for opt, meta in options:
                    if opt.lower().startswith(arg.lower().split(" ")[-1]):
                        yield Completion(opt, start_position=-len(arg.split(" ")[-1]), display_meta=meta)

        def toolbar():
            text = get_app().current_buffer.text
            if text.startswith("/") and " " not in text:
                hits = match_commands(text[1:])
                if hits:
                    more = f"   (+{len(hits) - 1} more)" if len(hits) > 1 else ""
                    return [("class:bar.cmd", f" {hits[0][1]} "), ("class:bar", f" {hits[0][2]}{more}")]
                return [("class:bar", " no command starts like that — type /help")]
            title = app.meta.get("title") or "new chat"
            return [("class:bar", f" ✦ {app.model}  │  chat: {title}  │  {len(app.sess.turns)} turns  │  "
                                  f"{app.prof['tier']}  │  type / for commands ")]

        style = Style.from_dict({
            "you": f"bold {pal['you']}", "arrow": pal["dim"],
            "bar": f"bg:{pal['rule']} #ffffff", "bar.cmd": f"bg:{pal['accent']} #000000 bold",
            "bottom-toolbar": f"bg:{pal['rule']} #ffffff",
            "completion-menu.completion": "bg:#2b2f3a #d0d4dc",
            "completion-menu.completion.current": f"bg:{pal['accent']} #000000",
            "completion-menu.meta.completion": "bg:#2b2f3a #8b92a3",
            "completion-menu.meta.completion.current": f"bg:{pal['accent']} #000000",
        })
        self.session = PromptSession(
            completer=Slash(), complete_while_typing=True, style=style,
            bottom_toolbar=toolbar if app.cfg.get("statusbar") else None,
            output=create_output(stdout=app.real), reserve_space_for_menu=9)

    def read(self):
        self.app.real.write("\n")
        self.app.real.flush()
        return self.session.prompt([("class:you", "You "), ("class:arrow", "› ")])


def make_reader(app):
    wants_menu = app.cfg.get("menu") and "--plain" not in ARGS
    if wants_menu and sys.stdin.isatty() and sys.stdout.isatty():
        try:
            return LiveReader(app)
        except Exception:
            pass                                  # missing package or odd terminal: use the plain reader
    return PlainReader(app)


# ------------------------------------------------------------------ main
def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if os.name == "nt":
        os.system("")                             # lets older Windows consoles show colors
    real = sys.stdout
    app = App(real)
    if not app.key and not app.first_run_key():
        app.say("\n  I have no Gemini key yet. Get a free one at https://aistudio.google.com/apikey, then run:  stella")
        app.say("  and follow the guide, or save it by hand in")
        app.say(f"  {ROOT / 'config' / 'providers.env'}  as one line:  STELLA_GEMINI_API_KEY=your_key_here\n")
        return 1
    app.start_chat()
    app.reader = make_reader(app)
    if not app.saving:
        app.say(f"(Chats will not be saved: {getattr(app, 'save_problem', 'folder problem')})", "err")
    app.banner()
    if app.prof["kind"] == "termux" and shutil.which("bash") and live.AWARENESS.is_file():
        if ROOT == (Path.home() / "stella").resolve():
            live.run_panels()                 # her original panels read Termux sensors and expect ~/stella
        else:
            app.say("  (Her original device panels expect Stella to live in ~/stella, so I skipped them.)", "dim")
    agent.approve = body.make_approver(agent)
    resumed = app.maybe_resume()
    app.welcome(resumed)
    live.log_event("Stella UI started")
    return app.loop()


if __name__ == "__main__":
    sys.exit(main())
