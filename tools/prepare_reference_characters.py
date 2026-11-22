"""Prepare the two approved reference-guided illustrations for cards and board pieces."""
from hashlib import sha256
import json
from pathlib import Path

from PIL import Image
from prepare_unit_pieces import figure

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "assets/art/characters/v2"
SUBJECTS = [
    ("shore_medic", "white-feather-oracle.png", (265, 155, 885, 775)),
    ("ash_notary", "crimson-parasol-diviner.png", (250, 225, 870, 845)),
]


def main():
    portraits = Image.new("RGBA", (1024, 512))
    pieces = Image.new("RGBA", (512, 256))
    for index, (_, filename, bounds) in enumerate(SUBJECTS):
        image = Image.open(DIRECTORY / filename).convert("RGBA")
        if image.getchannel("A").getextrema()[0] != 0:
            raise ValueError(f"Missing native transparency in {filename}")
        portraits.alpha_composite(image.crop(bounds).resize((512, 512), Image.Resampling.LANCZOS), (index * 512, 0))
        pieces.alpha_composite(figure(image), (index * 256, 0))
    portraits.save(ROOT / "assets/art/expansion/reference-characters-v1.png")
    pieces.save(ROOT / "assets/art/pieces/reference-characters-v1.png")
    record = json.loads((DIRECTORY / "redraw-sources.json").read_text("utf-8"))
    for entry, (card_id, filename, bounds) in zip(record["entries"], SUBJECTS, strict=True):
        entry.update(card_id=card_id, source_sha256=sha256((DIRECTORY / filename).read_bytes()).hexdigest(),
                     portrait_crop=list(bounds))
    record["processing"] = "Native alpha preserved. Card regions are cropped and resized to 512 px. Complete figures use the existing 256 px board-piece preparation and shared foot baseline."
    (DIRECTORY / "redraw-sources.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print("Prepared 2 card portraits and 2 matching battlefield pieces.")


if __name__ == "__main__":
    main()
