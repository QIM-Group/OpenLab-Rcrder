---
date: 2026-05-28
slug: cross_platform_installer
status: complete
---

# Summary — Cross-platform installer build session

Added Windows + macOS one-click installers and a macOS launcher to the OpenLab Recorder repository. Friend on macOS was the integration test; 9 forward commits before the working install landed. Full incident log: `CLAUDE_FAILURES_2026-05-28.md`. Per-repository design notes: `.serena/memories/cross_platform_installer_session_2026-05-28.md`.

## What landed (final state)

- `INSTALL_Windows.bat` — double-click Windows installer
- `INSTALL_macOS.command` — double-click macOS installer
- `LAUNCH_macOS.command` — double-click macOS launcher, repository root, git-tracked
- `install.py` — gained certifi-backed SSL context for cross-platform `urllib` trust-store handling
- `launch.py` — gained `platform.system()` dispatch for LabRecorder binary name; graphical user interface opens before dongle check (no-hardware-required)
- `scripts/install_windows.ps1`, `scripts/install_macos.sh` — operating-system-specific installer logic

## Key wins

- Friend can now `git clone` + double-click `INSTALL_macOS.command` + double-click `LAUNCH_macOS.command` end-to-end on macOS.
- 10 cross-platform install discipline rules persisted in the user's global Claude Code configuration and in the software-engineering iteration skill, so future sessions do not repeat the 9-commit fix cycle.

## Open items

- Verify `brew install labstreaminglayer/tap/lsl` tap path against the live brew registry (unverified-this-session claim in `install_macos.sh`).
- Linux one-click installer not built; `INSTALL_Linux.sh` is the natural next addition if anyone tries a Linux install.
- `README.md` still describes the old install flow; could be updated to point at `INSTALL_Windows.bat` / `INSTALL_macOS.command` as the primary path.
