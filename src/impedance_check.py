#!/usr/bin/env python3
"""OpenBCI Cyton / Cyton+Daisy electrode impedance check over BrainFlow.

The OpenBCI dongle exposes no first-class impedance API and BrainFlow's
``get_resistance_channels`` does NOT cover the Cyton (only Ant Neuro / Muse-class
boards). For the Cyton you must drive the ADS1299 lead-off detection yourself and
compute ohms from the injected-signal amplitude. This module does exactly that.

Mechanism (verified against primary sources, 2026-06-02):
  - OpenBCI Cyton serial command ``z CH P N Z`` applies a 31.5 Hz AC test signal to
    a channel's P and/or N input (P/N = 1 applied, 0 not).
    Source: https://docs.openbci.com/Cyton/CytonSDK/  (command ``z 4 1 0 Z`` example)
  - The resulting amplitude is converted to ohms with the OpenBCI_GUI formula
    (MIT, OpenBCI_GUI/DataProcessing.pde + BoardCyton.pde, verified verbatim):
        Z(ohms) = (sqrt(2) * Vrms_volts) / I_drive  -  R_series
    with I_drive = 6.0e-9 A (6 nA) and R_series = 2200 ohms (2.2 kOhm),
    clamped to >= 0.
    Source repo: https://github.com/OpenBCI/OpenBCI_GUI  (MIT)
  - Python pattern (config_board for ``z`` + 5-50 Hz bandpass + RMS) adapted from
    https://github.com/mikito-ogino/pyOpenBCI-impedance  (MIT).

CAVEATS (known, from the OpenBCI community — read before trusting the numbers):
  - You must be STREAMING to measure: the channel reads the injected 31.5 Hz tone
    instead of EEG during the test. This module starts the stream itself.
  - Community users report computed ohms can DISAGREE with the OpenBCI_GUI display;
    treat absolute values as indicative and the GREEN/YELLOW/RED banding as the
    operational signal. The formula here matches the GUI source exactly; residual
    disagreement is a measurement-window / filtering / settle-time effect.
  - Changing the board sample rate clobbers the ADS1299 LOFF register (0x04); run
    impedance at the board's native rate, do not reconfigure rate mid-check.

License: MIT (this file), adapting MIT sources above. No copyleft code is vendored.

Usage:
    python src/impedance_check.py --port COM34 --board daisy
    python src/impedance_check.py --self-test          # no hardware; validates math
"""
from __future__ import annotations

import argparse
import sys
import time

import numpy as np

# --- OpenBCI_GUI constants (BoardCyton.pde, verbatim) ---------------------------
LEADOFF_DRIVE_AMPS = 6.0e-9      # 6 nA lead-off current source
SERIES_RESISTOR_OHMS = 2200.0    # 2.2 kOhm series resistor on the OpenBCI front end
TEST_SIGNAL_HZ = 31.5            # injected AC frequency

# Channel-address ASCII codes used inside the ``z``/``x`` commands.
# 1-8 -> '1'..'8'; Daisy 9-16 -> 'Q','W','E','R','T','Y','U','I'.
# Source: OpenBCI_GUI BoardCyton.pde channelSelect + docs.openbci.com Cyton SDK.
# NOTE: confirm the 9-16 codes against your firmware before trusting Daisy values.
CHANNEL_CODES = ["1", "2", "3", "4", "5", "6", "7", "8",
                 "Q", "W", "E", "R", "T", "Y", "U", "I"]

# Contact-quality kOhm thresholds (research tier). The band edges are facts/ideas
# (re-derived independently); cf. OpenBCI_GUI green<=750k/yellow<=2500k and
# neuromore Studio "Research" 5/10/20/80 kOhm. We use a practical research banding.
QUALITY_BANDS_KOHM = (
    ("GREEN", 0.0, 10.0),     # excellent / good
    ("YELLOW", 10.0, 50.0),   # usable, watch it
    ("RED", 50.0, 1000.0),    # bad contact
)


