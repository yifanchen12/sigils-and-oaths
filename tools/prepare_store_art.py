"""Lay out the exact Steam store and library graphics over the original key art."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1] / "docs" / "release" / "steam"
GAME_ART = Path(__file__).resolve().parents[1] / "assets" / "art"
TITLE = "纹章与誓约"
ENGLISH = "SIGILS & OATHS"


def crop(source: Image.Image, size: tuple[int, int], focus: tuple[float, float]) -> Image.Image:
    width, height = source.size
    target_ratio = size[0] / size[1]
    cut_w, cut_h = min(width, height * target_ratio), min(height, width / target_ratio)
    left = max(0, min(width - cut_w, focus[0] * width - cut_w * 0.5))
    top = max(0, min(height - cut_h, focus[1] * height - cut_h * 0.5))
    return source.resize(size, Image.Resampling.LANCZOS, (left, top, left + cut_w, top + cut_h))


def title_font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(str(path), size)
    try:
        face.set_variation_by_name("Bold")
    except OSError:
        pass
    return face


def title_mark(font_path: Path, size: tuple[int, int], english: bool = True) -> Image.Image:
    width, height = size
    canvas = Image.new("RGBA", size)
    ink = ImageDraw.Draw(canvas)
    bound_w = width * 0.92
    bound_h = height * (0.51 if english else 0.78)
    for points in range(round(width / 4), 9, -1):
        heading = title_font(font_path, points)
        extent = ink.textbbox((0, 0), TITLE, font=heading)
        if extent[2] - extent[0] <= bound_w and extent[3] - extent[1] <= bound_h:
            break
    words = (width * 0.5, height * (0.44 if english else 0.52))
    outline = max(2, round(points * 0.041))
    ink.text((words[0], words[1] + outline * 1.5), TITLE, font=heading, anchor="mm", fill="#183449", stroke_width=outline + 1, stroke_fill="#102433")
    ink.text(words, TITLE, font=heading, anchor="mm", fill="#f6e7c4", stroke_width=outline, stroke_fill="#382923")
    if english:
        small = title_font(font_path, max(12, round(points * 0.27)))
        ink.text((width * 0.5, height * 0.81), ENGLISH, font=small, anchor="mm", fill="#f2ce87", stroke_width=max(1, round(points / 55)), stroke_fill="#27283b")
    return canvas


def backplate(picture: Image.Image, direction: str, strong: float) -> Image.Image:
    shade = Image.new("RGBA", picture.size)
    ink = ImageDraw.Draw(shade)
    width, height = shade.size
    axis = height if direction == "bottom" else width
    for step in range(axis):
        position = step / max(1, axis - 1)
        alpha = round(255 * strong * (position ** 3 if direction == "bottom" else (1 - position) ** 2))
        ink.line((0, step, width, step) if direction == "bottom" else (step, 0, step, height), fill=(10, 20, 29, alpha))
    return Image.alpha_composite(picture.convert("RGBA"), shade)


def capsule(source: Image.Image, size: tuple[int, int], focus: tuple[float, float], font_path: Path, layout: str) -> Image.Image:
    width, height = size
    picture = crop(source, size, focus)
    if layout == "small":
        picture = backplate(picture, "left", 0.92)
        mark = title_mark(font_path, (round(width * 0.73), round(height * 0.56)), False)
        at = (round(width * 0.018), round(height * 0.25))
    elif layout == "portrait":
        picture = backplate(picture, "bottom", 0.87)
        mark = title_mark(font_path, (round(width * 0.90), round(height * 0.22)))
        at = (round(width * 0.05), round(height * 0.745))
    else:
        picture = backplate(picture, "left", 0.62)
        mark = title_mark(font_path, (round(width * 0.43), round(height * 0.29)))
        at = (round(width * 0.018), round(height * 0.24))
    picture.alpha_composite(mark, at)
    return picture.convert("RGB")


def lantern_icon() -> Image.Image:
    scale = 4
    canvas = Image.new("RGBA", (512 * scale, 512 * scale))
    ink = ImageDraw.Draw(canvas)

    def shape(points: list[tuple[int, int]], fill: str, edge: str, width: int) -> None:
        ink.polygon([(x * scale, y * scale) for x, y in points], fill=fill, outline=edge, width=width * scale)

    def box(points: tuple[int, int, int, int], radius: int, fill: str, edge: str, width: int) -> None:
        ink.rounded_rectangle(tuple(value * scale for value in points), radius * scale, fill=fill, outline=edge, width=width * scale)

    box((12, 12, 500, 500), 80, "#153044", "#a87948", 15)
    box((39, 39, 473, 473), 57, "#1c3d4e", "#c4a672", 4)
    shape([(256, 57), (303, 103), (287, 139), (225, 139), (209, 103)], "#8b663f", "#edc481", 9)
    shape([(134, 184), (201, 123), (311, 123), (378, 184)], "#aa7946", "#f3c780", 11)
    shape([(146, 185), (366, 185), (348, 337), (316, 374), (196, 374), (164, 337)], "#326a65", "#e5b66d", 15)
    shape([(240, 202), (272, 202), (326, 279), (256, 342), (186, 279)], "#91d3b7", "#dfedbc", 8)
    shape([(256, 235), (296, 278), (256, 316), (216, 278)], "#fff1c5", "#446d68", 5)
    box((187, 366, 325, 393), 8, "#d19d56", "#f0c781", 6)
    shape([(221, 392), (291, 392), (272, 436), (240, 436)], "#ac5845", "#efc283", 6)
    return canvas.resize((512, 512), Image.Resampling.LANCZOS)


def render(font_path: Path, output: Path, with_runtime_icon: bool) -> None:
    output.mkdir(parents=True, exist_ok=True)
    source = Image.open(ROOT / "key-art-v1.png").convert("RGB")
    graphics = {
        "store-header": ((920, 430), (0.5, 0.4), "landscape"),
        "store-small": ((462, 174), (0.5, 0.325), "small"),
        "store-main": ((1232, 706), (0.5, 0.48), "landscape"),
        "store-vertical": ((748, 896), (0.68, 0.50), "portrait"),
        "library-capsule": ((600, 900), (0.70, 0.50), "portrait"),
        "library-header": ((920, 430), (0.5, 0.4), "landscape"),
    }
    for name, (size, focus, layout) in graphics.items():
        capsule(source, size, focus, font_path, layout).save(output / (name + ".jpg"), quality=94, subsampling=0, optimize=True)
    hero_source = source.crop((165, 0, source.width, source.height))
    crop(hero_source, (3840, 1240), (0.5, 0.275)).save(output / "library-hero.jpg", quality=94, subsampling=0, optimize=True)
    title_mark(font_path, (1280, 390)).save(output / "library-logo.png", optimize=True)
    icon = lantern_icon()
    icon.save(output / "shortcut-icon.png", optimize=True)
    square = Image.new("RGBA", icon.size, "#153044")
    square.alpha_composite(icon)
    square.convert("RGB").resize((184, 184), Image.Resampling.LANCZOS).save(output / "app-icon.jpg", quality=94, subsampling=0)
    if with_runtime_icon:
        icon.save(GAME_ART / "lantern-icon.png", optimize=True)
        icon.save(GAME_ART / "lantern-windows.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", type=Path, required=True, help="Path to an installed Noto Serif SC variable font")
    parser.add_argument("--output", type=Path, default=ROOT / "graphics")
    parser.add_argument("--runtime-icon", action="store_true", help="Also render the matching Godot and Windows executable icons")
    args = parser.parse_args()
    render(args.font, args.output, args.runtime_icon)
