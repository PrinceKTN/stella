"""
settings.py - every Stella preference in one place, each one changeable on its own.

Plain words: a list of knobs. Each knob has a name, a safe starting value (chosen by how strong the
device is), and a rule for what values are allowed. Your changes are saved in data/settings.json (private,
never pushed to GitHub). Anything you do not change keeps its starting value.

  /config              show every knob
  /set theme light     turn one knob
  /set theme reset     put one knob back

To add a new knob later: add one line to SPEC. Nothing else needs to change.
"""
import json
from pathlib import Path

# name: (kind, options-or-(min,max), default-or-{tier: default}, description)
SPEC = {
    "theme": ("choice", ["dark", "gold", "ocean", "light", "mono"], "dark",
              "Color theme. 'gold' is yellow and white, 'mono' turns colors off (for old terminals)."),
    "statusbar": ("bool", None, {"tiny": False, "small": True, "medium": True, "large": True},
                  "Show the bottom line with brain, chat name and hints."),
    "menu": ("bool", None, True,
             "Live '/' command menu while you type (needs the optional prompt_toolkit package)."),
    "timestamps": ("bool", None, False, "Show [HH:MM] before each of my answers."),
    "show_steps": ("bool", None, True, "Show the little '->' lines when I use a tool."),
    "autosave": ("bool", None, True, "Save every chat so you can /resume it later."),
    "resume": ("choice", ["last", "ask", "new"], "last",
               "When I start: 'last' continues your latest chat, 'ask' asks you first, 'new' always starts fresh."),
    "resume_hours": ("int", (1, 720), 12,
                     "Only a chat newer than this many hours counts as 'latest' for the setting above."),
    "color_you": ("color", None, "", "Color of your own lines. Empty = the theme's color."),
    "color_name": ("color", None, "", "Color of Stella's name label."),
    "color_reply": ("color", None, "", "Color of her final answers."),
    "color_think": ("color", None, "", "Color of her thinking-aloud lines (before she uses a tool)."),
    "color_step": ("color", None, "", "Color of the tool step lines."),
    "color_ask": ("color", None, "", "Color of approval questions."),
    "color_dim": ("color", None, "", "Color of hints and small print."),
    "color_err": ("color", None, "", "Color of problems."),
    "color_rule": ("color", None, "", "Color of lines and frames."),
    "color_title": ("color", None, "", "Color of headings."),
    "keep_turns": ("int", (1, 40), {"tiny": 4, "small": 6, "medium": 8, "large": 14},
                   "How many past requests I remember inside one chat (more = smarter, but heavier)."),
    "max_rounds": ("int", (1, 15), {"tiny": 4, "small": 5, "medium": 6, "large": 8},
                   "Most tool steps I may take for one request before I pause."),
}

def show(v):
    if v == "":
        return "theme"
    return ("on" if v else "off") if isinstance(v, bool) else str(v)


COLOR_NAMES = {
    "white": "#ffffff", "black": "#000000", "yellow": "#ffd166", "gold": "#ffc233", "orange": "#ff9f43",
    "red": "#ff6b6b", "pink": "#ff8fc7", "purple": "#c792ea", "violet": "#a78bfa", "blue": "#63b3ed",
    "cyan": "#5eead4", "teal": "#2dd4bf", "green": "#7ee787", "lime": "#b5f23d", "gray": "#8d99a6",
    "grey": "#8d99a6", "lightgray": "#cbd2d9", "lightgrey": "#cbd2d9", "cream": "#f5f0e1", "silver": "#c0c7d0",
}


def parse_color(raw):
    """'yellow' or '#ffcc00' or '#fc0'  ->  '#rrggbb', or None if it is not a color."""
    t = str(raw).strip().lower()
    if t in COLOR_NAMES:
        return COLOR_NAMES[t]
    if t.startswith("#"):
        h = t[1:]
        if len(h) == 3 and all(c in "0123456789abcdef" for c in h):
            h = "".join(c * 2 for c in h)
        if len(h) == 6 and all(c in "0123456789abcdef" for c in h):
            return "#" + h
    return None


_TRUE = {"on", "true", "yes", "y", "1"}
_FALSE = {"off", "false", "no", "n", "0"}


class Settings:
    def __init__(self, path, tier="small"):
        self.path = Path(path)
        self.tier = tier
        self.user = {}
        self._load()

    # -- reading ---------------------------------------------------------
    def _load(self):
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
        if isinstance(data, dict):
            for k, v in data.items():
                if k in SPEC and self._check(k, v)[0]:     # a damaged or old value is ignored, not trusted
                    self.user[k] = self._check(k, v)[1]

    def default(self, key):
        d = SPEC[key][2]
        return d[self.tier] if isinstance(d, dict) else d

    def get(self, key):
        return self.user.get(key, self.default(key))

    def is_custom(self, key):
        return key in self.user

    # -- changing --------------------------------------------------------
    def _check(self, key, raw):
        kind, opt, _, _ = SPEC[key]
        if kind == "bool":
            if isinstance(raw, bool):
                return True, raw
            s = str(raw).strip().lower()
            if s in _TRUE:
                return True, True
            if s in _FALSE:
                return True, False
            return False, "use on or off"
        if kind == "int":
            try:
                n = int(str(raw).strip())
            except ValueError:
                return False, f"use a whole number from {opt[0]} to {opt[1]}"
            if not opt[0] <= n <= opt[1]:
                return False, f"use a number from {opt[0]} to {opt[1]}"
            return True, n
        if kind == "color":
            c = parse_color(raw)
            return (True, c) if c else (False, "use a color name (like yellow, white, cream) or a code like #ffcc00")
        s = str(raw).strip().lower()
        if s in opt:
            return True, s
        return False, "choose one of: " + ", ".join(opt)

    def set(self, key, raw):
        """Returns (ok, message). Saves to disk only when the value is valid."""
        key = (key or "").strip().lower()
        if key not in SPEC:
            return False, "I have no setting called '%s'. Type /config to see them all." % key
        if str(raw).strip().lower() in ("reset", "default"):
            self.user.pop(key, None)
            self._save()
            return True, f"{key} is back to its starting value ({show(self.default(key))})."
        ok, val = self._check(key, raw)
        if not ok:
            return False, f"{key}: {val}."
        self.user[key] = val
        self._save()
        return True, f"{key} is now {show(val)}."

    def _save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_name(self.path.name + ".tmp")
        tmp.write_text(json.dumps(self.user, indent=2) + "\n", encoding="utf-8")
        tmp.replace(self.path)

    def rows(self):
        """For /config: (name, value, is_custom, description, allowed-text)"""
        out = []
        for k, (kind, opt, _, desc) in SPEC.items():
            allowed = {"bool": "on/off", "int": f"{opt[0]}-{opt[1]}" if kind == "int" else "",
                       "choice": "/".join(opt) if kind == "choice" else "", "color": "name or #hex"}[kind]
            out.append((k, self.get(k), self.is_custom(k), desc, allowed))
        return out
