#!/bin/sh
# Stella installer for Linux, WSL and Termux. Safe to run again. Adds only; asks first.
cd "$(dirname "$0")" || exit 1
PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "Python is missing."
  if command -v pkg >/dev/null 2>&1; then echo "Termux: run  pkg install python  then  sh install.sh";
  else echo "Debian/Ubuntu: run  sudo apt install python3  then  sh install.sh"; fi
  exit 1
fi
exec "$PY" install.py "$@"
