#!/usr/bin/env python3
"""
stella-launcher - makes ONE word, `stella`, open Stella from any folder.

Plain words: this file creates a tiny starter file named `stella` and tells your computer where to find it.
Then you type `stella` anywhere (PowerShell, cmd, Ubuntu/Debian in WSL, Termux) and she opens.
It only ADDS a file. It refuses to touch any `stella` file that it did not make itself.

  python3 stella-launcher.py --install-command      create the `stella` word            (undo: --uninstall-command)
  python3 stella-launcher.py --add-path             make sure your computer can find it (asks you to type yes first)
  python3 stella-launcher.py --setup                both of the above in one go (add --yes to skip the PATH question)
  python3 stella-launcher.py --desktop              put a "Stella" start icon on your Desktop (double-click to open her)
  python3 stella-launcher.py --full-setup           everything for a first install: word + PATH + free helper packages
                                                    + Desktop icon + health check (add --yes to say yes to all of it)
  python3 stella-launcher.py --install-command --replace
                                                    replace a DIFFERENT old `stella` (asks yes; keeps a backup copy)

Once installed:
  stella                open the new Stella (colors, saved chats)
  stella --continue     open your latest chat again
  stella classic        open your earlier screen (stella-live) exactly as it was
  stella doctor         check everything and say what is wrong in plain words
"""
import os
import platform
import shlex
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
SELF = Path(__file__).resolve()
ROOT = Path(os.environ.get("STELLA_HOME") or HERE.parents[2]).resolve()
MARK = "stella-launcher"
NAME = "stella"
UI, CLASSIC = HERE / "stella-ui.py", HERE / "stella-live.py"
ASSUME_YES = False
BASHRC_LINE = 'export PATH="$HOME/.local/bin:$PATH"  # added by stella-launcher'


def kind():
    if os.name == "nt":
        return "windows"
    if "com.termux" in os.environ.get("PREFIX", ""):
        return "termux"
    if "microsoft" in platform.release().lower():
        return "wsl"
    return "posix"


def target_for(name=NAME):
    k = kind()
    if k == "windows":
        return Path.home() / "bin" / (name + ".cmd")
    if k == "termux":
        return Path(os.environ["PREFIX"]) / "bin" / name
    return Path.home() / ".local" / "bin" / name


def on_path(folder):
    want = os.path.normcase(os.path.normpath(str(folder)))
    return any(os.path.normcase(os.path.normpath(p)) == want for p in os.environ.get("PATH", "").split(os.pathsep) if p)


def ours(path):
    try:
        return MARK in path.read_text(errors="ignore")
    except OSError:
        return False


def ask_yes(lines):
    print()
    for ln in lines:
        print("  " + ln)
    try:
        return input("  Type yes to continue (anything else cancels): ").strip().lower() == "yes"
    except EOFError:
        return False


def wrapper_text(k):
    if k == "windows":
        return (f"@echo off\r\nrem {MARK}\r\nset \"STELLA_HOME={ROOT}\"\r\nwhere py >nul 2>nul\r\n"
                f"if %errorlevel%==0 (\r\n  py -3 \"{SELF}\" %*\r\n) else (\r\n  python \"{SELF}\" %*\r\n)\r\n"
                f"exit /b %errorlevel%\r\n")
    sh = f"{os.environ['PREFIX']}/bin/sh" if k == "termux" else "/bin/sh"
    return (f"#!{sh}\n# {MARK}\nSTELLA_HOME={shlex.quote(str(ROOT))}\nexport STELLA_HOME\n"
            f"exec python3 {shlex.quote(str(SELF))} \"$@\"\n")