def impedance_ohms_from_rms(rms_microvolts: float) -> float:
    """Convert a band-limited RMS amplitude (microvolts) to electrode ohms.

    Implements the OpenBCI_GUI formula verbatim, clamped to >= 0.
    """
    vrms = rms_microvolts * 1.0e-6
    z = (np.sqrt(2.0) * vrms) / LEADOFF_DRIVE_AMPS - SERIES_RESISTOR_OHMS
    return float(max(0.0, z))


def quality_band(ohms: float) -> str:
    """Map ohms to GREEN / YELLOW / RED."""
    k = ohms / 1000.0
    for name, lo, hi in QUALITY_BANDS_KOHM:
        if lo <= k < hi:
            return name
    return "RED"


def _bandpassed_rms(signal_uv: np.ndarray, sample_rate_hz: float,
                    lo_hz: float = 5.0, hi_hz: float = 50.0) -> float:
    """RMS of ``signal_uv`` after a 5-50 Hz band-pass (captures the 31.5 Hz tone).

    Uses an FFT brick-wall band-pass so the module has no SciPy/BrainFlow-filter
    dependency; matches the pyOpenBCI-impedance 5-50 Hz approach.
    """
    x = np.asarray(signal_uv, dtype=np.float64)
    x = x - x.mean()
    n = x.size
    if n < 8:
        return 0.0
    freqs = np.fft.rfftfreq(n, d=1.0 / sample_rate_hz)
    spec = np.fft.rfft(x)
    spec[(freqs < lo_hz) | (freqs > hi_hz)] = 0.0
    filtered = np.fft.irfft(spec, n=n)
    return float(np.sqrt(np.mean(filtered * filtered)))


def measure_channel(board, eeg_row: int, channel_index: int, sample_rate_hz: float,
                    *, settle_s: float = 1.0, window_s: float = 1.5) -> float:
    """Measure one channel's impedance (ohms). ``board`` is a streaming BoardShim.

    Applies the P-input lead-off test signal, waits ``settle_s``, collects
    ``window_s`` of data, band-limits, computes ohms, then removes the test signal.
    ``channel_index`` is 0-based (0 -> OpenBCI channel 1).
    """
    code = CHANNEL_CODES[channel_index]
    board.config_board(f"z{code}10Z")     # P input test signal ON
    try:
        time.sleep(settle_s)
        board.get_board_data()             # flush the settle window
        time.sleep(window_s)
        data = board.get_board_data()
        if data.shape[1] == 0:
            return float("nan")
        rms_uv = _bandpassed_rms(data[eeg_row, :], sample_rate_hz)
        return impedance_ohms_from_rms(rms_uv)
    finally:
        board.config_board(f"z{code}00Z")  # P input test signal OFF


def measure_all_at_once(board, eeg_rows: list[int], channel_indices: list[int],
                        sample_rate_hz: float, *, settle_s: float = 1.0,
                        window_s: float = 1.5) -> dict[int, float]:
    """Drive lead-off on ALL given channels at once and read a single window (~Nx faster).

    The ADS1299 is a simultaneous-sampling ADC and LOFF_SENSP is a per-channel register, so
    the silicon supports driving + sampling every channel together (ADS1299 datasheet
    SBAS499C). OpenBCI_GUI still cycles one channel at a time — a firmware/UX choice, not a
    hardware limit. The cost here is analog: all channels' 6 nA currents return through the
    SHARED bias/SRB electrode, adding a common-mode cross-talk term that biases per-channel
    ohms. Use as a fast experimental scan; characterize its offset against the sequential
    pass on your rig. Returns {channel_index: ohms}.
    """
    for c in channel_indices:
        board.config_board(f"z{CHANNEL_CODES[c]}10Z")
    try:
        time.sleep(settle_s)
        board.get_board_data()
        time.sleep(window_s)
        data = board.get_board_data()
        out: dict[int, float] = {}
        for c in channel_indices:
            if data.shape[1] == 0:
                out[c] = float("nan")
            else:
                out[c] = impedance_ohms_from_rms(_bandpassed_rms(data[eeg_rows[c], :], sample_rate_hz))
        return out
    finally:
        for c in channel_indices:
            board.config_board(f"z{CHANNEL_CODES[c]}00Z")


