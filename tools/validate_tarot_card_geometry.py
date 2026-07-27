#!/usr/bin/env python3
"""Fail when generated tarot sheets contain missing or inconsistently sized cards."""

from __future__ import annotations

import argparse
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path

import cv2


EXPECTED_COUNTS = {
    "trumps-source.png": 22,
    "wands-source.png": 14,
    "cups-source.png": 14,
    "swords-source.png": 14,
    "pentacles-source.png": 14,
}


@dataclass(frozen=True)
class Card:
    sheet: str
    index: int
    x: int
    y: int
    width: int
    height: int

    @property
    def aspect(self) -> float:
        return self.width / self.height


def detect_cards(path: Path) -> list[Card]:
    image = cv2.imread(str(path))
    if image is None:
        raise ValueError(f"could not read {path}")

    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    # Generated sheets use a saturated ochre/gold outer card border.
    mask = cv2.inRange(hsv, (10, 50, 130), (45, 255, 255))
    contours, _ = cv2.findContours(
        mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    boxes = []
    for contour in contours:
        x, y, width, height = cv2.boundingRect(contour)
        if width >= 80 and height >= 120 and width * height >= 15_000:
            boxes.append((x, y, width, height))
    # Generated rows can drift by a few pixels. Cluster by vertical overlap first;
    # sorting directly by y can otherwise move a leftmost card behind its row.
    rows: list[list[tuple[int, int, int, int]]] = []
    for box in sorted(boxes, key=lambda item: (item[1] + item[3] / 2, item[0])):
        center_y = box[1] + box[3] / 2
        for row in rows:
            row_center = statistics.median(
                item[1] + item[3] / 2 for item in row
            )
            row_height = statistics.median(item[3] for item in row)
            if abs(center_y - row_center) < row_height * 0.4:
                row.append(box)
                break
        else:
            rows.append([box])
    boxes = [
        box
        for row in sorted(rows, key=lambda items: min(item[1] for item in items))
        for box in sorted(row, key=lambda item: item[0])
    ]
    return [
        Card(path.name, index, x, y, width, height)
        for index, (x, y, width, height) in enumerate(boxes)
    ]


def relative_error(value: float, expected: float) -> float:
    return abs(value - expected) / expected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "directory",
        nargs="?",
        type=Path,
        default=Path("assets/textures/ui/tarot-openai-separate"),
    )
    parser.add_argument(
        "--tolerance",
        type=float,
        default=0.02,
        help="maximum relative width, height, and aspect-ratio error (default: 0.02)",
    )
    args = parser.parse_args()

    cards: list[Card] = []
    failed = False
    for filename, expected_count in EXPECTED_COUNTS.items():
        path = args.directory / filename
        if not path.exists():
            print(f"FAIL {filename}: file is missing")
            failed = True
            continue
        detected = detect_cards(path)
        print(f"{filename}: detected {len(detected)}/{expected_count} cards")
        if len(detected) != expected_count:
            failed = True
        cards.extend(detected)

    if not cards:
        return 1

    median_width = statistics.median(card.width for card in cards)
    median_height = statistics.median(card.height for card in cards)
    median_aspect = statistics.median(card.aspect for card in cards)
    print(
        f"target: {median_width:g}x{median_height:g}, "
        f"aspect {median_aspect:.4f}, tolerance {args.tolerance:.1%}"
    )

    for card in cards:
        errors = (
            relative_error(card.width, median_width),
            relative_error(card.height, median_height),
            relative_error(card.aspect, median_aspect),
        )
        if max(errors) > args.tolerance:
            print(
                f"FAIL {card.sheet} card {card.index:02d}: "
                f"{card.width}x{card.height}, aspect {card.aspect:.4f}"
            )
            failed = True

    if failed:
        print("Tarot geometry validation failed.")
        return 1

    print("Tarot geometry validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
