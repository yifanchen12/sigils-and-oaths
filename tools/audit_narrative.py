"""Count only distinct player-accessible Chinese prose; never design docs or UI copy."""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\U00020000-\U0002ebef]")


def audit():
    source = ROOT / "data/narrative/codex.json"
    data = json.loads(source.read_text(encoding="utf-8"))
    errors, ids, text_seen, by_category = [], set(), {}, {}
    if data.get("version") != 1:
        errors.append("Unsupported codex version")
    entries = data.get("entries", [])
    if not entries:
        errors.append("Codex has no entries")
    count = paragraphs = 0
    for entry in entries:
        for field in ("id", "category", "title", "subtitle", "portrait", "summary", "body"):
            if not entry.get(field):
                errors.append(f"{entry.get('id')}: missing {field}")
        if entry["id"] in ids:
            errors.append(f"Duplicate entry ID: {entry['id']}")
        ids.add(entry["id"])
        entry_count = 0
        for paragraph in entry["body"]:
            line_id, text = paragraph["id"], paragraph["text"]
            if line_id in ids:
                errors.append(f"Duplicate line ID: {line_id}")
            ids.add(line_id)
            normalized = "".join(HAN.findall(text))
            if not normalized:
                errors.append(f"Empty Chinese prose: {line_id}")
            if normalized in text_seen:
                errors.append(f"Repeated prose: {line_id} / {text_seen[normalized]}")
                continue
            text_seen[normalized] = line_id
            entry_count += len(normalized)
            paragraphs += 1
        count += entry_count
        category = entry["category"]
        by_category[category] = by_category.get(category, 0) + entry_count
    required_people = {"warden", "pyromancer", "grove", "sword", "spear", "cavalry", "archer", "mage", "healer"}
    if not required_people.issubset({e["id"] for e in entries if e["category"] == "人物"}):
        errors.append("Missing established character profile")
    return {
        "scope": "All codex entries are exposed by LoreBook's directory. No chapter text is shipped yet.",
        "counting_method": "Distinct body paragraphs; Chinese Han characters only; excludes punctuation, summaries, headings, UI, plans and prompts.",
        "entries": len(entries), "paragraphs": paragraphs,
        "unique_chinese_characters": count, "by_category": by_category,
        "release_target": 100000, "remaining_to_target": max(0, 100000 - count),
        "campaign_route_characters": 0,
        "limitations": "Exact-repeat audit only; thematic repetition and prose quality require editorial review. Codex is not a playable campaign.",
        "errors": errors,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = audit()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Narrative audit failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered)
    raise SystemExit(1 if report["errors"] else 0)
