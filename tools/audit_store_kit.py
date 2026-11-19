"""Check real image files and write a SHA-256 inventory for the Steam materials."""
import hashlib
import json
import re
from pathlib import Path

from PIL import Image


PROJECT = Path(__file__).resolve().parents[1]
KIT = PROJECT / "docs" / "release" / "steam"
GRAPHICS = {
    "store-header.jpg": (920, 430),
    "store-small.jpg": (462, 174),
    "store-main.jpg": (1232, 706),
    "store-vertical.jpg": (748, 896),
    "library-capsule.jpg": (600, 900),
    "library-header.jpg": (920, 430),
    "library-hero.jpg": (3840, 1240),
    "library-logo.png": (1280, 390),
    "app-icon.jpg": (184, 184),
    "shortcut-icon.png": (512, 512),
}
SCREENSHOTS = {
    "01-local-spell.png": "Normal Frost Engine vs Balanced Host skirmish on the Blender-rendered Greenwood, seed 4107, before a legal ten-mana cast on side turn 21.",
    "02-bridge-engagement.png": "Normal Reed Legion vs Balanced Host skirmish, Rivergate seed 4186, attack preview on side turn 13.",
    "03-rivergate-story.png": "The opening chapter's actual c01.a03 dialogue page reached by reading from New Campaign.",
    "04-guard-drill.png": "The playable second tutorial, with the hand trap selected on the actual training board.",
    "05-three-lamps-mission.png": "The authored c17_runner objective and opening cards loaded in the production battlefield scene.",
    "06-glassroad-muster.png": "Salt Road Reserves vs Twin-Tide Orders, Greenwood seed 5423. Two legal reserve landings on side turn 21 after 108 legal actions.",
    "07-glassroad-dual-order.png": "Twin-Tide Orders vs Bell Ambush on the Blender-rendered Rivergate map, seed 5479. Enemy branch of Glassroad Treaty on side turn 19 after 94 legal actions.",
    "08-harbor-crossing.png": "Reed Legion vs Balanced Host on Harbor, seed 5501, side turn 13 after 57 legal actions. A healer on the southern drawbridge previews an attack on a spearman on the east bank.",
    "09-ridgepass.png": "Reed Legion vs Balanced Host, Ridgepass seed 56037. Mountain pass attack preview on side turn 23 after 145 legal actions.",
    "10-sunspire.png": "Reed Legion vs Balanced Host, Sunspire seed 56037. Attack preview on side turn 15 after 73 legal actions.",
    "11-citadel.png": "Twin-Tide Orders vs Balanced Host, Citadel seed 56037. An Anchor Snare hand trap targets G6 on side turn 35 after 203 legal actions.",
    "12-cast-impact.png": "Balanced Host mirror on Ridgepass, seed 56037. Fire impact sampled half a second after a legal Starfire Bolt, on side turn 27 after 170 preceding actions.",
    "13-frost-front.png": "Frost Engine vs Twin-Tide Orders on Rivergate, seed 57023, after 78 legal actions. On side turn 17 the player deploys a Gate Veteran from hand at I6, immediately guarding the archer at I5.",
    "14-river-signatures.png": "Pyromancer casts Fire Verdict on Sunspire on side turn 31. Balanced Host mirror, seed 56037, after 186 legal actions. Native frame sampled 0.50 s after casting.",
}


def verify(relative: str, expected: tuple[int, int], alpha: bool = False, scene: str = "") -> dict:
    file = KIT / relative
    with Image.open(file) as image:
        actual = image.size
        mode = image.mode
        kind = image.format
        if actual != expected:
            raise ValueError(f"{relative}: expected {expected}, read {actual}")
        if alpha:
            if mode != "RGBA" or image.getchannel("A").getextrema() != (0, 255):
                raise ValueError(f"{relative}: transparent and opaque pixels are both required")
        image.load()
    item = {"path": relative, "pixels": list(actual), "format": kind, "mode": mode,
            "bytes": file.stat().st_size, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
    if scene:
        item["capture"] = scene
    return item


def audit() -> None:
    assets = [verify("key-art-v1.png", (1672, 941))]
    for name, size in GRAPHICS.items():
        assets.append(verify("graphics/" + name, size, alpha=name.endswith(".png")))
    for name, capture in SCREENSHOTS.items():
        assets.append(verify("gameplay/" + name, (1920, 1080), scene=capture))
    with Image.open(PROJECT / "assets" / "art" / "lantern-windows.ico") as icon:
        if icon.ico.sizes() != {(n, n) for n in (16, 32, 48, 64, 128, 256)}:
            raise ValueError("Unexpected Windows executable icon sizes")
    version = re.search(r'^config/version="([^"]+)"$', (PROJECT / "project.godot").read_text(encoding="utf-8"), re.MULTILINE)
    if version is None:
        raise ValueError("Godot project is missing its release version")
    inventory = {"version": version.group(1), "images": assets, "viewport_screenshots": len(SCREENSHOTS),
                 "store_and_library_graphics_including_icons": len(GRAPHICS)}
    (KIT / "inventory.json").write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(assets)} decoded images, {len(SCREENSHOTS)} real gameplay viewports, six Windows executable icon sizes")


if __name__ == "__main__":
    audit()