def run(port: str, board_key: str, channels: list[int] | None,
        settle_s: float, window_s: float, all_at_once: bool = False) -> int:
    from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds

    board_id = {"cyton": BoardIds.CYTON_BOARD,
                "daisy": BoardIds.CYTON_DAISY_BOARD}[board_key]
    eeg_rows = BoardShim.get_eeg_channels(board_id)
    srate = BoardShim.get_sampling_rate(board_id)
    n_ch = len(eeg_rows)
    targets = channels if channels else list(range(n_ch))

    params = BrainFlowInputParams()
    params.serial_port = port
    BoardShim.disable_board_logger()
    board = BoardShim(board_id, params)
    board.prepare_session()
    board.start_stream()
    mode = "all-at-once (fast; shared-bias cross-talk)" if all_at_once else "sequential (ground truth)"
    print(f"{board_key}: {n_ch} ch @ {srate} Hz — impedance via 31.5 Hz lead-off [{mode}]\n"
          f"{'ch':>3} {'kOhm':>9}  band")
    try:
        if all_at_once:
            ohms_by_ch = measure_all_at_once(board, eeg_rows, targets, srate,
                                             settle_s=settle_s, window_s=window_s)
            for c in targets:
                ohms = ohms_by_ch[c]
                print(f"{c + 1:>3} {ohms / 1000.0:>9.1f}  {quality_band(ohms)}")
        else:
            for c in targets:
                ohms = measure_channel(board, eeg_rows[c], c, srate,
                                       settle_s=settle_s, window_s=window_s)
                print(f"{c + 1:>3} {ohms / 1000.0:>9.1f}  {quality_band(ohms)}")
    finally:
        board.stop_stream()
        board.release_session()
    return 0


def _self_test() -> int:
    """Validate the ohms math with a synthetic 31.5 Hz tone — no hardware."""
    srate = 125.0
    t = np.arange(int(srate * 2)) / srate
    # Pick an amplitude that should yield ~5 kOhm: invert the formula.
    target_ohms = 5000.0
    vrms = (target_ohms + SERIES_RESISTOR_OHMS) * LEADOFF_DRIVE_AMPS / np.sqrt(2.0)
    amp_uv = vrms * 1e6 * np.sqrt(2.0)  # sine peak = sqrt(2)*RMS
    sig = amp_uv * np.sin(2 * np.pi * TEST_SIGNAL_HZ * t)
    rms = _bandpassed_rms(sig, srate)
    z = impedance_ohms_from_rms(rms)
    ok = abs(z - target_ohms) < 250.0  # within 0.25 kOhm
    print(f"self-test: injected->{target_ohms:.0f} ohms, recovered {z:.0f} ohms, "
          f"band={quality_band(z)} -> {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 2


def main() -> int:
    ap = argparse.ArgumentParser(description="OpenBCI Cyton/Daisy impedance check")
    ap.add_argument("--port", help="Dongle serial port, e.g. COM34 or /dev/ttyUSB0")
    ap.add_argument("--board", choices=("cyton", "daisy"), default="daisy")
    ap.add_argument("--channels", type=int, nargs="*",
                    help="1-based channels to test (default: all)")
    ap.add_argument("--settle", type=float, default=1.0, help="settle seconds")
    ap.add_argument("--window", type=float, default=1.5, help="measure-window seconds")
    ap.add_argument("--all-at-once", action="store_true",
                    help="drive all channels' lead-off together + one read (~Nx faster; "
                         "biased by shared-bias cross-talk — cross-check vs sequential)")
    ap.add_argument("--self-test", action="store_true", help="validate math, no hardware")
    args = ap.parse_args()
    if args.self_test:
        return _self_test()
    if not args.port:
        ap.error("--port is required (or use --self-test)")
    chans = [c - 1 for c in args.channels] if args.channels else None
    try:
        return run(args.port, args.board, chans, args.settle, args.window, args.all_at_once)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
