#!/usr/bin/env python3
"""Worked example: the edit script behind the S10 placement reel (accepted v4).

Kept as a pattern to copy, with this video's constants still in it. It
prints one ffmpeg command; run it, then do the loudness pass from SKILL.md.

The music is the song the gym was already playing (Hardwell, Dare You), so
at the cut from intro to clean & jerk the clean track takes over from the
room recording at the same song position. The intro keeps only its own
recorded audio. After the cut every clip boundary sits on a downbeat of the
song, and at the end of the first drop the music jumps to the start of the
final drop (DJ-style), skipping the silent break and the quiet second verse.

usage: example-edl.py OUTPUT MUSIC GRID_FILE
"""
import os
import shlex
import sys

SOURCE = os.path.expanduser("~/aanleveringen/jappie/nationals-s10-plaatsing-wostje.mp4")
# Store path from: nix-store -r $(nix-instantiate '<nixpkgs>' -A oswald)
FONT = "/nix/store/y023zdzivvs6fxbkzs9xzwiblprg8iv8-oswald-4.103/share/fonts/truetype/Oswald-Bold.ttf"
FPS = 30

INTRO_END = 23.50      # right after "Dit is de placement WOD.", before the camera swings away
AMBIENT_UNDER_MUSIC = 0.20
FADE_OUT = 1.2
EDGE_FADE = 0.02       # removes clicks where gym audio is hard-cut
JUMP_FADE = 0.02

# Song position = video time + offset, fitted by cross-correlating the clean
# track with the room recording; the gym player runs ~0.1% slow, hence the slope.
SONG_OFFSET_AT_ZERO = 49.115
SONG_OFFSET_SLOPE = 0.00108

# Downbeats are the grid beats with index = 1 (mod 4). Beat 193 is the first
# drop's closing hit, beat 377 the first beat of the final drop.
LOCKOUT_BEAT = 169
CJ_END_BEAT = 185
JUMP_FROM_BEAT = 193
JUMP_TO_BEAT = 377
LOCKOUT_SOURCE = 117.0  # 1:57.0, arms locked out overhead

# (label, source start, bars) after the jump; they pair into 4-bar phrases.
AFTER_JUMP = [
    ("burpee_box", 687.90, 2),   # up from the burpee, then onto the box, on the drop
    ("ring_row", 979.00, 2),
    ("rings", 1034.00, 2),
    ("c2b", 1238.60, 2),         # clear of the rig upright, chest visibly at the bar
    ("c2b_last", 1306.30, 2),    # last rep, two seconds before the 20:00 cap
]
OUTRO = ("outro", 1311.90, 4.85)  # walks to camera, hands on knees; later frames show a bystander


def plan(period: float, phase: float) -> tuple[list[tuple[str, float, float]], float, float, float]:
    """Return (segments, song position at the intro cut, jump-from and jump-to song times)."""
    beat = lambda k: phase + k * period
    bar = 4 * period
    cut_song = INTRO_END + SONG_OFFSET_AT_ZERO + SONG_OFFSET_SLOPE * INTRO_END
    # Before the jump the song runs 1:1 with the output from the intro cut on.
    to_output = lambda k: INTRO_END + beat(k) - cut_song
    lockout = to_output(LOCKOUT_BEAT)
    # Start the clip early enough that the source lockout frame plays at that downbeat.
    cj_start = LOCKOUT_SOURCE - (lockout - INTRO_END)
    cj_end = to_output(CJ_END_BEAT)
    jump = to_output(JUMP_FROM_BEAT)
    segments = [
        ("intro", 0.0, INTRO_END),
        ("cj80", cj_start, cj_end - INTRO_END),   # the only clean & jerk that went overhead
        ("row", 420.00, jump - cj_end),
    ]
    segments += [(label, start, bars * bar) for label, start, bars in AFTER_JUMP]
    segments.append(OUTRO)
    return segments, cut_song, beat(JUMP_FROM_BEAT), beat(JUMP_TO_BEAT)


