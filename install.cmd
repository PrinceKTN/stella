@echo off
rem Stella installer for Windows. Safe to run again. Adds only; asks first.
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 install.py %*
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo Python is missing. Install it from https://www.python.org/downloads/ ^(tick "Add python.exe to PATH"^), then run install.cmd again.
    pause
    exit /b 1
  )
  python install.py %*
)
