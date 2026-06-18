#!/usr/bin/env bash
# install_linux.sh — one-click installer for OpenLab Recorder on Ubuntu 24.04 (Noble).
#
# Called by INSTALL_Linux.sh at the repo root. Can also be run directly:
#     bash scripts/install_linux.sh
#
# Target: Ubuntu 24.04 LTS (Noble Numbat), amd64. It also works on other recent
# Debian/Ubuntu derivatives that ship apt + Python 3.12; on non-apt distributions
# it stops early with manual-install guidance.
#
# Why each step exists:
#
#   1. apt packages — Ubuntu 24.04 ships Python 3.12 as /usr/bin/python3, but the
#      pip and venv modules live in separate apt packages (python3-pip,
#      python3-venv). ca-certificates is needed for the HTTPS downloads below.
#
#   2. Virtual environment — Ubuntu 23.04+ marks the system Python as
#      "externally managed" (PEP 668). `pip install` into it fails with
#      "error: externally-managed-environment". We create a repo-local .venv so
#      dependencies install cleanly without --break-system-packages and without
#      touching system Python. LAUNCH_Linux.sh prefers this same .venv.
#
#   3. install.py — pip deps + the Noble LabRecorder build download into vendor/.
#
#   4. liblsl — pylsl needs the native liblsl shared library. The pip wheel may
#      or may not bundle it on Linux, so we verify `import pylsl` and, only if it
#      fails, fetch the matching liblsl .deb from the sccn/liblsl releases. This
#      is best-effort: if the asset name has changed upstream, the script points
#      you at the releases page and the conda-forge fallback.
#
#   5b. Serial access — brltty (the default braille service) hijacks the FTDI
#      dongle on Ubuntu/Mint so /dev/ttyUSB* never persists; we remove it. The
#      user is added to the 'dialout' group so BrainFlow can open the port.
#
#   6. Desktop launcher — a .desktop entry (Terminal=true) so OpenLab Recorder is
#      double-clickable from the desktop and the applications menu. Bare .sh files
#      are not reliably double-clickable across Linux desktop environments, so the
#      .desktop file is the correct native affordance.

set -euo pipefail

