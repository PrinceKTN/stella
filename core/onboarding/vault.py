"""
vault.py - Stella's locked drawer for secrets (API keys, bot tokens).

Plain words: a secret goes in here once and is never shown again, not on screen, not in a chat, not in a
log, and never to the AI brain. Only the small program that needs it (for example the Telegram connector)
asks for it at the moment it connects.

Where it is kept (the best one that works on this computer is chosen automatically):
  1. keyring  - the computer's own secure store (Windows Credential Manager, macOS Keychain, Linux Secret Service)
  2. file     - data/vault/<name>.secret, locked so only your own account can read it
                (NOT encrypted. If someone can log in as you, they can read it. Stella tells you which one is used.)

What is written next to it (data/vault/index.json) holds NO secret: only the name, where it is kept,
and a masked label such as  AIza************wxyz  so you can recognize it.
"""
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

SERVICE = "stella"
NAME_RE = re.compile(r"^[a-z][a-z0-9_]{1,40}$")


def mask(secret, head=4, tail=4):
    """AIza************wxyz - first and last few characters only. Short secrets show less."""
    n = len(secret)
    if n <= head + tail + 6:
        head, tail = 1, 2
    return secret[:head] + "*" * 12 + secret[-tail:]


def _keyring():
    """The keyring module if it has a real secure store here, else None."""
    try:
        import keyring
        kr = keyring.get_keyring()
        mod = type(kr).__module__.lower()
        if "fail" in mod or "null" in mod:
            return None
        return keyring
    except Exception:
        return None


class Vault:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.index_path = self.folder / "index.json"

    # -- the label list (never holds secrets) -----------------------------
    def _index(self):
        try:
            d = json.loads(self.index_path.read_text(encoding="utf-8"))
            return d if isinstance(d, dict) else {}
        except (OSError, ValueError):
            return {}

    def _write_index(self, d):
        self.folder.mkdir(parents=True, exist_ok=True)
        tmp = self.index_path.with_name(".index.tmp")
        tmp.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
        tmp.replace(self.index_path)

    def names(self):
        return sorted(self._index())

    def has(self, name):
        return name in self._index()

    def info(self, name):
        """{'where': 'keyring'|'file', 'masked': 'AIza****wxyz', 'saved': iso} or None. Never the secret."""
        return self._index().get(name)

    # -- storing and reading ----------------------------------------------
    def save(self, name, secret):
        """Store a secret. Returns (where, note). Raises ValueError for a bad name or empty secret."""
        if not NAME_RE.match(name or ""):
            raise ValueError("bad secret name")
        if not secret or not secret.strip():
            raise ValueError("empty secret")
        secret = secret.strip()
        where, note = None, ""
        kr = _keyring()
        if kr is not None:
            try:
                kr.set_password(SERVICE, name, secret)
                if kr.get_password(SERVICE, name) == secret:      # must read back before we trust it
                    where = "keyring"
            except Exception:
                where = None
        if where is None:
            note = self._save_file(name, secret)
            where = "file"
        idx = self._index()
        idx[name] = {"where": where, "masked": mask(secret),
                     "saved": datetime.now().astimezone().isoformat(timespec="seconds")}
        self._write_index(idx)
        return where, note

    def get(self, name):
        """The secret itself. ONLY for the one connector that needs it, never for printing or for the AI."""
        meta = self._index().get(name)
        if not meta:
            return None
        if meta["where"] == "keyring":
            kr = _keyring()
            try:
                return kr.get_password(SERVICE, name) if kr else None
            except Exception:
                return None
        try:
            return (self.folder / f"{name}.secret").read_text(encoding="utf-8").strip() or None
        except OSError:
            return None

    def delete(self, name):
        meta = self._index().get(name)
        if not meta:
            return False
        if meta["where"] == "keyring":
            kr = _keyring()
            try:
                if kr:
                    kr.delete_password(SERVICE, name)
            except Exception:
                pass
        else:
            try:
                (self.folder / f"{name}.secret").unlink()
            except OSError:
                pass
        idx = self._index()
        idx.pop(name, None)
        self._write_index(idx)
        return True

    def describe(self, where):
        return {"keyring": "your computer's secure store",
                "file": "a locked file that only your account can read (not encrypted)"}.get(where, where)

    # -- file backend ------------------------------------------------------
    def _save_file(self, name, secret):
        self.folder.mkdir(parents=True, exist_ok=True)
        path = self.folder / f"{name}.secret"
        note = ""
        if os.name == "nt":
            with open(path, "w", encoding="utf-8") as f:
                f.write(secret + "\n")
            user = os.environ.get("USERNAME", "")
            try:
                r = subprocess.run(["icacls", str(path), "/inheritance:r", "/grant:r", f"{user}:F"],
                                   capture_output=True, text=True, timeout=30)
                if r.returncode != 0:
                    note = "I could not lock the file's permissions on this Windows setup."
            except (OSError, subprocess.SubprocessError):
                note = "I could not lock the file's permissions on this Windows setup."
        else:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(secret + "\n")
            os.chmod(path, 0o600)
        return note
