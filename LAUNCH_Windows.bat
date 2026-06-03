@echo off
REM ============================================================================
REM  OpenLab Recorder — Windows launcher.
REM  Double-click this file in the cloned repo. It opens LabRecorder and starts
REM  the bridge. (INSTALL_Windows.bat also creates a Desktop shortcut; this file
REM  is the always-available launcher that lives in the repo itself.)
REM
REM  What it does:
REM    1. Finds Python (py.exe launcher first, then python.exe on PATH).
REM    2. Runs launch.py — opens LabRecorder, then starts the bridge if the
REM       OpenBCI dongle is present (otherwise just leaves LabRecorder running).
REM    3. Keeps the window open on exit so any error is readable.
REM ============================================================================

setlocal
cd /d "%~dp0"

REM Prefer the py launcher (handles version selection); fall back to python.exe.
set "PYTHON="
where py.exe >nul 2>&1 && set "PYTHON=py.exe"
if not defined PYTHON (
  where python.exe >nul 2>&1 && set "PYTHON=python.exe"
)

if not defined PYTHON (
  echo [ERROR] No Python found on PATH. Run INSTALL_Windows.bat first to install Python.
  echo.
  pause
  exit /b 11
)

if not exist "%~dp0launch.py" (
  echo [ERROR] launch.py missing in this folder. Is this the OpenLab Recorder repo root?
  echo.
  pause
  exit /b 12
)

echo [launcher] python: %PYTHON%
echo [launcher] script: %~dp0launch.py
echo.

"%PYTHON%" "%~dp0launch.py" %*
set EXITCODE=%ERRORLEVEL%

echo.
echo [exit code %EXITCODE%]
pause
endlocal
exit /b %EXITCODE%
