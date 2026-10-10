#!/usr/bin/env python3
"""Find where a clean song file lines up with a recording that has it playing in the room.

usage: song_offset.py RECORDING.wav SONG.wav START:LENGTH [START:LENGTH ...]
  RECORDING.wav  mono 16 kHz audio of the video, aligned to its video stream:
                 ffmpeg -i video.mp4 -vn -af aresample=first_pts=0 -ac 1 -ar 16000 rec.wav
  SONG.wav       mono 16 kHz audio of the clean song
  START:LENGTH   stretches of the recording (seconds) where the song is audible;
                 prefer ones with little talking, 10-40 s each
run in: nix-shell -p 'python3.withPackages(p: [p.numpy])'

Prints, per stretch, the offset with song time = recording time + offset,
then a line fitted through them. Venue players and phone clocks drift (one
gym ran 0.1% slow), so evaluate the line at the cut instead of reusing one
stretch's offset. Speech-heavy stretches give weak, unreliable peaks.
"""
import sys
import wave

import numpy as np

HOP = 0.01


def load_mono(path: str) -> np.ndarray:
    with wave.open(path) as handle:
        if handle.getnchannels() != 1 or handle.getframerate() != 16000:
            raise SystemExit(f"{path}: need mono 16 kHz wav")
        return np.frombuffer(handle.readframes(handle.getnframes()), dtype=np.int16).astype(np.float32)


def flux_envelope(samples: np.ndarray, rate: int = 16000, window: int = 1024) -> np.ndarray:
    """Spectral flux in 200-4000 Hz per 10 ms; room speakers carry little bass."""
    hop = int(rate * HOP)
    frames = np.lib.stride_tricks.sliding_window_view(samples, window)[::hop] * np.hanning(window)
    spectrum = np.abs(np.fft.rfft(frames, axis=1))
    freqs = np.fft.rfftfreq(window, 1 / rate)
    band = np.log1p(spectrum[:, (freqs > 200) & (freqs < 4000)])
    flux = np.maximum(0.0, np.diff(band, axis=0)).sum(axis=1)
    flux = flux - np.convolve(flux, np.ones(50) / 50, "same")   # drop slow loudness changes
    return flux / (flux.std() + 1e-9)


def best_match(stretch: np.ndarray, song: np.ndarray) -> tuple[float, float]:
    """Song time (s) where the stretch correlates best, and that correlation."""
    stretch = (stretch - stretch.mean()) / stretch.std()
    windows = np.lib.stride_tricks.sliding_window_view(song, len(stretch))
    correlation = (windows @ stretch / len(stretch) - windows.mean(1) * stretch.mean()) / (windows.std(1) + 1e-9)
    index = int(np.argmax(correlation))
    return index * HOP, float(correlation[index])


def refine(stretch: np.ndarray, song: np.ndarray, guess: float) -> float:
    """Best song time within +-0.3 s of the guess at 1 ms resolution."""
    upsample = 10
    fine = lambda envelope: np.interp(np.arange(len(envelope) * upsample) / upsample,
                                      np.arange(len(envelope)), envelope)
    stretch_fine, song_fine = fine(stretch), fine(song)
    stretch_fine = (stretch_fine - stretch_fine.mean()) / stretch_fine.std()
    step = HOP / upsample
    candidates = np.arange(guess - 0.3, guess + 0.3, step)
    scores = []
    for candidate in candidates:
        start = int(round(candidate / step))
        piece = song_fine[start:start + len(stretch_fine)]
        if len(piece) < len(stretch_fine):
            scores.append(-np.inf)
            continue
        scores.append(np.dot(stretch_fine, (piece - piece.mean()) / piece.std()) / len(piece))
    return float(candidates[int(np.argmax(scores))])


def main() -> None:
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    recording = flux_envelope(load_mono(sys.argv[1]))
    song = flux_envelope(load_mono(sys.argv[2]))
    stretches = []
    for spec in sys.argv[3:]:
        start, length = (float(part) for part in spec.split(":"))
        envelope = recording[int(start / HOP):int((start + length) / HOP)]
        coarse, correlation = best_match(envelope, song)
        stretches.append((start, length, envelope, coarse - start, correlation))

    # Songs repeat their choruses, so a stretch can match the wrong repeat.
    # The offset most stretches agree on (within 0.5 s) is the real one.
    votes = lambda offset: sum(abs(offset - other) < 0.5 for _, _, _, other, _ in stretches)
    consensus = max((offset for _, _, _, offset, _ in stretches), key=votes)
    if len(stretches) >= 2 and votes(consensus) < 2:
        raise SystemExit("no two stretches agree on an offset; add stretches with less talking over the music")
    centres, offsets = [], []
    for start, length, envelope, offset, correlation in stretches:
        agrees = abs(offset - consensus) < 0.5
        song_time = refine(envelope, song, start + (offset if agrees else consensus))
        note = "" if agrees else f"  (best match was offset {offset:+.2f}s, a repeat; refined near consensus)"
        print(f"recording {start:7.2f}+{length:<5g} song at {song_time:8.3f}s  "
              f"offset {song_time - start:+8.3f}s  r={correlation:.2f}{note}")
        centres.append(start + length / 2)
        offsets.append(song_time - start)
    if len(offsets) >= 2:
        slope, intercept = np.polyfit(centres, offsets, 1)
        print(f"fit: offset = {intercept:+.4f} {slope:+.6f} * recording_time")


if __name__ == "__main__":
    main()
