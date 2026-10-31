#!/usr/bin/env python3
"""
install.py - the one install step after `git clone`. Same on Windows, WSL/Linux and Termux.

  git clone https://github.com/PrinceKTN/stella
  cd stella
  py -3 install.py        (Windows)        python3 install.py        (Linux / WSL / Termux)

It only ADDS things and asks before each one: the word `stella`, the PATH line, two small free helper
packages, and an optional Desktop icon. Then it opens Stella. Nothing existing is overwritten.
  --yes       answer yes to every question
  --no-start  install but do not open Stella afterwards
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LAUNCHER = ROOT / "core" / "interfaces" / "terminal" / "stella-launcher.py"


def main(argv):
    if sys.version_info < (3, 8):
        print("Stella needs Python 3.8 or newer. Install Python, then run this again.")
        return 1
    if not LAUNCHER.is_file():
        print("I cannot find the launcher. Run this from inside the stella folder you cloned.")
        return 1
    env = dict(os.environ, STELLA_HOME=str(ROOT))
    args = [sys.executable, str(LAUNCHER), "--full-setup"] + (["--yes"] if "--yes" in argv else [])
    rc = subprocess.call(args, env=env)
    if rc != 0:
        print("\nSetup finished with notes above. You can run it again any time; it is safe to repeat.")
    if "--no-start" in argv:
        return rc
    print("\nOpening Stella now. (Next time just type: stella  -- open a NEW terminal window first.)\n")
    return subprocess.call([sys.executable, str(LAUNCHER)], env=env)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
