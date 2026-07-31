from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH, HEIGHT = 640, 360
FRAMES = 40
DURATION_MS = 35
WIPE_COLOR = (5, 8, 12, 255)


def scene(incoming: bool) -> Image.Image:
    image = Image.new("RGBA", (WIDTH, HEIGHT), (91, 157, 190, 255) if not incoming else (232, 151, 87, 255))
    draw = ImageDraw.Draw(image)
    horizon = 205 if not incoming else 178
    draw.rectangle((0, horizon, WIDTH, HEIGHT), fill=(29, 111, 139, 255) if not incoming else (48, 119, 112, 255))
    draw.polygon(
        [(0, horizon + 38), (115, horizon - 24), (242, horizon + 14), (370, horizon - 48), (WIDTH, horizon + 20), (WIDTH, HEIGHT), (0, HEIGHT)],
        fill=(92, 127, 73, 255) if not incoming else (137, 109, 63, 255),
    )
    sun_x = 118 if not incoming else 516
    draw.ellipse((sun_x - 35, 48, sun_x + 35, 118), fill=(255, 234, 161, 255))
    tower_x = 425 if not incoming else 174
    draw.rectangle((tower_x - 26, horizon - 112, tower_x + 26, horizon + 4), fill=(239, 222, 181, 255))
    draw.polygon([(tower_x - 38, horizon - 112), (tower_x, horizon - 147), (tower_x + 38, horizon - 112)], fill=(173, 62, 45, 255))
    draw.rectangle((tower_x - 9, horizon - 73, tower_x + 9, horizon - 48), fill=(42, 77, 91, 255))
    title = "CAMERA B" if incoming else "CAMERA A"
    draw.rounded_rectangle((20, 20, 154, 58), radius=10, fill=(5, 8, 12, 205))
    draw.text((37, 31), title, fill=(255, 248, 220, 255), font=ImageFont.load_default())
    return image


def directional(a: Image.Image, b: Image.Image, kind: str, progress: float) -> Image.Image:
    frame = a.copy()
    if kind in ("left", "right"):
        amount = max(1, round(WIDTH * progress))
        x = 0 if kind == "left" else WIDTH - amount
        frame.paste(b.crop((x, 0, x + amount, HEIGHT)), (x, 0))
    else:
        amount = max(1, round(HEIGHT * progress))
        y = HEIGHT - amount if kind == "up" else 0
        frame.paste(b.crop((0, y, WIDTH, y + amount)), (0, y))
    return frame


def shaped(a: Image.Image, b: Image.Image, kind: str, progress: float) -> Image.Image:
    frame = (a if progress < .5 else b).copy()
    coverage = progress * 2 if progress <= .5 else (1 - progress) * 2
    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(mask)
    if kind == "iris":
        radius = math.hypot(WIDTH, HEIGHT) * .55 * coverage
        draw.ellipse((WIDTH / 2 - radius, HEIGHT / 2 - radius, WIDTH / 2 + radius, HEIGHT / 2 + radius), fill=255)
    elif kind == "clockwise":
        steps = max(1, math.ceil(72 * coverage))
        points = [(WIDTH / 2, HEIGHT / 2)]
        radius = math.hypot(WIDTH, HEIGHT) * .6
        for index in range(steps + 1):
            angle = -math.pi / 2 + index * 2 * math.pi / 72
            points.append((WIDTH / 2 + radius * math.cos(angle), HEIGHT / 2 + radius * math.sin(angle)))
        draw.polygon(points, fill=255)
    elif kind == "checker":
        cell_w, cell_h = WIDTH / 12, HEIGHT / 8
        threshold = coverage * 2
        for row in range(8):
            for column in range(12):
                cell_coverage = min(1, max(0, threshold - ((row + column) & 1)))
                if cell_coverage:
                    x, y = round(column * cell_w), round(row * cell_h)
                    draw.rectangle((x, y, round(x + cell_w * cell_coverage), math.ceil(y + cell_h)), fill=255)
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), WIPE_COLOR)
    frame.paste(overlay, mask=mask)
    return frame


def main() -> None:
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    outgoing, incoming = scene(False), scene(True)
    kinds = ("left", "right", "up", "down", "iris", "clockwise", "checker")
    for kind in kinds:
        frames = []
        for index in range(FRAMES):
            progress = index / (FRAMES - 1)
            frame = directional(outgoing, incoming, kind, progress) if kind in kinds[:4] else shaped(outgoing, incoming, kind, progress)
            frames.append(frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=128))
        path = output / f"wipe-{kind}.gif"
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=DURATION_MS, loop=0, disposal=2, optimize=True)


if __name__ == "__main__":
    main()
