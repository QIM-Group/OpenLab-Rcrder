# Impedance check + live view (added 2026-06-02)

Both capabilities were missing from this headless bridge. Upstream source
attribution for the adapted code is in [`../CREDITS.md`](../CREDITS.md).

## Impedance check — `src/impedance_check.py` (new, runnable)

Native Cyton/Daisy electrode impedance over BrainFlow — no new dependency (uses the
`brainflow` you already require). Adapted MIT→MIT from OpenBCI_GUI (`DataProcessing.pde`
formula) + `mikito-ogino/pyOpenBCI-impedance` (config_board pattern). Mechanism: the
`z CH P N Z` command drives the ADS1299 lead-off at 31.5 Hz; ohms = `(√2·Vrms)/6e-9 − 2200`.

```
python src/impedance_check.py --self-test            # validates math, no hardware (PASS)
python src/impedance_check.py --port COM34 --board daisy
python src/impedance_check.py --port COM34 --channels 1 2 3
```

Output is per-channel kΩ + a GREEN/YELLOW/RED band. **Caveats** (in the module docstring):
the board must be streaming during the check; absolute ohms can disagree with the OpenBCI
GUI (trust the banding); never change sample rate mid-check (clobbers the LOFF register).

## Live view — adopt mne-lsl (recommended), or a small PyQtGraph strip

The bridge already publishes an LSL outlet, so **any LSL viewer shows the stream with zero
new bridge code**. Recommended: `mne-lsl` (BSD-3, active 2026-06) —

```
pip install mne-lsl
mne-lsl viewer            # discovers the "OpenBCI_EEG" outlet this bridge publishes
```

Alternative (in-process strip): adapt BrainFlow's `python_package/examples/plot_real_time/`
(MIT, PyQtGraph). ~40 lines reading `board.get_current_board_data(n)` into a rolling plot.
Do NOT vendor neuromore (AGPL + non-commercial) or NeuroPype (proprietary) — license
incompatible with this MIT project.
