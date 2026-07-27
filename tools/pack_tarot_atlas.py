#!/usr/bin/env python3
"""Crop generated tarot sheets and normalize all 78 cards into one fixed atlas."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

from validate_tarot_card_geometry import EXPECTED_COUNTS, detect_cards


CELL_WIDTH = 108
CELL_HEIGHT = 158
ATLAS_COLUMNS = 14
ATLAS_ROWS = 6
# OpenCV stores colors as BGR; this is the UI's #1b102b aubergine.
BACKGROUND = (43, 16, 27)


def destination_cell(deck_index: int) -> tuple[int, int]:
    if deck_index < 14:
        return deck_index, 0
    if deck_index < 22:
        return deck_index - 14, 1
    suit_index = (deck_index - 22) // 14
    rank_index = (deck_index - 22) % 14
    return rank_index, suit_index + 2


def main() -> int:
    project = Path(__file__).resolve().parent.parent
    source_dir = project / "assets/textures/ui/tarot-openai-separate"
    output = project / "assets/textures/ui/tarot-atlas-v4.png"
    metadata = project / "assets/textures/ui/tarot-atlas-v4.json"
    ordered_sheets = (
        "trumps-source.png",
        "wands-source.png",
        "cups-source.png",
        "swords-source.png",
        "pentacles-source.png",
    )

    atlas = np.full(
        (ATLAS_ROWS * CELL_HEIGHT, ATLAS_COLUMNS * CELL_WIDTH, 3),
        BACKGROUND,
        dtype=np.uint8,
    )
    deck_index = 0
    source_geometry: dict[str, list[dict[str, int]]] = {}

    for filename in ordered_sheets:
        path = source_dir / filename
        cards = detect_cards(path)
        expected = EXPECTED_COUNTS[filename]
        if len(cards) != expected:
            print(f"FAIL {filename}: detected {len(cards)}/{expected} cards")
            return 1

        source = cv2.imread(str(path))
        source_geometry[filename] = []
        for card in cards:
            crop = source[
                card.y : card.y + card.height,
                card.x : card.x + card.width,
            ]
            normalized = cv2.resize(
                crop,
                (CELL_WIDTH, CELL_HEIGHT),
                interpolation=cv2.INTER_AREA,
            )
            column, row = destination_cell(deck_index)
            x = column * CELL_WIDTH
            y = row * CELL_HEIGHT
            atlas[y : y + CELL_HEIGHT, x : x + CELL_WIDTH] = normalized
            source_geometry[filename].append(
                {
                    "index": card.index,
                    "x": card.x,
                    "y": card.y,
                    "width": card.width,
                    "height": card.height,
                }
            )
            deck_index += 1

    if deck_index != 78:
        print(f"FAIL packed {deck_index}/78 cards")
        return 1
    expected_shape = (ATLAS_ROWS * CELL_HEIGHT, ATLAS_COLUMNS * CELL_WIDTH, 3)
    if atlas.shape != expected_shape:
        print(f"FAIL atlas shape {atlas.shape}, expected {expected_shape}")
        return 1
    if not cv2.imwrite(str(output), atlas):
        print(f"FAIL could not write {output}")
        return 1

    metadata.write_text(
        json.dumps(
            {
                "image": output.name,
                "sources": list(ordered_sheets),
                "width": atlas.shape[1],
                "height": atlas.shape[0],
                "columns": ATLAS_COLUMNS,
                "rows": ATLAS_ROWS,
                "cell_width": CELL_WIDTH,
                "cell_height": CELL_HEIGHT,
                "card_count": deck_index,
                "source_geometry": source_geometry,
            },
            indent=2,
        )
        + "\n"
    )
    print(
        f"PASS packed {deck_index} cards into "
        f"{atlas.shape[1]}x{atlas.shape[0]} atlas with "
        f"uniform {CELL_WIDTH}x{CELL_HEIGHT} cells"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
