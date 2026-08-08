#!/usr/bin/env python3
"""Restore opaque white labels inside blue controls in transparent guide assets."""

from collections import defaultdict
from pathlib import Path

from PIL import Image


ASSET_DIRECTORY = Path(__file__).resolve().parent / "assets" / "cs2-combiner-guide"
TARGETS = [
    "export-controls.png",
    "import-overview.png",
    "texture-slots.png",
    "opacity-controls-attached.png",
    "lod2-attached.png",
]


def is_blue(pixel):
    red, green, blue, alpha = pixel
    return (
        alpha > 128
        and blue > 160
        and blue > red * 1.35
        and blue > green * 1.08
        and red < 150
    )


def blue_components(image):
    pixels = image.load()
    width, height = image.size
    remaining = {
        (x, y)
        for y in range(height)
        for x in range(width)
        if is_blue(pixels[x, y])
    }

    while remaining:
        seed = remaining.pop()
        pending = [seed]
        component = [seed]
        while pending:
            x, y = pending.pop()
            for neighbour in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbour in remaining:
                    remaining.remove(neighbour)
                    pending.append(neighbour)
                    component.append(neighbour)
        if len(component) >= 100:
            yield component


def restore_labels(path):
    image = Image.open(path).convert("RGBA")
    pixels = image.load()
    restored = 0

    for component in blue_components(image):
        rows = defaultdict(list)
        for x, y in component:
            rows[y].append(x)

        interior = set()
        for y, blue_xs in rows.items():
            if len(blue_xs) < 2:
                continue
            for x in range(min(blue_xs), max(blue_xs) + 1):
                interior.add((x, y))
                _, _, _, alpha = pixels[x, y]
                if alpha < 250:
                    pixels[x, y] = (255, 255, 255, 255)
                    restored += 1

        # Background removal preserved dark antialiasing around the deleted white
        # glyph cores. Grow from the restored white cores through only neutral-colour
        # pixels inside the blue control, then normalise the complete glyph to white.
        candidates = {
            point
            for point in interior
            if max(pixels[point][:3]) - min(pixels[point][:3]) < 90
        }
        pending = [
            point
            for point in candidates
            if min(pixels[point][:3]) > 220 and pixels[point][3] > 0
        ]
        label_pixels = set(pending)
        while pending:
            x, y = pending.pop()
            for neighbour in (
                (x - 1, y - 1),
                (x, y - 1),
                (x + 1, y - 1),
                (x - 1, y),
                (x + 1, y),
                (x - 1, y + 1),
                (x, y + 1),
                (x + 1, y + 1),
            ):
                if neighbour in candidates and neighbour not in label_pixels:
                    label_pixels.add(neighbour)
                    pending.append(neighbour)

        for point in label_pixels:
            if pixels[point] != (255, 255, 255, 255):
                pixels[point] = (255, 255, 255, 255)
                restored += 1

    image.save(path, optimize=True)
    return restored


def main():
    for name in TARGETS:
        path = ASSET_DIRECTORY / name
        restored = restore_labels(path)
        print(f"{name}: restored {restored} white control-label pixels")


if __name__ == "__main__":
    main()
