#!/usr/bin/env bash
# ============================================================================
#  OpenLab Recorder — one-click installer for Linux (Ubuntu 24.04 / Noble).
#
#  Run it from a terminal in the cloned repo:
#      ./INSTALL_Linux.sh
#  (or:  bash INSTALL_Linux.sh)
#
#  What it does (calls scripts/install_linux.sh which holds the real logic):
#    1. apt-installs python3 + python3-venv + python3-pip.
#    2. Creates a repo-local .venv (Ubuntu 24.04 forbids pip into system Python).
#    3. Runs install.py (pip deps + LabRecorder download into vendor/).
#    4. Installs the native liblsl library if pylsl can't find it.
#    5. Creates a double-click "OpenLab Recorder" launcher on the Desktop and in
#       the applications menu.
#
#  The window stays open at the end (when run interactively) so you can read any
#  error output.
# ============================================================================

set -e

# Resolve repo dir from this file's own location, regardless of cwd.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

echo "[+] OpenLab Recorder — Linux installer"
echo "[+] Repo: $REPO"
echo

EXITCODE=0
bash "$REPO/scripts/install_linux.sh" || EXITCODE=$?

echo
if [ "$EXITCODE" -eq 0 ]; then
  echo "[SUCCESS] OpenLab Recorder installed. Look for the icon on your Desktop / menu."
else
  echo "[ERROR] Installer exited with code $EXITCODE. Scroll up to see what went wrong."
fi
echo

# Keep the window open only when attached to a terminal (avoids hanging in CI /
# non-interactive invocations).
if [ -t 0 ]; then
  echo "Press Enter to close this window..."
  read -r _
fi
exit "$EXITCODE"
