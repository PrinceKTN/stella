#!/usr/bin/env python3
"""
Stella file skill: find a ChatGPT export zip, keep the original untouched,
copy it, unzip the COPY, and give everything clear names.

Safety rules (match core/skills/permission-policy.json):
  * Never deletes, moves, or overwrites anything.
  * Writes only inside the archive folder (default: <stella>/data/archive).
  * Asks for approval before writing (skip with --yes).
  * Refuses to write inside a git repo unless that folder is git-ignored,
    so private chats cannot be pushed to GitHub by accident.
  * Standard library only; works on Termux and Windows.

Usage:
  python3 stella_files.py find [--root DIR ...]
  python3 stella_files.py archive ZIP [--dest DIR] [--yes]
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path

STELLA_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DEST = STELLA_ROOT / "data" / "archive"
MAX_DEPTH = 2


def default_roots():
    home = Path.home()
    candidates = [
        home / "Downloads", home / "storage" / "downloads",
        Path("/sdcard/Download"), Path("/storage/emulated/0/Download"),
        home / "Desktop", home, Path.cwd(),
    ]
    roots, seen = [], set()
    for c in candidates:
        try:
            r = c.resolve()
        except OSError:
            continue
        if r.is_dir() and r not in seen:
            seen.add(r)
            roots.append(r)
    return roots


def iter_zips(root, depth=0):
    try:
        entries = list(os.scandir(root))
    except OSError:
        return
    for e in entries:
        try:
            if e.is_file(follow_symlinks=False) and e.name.lower().endswith(".zip"):
                yield Path(e.path)
            elif e.is_dir(follow_symlinks=False) and depth < MAX_DEPTH and not e.name.startswith("."):
                yield from iter_zips(e.path, depth + 1)
        except OSError:
            continue


def is_chatgpt_export(path):
    try:
        if not zipfile.is_zipfile(path):
            return False
        with zipfile.ZipFile(path) as zf:
            return any(
                Path(n).name.startswith("conversations") and n.lower().endswith(".json")
                for n in zf.namelist()
            )
    except (OSError, zipfile.BadZipFile):
        return False


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def unique_path(p):
    if not p.exists():
        return p
    i = 2
    while True:
        cand = p.with_name(f"{p.stem}-{i}{p.suffix}")
        if not cand.exists():
            return cand
        i += 1


def cmd_find(args):
    roots = [Path(r).expanduser() for r in args.root] if args.root else default_roots()
    found, seen = [], set()
    for root in roots:
        for z in iter_zips(root):
            rz = z.resolve()
            if rz not in seen:
                seen.add(rz)
                if is_chatgpt_export(rz):
                    found.append(rz)
    if not found:
        print("No ChatGPT export zip found in:")
        for r in roots:
            print(f"  {r}")
        print("Tip: pass the folder with --root, or give the zip path to 'archive'.")
        return 1
    print("ChatGPT export zips found (newest first):")
    for z in sorted(found, key=lambda p: p.stat().st_mtime, reverse=True):
        st = z.stat()
        when = datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
        print(f"  {z}   {human(st.st_size)}   modified {when}")
    return 0


def git_blocks_dest(dest):
    """True only if dest is inside a git repo and NOT ignored."""
    probe = dest
    while not probe.exists():
        probe = probe.parent
    try:
        r = subprocess.run(
            ["git", "-C", str(probe), "check-ignore", "-q", str(dest)],
            capture_output=True, timeout=15,
        )
        return r.returncode == 1
    except (OSError, subprocess.SubprocessError):
        return False


def cmd_archive(args):
    src = Path(args.zip).expanduser().resolve()
    if not src.is_file() or not is_chatgpt_export(src):
        print(f"ERROR: not a ChatGPT export zip: {src}", file=sys.stderr)
        return 1
    dest = Path(args.dest).expanduser().resolve() if args.dest else DEFAULT_DEST

    if git_blocks_dest(dest):
        print(f"STOP: {dest} is inside a git repo and is not git-ignored.\n"
              "Private chats could be pushed to GitHub. Add the folder to .gitignore first "
              "(for example a line:  /data/ ).", file=sys.stderr)
        return 1

    digest = sha256(src)
    if dest.is_dir():
        for m in dest.glob("*_manifest.json"):
            try:
                if json.loads(m.read_text("utf-8")).get("sha256") == digest:
                    print(f"Already archived (same contents): {m.name}. Nothing to do.")
                    return 0
            except (OSError, ValueError):
                pass

    stamp = datetime.fromtimestamp(src.stat().st_mtime).strftime("%Y-%m-%d")
    base = f"chatgpt-export_{stamp}"
    copy_path = unique_path(dest / f"{base}_original.zip")
    base = copy_path.name[: -len("_original.zip")]
    out_dir = dest / f"{base}_extracted"
    manifest_path = dest / f"{base}_manifest.json"

    with zipfile.ZipFile(src) as zf:
        members = zf.infolist()
        total_unzipped = sum(m.file_size for m in members)
    needed = src.stat().st_size + total_unzipped
    dest_probe = dest
    while not dest_probe.exists():
        dest_probe = dest_probe.parent
    free = shutil.disk_usage(dest_probe).free

    print("PLAN (nothing is deleted or changed in the original):")
    print(f"  Original : {src}  ({human(src.stat().st_size)})")
    print(f"  Copy to  : {copy_path}")
    print(f"  Unzip to : {out_dir}  ({len(members)} entries, {human(total_unzipped)} unzipped)")
    print(f"  Manifest : {manifest_path}")
    print(f"  Disk     : need about {human(needed)}, free {human(free)}")
    if needed * 1.1 > free:
        print("STOP: not enough free space.", file=sys.stderr)
        return 1
    if not args.yes and input("Proceed? [y/N] ").strip().lower() not in ("y", "yes"):
        print("Cancelled. Nothing was written.")
        return 0

    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, copy_path)
    if sha256(copy_path) != digest:
        print("ERROR: copy does not match the original (checksum). Stopping.", file=sys.stderr)
        return 1

    out_dir.mkdir(parents=True, exist_ok=False)
    out_root = out_dir.resolve()
    written = 0
    with zipfile.ZipFile(copy_path) as zf:  # unzip the COPY, never the original
        for m in zf.infolist():
            target = (out_root / m.filename).resolve()
            if out_root != target and out_root not in target.parents:
                print(f"Skipped unsafe path in zip: {m.filename}", file=sys.stderr)
                continue
            if m.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(m) as s, open(target, "wb") as d:
                shutil.copyfileobj(s, d)
            written += 1

    convo_files = sorted(
        str(p.relative_to(out_root)) for p in out_root.rglob("conversations*.json")
    )
    manifest = {
        "kind": "chatgpt-export",
        "original_name": src.name,
        "original_path": str(src),
        "sha256": digest,
        "size_bytes": src.stat().st_size,
        "archived_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "copy": str(copy_path),
        "extracted_dir": str(out_dir),
        "files_extracted": written,
        "conversation_files": convo_files,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", "utf-8")

    print("\nDone.")
    print(f"  Copy      : {copy_path}")
    print(f"  Extracted : {out_dir}  ({written} files)")
    print(f"  Chat files: {', '.join(convo_files) or 'none found'}")
    print(f"  Manifest  : {manifest_path}")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Stella file skill")
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("find", help="find ChatGPT export zips")
    f.add_argument("--root", action="append", help="folder to search (repeatable)")
    a = sub.add_parser("archive", help="copy + unzip the copy with clear names")
    a.add_argument("zip")
    a.add_argument("--dest")
    a.add_argument("--yes", action="store_true", help="skip the approval prompt")
    args = ap.parse_args()
    sys.exit(cmd_find(args) if args.cmd == "find" else cmd_archive(args))


if __name__ == "__main__":
    main()
