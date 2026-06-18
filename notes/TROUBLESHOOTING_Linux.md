# Linux troubleshooting (Linux Mint 22.x / Ubuntu 24.04)

Linux Mint 22.x is built on Ubuntu 24.04 ("noble"). These are the issues seen
bringing OpenLab Recorder up on a fresh machine, in the order they tend to appear.

**First step for any problem:** run the one-shot health check — it reports all of
the items below (dependencies, dongle, brltty, dialout, the LabRecorder GUI
libraries) in a single block, each with the fix command:

```bash
bash scripts/diagnose_linux.sh
```

`INSTALL_Linux.sh` also runs this automatically at the end and on a dependency
failure.

---

## 1. "No serial dongle detected" — the dongle never shows up

The braille service **brltty** grabs the OpenBCI FTDI dongle (USB id `0403:6015`)
the moment it's plugged in, so `/dev/ttyUSB*` appears and immediately disappears.

```bash
sudo apt-get remove -y brltty     # then unplug and replug the dongle
ls /dev/ttyUSB*                    # should now persist
```

The installer does this for you; this is the manual version.

---

## 2. "Unable to open port, error 2, unable to prepare streaming session"

The dongle node now exists, but the program can't open it — you're not in the
**dialout** group *in your current login session*.

```bash
id -nG | grep -q dialout && echo "in dialout" || echo "NOT in dialout"
sudo usermod -aG dialout "$USER"   # if not in dialout
```

**Then log out and back in** (or run `newgrp dialout` in the terminal you launch
from). A group change does **not** take effect in an existing session — and
replugging the dongle does **not** refresh it. No full reboot is needed.

---

## 3. The launcher runs in the terminal but no LabRecorder window opens

LabRecorder is a Qt6 application. Two things are needed:

- **The right LabRecorder build.** The installer fetches **LabRecorder 1.16.4**,
  which works with the Qt 6.4 that Mint 22.x ships. (The newer 1.17.x Linux builds
  require Qt 6.8, which Mint does not provide — they exit with
  `libQt6Core.so.6: version Qt_6.8 not found` and no window.)
- **The Qt6 runtime + a couple of libraries**, which a fresh Mint lacks:

```bash
sudo apt-get install -y libqt6widgets6t64 libqt6network6t64 qt6-qpa-plugins \
                        libxcb-cursor0 libpugixml1v5
```

If you upgraded an existing clone and the window still doesn't appear, force a
fresh LabRecorder download (clears any old 1.17 build):

```bash
git pull
rm -rf vendor/LabRecorder
.venv/bin/python install.py --force    # should say: downloading ...LabRecorder-1.16.4-noble_amd64.deb
```

---

## 4. LabRecorder opens but the live stream isn't listed

The `OpenBCI_EEG` stream is not listed automatically. In LabRecorder click
**Update**, check **OpenBCI_EEG**, then **Start**.

That only works while the bridge is actually streaming. Check the launcher's
terminal:

- `Streaming from /dev/ttyUSB0 (daisy)...` → the bridge is publishing; just click
  **Update** in LabRecorder.
- `ERROR: BOARD_NOT_READY_ERROR:7` → the board is off / asleep / low battery — turn
  it on (PC position) and re-run.
- `No serial dongle detected` → back to sections 1–2.
