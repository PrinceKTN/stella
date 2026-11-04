"""
sessions.py - Stella remembers each conversation as its own saved chat.

Plain words: every chat gets a name and an ID and is saved as one small file inside data/sessions/.
You can start a new chat, see the old ones, and continue any of them with everything she remembered.
Nothing here ever edits or deletes a chat unless you ask (/delete asks you to type yes).

Files:  data/sessions/<id>.json        the full chat
        data/sessions/index.json       a small list so /sessions is fast (rebuilt if it is lost)
"""
import json
import os
import secrets
from datetime import datetime
from pathlib import Path


def _now():
    return datetime.now().astimezone().isoformat(timespec="milliseconds")


def new_id():
    return datetime.now().strftime("%Y%m%d_%H%M%S_") + secrets.token_hex(3)


def first_user_text(turns):
    for turn in turns:
        for c in turn:
            if c.get("role") == "user":
                for p in c.get("parts", []):
                    if isinstance(p, dict) and p.get("text"):
                        return p["text"]
    return ""


def _short(text, n=42):
    t = " ".join((text or "").split())
    return t if len(t) <= n else t[: n - 1].rstrip() + "…"


def _atomic(path, obj):
    tmp = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False)
        with open(tmp, "r", encoding="utf-8") as f:
            json.load(f)                                  # must read back as valid JSON first
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


class Store:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.index_path = self.folder / "index.json"

    # -- index -----------------------------------------------------------
    def _read_index(self):
        try:
            idx = json.loads(self.index_path.read_text(encoding="utf-8"))
            if isinstance(idx, dict) and isinstance(idx.get("sessions"), list):
                return idx["sessions"]
        except (OSError, ValueError):
            pass
        return self._rebuild()

    def _rebuild(self):
        out = []
        if self.folder.is_dir():
            for f in self.folder.glob("2*.json"):
                try:
                    d = json.loads(f.read_text(encoding="utf-8"))
                    out.append({"id": d["id"], "title": d.get("title", ""), "created": d.get("created", ""),
                                "updated": d.get("updated", ""), "count": len(d.get("turns", []))})
                except (OSError, ValueError, KeyError):
                    continue
        return out

    def _write_index(self, rows):
        self.folder.mkdir(parents=True, exist_ok=True)
        _atomic(self.index_path, {"sessions": rows})

    # -- saving and loading ----------------------------------------------
    def save(self, meta, turns):
        """meta: dict with id, title, created, model. Fills in title/updated. Returns the saved meta."""
        if not turns:
            return meta                                    # an empty chat is never saved
        self.folder.mkdir(parents=True, exist_ok=True)
        if not meta.get("title"):
            meta["title"] = _short(first_user_text(turns), 40) or "Untitled chat"
        meta["updated"] = _now()
        meta.setdefault("created", meta["updated"])
        _atomic(self.folder / f"{meta['id']}.json", {**meta, "turns": turns})
        rows = [r for r in self._read_index() if r.get("id") != meta["id"]]
        rows.append({"id": meta["id"], "title": meta["title"], "created": meta["created"],
                     "updated": meta["updated"], "count": len(turns)})
        self._write_index(rows)
        return meta

    def load(self, sid):
        d = json.loads((self.folder / f"{sid}.json").read_text(encoding="utf-8"))
        meta = {k: d.get(k, "") for k in ("id", "title", "created", "updated", "model")}
        return meta, d.get("turns", [])

    def listing(self, limit=15):
        rows = sorted(self._read_index(), key=lambda r: r.get("updated", ""), reverse=True)
        return rows[:limit]

    def find(self, ref, listing=None):
        """ref = a number from the last /sessions list, an ID (or its start), or part of a title."""
        ref = (ref or "").strip()
        if not ref:
            return None
        rows = listing if listing is not None else self.listing(50)
        if ref.isdigit() and 1 <= int(ref) <= len(rows):
            return rows[int(ref) - 1]["id"]
        every = self.listing(10000)
        ids = [r["id"] for r in every if r["id"].startswith(ref)]
        if len(ids) == 1:
            return ids[0]
        low = ref.lower()
        hits = [r["id"] for r in every if low in (r.get("title") or "").lower()]
        return hits[0] if hits else None

    def delete(self, sid):
        try:
            (self.folder / f"{sid}.json").unlink()
        except OSError:
            pass
        self._write_index([r for r in self._read_index() if r.get("id") != sid])
