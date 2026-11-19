"""Crop the empty-berth sprite sheet from Harbor's second full-resolution render."""

import argparse
import re
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bare_quay", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    art = project / "assets/art/battlefields"
    source = (project / "scripts/map_artwork.gd").read_text(encoding="utf-8")
    layout = next(line for line in source.splitlines() if line.startswith("const MOORINGS:"))
    berths = [(int(x), int(y)) for x, y in re.findall(r"Vector2i\((\d+), (\d+)\)", layout)]
    if len(set(berths)) != 4:
        raise ValueError("The harbor requires four separate berths")
    with Image.open(art / "harbor-relief-v1.png") as moored, Image.open(args.bare_quay) as empty:
        if moored.size != empty.size or empty.size != (2160, 1800):
            raise ValueError("Matching final-size harbor renders are required")
        tile = empty.width // 12
        sheet = Image.new("RGB", (2 * tile, 2 * tile))
        outside = ImageChops.difference(moored, empty).convert("L")
        for index, (x, y) in enumerate(berths):
            box = (x * tile, y * tile, (x + 1) * tile, (y + 1) * tile)
            water = empty.crop(box)
            change = ImageStat.Stat(ImageChops.difference(moored.crop(box), water))
            if max(change.mean) < 5:
                raise ValueError(f"Missing vessel or mooring lines in source tile {x},{y}")
            sheet.paste(water, (index % 2 * tile, index // 2 * tile))
            outside.paste(0, box)
        if sum(outside.histogram()[32:]) > 12:
            raise ValueError("A vessel or its cast shadow extends beyond the replacement tiles")
        sheet.save(art / "harbor-empty-moorings-v1.png")
    print(f"Packed four {tile}px empty berths from the matching camera")


if __name__ == "__main__":
    main()
