# Claude Code failure log — OpenLab Recorder cross-platform installer, 2026-05-28

This file is the source-of-truth incident log for the cross-platform installer build session on 2026-05-28. The friend's macOS install of this repository failed repeatedly; the install scripts that Claude Code wrote required 9 forward commits to land working. This log enumerates every mistake, the root cause, the fix that landed, and the rule that must hold next time.

Anchor commits: c2f0a35 (pre-existing baseline) → 5aac3b2 → 7a6d01b → 20967bb → 28c51a4 → 6a6029b → 8757ced → 926d92d → d5bba92 → 3fb6705 → 603c721.

## Mistake 1 — Hard-coded Windows binary name in a cross-platform Python script

**What I did:** `launch.py` had `LABRECORDER = next((HERE / "vendor" / "LabRecorder").rglob("LabRecorder.exe"), None)`.

**Why it failed:** macOS LabRecorder is `LabRecorder.app` (an app bundle), Linux is bare `LabRecorder` (no extension). `rglob("LabRecorder.exe")` returned nothing on macOS → the launcher silently printed "LabRecorder not found in vendor/" even though it was there → graphical user interface never opened → user saw the bridge start but no recorder.

**Fix landed:** commit 8757ced. New `find_labrecorder()` dispatches on `platform.system()`. New `launch_labrecorder()` uses `subprocess.Popen(["open", str(path)])` for macOS .app bundles, direct `Popen` for Linux / Windows.

**Rule:** Any cross-platform script that references a binary name MUST dispatch on `platform.system()`. Windows binaries end in `.exe`. macOS application bundles end in `.app` and launch via the `open` command. Linux executables have no extension and launch via direct `subprocess.Popen`.

## Mistake 2 — Required hardware connected before launching the graphical user interface

**What I did:** `launch.py` called `find_dongle_port()` and if no dongle was detected, returned exit code 1 with "No serial dongle found" BEFORE opening LabRecorder.

**Why it failed:** Friend wanted to open the graphical user interface to browse past recordings, configure the study folder, or verify the install — none of which require the hardware to be plugged in. The dongle is needed only to feed the bridge, not the graphical user interface.

**Fix landed:** commit 926d92d. Reordered `main()`: LabRecorder opens FIRST, then dongle detection runs. If no dongle, the bridge is skipped with a clear message and LabRecorder stays running independently. Exit code is now 0 (graphical user interface successfully opened).

**Rule:** Graphical user interface software must launch independent of optional hardware dependencies. Hardware connection is a runtime feature, not a launch precondition. The user must be able to open the application without the peripheral being plugged in.

## Mistake 3 — urllib.request without certifi on macOS

**What I did:** `install.py` called `urllib.request.urlretrieve(url, archive)` to download LabRecorder from a GitHub releases URL without any explicit SSL context.

**Why it failed:** Python's default SSL context on macOS frequently has no populated certificate authority trust store. The python.org installer requires the user to run `Install Certificates.command` after install; brew-installed Python links to its own OpenSSL which may not be hooked up to the system keychain. Result: friend's install crashed mid-download with "failed to locate issuer certificate."

**Fix landed:** commit 6a6029b. New `_install_ssl_context_with_certifi()` in install.py — imports certifi (pip-installs as fallback), builds `ssl.create_default_context(cafile=certifi.where())`, installs as the default urllib opener, exports `SSL_CERT_FILE` + `REQUESTS_CA_BUNDLE` for child processes. Called BEFORE any urllib network call. install_macos.sh ALSO pre-pip-installs certifi to the chosen Python so install.py doesn't have to recursively pip-install certifi (which would itself hit the same TLS error).

**Rule:** Any cross-platform install script that does urllib downloads MUST prime a certifi-backed SSL context before any HTTPS call. Pre-install certifi at the install-script layer, not the install.py layer — the install.py layer cannot bootstrap a package needed for its own bootstrap.

## Mistake 4 — chmod +x via WSL on /mnt/c does not propagate to git

**What I did:** Wrote `INSTALL_macOS.command`, `scripts/install_macos.sh`, `scripts/install_windows.ps1` and ran `chmod +x` on each via WSL Bash. Committed them. All four landed at git mode 100644 (not executable).

**Why it failed:** WSL on `/mnt/c` (NTFS without metadata mount option) does not track Unix executable bits. `git ls-tree HEAD` showed `100644`, not `100755`. Friend's macOS double-click on the `.command` file would have failed with "permission denied."

**Fix landed:** commit 20967bb. `git update-index --chmod=+x` on all three scripts; mode flipped to `100755`.

**Rule:** After committing any script intended to be executable from WSL on `/mnt/c`, ALWAYS verify with `git ls-tree HEAD <file>`. If mode is `100644` instead of `100755`, fix with `git update-index --chmod=+x <file>` and re-commit. This is a workspace-specific gotcha that does not exist on native Linux / macOS clones.

## Mistake 5 — No repo-root double-clickable launcher

**What I did:** The only macOS launcher was created at install time on the user's Desktop by `install_macos.sh` (via `cat > ~/Desktop/'OpenLab Recorder.command'`). No git-tracked launcher existed at the repo root.

