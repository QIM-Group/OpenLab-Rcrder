# Credits and third-party attribution

OpenLab Recorder is a thin bridge that connects several existing open-source
projects. It would not exist without them. This file gives explicit credit to
every upstream project, what it is used for here, its license, and whether its
code is a runtime dependency, adapted source, or downloaded at install time.

None of the projects below are vendored as source in this repository except as
noted; they are pulled in as dependencies (`requirements.txt`) or downloaded by
`install.py`. No copyleft code is copied into this project.

## Transport, acquisition, and recording stack

| Project | What it does here | License | Link | How it is used |
|---|---|---|---|---|
| **BrainFlow** | Opens the OpenBCI Cyton / Cyton+Daisy board over the USB dongle and yields samples in microvolts | MIT | https://github.com/brainflow-dev/brainflow | pip dependency (`brainflow`) |
| **Lab Streaming Layer — liblsl** | Native transport library the bridge publishes onto | MIT | https://github.com/sccn/liblsl | native library (pip wheel or system `.deb` / brew / conda-forge) |
| **Lab Streaming Layer — pylsl** | Python binding used to create the LSL `StreamOutlet` | MIT | https://github.com/labstreaminglayer/pylsl | pip dependency (`pylsl`) |
| **LabRecorder (App-LabRecorder)** | Records the LSL stream to a standard `.xdf` file | MIT | https://github.com/labstreaminglayer/App-LabRecorder | downloaded into `vendor/` by `install.py` (not redistributed in this repo) |
| **pyxdf** | Reads the `.xdf` back for verification / smoke tests | BSD-2-Clause | https://github.com/xdf-modules/pyxdf | pip dependency (`pyxdf`) |
| **pyserial** | Enumerates serial ports to auto-detect the OpenBCI dongle | BSD-3-Clause | https://github.com/pyserial/pyserial | pip dependency (`pyserial`) |

BrainFlow has no built-in Lab Streaming Layer output; that specific gap is what
`src/openbci_lsl_bridge.py` fills.

## Electrode impedance check (`src/impedance_check.py`)

The Cyton has no first-class impedance API, so the impedance module drives the
ADS1299 lead-off detection directly and converts the injected-signal amplitude to
ohms. The mechanism and formula are adapted from:

| Source | What was adapted | License | Link |
|---|---|---|---|
| **OpenBCI_GUI** | The ohms-from-amplitude formula `Z = (√2·Vrms)/I_drive − R_series` (`DataProcessing.pde`, `BoardCyton.pde`), used verbatim with `I_drive = 6 nA`, `R_series = 2200 Ω` | MIT | https://github.com/OpenBCI/OpenBCI_GUI |
| **pyOpenBCI-impedance** (mikito-ogino) | The Python `config_board` pattern for the `z CH P N Z` lead-off command plus the bandpass + RMS measurement approach | MIT | https://github.com/mikito-ogino/pyOpenBCI-impedance |
| **OpenBCI Cyton SDK docs** | The `z CH P N Z` serial command and the 31.5 Hz lead-off test-signal definition | docs | https://docs.openbci.com/Cyton/CytonSDK/ |

Both code sources are MIT; the adapted code in `impedance_check.py` is likewise
MIT and re-credits them in its module docstring.

## Hardware

| Project | Role | Link |
|---|---|---|
| **OpenBCI** | Open biosensing hardware (Cyton / Cyton+Daisy boards, USB dongle, ADS1299 front end) that this project records from | https://openbci.com |

## Install / tooling helpers

| Project | What it does here | License | Link |
|---|---|---|---|
| **certifi** | Provides a Mozilla CA bundle so `install.py` can complete HTTPS downloads on systems with an unpopulated trust store (notably macOS) | MPL-2.0 | https://github.com/certifi/python-certifi |

## Suggested viewer (referenced, not bundled)

| Project | Why it is mentioned | License | Link |
|---|---|---|---|
| **MNE-LSL** | Recommended live viewer for the `OpenBCI_EEG` outlet this bridge publishes (no bundling — install separately if you want a live strip) | BSD-3-Clause | https://github.com/mne-tools/mne-lsl |

## License of this project

OpenLab Recorder itself is released under the MIT License — see
[LICENSE](LICENSE). Each upstream project above retains its own license; this
file and the README acknowledge them as the work this bridge depends on and
builds upon.
