"""Pack approved transparent character sheets into the same slots as their card portraits."""
import argparse
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SIZE = 256
FLOOR = 246


def gutter(projection, near, radius):
    start, stop = max(1, near - radius), min(len(projection) - 1, near + radius)
    band = projection[start:stop + 1]
    candidates = np.flatnonzero(band == band.min()) + start
    place = int(candidates[np.argmin(abs(candidates - near))])
    if projection[place] > 2:
        raise ValueError(f"No clear gutter near {near}; inspect source before packing")
    return place


def cells(sheet, columns):
    if sheet.mode != "RGBA":
        raise ValueError("A transparent RGBA sheet is required")
    mask = np.asarray(sheet.getchannel("A")) > 70
    height, width = mask.shape
    step = width // columns
    xs = [0] + [gutter(mask.sum(axis=0), i * step, step // 4)
                for i in range(1, columns)] + [width]
    for row in range(2):
        for left, right in zip(xs, xs[1:]):
            cut = gutter(mask[:, left:right].sum(axis=1), height // 2, height // 8)
            rect = (left, 0 if row == 0 else cut, right, cut if row == 0 else height)
            yield sheet.crop(rect)


def figure(cell, width=SIZE, fixed_scale=None):
    alpha = np.asarray(cell.getchannel("A")).copy()
    alpha[alpha < 12] = 0
    cell.putalpha(Image.fromarray(alpha))
    ys, xs = np.nonzero(alpha >= 55)
    if len(xs) < 800 or (alpha == 0).mean() < 0.15:
        raise ValueError("Missing silhouette or opaque background")
    left, right, top, bottom = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    # Estimate the planted feet from the lowest 8% of ink. A spear or flag tip
    # touching the ground must not pull the pivot to the edge of the piece.
    feet = xs[ys >= bottom - max(5, int((bottom - top) * 0.08))]
    pivot = (np.percentile(feet, 8) + np.percentile(feet, 92)) / 2
    scale = fixed_scale or min(226 / (bottom - top), (width / 2 - 7) / max(1, pivot - left, right - pivot))
    box = (max(0, left - 2), max(0, top - 2), min(cell.width, right + 2), min(cell.height, bottom + 2))
    ink = cell.crop(tuple(map(int, box)))
    scaled = ink.resize((round(ink.width * scale), round(ink.height * scale)), Image.Resampling.LANCZOS)
    location = (round(width / 2 - (pivot - box[0]) * scale), round(FLOOR - (bottom - box[1]) * scale))
    if min(location) < 0 or location[0] + scaled.width > width or location[1] + scaled.height > SIZE:
        raise ValueError(f"Figure would be clipped at {location} / {scaled.size}")
    result = Image.new("RGBA", (width, SIZE))
    result.alpha_composite(scaled, location)
    return result


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("originals", type=Path)
    cli.add_argument("--record", type=Path, default=ROOT / "assets/art/pieces/production.json")
    cli.add_argument("--output", type=Path, default=ROOT / "assets/art/pieces")
    args = cli.parse_args()
    args.output.mkdir(exist_ok=True, parents=True)
    record = json.loads(args.record.read_text(encoding="utf-8"))
    figures = {}
    for group in record["standing"]:
        with Image.open(args.originals / group["source"]) as source:
            members = group["cards"]
            for key, cell in zip(members, cells(source, len(members) // 2), strict=True):
                if key in figures:
                    raise ValueError(f"Duplicate unit {key}")
                figures[key] = figure(cell)
    with Image.open(args.originals / record["ferryman"]["source"]) as source:
        cels = list(cells(source, 2))
        figures["ferry_pikeman"] = figure(cels[0], fixed_scale=0.45)
        strip = Image.new("RGBA", (448 * 3, SIZE))
        for i, cell in enumerate(cels[1:]):
            strip.paste(figure(cell, width=448, fixed_scale=0.45), (i * 448, 0))
        strip.save(args.output / "ferry-pikeman-actions.png", optimize=True)
    library = (ROOT / "scripts/art_library.gd").read_text(encoding="utf-8")
    for name, cols, rows, ids in re.findall(r'"([\w-]+)": \{"columns": (\d+), "rows": (\d+), "ids": (\[[^\]]+\])\}', library):
        members = json.loads(ids)
        if not any(key in figures for key in members):
            continue
        sheet = Image.new("RGBA", (int(cols) * SIZE, int(rows) * SIZE))
        for i, key in enumerate(members):
            if key in figures:
                sheet.paste(figures.pop(key), (i % int(cols) * SIZE, i // int(cols) * SIZE))
        sheet.save(args.output / (name + ".png"), optimize=True)
    if figures:
        raise ValueError("Unmapped figures: " + ", ".join(figures))


if __name__ == "__main__":
    main()
