#!/usr/bin/env bash
# install_macos.sh — one-click macOS installer for OpenLab Recorder.
#
# Called by INSTALL_macOS.command at the repo root. Can also be run directly:
#     bash scripts/install_macos.sh
#
# Why each step exists:
#
#   1. Homebrew — macOS has no built-in package manager. brew is the de facto
#      standard for installing python@3.12 and liblsl. Apple Silicon installs
#      to /opt/homebrew, Intel to /usr/local — handled below.
#
#   2. Python 3.12 — modern macOS ships /usr/bin/python3 only after Xcode
#      Command Line Tools is installed (and it's older). brew install
#      python@3.12 is the reliable path. Pinned to 3.12 because brainflow's
#      wheel coverage for 3.13 may lag on macOS arm64.
#
#   3. liblsl — pylsl on macOS is the silent failure: `pip install pylsl`
#      succeeds, but `import pylsl` throws because liblsl.dylib isn't found.
#      The labstreaminglayer org's brew tap (labstreaminglayer/tap/lsl) is
#      the standard install path. UNVERIFIED against the live brew tap
#      this session — if `brew install labstreaminglayer/tap/lsl` fails,
#      falls back to suggesting the conda-forge path.
#
#   4. install.py — pip deps + LabRecorder download (existing repo script).
#
#   5. Gatekeeper quarantine strip — macOS quarantines any file downloaded
#      from a browser / curl / urlretrieve with the com.apple.quarantine
#      extended attribute. Trying to launch the LabRecorder binary then
#      triggers "cannot be opened because the developer cannot be verified."
#      `xattr -d -r com.apple.quarantine <path>` removes the attribute.
#      This is the canonical Gatekeeper bypass for user-trusted downloads.
#
#   6. Desktop alias — macOS equivalent of the Windows .lnk shortcut.
#      Uses osascript to make a Finder alias since `ln -s` puts a unix
#      symlink that Finder treats oddly.

set -euo pipefail

