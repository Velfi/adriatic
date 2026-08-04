#!/usr/bin/env python3
"""Capture a deterministic plant-wind phase review and assemble it as a GIF."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT / "build/dev/adriatic"
SPECIES = (
    "gallery",
    "olive",
    "cypress",
    "grapevine",
    "fig",
    "lemon",
    "pomegranate",
    "almond",
    "oleander",
    "bougainvillea",
    "rosemary",
    "stone-pine",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--species", choices=SPECIES, default="almond")
    parser.add_argument("--weather", choices=("calm", "windy", "storm"), default="windy")
    parser.add_argument("--output", type=Path, default=ROOT / "build/captures/plant-wind.gif")
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--frames", type=int, choices=(8, 16), default=16)
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument(
        "--keep-frames",
        action="store_true",
        help="retain the captured PNG sequence beside the GIF",
    )
    return parser.parse_args()


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> int:
    args = parse_args()
    app = args.app.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not app.is_file():
        raise SystemExit(f"missing capture app: {app}; run `make build` first")
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise SystemExit("ffmpeg is required to assemble the GIF")

    frame_dir = output.with_suffix("")
    frame_dir.mkdir(parents=True, exist_ok=True)
    run(
        [
            str(app),
            "capture",
            "plant-generator",
            "--output",
            str(frame_dir),
            "--target",
            f"{args.species}-{args.weather}-phase16-0",
            "--width",
            str(args.width),
            "--height",
            str(args.height),
            "--settle-frames",
            "2",
            "--wind-phase-frames",
            str(args.frames),
        ]
    )
    for output_index in range(args.frames):
        captured = frame_dir / f"frame-{output_index:06d}.png"
        captured.rename(frame_dir / f"frame-{output_index:03d}.png")

    # Reverse the interior frames to make the review loop seamlessly even
    # though foliage uses several deliberately incommensurate gust frequencies.
    forward = list(range(args.frames))
    playback = forward + forward[-2:0:-1]
    concat = frame_dir / "frames.txt"
    frame_duration = 1 / max(args.fps, 1)
    concat.write_text(
        "".join(
            f"file '{(frame_dir / f'frame-{index:03d}.png').as_posix()}'\n"
            f"duration {frame_duration:.9f}\n"
            for index in playback
        ),
        encoding="utf-8",
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    palette = frame_dir / "palette.png"
    run(
        [
            ffmpeg,
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat),
            "-vf",
            "palettegen=stats_mode=diff",
            str(palette),
        ]
    )
    run(
        [
            ffmpeg,
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat),
            "-i",
            str(palette),
            "-lavfi",
            "paletteuse=dither=sierra2_4a",
            "-loop",
            "0",
            str(output),
        ]
    )
    if not args.keep_frames:
        shutil.rmtree(frame_dir)
    print(f"Plant wind GIF: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