def install(name, replace, quiet=False):
    k, target = kind(), target_for(name)
    if target.exists() and not ours(target):
        if not replace:
            print(f"STOP: {target} already exists and is not mine. I will not touch it.\n"
                  f"  Choices: use another word (--name stella2), or ask to replace it with --replace\n"
                  f"  (replacing asks you to type yes and keeps a backup copy).")
            return 1
        if not ask_yes([f"An older '{name}' already exists here:", f"   {target}",
                        "I will RENAME it to keep it safe (not delete it), then put my starter in its place.",
                        f"You can undo by deleting mine and renaming the backup back to '{target.name}'."]):
            print("\nCancelled. Nothing was changed.")
            return 1
        backup = target.with_name(target.name + ".original-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
        target.rename(backup)
        print(f"  Old one kept as: {backup}")
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "w", newline="") as f:
        f.write(wrapper_text(k))
    if k != "windows":
        target.chmod(0o755)
    print(f"Installed: {target}")
    if quiet:
        return 0
    if on_path(target.parent):
        print(f"Open a NEW window and type:  {name}")
    else:
        print(f"\nOne more step: your computer cannot find that folder yet ({target.parent}).")
        print("Run this and I will do it for you (it asks you first):")
        print(f"  {'py -3' if k == 'windows' else 'python3'} \"{SELF}\" --add-path")
    return 0


def uninstall(name):
    target = target_for(name)
    if not target.exists():
        print("Nothing to remove.")
        return 0
    if not ours(target):
        print(f"STOP: {target} is not mine. I will not touch it.")
        return 1
    target.unlink()
    print(f"Removed: {target}")
    return 0


def add_path():
    k, folder = kind(), target_for().parent
    if k == "termux":
        print("Termux already looks in its own bin folder. Nothing to do.")
        return 0
    if k == "windows":
        ps = ["powershell", "-NoProfile", "-Command"]
        try:
            cur = subprocess.run(ps + ["[Environment]::GetEnvironmentVariable('Path','User')"],
                                 capture_output=True, text=True, timeout=30).stdout.strip()
        except (OSError, subprocess.SubprocessError) as e:
            print(f"I could not read your PATH ({e}). Nothing was changed.")
            return 1
        if any(os.path.normcase(os.path.normpath(p)) == os.path.normcase(os.path.normpath(str(folder)))
               for p in cur.split(";") if p):
            print(f"{folder} is already on your PATH. Open a NEW window and type: {NAME}")
            return 0
        if not ASSUME_YES and not ask_yes([f"I will add this folder to YOUR user PATH (only your account): {folder}",
                        "It is saved in Windows settings. Undo: Settings > search 'environment variables' > Path > remove it."]):
            print("\nCancelled. Nothing was changed.")
            return 1
        cmd = ("[Environment]::SetEnvironmentVariable('Path',"
               "[Environment]::GetEnvironmentVariable('Path','User')+';'+$env:USERPROFILE+'\\bin','User')")
        r = subprocess.run(ps + [cmd], capture_output=True, text=True)
        print("Done. Open a NEW PowerShell window and type:  " + NAME if r.returncode == 0
              else f"That did not work: {r.stderr.strip()}")
        return r.returncode
    rc = Path.home() / ".bashrc"
    if shell_is_zsh():
        rc = Path.home() / ".zshrc"
    text = rc.read_text(errors="ignore") if rc.exists() else ""
    if "added by stella-launcher" in text:
        print(f"{rc} already has the line. Open a new window (or run: source {rc}) and type: {NAME}")
        return 0
    if not ASSUME_YES and not ask_yes([f"I will add ONE line to the end of {rc}:", f"   {BASHRC_LINE}",
                    f"A backup copy is saved first. Undo: delete that line, or copy the backup back."]):
        print("\nCancelled. Nothing was changed.")
        return 1
    if rc.exists():
        shutil.copy2(rc, rc.with_name(rc.name + ".stella-backup-" + datetime.now().strftime("%Y%m%d-%H%M%S")))
    with open(rc, "a", encoding="utf-8") as f:
        f.write(("\n" if text and not text.endswith("\n") else "") + BASHRC_LINE + "\n")
    print(f"Done. Open a NEW window (or run: source {rc}) and type:  {NAME}")
    return 0