**Why it failed:** If install never completed (which it didn't, repeatedly), no launcher existed. Friend tried to double-click `launch.py` from Finder, which opens in the default text editor since `.py` has no executable association on macOS. Symptom reported: "its just opening the file."

**Fix landed:** commit 3fb6705. New `LAUNCH_macOS.command` at repo root, git-tracked at mode `100755`, finds python3 via priority list (brew python@3.12, brew python3, /usr/local/bin/python3, /usr/bin/python3, PATH), runs launch.py, traps EXIT to keep Terminal open on any exit code.

**Rule:** Any cross-platform repository with one-click installers SHOULD also have an OS-labelled launcher at the repo root that is git-tracked and chmod +x'd, independent of install-time generation. The launcher works on a fresh clone before install runs.

## Mistake 6 — Asymmetric OS labelling in script names

**What I did:** Named the Windows installer `INSTALL.bat` and the macOS installer `INSTALL_macOS.command`. Asymmetric.

**Why it failed:** A user looking at the repo root saw "INSTALL.bat" and could not immediately tell whether it was Windows, Linux, or generic. The macOS one was clearly labelled; the Windows one was not.

**Fix landed:** commit 603c721. Renamed `INSTALL.bat` → `INSTALL_Windows.bat` via `git mv` (preserves history). Updated 3 references inside `scripts/install_windows.ps1`.

**Rule:** When a repository carries operating-system-specific install / launch scripts, label them consistently with the operating system name. `INSTALL_Windows.bat` / `INSTALL_macOS.command` / `INSTALL_Linux.sh`. Never rely on the extension alone to communicate intent.

## Mistake 7 — Did not ask which operating system the friend used before building

**What I did:** Initially built `INSTALL.bat` + `scripts/install_windows.ps1` believing the friend was on Windows. Pushed at commit 5aac3b2. User had to correct me afterward: "the failure was on MAC OS."

**Why it failed:** I pattern-matched OpenBCI users as Windows-first. The friend was on macOS. The entire Windows installer build was wasted relative to the actual user need (it does work on Windows, but it does not solve the friend's problem).

**Fix landed:** Built the macOS installer at commits 7a6d01b through 28c51a4. The Windows installer remains valid as a side-deliverable.

**Rule:** When asked to write an install script for a user's friend / collaborator / external party, ASK which operating system they use BEFORE building. Building for the wrong operating system is a guaranteed waste of effort and tokens.

## Mistake 8 — Did not handle macOS Gatekeeper quarantine on downloaded binaries

**What I did:** `install.py` downloads the LabRecorder release via `urlretrieve`. On macOS, `urlretrieve` sets the `com.apple.quarantine` extended attribute on the downloaded file. Friend would later try to launch and get "cannot be opened because the developer cannot be verified."

**Fix landed:** Part of commit 7a6d01b. `install_macos.sh` runs `xattr -dr com.apple.quarantine "$VENDOR"` after install.py completes, stripping the quarantine attribute recursively from `vendor/LabRecorder`.

**Rule:** When install scripts download binaries on macOS via urllib / curl, ALWAYS strip the `com.apple.quarantine` extended attribute with `xattr -dr com.apple.quarantine <path>` before the user tries to launch the binary. Without this, Gatekeeper blocks the launch even on signed-and-notarized binaries.

## Mistake 9 — Did not pre-install certifi before install.py call

**What I did:** Initial version of the certifi fix relied on `install.py` doing the `pip install certifi` itself as a fallback when `import certifi` failed.

**Why it failed:** If the original certificate trust store problem broke pip's ability to talk to PyPI, then `pip install certifi` would also fail with the same TLS error. The fix would never bootstrap.

**Fix landed:** Already accounted for in commit 6a6029b. `install_macos.sh` pre-installs certifi at the shell layer (`"$PYTHON" -m pip install certifi`) BEFORE calling `install.py`. Then `install.py` can safely use certifi because it is guaranteed to be present.

**Rule:** When a runtime fix depends on a package, pre-install that package at the install-script layer BEFORE the runtime code that needs it. Don't rely on the runtime to self-bootstrap a dependency needed for its own bootstrap. Pin the dependency one layer earlier than the failure it prevents.

## Mistake 10 — No verification / static-audit step before declaring done

**What I did:** Pushed N commits with the friend acting as a live integration test on macOS. Each push: friend tries, fails, reports, I fix, repush, friend tries again. Burnt the friend's time and the user's tokens.

**Why it failed:** I am running in WSL Ubuntu and cannot emulate macOS to test before pushing. I did not write a static-audit simulation that mocks `platform.system()` and traces every macOS-specific branch before pushing. I only did so after the user explicitly asked "can you emulate mac os" — and at that point the audit confirmed the code was structurally correct, but the iterative ship-fail cycles had already happened.

**Rule:** For cross-platform code on an operating system I cannot run locally, write a static-audit simulation that mocks `platform.system()` and traces every operating-system-specific branch BEFORE pushing. Run the simulation, identify the failure modes I can predict, then push. Reduces the "ship and fail" loop count from N to 1-2.

## Aggregate rule

Cross-platform install scripts are a category I have repeatedly underestimated. They look simple. They are not. The combination of (a) operating-system-specific binary names, (b) Gatekeeper / SmartScreen / signing behaviors, (c) certificate trust store gaps, (d) executable-bit tracking, (e) double-click association quirks, (f) shell vs Python vs PowerShell launch conventions, and (g) the impossibility of testing one operating system from another locally produces a long-tail failure surface. Future Claude Code sessions touching cross-platform install scripts MUST consult this incident log AND the rules baked into `~/.claude/CLAUDE.md` and the `software-ooda` skill before writing the first line of script.

## Where the rules are persisted

- `~/.claude/CLAUDE.md` — global cross-platform install rules section (deployed from `VSC_HarnessEngineer/claude/CLAUDE.md` via `deploy_global.sh`)
- `VSC_OODA_Stack/skills/software-ooda/SKILL.md` — software-ooda skill carries the rules so any software-engineering-shaped iteration touching installers loads them
- This file — incident-specific log; first stop for anyone debugging OpenLab Recorder install issues
