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

_REL = "https://github.com/labstreaminglayer/App-LabRecorder/releases/download"
# Per-platform LabRecorder build.
#   Windows / macOS: self-contained 1.17.1 builds (they bundle their own Qt).
#   Linux: MUST be 1.16.4, NOT 1.17.x. The 1.17.x Linux builds are linked against
#   Qt 6.8, which Ubuntu 24.04 / Mint 22.x do NOT ship (stock Qt is 6.4); they
#   start with no window ("libQt6Core.so.6: version Qt_6.8 not found"). The 1.16.4
#   build links Qt 6.4 and runs against the distro Qt that install_linux.sh pulls
#   in. It ships only as a .deb (no 1.16.4 tarball); we extract it into vendor/.
ASSET_URLS = {
    "Windows": f"{_REL}/v1.17.1/LabRecorder-1.17.0-Win_amd64.zip",
    "Darwin":  f"{_REL}/v1.17.1/LabRecorder-1.17.0-macOS_universal-signed.tar.gz",
    "Linux":   f"{_REL}/v1.16.5/LabRecorder-1.16.4-noble_amd64.deb",
}


def install_deps() -> None:
    print(f"[deps] pip install -r {REQS.name}")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", str(REQS)])


def fetch_labrecorder(force: bool) -> None:
    url = ASSET_URLS.get(platform.system())
    if url is None:
        print(f"[labrecorder] no prebuilt asset mapped for {platform.system()}; "
              f"download manually from {_REL}")
        return
    asset = url.rsplit("/", 1)[1]
    if VENDOR.exists() and any(p.is_file() for p in VENDOR.rglob("LabRecorder")) and not force:
        print(f"[labrecorder] already present in {VENDOR} (use --force to re-download)")
        return
    VENDOR.mkdir(parents=True, exist_ok=True)
    archive = VENDOR / asset
    print(f"[labrecorder] downloading {url}")
    urllib.request.urlretrieve(url, archive)
    print(f"[labrecorder] extracting {asset}")
    if asset.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            z.extractall(VENDOR)
    elif asset.endswith(".deb"):
        # A .deb is an `ar` archive; dpkg-deb (present on Debian/Ubuntu/Mint)
        # unpacks its file tree → vendor/.../usr/bin/LabRecorder. The binary
        # links the system Qt6 / liblsl / pugixml that install_linux.sh installs.
        subprocess.check_call(["dpkg-deb", "-x", str(archive), str(VENDOR)])
    else:
        with tarfile.open(archive) as t:
            t.extractall(VENDOR)
    archive.unlink()
    exe = next((p for p in VENDOR.rglob("LabRecorder") if p.is_file()), None)
    if exe is not None:
        exe.chmod(exe.stat().st_mode | 0o111)
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