def pip_install(pkg):
    """Install a free helper package for this user only. Never fatal. Returns True when it worked."""
    base = [sys.executable, "-m", "pip", "install", "--user", "--quiet", pkg]
    try:
        r = subprocess.run(base, capture_output=True, text=True, timeout=600)
        if r.returncode != 0 and "externally-managed" in (r.stdout + r.stderr):
            r = subprocess.run(base + ["--break-system-packages"], capture_output=True, text=True, timeout=600)
        if r.returncode != 0 and "No module named pip" in (r.stdout + r.stderr):
            print("    pip is missing. On Debian/Ubuntu run:  sudo apt install python3-pip   (then run me again)")
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def yes_no(question):
    if ASSUME_YES:
        return True
    try:
        return input(f"  {question} [Y/n] ").strip().lower() in ("", "y", "yes")
    except EOFError:
        return False


def desktop_folder():
    k = kind()
    if k == "windows":
        try:   # the Desktop can be redirected (for example into OneDrive), so ask Windows where it is
            out = subprocess.run(["powershell", "-NoProfile", "-Command", "[Environment]::GetFolderPath('Desktop')"],
                                 capture_output=True, text=True, timeout=30).stdout.strip()
            if out:
                return Path(out)
        except (OSError, subprocess.SubprocessError):
            pass
        return Path.home() / "Desktop"
    if k == "termux":
        return Path.home() / ".shortcuts"          # the folder the free Termux:Widget app reads
    return Path.home() / "Desktop"


def desktop_file(k):
    """(file name, text) of the double-click starter for this kind of computer."""
    if k == "windows":
        text = (f"@echo off\r\nrem {MARK}\r\ntitle Stella\r\nset \"STELLA_HOME={ROOT}\"\r\nwhere py >nul 2>nul\r\n"
                f"if %errorlevel%==0 (\r\n  py -3 \"{SELF}\" %*\r\n) else (\r\n  python \"{SELF}\" %*\r\n)\r\n"
                f"if errorlevel 1 pause\r\n")
        return "Stella.cmd", text
    if k == "termux":
        sh = f"{os.environ.get('PREFIX', '/usr')}/bin/sh"
        return "Stella", (f"#!{sh}\n# {MARK}\nSTELLA_HOME={shlex.quote(str(ROOT))}\nexport STELLA_HOME\n"
                          f"exec python3 {shlex.quote(str(SELF))} \"$@\"\n")
    return "Stella.desktop", (f"[Desktop Entry]\n# {MARK}\nType=Application\nName=Stella\nComment=Open Stella\n"
                              f"Exec=env STELLA_HOME={shlex.quote(str(ROOT))} python3 {shlex.quote(str(SELF))}\n"
                              f"Terminal=true\nIcon=utilities-terminal\n")


def desktop():
    k = kind()
    folder = desktop_folder()
    name, text = desktop_file(k)
    target = folder / name
    if target.exists() and not ours(target):
        print(f"STOP: {target} already exists and is not mine. I will not touch it.")
        return 1
    try:
        folder.mkdir(parents=True, exist_ok=True)
        with open(target, "w", newline="") as f:
            f.write(text)
        if k != "windows":
            target.chmod(0o755)
    except OSError as e:
        print(f"I could not create the shortcut ({e}). Nothing else was changed.")
        return 1
    print(f"Desktop starter created: {target}")
    if k == "termux":
        print("  It appears in the free 'Termux:Widget' app (install it from F-Droid, then add its widget to your home screen).")
    elif k == "posix" or k == "wsl":
        print("  If your desktop asks, right-click it and choose 'Allow Launching'.")
    return 0


