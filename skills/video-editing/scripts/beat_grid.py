#!/usr/bin/env python3
"""Fit a steady beat grid to a song and show per-beat energy for finding downbeats.

usage: beat_grid.py SONG.wav T0 T1 [--show A:B ...] [--bpm N] [--anchor T]
  SONG.wav  mono 16 kHz wav (ffmpeg -i song -ac 1 -ar 16000 song.wav)
  T0 T1     stretch of the song, in seconds, the grid is fitted on; pick a
            section with a steady beat (a drop or chorus)
  --show    print every beat between A and B seconds with its index and
            loudness, to see on which beat a section starts
  --bpm     tempo hint, searched +-1%; for when the 80-180 BPM
            autocorrelation picks the wrong tempo or the music is outside it
  --anchor  a time known to be on a beat, eg a section start where the
            loudness jumps; fixes the phase so only the tempo is fitted
run in: nix-shell -p 'python3.withPackages(p: [p.numpy])'

Prints `period phase`; beat k sits at phase + k * period. aubiotrack's beats
wander by half a beat in places, which breaks cutting on downbeats, so the
grid is instead the single (period, phase) whose beats land on the most
onset energy. The quality line compares onset energy on the grid beats with
the average; near 1x the grid is no better than random. Measured: Dare You
(EDM) 1.6x at 127.85 BPM; My War (dense rock) 1.3x at 144, its published
140-144, but 1.0x at aubiotrack's median of 148. So when tools disagree,
trust the quality line and a published tempo over aubio. Downbeats are not
detected: read section starts off --show and pick the beat index class
(index mod 4) that most section starts share; a single boundary can read a
beat early when a riser or pickup leads into it.
"""
import argparse
import wave

import numpy as np

HOP_SECONDS = 0.005
WINDOW = 1024


def load_mono(path: str) -> tuple[np.ndarray, int]:
    with wave.open(path) as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise SystemExit(f"{path}: need 16-bit mono wav")
        samples = np.frombuffer(handle.readframes(handle.getnframes()), dtype=np.int16)
        return samples.astype(np.float32), handle.getframerate()


def onset_novelty(samples: np.ndarray, rate: int) -> np.ndarray:
    """Positive log-spectral flux per hop; peaks at note and drum attacks."""
    hop = int(rate * HOP_SECONDS)
    frames = np.lib.stride_tricks.sliding_window_view(samples, WINDOW)[::hop] * np.hanning(WINDOW)
    spectrum = np.log1p(np.abs(np.fft.rfft(frames, axis=1)))
    flux = np.maximum(0.0, np.diff(spectrum, axis=0)).sum(axis=1)
    return np.concatenate([[0.0], flux])


def coarse_period(novelty: np.ndarray, t0: float, t1: float) -> float:
    """Beat period from the autocorrelation peak within 80-180 BPM.

    The range excludes half and double tempo, the usual autocorrelation
    mistakes; pass --bpm for music outside it.
    """
    first, last = int(t0 / HOP_SECONDS), int(t1 / HOP_SECONDS)
    span = novelty[first:last] - novelty[first:last].mean()
    spectrum = np.fft.rfft(span, n=2 * len(span))
    autocorrelation = np.fft.irfft(spectrum * np.conj(spectrum))[:len(span)]
    lags = np.arange(len(autocorrelation)) * HOP_SECONDS
    plausible = (lags >= 60 / 180) & (lags <= 60 / 80)
    return float(lags[plausible][np.argmax(autocorrelation[plausible])])


def pooled_novelty(novelty: np.ndarray) -> np.ndarray:
    """Max-pool +-10 ms so a beat a hop off still counts its attack."""
    return np.maximum.reduce([np.roll(novelty, shift) for shift in range(-2, 3)])


def fit_grid(novelty: np.ndarray, t0: float, t1: float, coarse: float,
             spread: float, anchor: float | None) -> tuple[float, float]:
    """The (period, phase) within coarse * (1 +- spread) whose beats hit the most onset energy.

    With an anchor only the phase putting a beat on it is tried per period.
    """
    pooled = pooled_novelty(novelty)
    best = (-1.0, coarse, 0.0)
    for period in np.arange(coarse * (1 - spread), coarse * (1 + spread), 0.0002):
        if anchor is None:
            phases = np.arange(0.0, period, HOP_SECONDS)
        else:
            phases = np.array([anchor % period])
        first_beat = np.ceil((t0 - phases) / period)
        count = int((t1 - t0) / period) - 1
        times = phases[:, None] + (first_beat[:, None] + np.arange(count)[None, :]) * period
        scores = pooled[np.round(times / HOP_SECONDS).astype(int)].sum(axis=1)
        index = int(np.argmax(scores))
        if scores[index] > best[0]:
            best = (float(scores[index]), float(period), float(phases[index]))
    return best[1], best[2]


def grid_quality(novelty: np.ndarray, t0: float, t1: float, period: float, phase: float) -> float:
    """Mean onset energy on the grid beats divided by the mean over the stretch."""
    pooled = pooled_novelty(novelty)
    beats = phase + np.arange(np.ceil((t0 - phase) / period), (t1 - phase) / period) * period
    on_beats = pooled[np.round(beats / HOP_SECONDS).astype(int)].mean()
    return float(on_beats / pooled[int(t0 / HOP_SECONDS):int(t1 / HOP_SECONDS)].mean())


def rms_db(samples: np.ndarray, rate: int, start: float, length: float) -> float:
    chunk = samples[int(start * rate):int((start + length) * rate)]
    return float(20 * np.log10(np.sqrt(np.mean(chunk ** 2)) / 32768 + 1e-9))


def main() -> None:
    parser = argparse.ArgumentParser(description="fit a steady beat grid")
    parser.add_argument("song")
    parser.add_argument("t0", type=float)
    parser.add_argument("t1", type=float)
    parser.add_argument("--show", action="append", default=[], metavar="A:B")
    parser.add_argument("--anchor", type=float, help="a time known to be on a beat (seconds)")
    parser.add_argument("--bpm", type=float,
                        help="tempo hint, eg 60 / median aubiotrack interval; searched +-1%%")
    args = parser.parse_args()

    samples, rate = load_mono(args.song)
    novelty = onset_novelty(samples, rate)
    if args.bpm:
        period, phase = fit_grid(novelty, args.t0, args.t1, 60 / args.bpm, 0.01, args.anchor)
    else:
        period, phase = fit_grid(novelty, args.t0, args.t1,
                                 coarse_period(novelty, args.t0, args.t1), 0.03, args.anchor)
    print(f"{period:.6f} {phase:.4f}")
    print(f"# {60 / period:.2f} BPM, bar of 4 = {4 * period:.4f}s, "
          f"onsets on beats {grid_quality(novelty, args.t0, args.t1, period, phase):.2f}x average",
          flush=True)
    for window in args.show:
        low, high = (float(part) for part in window.split(":"))
        print(f"# beats {low}-{high}s: index time loudness_dB (over the beat)")
        for k in range(int(np.ceil((low - phase) / period)), int((high - phase) / period) + 1):
            time = phase + k * period
            print(f"{k:5d} {time:8.3f} {rms_db(samples, rate, time, period):6.1f}")


if __name__ == "__main__":
    main()
