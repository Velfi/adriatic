#!/usr/bin/env python3
"""Capture front, side, and top plant views and compose a reference sheet."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "build" / "captures" / "plant-sheet.png"
VIEW_SIZE = (640, 640)


@dataclass(frozen=True)
class PlantInfo:
    title: str
    form: str
    habit: str
    size: str


# This is presentation metadata, not generation input. Keep generated geometry
# authoritative; callers can override the size line for a particular specimen.
PLANTS: dict[str, PlantInfo] = {
    "olive": PlantInfo("Olive", "tree", "free-standing", "medium tree"),
    "cypress": PlantInfo("Italian cypress", "tree", "free-standing", "tall tree"),
    "grapevine": PlantInfo("Grapevine", "vine", "trellised", "climber"),
    "fig": PlantInfo("Common fig", "tree", "free-standing", "small tree"),
    "lemon": PlantInfo("Lemon", "tree", "free-standing", "small tree"),
    "pomegranate": PlantInfo("Pomegranate", "tree", "free-standing", "small tree"),
    "almond": PlantInfo("Almond", "tree", "free-standing", "medium tree"),
    "oleander": PlantInfo("Oleander", "shrub", "free-standing", "large shrub"),
    "bougainvillea": PlantInfo("Bougainvillea", "vine", "wall-trained", "climber"),
    "rosemary": PlantInfo("Rosemary", "shrub", "free-standing", "small shrub"),
    "stone-pine": PlantInfo("Stone pine", "tree", "free-standing", "large tree"),
    "bay-laurel": PlantInfo("Bay laurel", "tree", "free-standing", "medium tree"),
    "carob": PlantInfo("Carob", "tree", "free-standing", "large tree"),
    "strawberry-tree": PlantInfo("Strawberry tree", "tree", "free-standing", "small tree"),
    "myrtle": PlantInfo("Myrtle", "shrub", "free-standing", "medium shrub"),
    "mastic": PlantInfo("Mastic", "shrub", "free-standing", "medium shrub"),
    "lavender": PlantInfo("Lavender", "shrub", "free-standing", "small shrub"),
    "thyme": PlantInfo("Thyme", "herb", "free-standing", "groundcover"),
    "sage": PlantInfo("Sage", "herb", "free-standing", "small shrub"),
    "prickly-pear": PlantInfo("Prickly pear", "cactus", "free-standing", "large succulent"),
    "pelargonium": PlantInfo("Pelargonium", "flower", "free-standing", "small plant"),
    "wisteria": PlantInfo("Wisteria", "vine", "wall-trained", "climber"),
    "climbing-rose": PlantInfo("Climbing rose", "vine", "wall-trained", "climber"),
    "hydrangea-bush": PlantInfo("Pruned hydrangea", "shrub", "free-standing", "medium shrub"),
    "hydrangea-tree": PlantInfo("Tree hydrangea", "tree", "free-standing", "small tree"),
    "agapanthus": PlantInfo("Agapanthus", "flower", "free-standing", "small plant"),
    "star-jasmine": PlantInfo("Star jasmine", "vine", "wall-trained", "climber"),
    "holm-oak": PlantInfo("Holm oak", "tree", "free-standing", "large tree"),
    "oriental-plane": PlantInfo("Oriental plane", "tree", "free-standing", "large tree"),
    "european-hackberry": PlantInfo("European hackberry", "tree", "free-standing", "large tree"),
    "white-poplar": PlantInfo("White poplar", "tree", "free-standing", "large tree"),
    "golden-barrel": PlantInfo("Golden barrel cactus", "cactus", "free-standing", "small succulent"),
    "agave": PlantInfo("Agave", "succulent", "free-standing", "medium succulent"),
    "aloe": PlantInfo("Aloe", "succulent", "free-standing", "small succulent"),
    "aeonium": PlantInfo("Aeonium", "succulent", "free-standing", "small succulent"),
    "echeveria": PlantInfo("Echeveria", "succulent", "free-standing", "groundcover"),
    "jade": PlantInfo("Jade plant", "succulent", "free-standing", "small succulent"),
    "stonecrop": PlantInfo("Stonecrop", "succulent", "free-standing", "groundcover"),
    "blue-chalk-sticks": PlantInfo("Blue chalk sticks", "succulent", "free-standing", "groundcover"),
    "golden-torch": PlantInfo("Golden torch cactus", "cactus", "free-standing", "medium succulent"),
}


# Keep the overhead view slightly oblique so the camera retains a stable up
# vector and the crown still reads as volume instead of a flat silhouette.
VIEWS = (("FRONT", "0,0"), ("SIDE", "90,0"), ("TOP", "0,65"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("species", choices=sorted(PLANTS))
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--seed", type=int, default=73)
    parser.add_argument("--size", help="specimen size, for example '4.2 m high x 3.6 m wide'")
    parser.add_argument("--note", action="append", default=[], help="extra card line; repeatable")
    parser.add_argument("--settle-frames", type=int, default=4)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--keep-frames", action="store_true")
    parser.add_argument("--reuse-frames", action="store_true")
    return parser.parse_args()


def capture(args: argparse.Namespace, frame_dir: Path) -> list[Path]:
    app = ROOT / "build" / "dev" / "adriatic"
    if args.build or not app.exists():
        subprocess.run(["make", "build"], cwd=ROOT, check=True)
    if not app.exists():
        raise RuntimeError(f"capture app was not produced: {app}")

    # The sheet suffix asks the plant lab for a world-only presentation while
    # leaving ordinary interactive and diagnostic captures unchanged.
    target = f"{args.species}-sheet"
    # Seed-series capture is the generic seed override supported by the app.
    # Capture one seed, then move its deterministic output into each view slot.
    frames: list[Path] = []
    for label, orbit in VIEWS:
        temporary = frame_dir / f"{label.lower()}-seed"
        temporary.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                str(app), "capture", "plant-generator", "--output", str(temporary),
                "--target", target, "--width", str(VIEW_SIZE[0]), "--height", str(VIEW_SIZE[1]),
                "--settle-frames", str(args.settle_frames), "--camera-orbit", orbit,
                "--seed-frames", "1", "--seed-start", str(args.seed),
            ],
            cwd=ROOT,
            check=True,
        )
        produced = temporary / f"seed-{args.seed}.png"
        if not produced.exists() or produced.stat().st_size == 0:
            raise RuntimeError(f"capture did not produce {produced}")
        destination = frame_dir / f"{label.lower()}.png"
        produced.replace(destination)
        temporary.rmdir()
        frames.append(destination)
    return frames


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/System/Library/Fonts/SFNS.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def compose(args: argparse.Namespace, frames: list[Path]) -> None:
    info = PLANTS[args.species]
    margin, gap, card_width = 34, 18, 360
    view_width, view_height = VIEW_SIZE
    header = 112
    width = margin * 2 + view_width * 3 + gap * 3 + card_width
    height = header + view_height + margin
    sheet = Image.new("RGB", (width, height), (23, 27, 24))
    draw = ImageDraw.Draw(sheet)
    title_font, label_font, body_font, small_font = font(34, True), font(19, True), font(19), font(15)
    draw.text((margin, 28), info.title.upper(), fill=(239, 236, 215), font=title_font)
    draw.text((margin, 72), f"SEED {args.seed}  /  MATURE  /  NEAR DETAIL", fill=(143, 164, 143), font=small_font)

    x = margin
    for (label, _), path in zip(VIEWS, frames, strict=True):
        with Image.open(path) as source:
            image = source.convert("RGB")
            if image.size != VIEW_SIZE:
                image = image.resize(VIEW_SIZE, Image.Resampling.LANCZOS)
            sheet.paste(image, (x, header))
        draw.rectangle((x, header, x + 92, header + 36), fill=(23, 27, 24))
        draw.text((x + 12, header + 7), label, fill=(239, 236, 215), font=label_font)
        x += view_width + gap

    card_x = x
    draw.rounded_rectangle((card_x, header, card_x + card_width, header + view_height), radius=16, fill=(38, 45, 39), outline=(91, 109, 91), width=2)
    y = header + 32
    draw.text((card_x + 28, y), "PLANT", fill=(142, 166, 143), font=small_font)
    y += 30
    draw.text((card_x + 28, y), info.title, fill=(239, 236, 215), font=label_font)
    y += 58
    lines = [
        ("SIZE", args.size or info.size),
        ("FORM", info.form),
        ("HABIT", info.habit),
        ("MATURITY", "100%"),
        ("DETAIL", "near"),
        ("SEED", str(args.seed)),
    ]
    for key, value in lines:
        draw.text((card_x + 28, y), key, fill=(142, 166, 143), font=small_font)
        draw.text((card_x + 28, y + 23), value, fill=(229, 228, 209), font=body_font)
        y += 67
    for note in args.note[:2]:
        draw.text((card_x + 28, y), note[:34], fill=(197, 204, 184), font=small_font)
        y += 25

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    manifest = {
        "species": args.species,
        "seed": args.seed,
        "maturity": 1.0,
        "detail": "near",
        "size": args.size or info.size,
        "plant": asdict(info),
        "views": [{"name": label.lower(), "camera_orbit": orbit} for label, orbit in VIEWS],
        "output": str(args.output),
    }
    args.output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")


def main() -> None:
    args = parse_args()
    if args.seed < 0:
        raise SystemExit("--seed must be non-negative")
    args.output = args.output.resolve()
    frame_dir = args.output.parent / f"{args.output.stem}-frames"
    frame_dir.mkdir(parents=True, exist_ok=True)
    frames = [frame_dir / f"{label.lower()}.png" for label, _ in VIEWS]
    if args.reuse_frames:
        missing = [str(path) for path in frames if not path.exists() or path.stat().st_size == 0]
        if missing:
            raise RuntimeError("missing reusable frames: " + ", ".join(missing))
    else:
        frames = capture(args, frame_dir)
    compose(args, frames)
    if not args.keep_frames and not args.reuse_frames:
        shutil.rmtree(frame_dir)
    print(args.output)


if __name__ == "__main__":
    main()
