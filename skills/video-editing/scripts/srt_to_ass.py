#!/usr/bin/env python3
"""Turn an SRT file into an ASS file styled for burning into a vertical reel.

usage: srt_to_ass.py IN.srt OUT.ass [--width 720] [--height 1280] [--font Montserrat]
burn in: ffmpeg -i in.mp4 -vf "ass=OUT.ass:fontsdir=FONT_DIR" -c:a copy out.mp4
  FONT_DIR: $(nix-store -r $(nix-instantiate '<nixpkgs>' -A montserrat))/share/fonts/otf

Decision: ASS instead of `subtitles=x.srt:force_style=...`: SRT is laid out on a 288
pixel high canvas, so sizes in force_style are fractions of 288 rather than
pixels. Here PlayRes equals the video size and every number is a pixel.
Placement: Instagram and TikTok cover roughly the bottom fifth with the
caption and the right edge with buttons, so lines sit centred at about two
thirds of the height, white bold with a black outline for bright gyms.
"""
import argparse
import re

STYLE = ("Style: Reel,{font},{size},&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,"
         "-1,0,0,0,100,100,0,0,1,{outline},0,2,{side},{side},{bottom},1")
TIME = re.compile(r"(\d+):(\d\d):(\d\d)[,.](\d{3})")


def ass_time(srt_time: str) -> str:
    match = TIME.fullmatch(srt_time.strip())
    if not match:
        raise SystemExit(f"not an SRT timestamp: {srt_time!r}")
    hours, minutes, seconds, millis = (int(group) for group in match.groups())
    return f"{hours}:{minutes:02d}:{seconds:02d}.{millis // 10:02d}"


def cues(srt: str) -> list[tuple[str, str, str]]:
    """(start, end, text) per SRT block; lines of one cue are joined with ASS line breaks."""
    parsed = []
    for block in re.split(r"\n\s*\n", srt.strip()):
        lines = block.strip().splitlines()
        if len(lines) < 3 or "-->" not in lines[1]:
            raise SystemExit(f"malformed SRT block:\n{block}")
        start, end = lines[1].split("-->")
        parsed.append((ass_time(start), ass_time(end), r"\N".join(line.strip() for line in lines[2:])))
    return parsed


def main() -> None:
    parser = argparse.ArgumentParser(description="SRT to reel-styled ASS")
    parser.add_argument("srt")
    parser.add_argument("ass")
    parser.add_argument("--width", type=int, default=720)
    parser.add_argument("--height", type=int, default=1280)
    parser.add_argument("--font", default="Montserrat")
    args = parser.parse_args()

    size = round(args.height * 0.045)            # 58 px at 1280: readable on a phone, two lines fit
    style = STYLE.format(font=args.font, size=size, outline=max(2, size // 12),
                         side=round(args.width * 0.08), bottom=round(args.height * 0.30))
    header = "\n".join([
        "[Script Info]", "ScriptType: v4.00+", f"PlayResX: {args.width}", f"PlayResY: {args.height}",
        "WrapStyle: 0", "ScaledBorderAndShadow: yes", "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
        "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, "
        "Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        style, "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ])
    with open(args.srt, encoding="utf-8") as handle:
        events = [f"Dialogue: 0,{start},{end},Reel,,0,0,0,,{text}" for start, end, text in cues(handle.read())]
    with open(args.ass, "w", encoding="utf-8") as handle:
        handle.write(header + "\n" + "\n".join(events) + "\n")


if __name__ == "__main__":
    main()
