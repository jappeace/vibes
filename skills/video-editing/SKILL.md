---
name: video-editing
description: >
  Edit videos headlessly with ffmpeg under nix: cut a highlight reel out of
  long footage, add a text label, put music under it with every cut on the
  beat, and deliver a loudness-normalised mp4. Use when asked to edit, trim,
  cut, montage, or make a reel or highlight of a video, or to add music, text
  or subtitles to one. Covers seeing footage (contact sheets), hearing it
  (whisper, songrec, loudness), A/V sync pitfalls, music licensing, beat
  grids and downbeat cuts.
argument-hint: "[video-path]"
---

# Video editing with ffmpeg

You cannot watch or listen. You see a video as sampled stills and hear it
through transcripts, loudness numbers and fingerprints. So do the measurable
parts exactly, and tell the user which judgements only they can make: taste,
pacing, whether music enters in the middle of a word.

Distilled from the S10 placement reel (10 Oct 2026): 22 minutes of a CrossFit
workout cut to a 65 s reel in five versions. The user rejected two picked
songs, then asked for the song the gym was already playing; that version was
accepted because "the transition works really well". Subtitles were
forgotten until the end ("for those who play this on mute"): plan them in
from the start.

## Tools

All from nixpkgs; nothing needs to be on PATH beforehand.