err()  { printf '[!] %s\n' "$*" >&2; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[~] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------- 0. Sanity ----------
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This installer is for macOS. uname -s reports: $(uname -s)"
  err "On Windows use INSTALL.bat. On Linux see the README for manual install."
  exit 1
fi

ARCH="$(uname -m)"
MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
ok "macOS ${MACOS_VER} (arch: ${ARCH})"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# ---------- 1a. Xcode Command Line Tools ----------
# Homebrew formulae that build from source need cc / make from Xcode CLT.
# Without CLT, brew sometimes silently no-ops mid-formula. Trigger Apple's
# installer if missing; user gets a single GUI prompt.
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools present at: $(xcode-select -p)"
else
  warn "Xcode Command Line Tools not installed. Triggering Apple installer..."
  warn "A macOS dialog will appear. Click 'Install', wait for it to finish, then re-run INSTALL_macOS.command."
  xcode-select --install || true
  err "Re-run INSTALL_macOS.command after Xcode CLT install completes."
  exit 1
fi

# ---------- 1b. Homebrew ----------
if have brew; then
  ok "Homebrew already installed: $(brew --version | head -1)"
else
  ok "Installing Homebrew (will prompt for your macOS password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Make brew available in this shell without opening a new terminal
  if [[ "${ARCH}" == "arm64" ]] && [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! have brew; then
    err "Homebrew install completed but brew is not on PATH for this shell."
    err "Quit Terminal, reopen it, and re-run INSTALL_macOS.command."
    exit 2
  fi
fi

# ---------- 2. Python 3.12 ----------
if have python3.12; then
  PYTHON="$(command -v python3.12)"
  ok "python3.12 already installed: $PYTHON ($(python3.12 --version))"
else
  ok "Installing python@3.12 via Homebrew..."
  brew install python@3.12
  # brew install python doesn't always symlink python3.12 onto PATH cleanly;
  # use the brew --prefix path explicitly.
  BREW_PY="$(brew --prefix python@3.12)/bin/python3.12"
  if [[ -x "$BREW_PY" ]]; then
    PYTHON="$BREW_PY"
    ok "python3.12 installed at: $PYTHON"
  elif have python3; then
    PYTHON="$(command -v python3)"
    warn "python3.12 not on PATH; falling back to $PYTHON ($(python3 --version))"
  else
    err "Python install completed but no python3.12 / python3 on PATH."
    err "Quit Terminal, reopen it, and re-run INSTALL_macOS.command."
    exit 3
  fi
fi

# ---------- 3. liblsl ----------
# pylsl on macOS NEEDS liblsl installed separately. This is the most likely
# cause of the "install fails on macOS but Windows is fine" pattern.
if [[ -f "$(brew --prefix)/lib/liblsl.dylib" ]] || [[ -f /usr/local/lib/liblsl.dylib ]] || [[ -f /opt/homebrew/lib/liblsl.dylib ]]; then
  ok "liblsl already installed (found liblsl.dylib in brew prefix)"
else
  ok "Installing liblsl via labstreaminglayer/tap..."
  if brew install labstreaminglayer/tap/lsl 2>&1 | tail -5; then
    ok "liblsl installed via brew tap."
  else
    warn "brew install labstreaminglayer/tap/lsl failed."
    warn "Fallback paths to try manually:"
    warn "    conda install -c conda-forge liblsl   (if you have conda/miniforge)"
    warn "    Download liblsl from https://github.com/sccn/liblsl/releases"
    warn "Continuing — pylsl pip wheel will install but `import pylsl` will fail at runtime."
  fi
fi

# ---------- 4. install.py (with TLS-cert priming) ----------
ok "Priming TLS certificate trust store (fixes 'failed to locate issuer certificate')..."

# Run python.org Python's Install Certificates.command if it exists. This
# handles the case where the friend has a python.org Python installation
# alongside the brew one and pip happens to pick the python.org one.
for clicmd in /Applications/Python\ 3.13/Install\ Certificates.command \
              /Applications/Python\ 3.12/Install\ Certificates.command \
              /Applications/Python\ 3.11/Install\ Certificates.command; do
  if [[ -f "$clicmd" ]]; then
    ok "Found python.org Install Certificates.command — running it..."
    bash "$clicmd" 2>&1 | tail -3 || true
  fi
done

# Pre-install certifi so install.py's _install_ssl_context_with_certifi
# finds it on first try (without that, install.py tries a recursive pip
# install of certifi — which itself can hit the same TLS error).
ok "Pre-installing certifi to chosen Python..."
"$PYTHON" -m pip install --quiet --upgrade pip certifi

# Export SSL_CERT_FILE so any urllib in this shell or its children trusts
# certifi's bundle. install.py also sets this internally, but exporting
# here covers the case where pip itself is the failing layer.
export SSL_CERT_FILE="$("$PYTHON" -c 'import certifi; print(certifi.where())')"
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
ok "SSL_CERT_FILE = $SSL_CERT_FILE"

ok "Running install.py (pip deps + LabRecorder download)..."
"$PYTHON" "$REPO/install.py"

# ---------- 5. Gatekeeper quarantine strip on the downloaded LabRecorder ----------
VENDOR="$REPO/vendor/LabRecorder"
if [[ -d "$VENDOR" ]]; then
  ok "Stripping macOS Gatekeeper quarantine on downloaded LabRecorder..."
  # -r recursive, -d delete; ignores files that don't have the attribute
  xattr -dr com.apple.quarantine "$VENDOR" 2>/dev/null || true
  ok "Quarantine cleared. LabRecorder will launch without 'unidentified developer' block."
else
  warn "vendor/LabRecorder not found after install.py — Gatekeeper strip skipped."
fi

# ---------- 5b. Verify every runtime dependency actually imports ----------
# pip install can succeed while runtime import fails — this is the exact
# macOS pylsl failure mode (pip wheel installs but liblsl.dylib is missing).
# Fail fast here so the friend doesn't discover it mid-recording session.
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
  err "Most common cause on macOS: liblsl.dylib not found (pylsl install fails at import)."
  err "Re-check the liblsl step above. If brew install labstreaminglayer/tap/lsl failed,"
  err "the bridge will not run."
  exit 6
fi
ok "All runtime dependencies verified."

# ---------- 6. Desktop alias ----------
DESKTOP="$HOME/Desktop"
LAUNCH_PY="$REPO/launch.py"
ALIAS_PATH="$DESKTOP/OpenLab Recorder.command"

if [[ -f "$LAUNCH_PY" ]]; then
  ok "Creating Desktop launcher (OpenLab Recorder.command)..."
  cat > "$ALIAS_PATH" <<EOF
#!/bin/bash
# Launches OpenLab Recorder: auto-detects OpenBCI dongle, opens LabRecorder, starts bridge.
cd "$REPO"
"$PYTHON" "$LAUNCH_PY"
EOF
  chmod +x "$ALIAS_PATH"
  ok "Desktop launcher: $ALIAS_PATH"
else
  warn "launch.py not found at $LAUNCH_PY — Desktop launcher skipped."
fi

echo
ok "=================================================================="
ok "  OpenLab Recorder install complete."
ok "  Double-click 'OpenLab Recorder.command' on your Desktop."
ok "  It will:"
ok "    - auto-detect the OpenBCI dongle serial port"
ok "    - open LabRecorder"
ok "    - start the bridge"
ok "  In LabRecorder, pick 'OpenBCI_EEG' and press Start."
ok "=================================================================="
ok ""
ok "First-time-only note: macOS may show one Gatekeeper warning the very"
ok "first time you run the Desktop launcher. Right-click it -> Open ->"
ok "Open (instead of double-click). After that double-click works normally."
exit 0