err()  { printf '[!] %s\n' "$*" >&2; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[~] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------- 0. Sanity ----------
if [[ "$(uname -s)" != "Linux" ]]; then
  err "This installer is for Linux. uname -s reports: $(uname -s)"
  err "On Windows use INSTALL_Windows.bat. On macOS use INSTALL_macOS.command."
  exit 1
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# Distro / version report (informational; we do not hard-block non-Ubuntu).
DISTRO="unknown"; VERSION="unknown"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO="${ID:-unknown}"; VERSION="${VERSION_ID:-unknown}"
fi
ok "Linux distro: ${DISTRO} ${VERSION} (arch: $(uname -m))"
if [[ "$DISTRO" != "ubuntu" || "$VERSION" != "24.04" ]]; then
  warn "Tested target is Ubuntu 24.04. Detected ${DISTRO} ${VERSION} — continuing,"
  warn "but apt package and liblsl steps may need manual adjustment."
fi

# ---------- 0b. sudo helper ----------
# The end user running this on their own desktop has a terminal, so a normal
# sudo password prompt is expected and fine.
if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
elif have sudo; then
  SUDO="sudo"
  ok "Some steps need root via sudo — you may be prompted for your password."
else
  err "Not running as root and sudo is not installed. Install sudo or re-run as root."
  exit 2
fi

# ---------- 1. apt packages ----------
if ! have apt-get; then
  err "apt-get not found — this installer targets Debian/Ubuntu."
  err "On another distribution, install Python 3.12 + pip + venv with your package"
  err "manager, then run:  python3 -m venv .venv && .venv/bin/python install.py"
  exit 3
fi

ok "Updating apt package index..."
$SUDO apt-get update -y

ok "Installing python3, python3-venv, python3-pip, ca-certificates..."
$SUDO apt-get install -y python3 python3-venv python3-pip ca-certificates

# LabRecorder (the recording window) is a Qt6 application and bundles NO Qt of
# its own — its binary is dynamically linked against libQt6Widgets/Gui/Core/Network
# plus the xcb platform plugin. A fresh Ubuntu 24.04 / Mint 22.x ships none of
# these, so LabRecorder exits instantly with no window ("launcher runs in the
# terminal but no GUI appears"). On noble the Qt6 packages carry the t64 suffix.
ok "Installing LabRecorder's Qt6 GUI runtime (Qt6 widgets/network + xcb plugin)..."
$SUDO apt-get install -y libqt6widgets6t64 libqt6network6t64 qt6-qpa-plugins libxcb-cursor0 \
  || warn "Qt6 runtime install failed — LabRecorder's window may not open (see scripts/diagnose_linux.sh)."

PYBASE="$(command -v python3)"
ok "System Python: $PYBASE ($("$PYBASE" --version 2>&1))"

# ---------- 2. Virtual environment (PEP 668 work-around) ----------
VENV="$REPO/.venv"
if [[ -x "$VENV/bin/python" ]]; then
  ok "Virtual environment already present: $VENV"
else
  ok "Creating virtual environment at $VENV ..."
  "$PYBASE" -m venv "$VENV"
fi
PYTHON="$VENV/bin/python"
ok "Upgrading pip inside the virtual environment..."
"$PYTHON" -m pip install --quiet --upgrade pip

# ---------- 3. install.py (pip deps + LabRecorder download) ----------
ok "Running install.py (pip dependencies + LabRecorder download)..."
"$PYTHON" "$REPO/install.py"

# Ensure the downloaded LabRecorder binary is executable (tar should preserve the
# bit, but make it robust against extraction quirks).
VENDOR="$REPO/vendor/LabRecorder"
if [[ -d "$VENDOR" ]]; then
  while IFS= read -r -d '' f; do chmod +x "$f" 2>/dev/null || true; done \
    < <(find "$VENDOR" -type f -name 'LabRecorder' -print0 2>/dev/null)
fi

# ---------- 4. liblsl: verify, then fetch only if pylsl import fails ----------
LIBLSL_VER="1.16.2"
LIBLSL_DEB="liblsl-${LIBLSL_VER}-noble_amd64.deb"
LIBLSL_URL="https://github.com/sccn/liblsl/releases/download/v${LIBLSL_VER}/${LIBLSL_DEB}"

pylsl_ok() { "$PYTHON" -c "import pylsl" >/dev/null 2>&1; }

if pylsl_ok; then
  ok "pylsl imports cleanly (liblsl already available)."
else
  warn "pylsl could not import liblsl — installing the native library..."
  TMPDEB="$(mktemp -d)/${LIBLSL_DEB}"
  if "$PYTHON" - "$LIBLSL_URL" "$TMPDEB" <<'PYEOF'
import ssl, sys, urllib.request
try:
    import certifi
    ctx = ssl.create_default_context(cafile=certifi.where())
except Exception:
    ctx = ssl.create_default_context()
url, dest = sys.argv[1], sys.argv[2]
urllib.request.urlretrieve(url, dest)
print(dest)
PYEOF
  then
    ok "Downloaded ${LIBLSL_DEB}; installing with dpkg..."
    $SUDO dpkg -i "$TMPDEB" || $SUDO apt-get install -f -y
  else
    warn "Could not download ${LIBLSL_DEB} (asset name may have changed upstream)."
  fi
  if ! pylsl_ok; then
    warn "liblsl still not importable. Manual fallbacks:"
    warn "    - Newest .deb:   ${LIBLSL_URL%/*}  (pick the *noble_amd64.deb)"
    warn "    - conda-forge:   conda install -c conda-forge liblsl"
    warn "    - build source:  https://github.com/sccn/liblsl#build"
  fi
fi

# ---------- 5. Verify every runtime dependency actually imports ----------
ok "Verifying every runtime dependency imports cleanly..."
VERIFY_OUTPUT=$("$PYTHON" - <<'PYEOF' 2>&1
import importlib, sys
checks = [
    ("brainflow", "BrainFlow"),
    ("pylsl",     "pylsl (needs liblsl native lib)"),
    ("serial",    "pyserial"),
    ("pyxdf",     "pyxdf"),
]
failed = []
for mod, label in checks:
    try:
        importlib.import_module(mod)
        print(f"  [ok]   {label}")
    except Exception as e:
        print(f"  [FAIL] {label}: {type(e).__name__}: {e}")
        failed.append((mod, e))
sys.exit(1 if failed else 0)
PYEOF
)
echo "$VERIFY_OUTPUT"
if echo "$VERIFY_OUTPUT" | grep -q "\[FAIL\]"; then
  err "One or more runtime dependencies failed to import."
  err "Most common cause on Linux: liblsl not found (see the liblsl step above)."
  echo
  warn "Full self-diagnostic (dependencies + serial/dongle state):"
  bash "$REPO/scripts/diagnose_linux.sh" || true
  exit 6
fi
ok "All runtime dependencies verified."

# ---------- 5b. Serial-port access: brltty FTDI grab + dialout group ----------
# Two failure modes specific to the OpenBCI FTDI dongle (USB ID 0403:6015) on
# Ubuntu/Mint that otherwise stop the bridge dead, fixed here so a fresh machine
# works without manual follow-up:
#
#   - brltty (a braille service installed by default) claims FT231X-class FTDI
#     adapters the instant they are plugged in, so /dev/ttyUSB* appears then
#     vanishes and the launcher reports "No serial dongle detected."
#     (Ubuntu bug #1976534.) Removing the package deletes the udev rule that does
#     the grab; masking the service alone does not. This tool exists to talk to an
#     FTDI serial dongle, so brltty's serial grab is pure interference here.
#
#   - Opening /dev/ttyUSB* requires membership in the 'dialout' group; without it
#     BrainFlow fails prepare_session() with "unable to open port".

NEED_RELOGIN=0

if have lsusb && lsusb | grep -qiE '0403:6015|FT231X'; then
  ok "OpenBCI FTDI dongle (0403:6015) detected on USB."
fi

if dpkg -s brltty >/dev/null 2>&1; then
  warn "Removing 'brltty' — it hijacks the FTDI serial dongle on Ubuntu/Mint."
  warn "    (Braille users can reinstall later with: sudo apt-get install brltty)"
  $SUDO systemctl stop brltty brltty-udev 2>/dev/null || true
  $SUDO systemctl mask brltty brltty-udev 2>/dev/null || true
  if $SUDO apt-get remove -y brltty; then
    ok "brltty removed; unplug and replug the dongle so /dev/ttyUSB* persists."
  else
    warn "Could not remove brltty automatically. If the dongle is not detected,"
    warn "remove it manually:   sudo apt-get remove brltty"
  fi
else
  ok "brltty not installed — nothing to neutralise."
fi

TARGET_USER="${SUDO_USER:-$(id -un)}"
if id -nG "$TARGET_USER" 2>/dev/null | grep -qw dialout; then
  ok "User '$TARGET_USER' is already in the 'dialout' group (serial access OK)."
else
  ok "Adding '$TARGET_USER' to the 'dialout' group (needed to open /dev/ttyUSB*)..."
  if $SUDO usermod -aG dialout "$TARGET_USER"; then
    NEED_RELOGIN=1
    ok "Added. Takes effect after a full log out / log in (or reboot)."
  else
    warn "Could not add '$TARGET_USER' to dialout. Run it manually:"
    warn "    sudo usermod -aG dialout $TARGET_USER"
  fi
fi

# ---------- 6. Desktop launcher (.desktop entry) ----------
LAUNCH_SH="$REPO/LAUNCH_Linux.sh"
chmod +x "$LAUNCH_SH" 2>/dev/null || true
ICON="$(find "$VENDOR" -type f -iname '*.png' 2>/dev/null | head -1 || true)"
DESKTOP_ENTRY_NAME="OpenLab Recorder.desktop"

write_desktop_entry() {
  local dest="$1"
  cat > "$dest" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=OpenLab Recorder
Comment=Stream OpenBCI to LabRecorder over Lab Streaming Layer
Exec=bash "$LAUNCH_SH"
Path=$REPO
Terminal=true
Categories=Science;Education;
${ICON:+Icon=$ICON}
EOF
  chmod +x "$dest" 2>/dev/null || true
  # GNOME 42+ requires the launcher to be marked trusted before it runs.
  gio set "$dest" metadata::trusted true 2>/dev/null || true
}

APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
write_desktop_entry "$APPS_DIR/$DESKTOP_ENTRY_NAME"
ok "Applications-menu entry: $APPS_DIR/$DESKTOP_ENTRY_NAME"

if [[ -d "$HOME/Desktop" ]]; then
  write_desktop_entry "$HOME/Desktop/$DESKTOP_ENTRY_NAME"
  ok "Desktop launcher: $HOME/Desktop/$DESKTOP_ENTRY_NAME"
fi

echo
ok "=================================================================="
ok "  OpenLab Recorder install complete."
ok "  Launch it one of these ways:"
ok "    - double-click 'OpenLab Recorder' on your Desktop or in the menu"
ok "    - or from a terminal:  ./LAUNCH_Linux.sh"
ok "  It will:"
ok "    - auto-detect the OpenBCI dongle (/dev/ttyUSB*)"
ok "    - open LabRecorder"
ok "    - start the bridge"
ok "  In LabRecorder, pick 'OpenBCI_EEG' and press Start."
ok "=================================================================="
ok ""
if [[ "${NEED_RELOGIN:-0}" -eq 1 ]]; then
  warn "IMPORTANT: you were just added to the 'dialout' group. LOG OUT and back in"
  warn "(or reboot) before launching, or the dongle will fail with 'unable to open"
  warn "port'. In a pinch, run the launcher from a shell started with: newgrp dialout"
else
  ok "Serial-port access (dialout group + brltty) already handled above."
fi
echo
ok "Self-diagnostic (re-runnable any time with: bash scripts/diagnose_linux.sh)"
bash "$REPO/scripts/diagnose_linux.sh" || true
exit 0
