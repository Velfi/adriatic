#!/usr/bin/env python3
"""Render the deterministic forest from eye level through an aerial overview."""

from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "build" / "captures" / "forest-zoom-contact-sheet.png"


@dataclass(frozen=True)
class Shot:
    name: str
    distance: int
    pitch: int
    description: str


SHOTS = (
    Shot("01-eye-level", 105, -21, "eye level / individual trunks"),
    Shot("02-forest-edge", 175, -13, "forest edge / crown overlap"),
    Shot("03-raised", 285, 0, "raised view / grove composition"),
    Shot("04-overview", 430, 17, "overview / canopy hierarchy"),
    Shot("05-high-aerial", 650, 38, "high aerial / woodland mass"),
    Shot("06-map-aerial", 920, 56, "map aerial / Ghibli blob read"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--width", type=int, default=640, help="width of each captured frame")
    parser.add_argument("--height", type=int, default=400, help="height of each captured frame")
    parser.add_argument("--settle-frames", type=int, default=4)
    parser.add_argument("--crop-top", type=int, default=158, help="remove deterministic gameplay HUD band")
    parser.add_argument("--build", action="store_true", help="run make build before capturing")
    parser.add_argument("--keep-frames", action="store_true")
    parser.add_argument("--reuse-frames", action="store_true", help="compose existing frame PNGs without capturing")
    return parser.parse_args()


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=REPO_ROOT, check=True)


def capture_shots(args: argparse.Namespace, frames_dir: Path) -> list[Path]:
    binary = REPO_ROOT / "build" / "dev" / "adriatic"
    if args.build or not binary.exists():
        run(["make", "build"])
    if not binary.exists():
        raise RuntimeError(f"capture binary was not produced: {binary}")

    frames: list[Path] = []
    for shot in SHOTS:
        frame = frames_dir / f"{shot.name}.png"
        run(
            [
                str(binary),
                "capture",
                "foliage-forest",
                "--output",
                str(frame),
                "--target",
                "contact-sheet",
                "--width",
                str(args.width),
                "--height",
                str(args.height),
                "--settle-frames",
                str(args.settle_frames),
                "--camera-orbit",
                f"0,{shot.pitch}",
                "--camera-distance",
                str(shot.distance),
            ]
        )
        if not frame.exists() or frame.stat().st_size == 0:
            raise RuntimeError(f"capture did not produce a frame: {frame}")
        frames.append(frame)
    return frames


def compose(args: argparse.Namespace, frames: list[Path]) -> None:
    columns = 3
    rows = 2
    gutter = 18
    header = 68
    label_height = 42
    tile_width = args.width
    visible_height = args.height - args.crop_top
    if visible_height <= 0:
        raise ValueError("--crop-top must be smaller than --height")
    tile_height = visible_height + label_height
    sheet = Image.new(
        "RGB",
        (
            gutter + columns * (tile_width + gutter),
            header + rows * (tile_height + gutter),
        ),
        (24, 29, 27),
    )
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    draw.text((gutter, 18), "FOREST SCALE STUDY - EYE LEVEL TO AERIAL", fill=(232, 229, 205), font=font)
    draw.text(
        (gutter, 38),
        "Matched scene, focus, lighting, and yaw - distance and elevation change only",
        fill=(148, 164, 143),
        font=font,
    )

    for index, (shot, frame_path) in enumerate(zip(SHOTS, frames, strict=True)):
        column = index % columns
        row = index // columns
        x = gutter + column * (tile_width + gutter)
        y = header + row * (tile_height + gutter)
        with Image.open(frame_path) as source:
            frame = source.convert("RGB")
            if frame.size != (tile_width, args.height):
                frame = frame.resize((tile_width, args.height), Image.Resampling.LANCZOS)
            if args.crop_top:
                frame = frame.crop((0, args.crop_top, tile_width, args.height))
            sheet.paste(frame, (x, y))
        draw.text((x + 8, y + visible_height + 7), shot.description, fill=(226, 224, 201), font=font)
        draw.text(
            (x + 8, y + visible_height + 23),
            f"distance {shot.distance} m  -  pitch offset {shot.pitch:+d} deg",
            fill=(134, 157, 130),
            font=font,
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    manifest = args.output.with_suffix(".json")
    manifest.write_text(
        json.dumps(
            {
                "scene": "foliage-forest",
                "output": str(args.output),
                "frame_size": [args.width, args.height],
                "crop_top": args.crop_top,
                "shots": [asdict(shot) for shot in SHOTS],
            },
            indent=2,
        )
        + "\n"
    )


def main() -> None:
    args = parse_args()
    args.output = args.output.resolve()
    frames_dir = args.output.parent / f"{args.output.stem}-frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    frames = [frames_dir / f"{shot.name}.png" for shot in SHOTS]
    if args.reuse_frames:
        missing = [str(frame) for frame in frames if not frame.exists() or frame.stat().st_size == 0]
        if missing:
            raise RuntimeError("missing reusable frames: " + ", ".join(missing))
    else:
        frames = capture_shots(args, frames_dir)
    compose(args, frames)
    if not args.keep_frames and not args.reuse_frames:
        for frame in frames:
            frame.unlink()
        frames_dir.rmdir()
    print(args.output)


if __name__ == "__main__":
    main()
