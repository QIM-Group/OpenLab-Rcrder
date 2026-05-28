#!/bin/bash
# ============================================================================
#  OpenLab Recorder — macOS launcher.
#  Double-click this file in Finder from the cloned repo. macOS opens
#  Terminal and runs it. No Desktop launcher needed.
#
#  What it does:
#    1. Resolves the repo dir from this file's own location.
#    2. Finds python3 via a priority list (brew python@3.12, brew python3,
#       /usr/local/bin/python3, /usr/bin/python3, PATH).
#    3. Runs launch.py — which opens LabRecorder, then starts the bridge
#       if a dongle is present (otherwise just leaves LabRecorder running).
#    4. Keeps Terminal open on any exit so errors are readable.
# ============================================================================

# Keep Terminal open whatever happens
trap 'rc=$?; echo; echo "[exit code $rc]"; echo "Press Enter to close..."; read -r _' EXIT

# Repo dir = this file's directory (works regardless of cwd or how Finder invoked it)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

echo "[launcher] repo: $REPO"

# Find a usable python3 — checked in preference order
PYTHON=""
for candidate in \
    "/opt/homebrew/opt/python@3.12/bin/python3.12" \
    "/usr/local/opt/python@3.12/bin/python3.12" \
    "/opt/homebrew/bin/python3" \
    "/usr/local/bin/python3" \
    "/usr/bin/python3"; do
  if [ -x "$candidate" ]; then
    PYTHON="$candidate"
    break
  fi
done
if [ -z "$PYTHON" ] && command -v python3 >/dev/null 2>&1; then
  PYTHON="$(command -v python3)"
fi

if [ -z "$PYTHON" ]; then
  echo "[ERROR] No python3 found. Run INSTALL_macOS.command first to install Python."
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