def music_filters(input_index: int, music_len: float, cut_song: float,
                  jump_from: float, jump_to: float) -> list[str]:
    """Song audio for the montage, labelled [music], silent until the intro cut.

    Output timeline after the cut, in song time:
      cut_song .. jump_from   rest of the first drop
      jump_to  .. (end)       final drop, for whatever montage time remains
    Each piece runs half the crossfade past the jump, so the crossfade is
    centred on the downbeat.
    """
    half = JUMP_FADE / 2
    final_len = music_len - (jump_from - cut_song)
    return [
        f"[{input_index}:a]aresample=48000,asplit=2[song_a][song_b]",
        f"[song_a]atrim={cut_song:.6f}:{jump_from + half:.6f},asetpts=PTS-STARTPTS[drop1]",
        f"[song_b]atrim={jump_to - half:.6f}:{jump_to + final_len + half:.6f},asetpts=PTS-STARTPTS[final]",
        f"[drop1][final]acrossfade=d={JUMP_FADE}:c1=tri:c2=tri,atrim=0:{music_len:.6f},"
        f"afade=t=out:st={music_len - 1.6:.3f}:d=1.6,adelay={int(INTRO_END * 1000)}:all=1[music]",
    ]


def build(output: str, music: str, period: float, phase: float) -> list[str]:
    segments, cut_song, jump_from, jump_to = plan(period, phase)

    # Frame counts from cumulative output time so A/V never drifts across cuts.
    # The source audio starts 64 ms after its video; first_pts=0 and
    # start_time=0 pad both streams onto the same zero instead of shifting
    # each to its own first sample, which put the intro audio 64 ms early.
    frame_bounds = []
    t = 0.0
    for _, _, dur in segments:
        frame_bounds.append((round(t * FPS), round((t + dur) * FPS)))
        t += dur
    total = frame_bounds[-1][1] / FPS

    args = ["ffmpeg", "-hide_banner", "-y"]
    for _, start, dur in segments:
        args += ["-ss", f"{start:.3f}", "-t", f"{dur + 0.5:.3f}", "-i", SOURCE]
    args += ["-i", music]

    filters = []
    for i, ((label, _, _), (f0, f1)) in enumerate(zip(segments, frame_bounds)):
        frames = f1 - f0
        seconds = frames / FPS
        video = f"[{i}:v]fps={FPS}:start_time=0,trim=end_frame={frames},setpts=PTS-STARTPTS,format=yuv420p"
        audio = (f"[{i}:a]aresample=48000:first_pts=0,atrim=end={seconds:.6f},asetpts=PTS-STARTPTS,"
                 f"pan=stereo|c0=c0|c1=c0,afade=t=in:d={EDGE_FADE}")
        if label == "cj80":
            video += (f",drawtext=fontfile={FONT}:text='80kg':fontsize=170:fontcolor=white"
                      f":borderw=8:bordercolor=black@0.85:shadowx=4:shadowy=4:shadowcolor=black@0.5"
                      f":x=(w-tw)/2:y=h*0.835-th/2:alpha='min(1,t/0.35)'")
        if label != "intro":
            audio += f",volume={AMBIENT_UNDER_MUSIC}"
        if label == "outro":
            video += f",fade=t=out:st={seconds - FADE_OUT:.3f}:d={FADE_OUT}"
            audio += f",afade=t=out:st={seconds - FADE_OUT:.3f}:d={FADE_OUT}"
        else:
            audio += f",afade=t=out:st={seconds - EDGE_FADE:.6f}:d={EDGE_FADE}"
        filters.append(video + f"[v{i}]")
        filters.append(audio + f"[a{i}]")

    n = len(segments)
    concat_inputs = "".join(f"[v{i}][a{i}]" for i in range(n))
    filters.append(f"{concat_inputs}concat=n={n}:v=1:a=1[vout][orig]")

    filters += music_filters(n, total - INTRO_END, cut_song, jump_from, jump_to)
    # amix sums without normalizing; halve the master so the s16 render can't
    # clip, the final loudness pass restores the level with a limiter.
    filters.append("[orig][music]amix=inputs=2:normalize=0:duration=first,volume=0.5[aout]")

    args += ["-filter_complex", ";".join(filters), "-map", "[vout]", "-map", "[aout]",
             "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high",
             "-r", str(FPS), "-c:a", "pcm_s16le", output]
    cuts = " ".join(f"{label}={start:.2f}+{dur:.2f}" for label, start, dur in segments)
    print(f"# total={total:.3f}s song@cut={cut_song:.3f} jump {jump_from:.3f}->{jump_to:.3f} {cuts}",
          file=sys.stderr)
    return args


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    period, phase = map(float, open(sys.argv[3]).read().split())
    print(" ".join(shlex.quote(a) for a in build(sys.argv[1], sys.argv[2], period, phase)))


if __name__ == "__main__":
    main()