def full_setup():
    print(f"\nStella full setup ({kind()}). I only add things, and I ask first.\n")
    if yes_no("Make the word 'stella' work from any folder?"):
        rc = install(NAME, False, quiet=True)
        if rc == 0:
            add_path()
        else:
            print("    (The 'stella' word was not set up. Details are above.)")
    try:
        import prompt_toolkit  # noqa: F401
        print("  live '/' menu package: already installed")
    except ImportError:
        if yes_no("Install the free package for the live '/' menu?"):
            print("  installing prompt_toolkit ...", end=" ", flush=True)
            print("done" if pip_install("prompt_toolkit") else "skipped (Stella works without it; type /help)")
    if kind() == "windows":
        try:
            import keyring  # noqa: F401
        except ImportError:
            print("  installing the Windows secure store helper ...", end=" ", flush=True)
            print("done" if pip_install("keyring") else "skipped (Stella will use a locked file instead)")
    if yes_no("Put a 'Stella' start icon on your Desktop?"):
        desktop()
    doctor()
    return 0


def shell_is_zsh():
    return os.environ.get("SHELL", "").endswith("zsh")


def doctor():
    ok = True

    def line(good, text):
        nonlocal ok
        ok = ok and good
        print(f"  [{'OK ' if good else '!! '}] {text}")
    print(f"\nStella doctor  ({kind()}, Python {platform.python_version()})")
    line(True, f"Stella lives in: {ROOT}")
    line(UI.is_file(), "new screen file (stella-ui.py) " + ("found" if UI.is_file() else "MISSING: run the newest stella-bundle again"))
    line(CLASSIC.is_file(), "earlier screen file (stella-live.py) " + ("found" if CLASSIC.is_file() else "MISSING"))
    key = ROOT / "config" / "providers.env"
    has_key = key.is_file() and "STELLA_GEMINI_API_KEY=" in key.read_text(errors="ignore")
    vault = ROOT / "data" / "vault" / "index.json"
    has_vault = vault.is_file() and "gemini" in vault.read_text(errors="ignore")
    line(True, "Gemini key " + ("found (value not shown)" if has_key or has_vault else
                                "not added yet: Stella asks for it the first time she opens (or type /connect)"))
    try:
        import prompt_toolkit  # noqa: F401
        line(True, "live '/' menu package (prompt_toolkit) installed")
    except ImportError:
        line(True, "live '/' menu not installed (optional): " + ("py -m pip install prompt_toolkit" if kind() == "windows"
                                                               else "python3 -m pip install prompt_toolkit"))
    found = shutil.which(NAME)
    t = target_for()
    fresh = bool(not found and t.exists() and ours(t))      # installed a moment ago: this window just has not seen it
    line(bool(found) or fresh, f"the word '{NAME}' is found at: {found}" if found else
         (f"the word '{NAME}' is installed; open a NEW terminal window and type: {NAME}" if fresh else
          f"the word '{NAME}' is not found from here yet (run --install-command, then --add-path)"))
    if t.exists() and not ours(t):
        line(False, f"{t} is an older '{NAME}' that is NOT mine, so it runs instead of Stella's new one")
    print("\n  Everything looks fine." if ok else "\n  Fix the [!!] lines above, then run: stella doctor again.")
    return 0 if ok else 1


def run(face, extra):
    if not face.is_file():
        print(f"I cannot find {face.name}. Run: stella doctor")
        return 1
    env = dict(os.environ, STELLA_HOME=str(ROOT))
    try:
        return subprocess.call([sys.executable, str(face), *extra], env=env)
    except KeyboardInterrupt:
        return 130


def main(argv):
    flags = {a for a in argv if a.startswith("--")}
    name = NAME
    if "--name" in argv and argv.index("--name") + 1 < len(argv):
        name = argv[argv.index("--name") + 1]
    global ASSUME_YES
    ASSUME_YES = "--yes" in flags
    if "--full-setup" in flags:
        return full_setup()
    if "--desktop" in flags:
        return desktop()
    if "--setup" in flags:
        rc = install(name, False, quiet=True)
        return rc if rc else add_path()
    if "--install-command" in flags:
        return install(name, "--replace" in flags)
    if "--uninstall-command" in flags:
        return uninstall(name)
    if "--add-path" in flags:
        return add_path()
    if argv and argv[0] == "doctor":
        return doctor()
    if argv and argv[0] == "classic":
        return run(CLASSIC, argv[1:])
    if argv and argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    return run(UI if UI.is_file() else CLASSIC, argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
