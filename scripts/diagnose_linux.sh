#!/usr/bin/env bash
# diagnose_linux.sh — one-look health check for OpenLab Recorder on Linux.
#
# Prints, in a single block, both halves needed to explain "it doesn't work":
#   1. Python dependency imports (brainflow, pylsl, pyserial, pyxdf)
#   2. USB / serial-dongle state (dongle USB id, /dev/ttyUSB*|ttyACM* node,
#      brltty hijack, dialout group membership)
#
# Pure reporting: it never changes anything and always exits 0. Run it any time,
# with or without a full install:
#     bash scripts/diagnose_linux.sh
#
# The installer (scripts/install_linux.sh) calls this automatically at the end,
# and also on a dependency-import failure, so a coworker sees the whole picture
# in one run.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$REPO/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3 2>/dev/null || true)"

line() { printf '%s\n' "--------------------------------------------------------------------"; }

line
echo " OpenLab Recorder — Linux self-diagnostic"
line

# --- environment ---
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo " distro : ${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-}}  (arch $(uname -m))"
fi
echo " python : ${PY:-<none found>}"
[ -n "${PY:-}" ] && [ -x "$PY" ] && echo "          $("$PY" --version 2>&1)"
echo

# --- 1. Python dependencies ---
echo " [1] Python dependencies"
if [ -n "${PY:-}" ] && [ -x "$PY" ]; then
  "$PY" - <<'PYEOF'
import importlib
checks = [
    ("brainflow", "brainflow"),
    ("pylsl",     "pylsl (needs native liblsl)"),
    ("serial",    "pyserial (USB auto-detect)"),
    ("pyxdf",     "pyxdf"),
]
for mod, label in checks:
    try:
        importlib.import_module(mod)
        print(f"     [ok]   {label}")
    except Exception as e:
        print(f"     [FAIL] {label}: {type(e).__name__}: {e}")
PYEOF
else
  echo "     [FAIL] no Python interpreter / .venv — run ./INSTALL_Linux.sh first"
fi
echo

# --- 2. USB / serial dongle ---
echo " [2] USB / serial dongle"

# 2a. dongle on the USB bus (best-effort; lsusb is optional)
if command -v lsusb >/dev/null 2>&1; then
  if lsusb | grep -qiE '0403:6015'; then
    echo "     [ok]   genuine OpenBCI FTDI dongle (0403:6015) on USB"
  elif lsusb | grep -qiE '0483:5741'; then
    echo "     [~]    OpenBCI STM32 clone (0483:5741) on USB — comes up as /dev/ttyACM*"
  else
    echo "     [~]    no known OpenBCI USB id (0403:6015 / 0483:5741) seen by lsusb"
  fi
else
  echo "     [..]   lsusb not installed (optional) — skipping USB-id check"
fi

# 2b. serial node present
nodes="$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' ')"
if [ -n "$nodes" ]; then
  echo "     [ok]   serial node present: $nodes"
else
  echo "     [FAIL] no /dev/ttyUSB* or /dev/ttyACM* — dongle unplugged, or grabbed by brltty (below)"
fi

# 2c. brltty (hijacks the FTDI dongle on Ubuntu/Mint)
if dpkg -s brltty >/dev/null 2>&1; then
  echo "     [FAIL] brltty STILL installed — it hijacks the dongle. Fix: sudo apt-get remove -y brltty  (then replug)"
else
  echo "     [ok]   brltty not present"
fi

# 2d. dialout membership (needed to OPEN the port)
me="$(id -un 2>/dev/null || echo "$USER")"
if id -nG "$me" 2>/dev/null | tr ' ' '\n' | grep -qx dialout; then
  echo "     [ok]   user '$me' is in the dialout group"
else
  echo "     [FAIL] user '$me' NOT in dialout. Fix: sudo usermod -aG dialout $me   then log out/in (or: newgrp dialout)"
fi

echo

# --- 3. LabRecorder GUI (Qt6) ---
echo " [3] LabRecorder GUI (Qt6 runtime)"
LR="$(find "$REPO/vendor/LabRecorder" -type f -name 'LabRecorder' 2>/dev/null | head -1)"
if [ -z "$LR" ]; then
  echo "     [~]    LabRecorder not downloaded yet — run ./INSTALL_Linux.sh"
elif command -v ldd >/dev/null 2>&1; then
  missing="$(ldd "$LR" 2>/dev/null | awk '/not found/{print $1}' | tr '\n' ' ')"
  if [ -n "$missing" ]; then
    echo "     [FAIL] LabRecorder is missing shared libraries: $missing"
    echo "            (this is why the launcher runs but no window opens). Fix:"
    echo "            sudo apt-get install -y libqt6widgets6t64 libqt6network6t64 qt6-qpa-plugins libxcb-cursor0"
  else
    echo "     [ok]   LabRecorder's shared libraries all resolve (Qt6 GUI runtime present)"
  fi
else
  echo "     [..]   ldd not available — cannot check LabRecorder libraries"
fi

line
echo " Any [FAIL] above is the thing to fix; the hint after it is the command."
line
exit 0
