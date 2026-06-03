# OpenLab Recorder

A small, open bridge that streams an **OpenBCI** Cyton / Cyton+Daisy board into
**LabRecorder** over **Lab Streaming Layer**, so brain-signal data records to a
standard Extensible Data Format (`.xdf`) file alongside any other Lab Streaming
Layer source. Free for research and other use under the MIT license.

## What this integrates, and why a bridge is needed

The OpenBCI USB dongle speaks OpenBCI's own serial protocol; it does **not**
emit a Lab Streaming Layer stream. LabRecorder, in turn, only records Lab
Streaming Layer streams. So "the dongle recording directly into LabRecorder" is
not possible out of the box — a small software bridge sits in the middle:

```
OpenBCI board --(dongle serial)--> BrainFlow --(this bridge)--> Lab Streaming Layer outlet
                                                                       |
                                              LabRecorder discovers + records to .xdf
```

`src/openbci_lsl_bridge.py` opens the board with BrainFlow (which delivers
samples in microvolts), reads the channel layout and sample rate live from the
board, and republishes them as a Lab Streaming Layer outlet with proper
per-channel metadata (10-20 labels, microvolt units) so the resulting `.xdf` is
well-formed and loads cleanly in MNE-Python / pyxdf.

## Source codebases this builds on

| Component | Role here | Project | License |
|---|---|---|---|
| **BrainFlow** | Opens the OpenBCI board over the dongle and yields samples | https://github.com/brainflow-dev/brainflow | MIT |
| **Lab Streaming Layer** (`liblsl` + `pylsl`) | Transport the bridge publishes onto | https://github.com/sccn/labstreaminglayer · https://github.com/labstreaminglayer/pylsl | MIT |
| **LabRecorder** | Records the Lab Streaming Layer stream to `.xdf` | https://github.com/labstreaminglayer/App-LabRecorder | MIT |
| **pyxdf** | Reads the `.xdf` back for verification | https://github.com/xdf-modules/pyxdf | BSD-2-Clause |

BrainFlow has no built-in Lab Streaming Layer output, which is the specific gap
this bridge fills.

## Contents

| Path | What |
|---|---|
| `src/openbci_lsl_bridge.py` | The OpenBCI → Lab Streaming Layer bridge |
| `src/probe_board.py` | Hardware probe: open the board, stream briefly, report shape |
| `src/run_end_to_end.py` | Spawns the bridge + LabRecorderCLI, records, verifies the `.xdf` |
| `src/diag_inlet.py` | Diagnostic: pull from the outlet with an inlet (isolates the recorder) |
| `requirements.txt` | `brainflow`, `pylsl`, `pyxdf` |

LabRecorder itself is not redistributed here; download it from its release page
(link above) and run it alongside the bridge.

## Install

### One-click (recommended)

Clone the repo, then run the installer for your operating system. Each one
installs Python (if missing), the Python dependencies, the native `liblsl`
library, and the matching LabRecorder build into `vendor/`, and creates a
double-click launcher.

| Operating system | Install | Launch |
|---|---|---|
| **Windows** | double-click `INSTALL_Windows.bat` | `LAUNCH_Windows.bat` (or the Desktop icon) |
| **macOS** | double-click `INSTALL_macOS.command` | `LAUNCH_macOS.command` (or the Desktop icon) |
| **Linux** (Ubuntu 24.04) | run `./INSTALL_Linux.sh` | `./LAUNCH_Linux.sh` (or the Desktop / menu entry) |

The launcher auto-detects the OpenBCI dongle, opens LabRecorder, and starts the
bridge. It opens LabRecorder even when no dongle is plugged in, so you can browse
past recordings and configure the study folder without the hardware.

### Manual

One command — installs the Python dependencies and downloads the matching
LabRecorder build into `vendor/` (Windows / macOS / Linux):

```bash
python install.py
```

Or fully by hand:

```bash
pip install -r requirements.txt   # then download LabRecorder from its release page (link above)
```

`pylsl` needs the native `liblsl`. On Windows the pip wheel bundles it; on macOS
install it via `brew install labstreaminglayer/tap/lsl`; on Linux install
`liblsl` separately (the Ubuntu installer fetches the matching `.deb`, or use
conda-forge).

## Use

Run the bridge first, then record in LabRecorder.

```bash
# 16-channel Cyton+Daisy on, e.g., COM3 (Windows) or /dev/ttyUSB0 (Linux):
python src/openbci_lsl_bridge.py --port COM3 --board daisy
# 8-channel Cyton:
python src/openbci_lsl_bridge.py --port COM3 --board cyton
```
The stream `OpenBCI_EEG` then appears in LabRecorder's "Record from Streams"
list; select it, choose a study folder, and Start. Stop the bridge with Ctrl-C.

Find the dongle's port in Device Manager → Ports (Windows) or as `/dev/ttyUSB*`
(Linux). Close the OpenBCI GUI first — it holds the serial port.

### One-click (Windows desktop icon)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\make_desktop_shortcut.ps1
```
This puts an **OpenLab Recorder** icon on your Desktop. Double-click it to run
`launch.py`, which auto-detects the dongle's COM port, opens LabRecorder, and
starts streaming — no typing the port. (Defaults to the 16-channel Cyton+Daisy;
edit the shortcut's target to add `cyton` for the 8-channel board.)

### Verify a recording

```python
import pyxdf
streams, _ = pyxdf.load_xdf("your_recording.xdf")
eeg = next(s for s in streams if s["info"]["type"][0] == "EEG")
print(eeg["time_series"].shape, eeg["info"]["nominal_srate"])
```

`src/run_end_to_end.py` automates this whole loop (bridge → record → load back)
as a smoke test. Validated on a Cyton+Daisy at 16 channels / 125 Hz.

## Notes

- Samples are in microvolts (BrainFlow applies the board's gain conversion); the
  outlet declares `unit=microvolts` per channel.
- Cyton over the dongle caps at 250 Hz; the Daisy module halves it to 125 Hz at
  16 channels.
- Channel names and sample rate are read live from BrainFlow, so they track your
  installed BrainFlow version rather than being hard-coded.

## Acknowledgments

With thanks to **OpenBCI** for open biosensing hardware, and to the
**LabRecorder** and **Lab Streaming Layer** maintainers for the recording and
transport stack this bridge connects. This project would not exist without their
open tools.

Built with time donated by **QIM Group volunteers**, and catalyzed by the
**Consciousness Studies Club** and its brain-computer-interface lab, whose
research environment and recording needs sparked this work.

## License

MIT — see [LICENSE](LICENSE). Free to use, modify, and redistribute, including
for research. The upstream components retain their own licenses (MIT for
BrainFlow, Lab Streaming Layer, and LabRecorder; BSD-2-Clause for pyxdf).

Full third-party attribution — every project this bridge depends on or adapts,
with its license and link — is in [CREDITS.md](CREDITS.md).
