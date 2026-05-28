#!/usr/bin/env python3
"""One-command setup for OpenLab Recorder.

Installs the Python dependencies and downloads + extracts the matching
LabRecorder build into vendor/. Cross-platform (Windows / macOS / Linux).

    python install.py            # install deps + fetch LabRecorder
    python install.py --no-deps  # only fetch LabRecorder
    python install.py --force    # re-download LabRecorder even if present
"""
from __future__ import annotations

import argparse
import os
import platform
import ssl
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path


def _install_ssl_context_with_certifi() -> None:
    """Make urllib trust certifi's CA bundle if available.

    Fixes the macOS "unable to get local issuer certificate" /
    "failed to locate issuer certificate" failure mode when downloading
    the LabRecorder release from GitHub. Python on macOS frequently ships
    without a populated CA trust store (python.org installer requires the
    user to run Install Certificates.command; brew Python links to its
    own openssl which may not be hooked up). certifi bundles Mozilla's CA
    list and works on every platform.

    Silent no-op on Linux/Windows if Python's default trust store already
    works; certifi just becomes the explicit-and-correct choice.
    """
    try:
        import certifi
    except ImportError:
        # Best-effort install — if pip itself can't reach PyPI, we'll fall
        # through to the default trust store and let the original error
        # surface.
        try:
            subprocess.check_call(
                [sys.executable, "-m", "pip", "install", "--quiet", "certifi"]
            )
            import certifi
        except Exception:
            return
    cafile = certifi.where()
    os.environ.setdefault("SSL_CERT_FILE", cafile)
    os.environ.setdefault("REQUESTS_CA_BUNDLE", cafile)
    ctx = ssl.create_default_context(cafile=cafile)
    https_handler = urllib.request.HTTPSHandler(context=ctx)
    opener = urllib.request.build_opener(https_handler)
    urllib.request.install_opener(opener)

HERE = Path(__file__).resolve().parent
VENDOR = HERE / "vendor" / "LabRecorder"
REQS = HERE / "requirements.txt"

LABRECORDER_VER = "v1.17.1"
BASE = f"https://github.com/labstreaminglayer/App-LabRecorder/releases/download/{LABRECORDER_VER}/"
# Asset per platform (filenames verified against the v1.17.1 release).
ASSETS = {
    "Windows": "LabRecorder-1.17.0-Win_amd64.zip",
    "Darwin": "LabRecorder-1.17.0-macOS_universal-signed.tar.gz",
    "Linux": "LabRecorder-1.17.0-noble_amd64.tar.gz",
}


def install_deps() -> None:
    print(f"[deps] pip install -r {REQS.name}")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", str(REQS)])


def fetch_labrecorder(force: bool) -> None:
    asset = ASSETS.get(platform.system())
    if asset is None:
        print(f"[labrecorder] no prebuilt asset mapped for {platform.system()}; "
              f"download manually from {BASE}")
        return
    if VENDOR.exists() and any(VENDOR.rglob("LabRecorder*")) and not force:
        print(f"[labrecorder] already present in {VENDOR} (use --force to re-download)")
        return
    VENDOR.mkdir(parents=True, exist_ok=True)
    url = BASE + asset
    archive = VENDOR / asset
    print(f"[labrecorder] downloading {url}")
    urllib.request.urlretrieve(url, archive)
    print(f"[labrecorder] extracting {asset}")
    if asset.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            z.extractall(VENDOR)
    else:
        with tarfile.open(archive) as t:
            t.extractall(VENDOR)
    archive.unlink()
    exe = next(VENDOR.rglob("LabRecorder*"), None)
    print(f"[labrecorder] ready: {exe}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Set up OpenLab Recorder")
    ap.add_argument("--no-deps", action="store_true", help="skip pip install")
    ap.add_argument("--force", action="store_true", help="re-download LabRecorder")
    args = ap.parse_args()

    # Fix TLS-validation failures BEFORE any urllib / pip network call.
    _install_ssl_context_with_certifi()

    if not args.no_deps:
        install_deps()
    fetch_labrecorder(args.force)
    print("\nDone. Next: python src/openbci_lsl_bridge.py --port <COM3 or /dev/ttyUSB0> --board daisy")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
