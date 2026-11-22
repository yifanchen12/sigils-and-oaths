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
    "27-white-feather-medic.png": "The redesigned Shore Medic deployed by a legal card action in Rivergate, fifth round, original character portrait and matching full-body piece visible.",
    "28-crimson-parasol-mage.png": "The redesigned Ash Notary deployed by a legal card action in Rivergate, seventh round, original character portrait and matching parasol piece visible.",
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
    "15-field-frost.png": "Frostbind played from hand on Harbor. Twin-Tide Orders against Balanced Host, seed 56037, side turn 45 after 275 preceding legal actions, at 0.50 seconds after casting.",
    "16-channel-review.png": "Campaign chapter 14 after-action map loaded from an authentic 0.57 save. Third standard attempt, both commanders alive, F6 and K9 held by the enemy at the 22-round deadline.",
    "17-lantern-weather.png": "Night Muster played from the Lantern Convoy hand on Citadel, seed 56037, side turn 9 after 28 legal actions. Native frame 0.50 seconds after casting.",
    "18-hammer-order.png": "Hollow Hammer marked on Citadel F5 on side turn 15 and resolved at the start of turn 17, seed 56377. The cross covers nine cells and one enemy takes the hit. Native frame 5/24 seconds after resolution.",
    "19-chapter-chronicle.png": "Chapter archive opened from the standard river, relief and school campaign ending. The archive displays the chosen split covenant and its reached epilogue.",
    "20-snare-training.png": "The fifth native tutorial on Citadel. Hollow Hammer marks G5 and the selected two-mana hand trap can stop the announced E6 to H6 rider at F6 or G6.",
    "21-hollow-hammer.png": "Second attempt in the fifth tutorial, seed 4215. The rider actually stopped at G6 after hitting the hand trap. The original bronze drop hammer descends over G5 and reaches one enemy.",
    "22-bridge-reinforcement.png": "Sixth drill on Rivergate, seed 4216. A three-mana medic is selected in hand. C4 and D5 both extend the D4 spearman's formation. The enemy archer can reach the bridge at D5 after moving.",
    "23-rivergate-threat.png": "Standard first-chapter bridge encounter, seed 1319. On side turn nine, the archer on H3 is in the red cavalry's move-and-attack range. On the next turn that rider moves from I6 to G3 and attacks H3.",
    "24-ferry-pikeman.png": "Rivergate skirmish, seed 6205. After nine legal actions, the Relay Watch deploys its Ferryman Pikeman to G1. His illustrated card, bearded figure and cover status appear together.",
    "25-ferryman-strike.png": "The same deployed ferryman attacks from H2 to I2 after 41 legal actions. Native frame at 0.23 seconds, with his copper armor, grey beard and curved boat hook.",
    "26-ferryman-moving.png": "The same ferryman moves from G1 to H1 after 16 legal actions in the Rivergate match. The native movement tween is captured before reaching the destination.",
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