| Need | Package | Notes |
|---|---|---|
| cut, filter, encode | `ffmpeg` | plain ffmpeg has drawtext; ffmpeg-full is not needed |
| speech to text | `whisper-cpp` | models from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/`: `ggml-large-v3-turbo-q5_0.bin`, plus `ggml-large-v3-q5_0.bin` as a second opinion for subtitles |
| beats, onsets | `aubio` | binaries are `aubiotrack`, `aubioonset`; there is no `aubio` CLI |
| which song plays | `songrec` | see scripts/song-id.sh for its TLS setting |
| analysis scripts | `python3.withPackages(p: [p.numpy])` | building the env needs `nix-shell --max-jobs 4` |
| bold label font | `oswald` | `nix-store -r $(nix-instantiate '<nixpkgs>' -A oswald)` |
| subtitle font, burn-in | `montserrat`, ffmpeg's `ass` filter | plain ffmpeg is built with libass |

In this sandbox `TMPDIR` and `/tmp` resolve into `/nix/store`, so `nix-build`
refuses its GC root; use `nix-store -r $(nix-instantiate ...)` or
`TMPDIR=$HOME/.cache/nixtmp`. Work in the scratchpad. Source files in
`~/aanleveringen` are read-only. Deliver to `~/vibes/video/` with a version in
the name (`-v2`, `-v3`) so the user can compare.

## 1. Probe

```bash
ffprobe -v error -show_entries format=duration:stream=codec_type,codec_name,width,height,r_frame_rate,start_time -of compact IN.mp4
```

Phone files are variable frame rate (`r_frame_rate=90000/1`), and their audio
can start later than the video (64 ms in the S10 recording). Both matter in
section 5.

## 2. See the footage

[scripts/contact-sheet.sh](scripts/contact-sheet.sh) tiles timestamped frames into one image for the Read tool:

| Purpose | FPS | Grid |
|---|---|---|
| map the whole video | 1/3 | 8x4, `OUT` with `%02d` writes every sheet (22 min = 14 sheets) |
| choose a clip | 2 to 4 | 8x4 over 8 to 16 s |
| pin a moment (lockout, landing) | 10 | 10x2 over 2 s |

The stamp is the source time, so seek positions come straight off the sheet.
Check every chosen clip at 2 fps for things hiding the action: in S10 the rig's
upright covered the chest-to-bar rep, and the user reported the movement as
missing.

## 3. Hear the footage

- Transcribe short windows; over minutes of gym noise whisper loops on "Ja.".
  `whisper-cli -m MODEL -l nl -bs 5 -f clip.wav`
- Turbo's timestamps snap to whole seconds. To find where a phrase ends,
  transcribe growing windows (0 to 1.2 s, 0 to 1.6 s, ...) and read a 20 to
  50 ms RMS envelope.
- Whisper mangles names and slang ("ik ben worsje" came out as
  "Hekweerborst"). When you can only infer a line, say so.
- `--prompt` with the expected words biases the decoder: a test of a
  hypothesis, not evidence.

## 4. Plan the edit as a script

Write the edit decision list as a small program that prints one ffmpeg
command, with each source time a commented constant and durations computed
(from the beat grid once there is music). Each segment is its own
`-ss START -t DURATION+0.5 -i SOURCE` input, joined with `concat` in
`filter_complex`. Render to `.mkv` with `pcm_s16le` audio, then run the
loudness pass of section 8 into the final mp4.
[reference/example-edl.py](reference/example-edl.py) is the accepted S10 script.

The shape the user liked: the talking intro with only its original audio; the
hero moment in full with a big label ("80kg", Oswald Bold 170 px, white with
an 8 px black border, below the athlete and clear of burnt-in watermarks); 2
bars of each movement; the athlete bent over at the time cap with a 1.2 s fade
to black; burned-in subtitles for everything spoken. About 60 s.

## 5. Keep audio and video in sync

- Pad both streams to one zero before trimming: `fps=30:start_time=0` and
  `aresample=48000:first_pts=0`. A `PTS-STARTPTS` before that padding moves
  each stream to its own first sample, which put the S10 intro audio 64 ms
  ahead of the lips.
- Frame counts come from cumulative output time (`round(t * 30)`), and each
  segment's audio is trimmed to `frames / 30`, so cuts never drift.
- A 20 ms `afade` in and out on every hard-cut audio segment removes clicks.
- Check it: render once without music, cross-correlate each segment's audio
  envelope with the source audio (extracted with `aresample=first_pts=0`),
  expect 0 ms. Compute the expected output start with the same frame
  rounding, or you chase a one-frame error that is your own arithmetic.

## 6. Music

### Licensing

- Instagram mutes or blocks copyrighted songs. Do not download them from
  YouTube yourself; the user puts a file they want in `~/aanleveringen`.
- For Creative Commons prefer CC0 or CC BY. Music synced to video is an
  adaptation (CC BY-SA 4.0, section 1(a)): BY-SA puts the whole video under
  BY-SA, with license link and a "modified" notice in the caption, and ND
  forbids it.
- archive.org hosts famous albums mislabelled CC0 (Yes, Tool); use only
  uploads by the artists themselves.

### The song already playing in the recording

Offer this first; it gives the transition the user valued most.

1. `scripts/song-id.sh VIDEO 0 60 100` (in `nix-shell -p songrec ffmpeg python3`)
   prints artist, title and song-minus-video offset per 12 s clip.
2. With the clean file from the user, run
   [scripts/song_offset.py](scripts/song_offset.py) over several stretches
   with little talking. It discards matches on a repeated chorus and fits the
   drift: the S10 gym player ran 0.1% slow (offset 49.13 s + 0.001 s per second).
3. At the intro cut, start the clean track at `cut + offset(cut)`. The music
   moves from tinny room speakers to full sound without restarting.
4. Keep the gym audio under the music low (0.2); it holds the same song at
   other positions.

### Beat grid and downbeats

[scripts/beat_grid.py](scripts/beat_grid.py) `SONG.wav T0 T1 --show A:B`
fits one steady grid and prints `period phase`.

- Read its quality line: onset energy on the beats was 1.6x average for EDM
  and 1.3x for dense rock; near 1.0x the tempo is wrong.
- aubiotrack's beats jump half a beat in places, and its median tempo was 3%
  above the published one for the rock song. Cross-check a published BPM.
- Downbeats are not detected. Find section starts by loudness jumps (ebur128
  per second for the map, `--show` per beat for the exact beat). The section
  starts share one beat index class mod 4; in Dare You they were beats 65,
  129, 193, 265 and 377, all 1 mod 4. A single boundary can read a beat early
  when a riser leads into the drop.

### Cutting on the beat

- Put every cut on a downbeat and make every clip a whole number of bars (2
  bars at 128 BPM = 3.75 s). Pairs of clips then fill 4-bar phrases.
- Land the hero moment on a downbeat or a big hit by choosing where its clip
  starts: `clip_start = moment_in_source - (beat_in_output - clip_cut_in_output)`.
- When the song goes quiet mid-montage, jump like a DJ: from a phrase-ending
  downbeat to the first downbeat of a later drop, with a 20 ms crossfade
  centred on the downbeat. `music_filters` in the example does this with two
  overlapping `atrim`s and `acrossfade`.
- Music that does not continue from the room starts on a downbeat with an
  80 ms fade-in. Say that you cannot hear whether it starts mid-word.
- If the user wants no added music in the intro, start it at the first cut.

## 7. Subtitles

Reels get watched on mute, so every spoken line needs subtitles, burned in
because that works on every platform; a separate SRT only helps where one
can be uploaded (YouTube). Do them after the picture is locked: burning in
re-encodes the video.

1. Transcribe the spoken stretch from the video-aligned audio
   (`aresample=first_pts=0`, section 5) with both large-v3 and turbo,
   `-bs 5 -ml 36 -sow -osrt` for subtitle-sized segments. They make
   different mistakes (S10: "Hekken" against "Hacken"), so agreement is
   the signal.
2. Where they disagree, re-run that window alone with each; if it still
   differs per run (S10: "Joost! Ons dode!" against "Goast het"), leave
   that stretch without a subtitle and ask the user what was said. A wrong
   name on screen is worse than a gap.
3. Hand-edit the SRT into readable cues: at least 1.2 s on screen, at most
   two lines, a `- ` per speaker in a quick exchange, names the user has
   confirmed ("Worsje"). A disputed word may be filled from context only
   when the domain makes it near certain, and then it is listed in your
   reply as a guess: S10 used "placement WOD" where the models heard
   "placement bot", "placementbord" and "basement wat".
4. [scripts/srt_to_ass.py](scripts/srt_to_ass.py) `in.srt out.ass` styles
   it: Montserrat Bold 58 px with a black outline at 1280 high, centred at
   about two thirds of the height, above the caption and button areas of
   Reels and TikTok. It writes ASS because `subtitles=x.srt:force_style=`
   measures on a 288 px canvas, not in pixels.
5. Burn in and keep the finished audio:
   `ffmpeg -i render.mkv -i final.mp4 -map 0:v -map 1:a -vf "ass=out.ass:fontsdir=MONTSERRAT/share/fonts/otf" -c:v libx264 -crf 18 -c:a copy out.mp4`
6. Deliver the SRT next to the video as `NAME.nl.srt` for platforms with soft
   subtitles, and list the gaps in your reply.

## 8. Loudness

- `amix` with `normalize=0` sums its inputs and the conversion to s16 then
  clips (measured +0.6 dBTP). Halve the master (`volume=0.5`) in the render.
- Measure with `ebur128=peak=true`, then in the final encode apply
  `volume=<gain>dB,alimiter=limit=0.841:level=disabled` (ceiling -1.5 dB) to
  reach -14 LUFS, with AAC 192k and `-movflags +faststart`.
- Music under speech sits 13 to 15 dB below the speech.

## 9. Verify before delivering

- A 2 fps contact sheet of the whole render, and 10 fps around the hero
  moment to see it fall on its beat.
- Per-segment A/V sync, as in section 5.
- An untouched intro: its audio envelope correlates 1.0 with the source.
- Music position: cross-correlate the render after the cut and after any jump
  against the clean song; expect the planned song time within 20 ms.
- Speech over music: whisper on the mixed intro should still get the words.
- Subtitles: a 1 fps contact sheet over the spoken part; each line readable,
  clear of watermarks, and on screen while it is said.
- Report duration, LUFS and peak, and list what you could not check.
