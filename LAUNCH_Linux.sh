#!/usr/bin/env bash
# ============================================================================
#  OpenLab Recorder — Linux launcher.
#  Run from a terminal in the cloned repo (./LAUNCH_Linux.sh) or double-click the
#  "OpenLab Recorder" entry that INSTALL_Linux.sh placed on your Desktop / menu.
#
#  What it does:
#    1. Resolves the repo dir from this file's own location.
#    2. Prefers the repo-local .venv created by the installer; falls back to a
#       system python3.
#    3. Runs launch.py — opens LabRecorder, then starts the bridge if the OpenBCI
#       dongle is present (otherwise just leaves LabRecorder running).
#    4. Keeps the terminal open on any exit so errors are readable.
# ============================================================================

# Keep the terminal open whatever happens (only matters when run interactively).
trap 'rc=$?; echo; echo "[exit code $rc]"; [ -t 0 ] && { echo "Press Enter to close..."; read -r _; }' EXIT

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

echo "[launcher] repo: $REPO"

# Prefer the installer's virtual environment; otherwise the first system python3.
PYTHON=""
if [ -x "$REPO/.venv/bin/python" ]; then
  PYTHON="$REPO/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="$(command -v python3)"
fi

if [ -z "$PYTHON" ]; then
  echo "[ERROR] No Python found. Run ./INSTALL_Linux.sh first to set things up."
  exit 11
fi
echo "[launcher] python: $PYTHON"

LAUNCH_FILE="$REPO/launch.py"
if [ ! -f "$LAUNCH_FILE" ]; then
  echo "[ERROR] launch.py missing at: $LAUNCH_FILE"
  echo "Is this the OpenLab Recorder repo root?"
  exit 12
fi
echo "[launcher] script: $LAUNCH_FILE"
echo

"$PYTHON" "$LAUNCH_FILE" "$@"
