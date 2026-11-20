"""Reconcile the actual Windows pack with production records at its source commit."""
import argparse
from base64 import b64decode
from collections import Counter
from functools import cache
from hashlib import file_digest, sha256
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ART = "assets/art/manifest.json"
EXPANSION = "assets/art/expansion/sources.json"
TERRACE = "assets/art/narrative/chapter09-sources.json"


def file_hash(path):
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def audit(build, godot):
    release = read_json(build / "windows-x64/RELEASE_INFO.json")
    commit = release["source_commit"]
    if release["source_dirty"] or not re.fullmatch("[0-9a-f]{40,64}", commit):
        raise ValueError("The package needs a known clean source commit.")
    payload = build / "windows-x64"
    packed_hashes = {}
    for item in release["payload"]:
        if item["file"] not in {"SigilsAndOaths.exe", "SigilsAndOaths.pck"}:
            raise ValueError("Unrecognized release payload.")
        path = payload / item["file"]
        digest = file_hash(path)
        if path.stat().st_size != item["bytes"] or digest != item["sha256"]:
            raise ValueError(f"Release manifest mismatch for {path.name}")
        packed_hashes[path.name] = digest
    if set(packed_hashes) != {"SigilsAndOaths.exe", "SigilsAndOaths.pck"}:
        raise ValueError("The release manifest must identify the executable and game pack.")
    with tempfile.TemporaryDirectory() as tmp:
        found = Path(tmp) / "observed.json"
        subprocess.run([godot, "--headless", "--main-pack", payload / "SigilsAndOaths.pck",
                        "--script", ROOT / "tools/read_packed_content.gd", "--log-file", Path(tmp) / "godot.log",
                        "--", found], cwd=payload, check=True, timeout=140)
        observed = read_json(found)
    if observed["version"] != release["version"]:
        raise ValueError("The mounted pack has a different version.")
    paths = set(subprocess.check_output(["git","ls-tree","-rz","--name-only",commit],
                                        cwd=ROOT).decode("utf-8").split("\0"))

    def blob(path):
        if path not in paths:
            raise ValueError(f"Source is missing at the release commit: {path}")
        return subprocess.check_output(["git","cat-file","blob",f"{commit}:{path}"],cwd=ROOT)

    @cache
    def source_hash(path):
        return sha256(blob(path)).hexdigest()

    art = {row["path"]:(row,ART) for row in json.loads(blob(ART))["assets"]}
    early_cards = json.loads(blob(EXPANSION))
    for row in early_cards["sources"]:
        folder = PurePosixPath(EXPANSION).parent
        art[str(folder / row["file"])] = ({**row, "prompt_file":str(folder / early_cards["prompt_file"])}, EXPANSION)
    for row in json.loads(blob(TERRACE))["assets"]:
        art[row["path"]] = (row, TERRACE)
    sources = {}
    for item in observed["content"]:
        source = sources.setdefault(item["source"], {"payload":[]})
        source["payload"].extend(item["payload"])
        if "json_base64" in item:
            source["json_bytes"] = b64decode(item["json_base64"],validate=True)
    records = []
    for path, item in sorted(sources.items()):
        digest = source_hash(path)
        packed = sorted(item["payload"],key=lambda part: part["path"])
        entry = {"source":path, "source_sha256":digest, "packed":packed}
        refs = []
        if path.startswith("assets/art/") and path.endswith(".json"):
            entry.update(method="art production record", authoring_reference=True)
            refs.append(path)
        elif path in art:
            row, document = art[path]
            if row.get("sha256") and row["sha256"] != digest:
                raise ValueError(f"Artwork differs from its production record: {path}")
            entry["method"] = "pre-generated illustration"
            refs.append(document)
            if row.get("id"): entry["record_id"] = row["id"]
            refs.extend(row.get("prompt_files", []))
            if row.get("prompt_file"): refs.append(row["prompt_file"])
            if row.get("source_path"):
                model = row["source_path"]
                if source_hash(model) != row["source_sha256"]:
                    raise ValueError(f"Blender project differs from its recorded digest: {model}")
                entry.update(method="Blender render with project materials", model_sha256=row["source_sha256"])
                refs.extend([model,row["build_script"]])
        elif path.startswith("assets/art/map-guides/"):
            entry.update(method="terrain guide rendered from game data", authoring_reference=True)
            refs.extend(["tools/export_map_guides.gd","data/maps.tres"])
        elif path == "assets/art/unit_portraits_cel_2_draft.png":
            entry.update(method="pre-generated portrait draft", authoring_reference=True)
            refs.extend(["assets/art/generation-record.md",ART])
        elif path in ("assets/art/lantern-icon.png","assets/art/lantern-windows.ico"):
            entry["method"] = "project-drawn lantern icon"
            refs.append("tools/prepare_store_art.py")
        elif path == "assets/art/actions/river-signatures-v1.png":
            entry["method"] = "pre-generated illustration"
            refs.append("assets/art/actions/river-signatures.md")
        elif path in ("assets/audio/evening.ogg", "assets/audio/angevin.ogg"):
            entry["method"] = "licensed recording, Kevin MacLeod, CC BY 4.0"
            refs.extend(["assets/audio/MUSIC-CREDITS.txt", "tools/prepare_music.py"])
        elif path == "assets/audio/MUSIC-CREDITS.txt":
            entry["method"] = "music attribution and recording sources"
            refs.append(path)
        elif path.startswith("assets/audio/") and path.endswith((".wav",".ogg")):
            entry["method"] = "synthesized music" if path.endswith(".ogg") else "synthesized sound effect"
            refs.append("tools/compose_audio.py")
        elif path.startswith("data/narrative/"):
            entry["method"] = "fixed narrative text, development-time AI assistance disclosed"
            refs.extend(["docs/narrative/writing-bible.md","docs/narrative/writing-plan.json"])
        elif path in ("data/campaign.json","data/cards.tres","data/heroes.tres","data/maps.tres","data/decks.tres"):
            entry["method"] = "project game data"
            refs.append(path)
        else:
            raise ValueError(f"Unaccounted packaged asset: {path}")
        for part in packed:
            if part["path"] != path or part["sha256"] == digest:
                continue
            original = blob(path)
            raw = item.get("json_bytes")
            if raw is None or sha256(raw).hexdigest() != part["sha256"] or json.loads(raw) != json.loads(original):
                raise ValueError(f"Raw packaged content differs from its published source: {path}")
            entry["text_equivalence"] = ("line endings only" if raw.replace(b"\r\n",b"\n") == original.replace(b"\r\n",b"\n")
                                         else "identical parsed JSON values")
        for ref in refs:
            if ref not in paths:
                raise ValueError(f"Missing production record for {path}: {ref}")
        entry["evidence"] = list(dict.fromkeys(refs))
        records.append(entry)
    if not records:
        raise ValueError("Empty resource inventory.")
    copyright_files = {"project":"LICENSE.txt", "Godot":"licenses/Godot-LICENSE.txt",
                       "Godot and bundled third parties":"licenses/Godot-COPYRIGHT.txt"}
    if "assets/audio/MUSIC-CREDITS.txt" in sources:
        copyright_files["music by Kevin MacLeod, CC BY 4.0"] = "licenses/MUSIC-CREDITS.txt"
    return {"version":release["version"], "commit":commit, "release_payload_sha256":packed_hashes,
            "scope":"Resources found in the Windows PCK, matched to source at the release commit. Packed hashes cover the actual imported bytes. Production records describe creation; commercial authorization and platform review remain with the publisher.",
            "counts":dict(sorted(Counter(row["method"] for row in records).items())),
            "authoring_references_in_pack":sum(bool(row.get("authoring_reference")) for row in records),
            "standalone_font_files_in_pack":observed["fonts"],
            "distributed_notices":[{"component":name,"file":path,"sha256":file_hash(payload/path)}
                                   for name,path in copyright_files.items()], "resources":records}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build",type=Path)
    parser.add_argument("--godot",type=Path,default=ROOT/".tools/godot/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--output",required=True,type=Path)
    args = parser.parse_args()
    report = audit(args.build.resolve(),args.godot.resolve())
    args.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(f"{len(report['resources'])} packaged resources reconciled at {report['commit'][:8]}")
