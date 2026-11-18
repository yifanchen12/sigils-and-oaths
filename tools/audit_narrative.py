"""Separate verified archive prose from wired, graph-reachable chapter candidates."""
from pathlib import Path
import argparse
import json
import hashlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\U00020000-\U0002ebef]")


def chapter_audit(ids, text_seen, errors):
    index = json.loads((ROOT / "data/campaign.json").read_text(encoding="utf-8"))
    evidence_path = ROOT / "docs/narrative-native-ui.json"
    evidence = json.loads(evidence_path.read_text(encoding="utf-8")) if evidence_path.exists() else {}
    rendered_sources = evidence.get("chapter_sha256", {}).copy() if evidence.get("passed") is True else {}
    for later_path in sorted((ROOT / "docs").glob("narrative-native-ui-v*.json")):
        later = json.loads(later_path.read_text(encoding="utf-8"))
        if later.get("passed") is True:
            rendered_sources.update(later.get("chapter_sha256", {}))
    reports = []
    # Keep multiplicity while merging histories that no remaining chapter can
    # distinguish. A late chapter otherwise expands millions of equivalent
    # earlier combinations before checking its handful of conditional facts.
    future_conditions = []
    for entry in index["chapters"]:
        source = json.loads((ROOT / entry["path"].removeprefix("res://")).read_text(encoding="utf-8"))
        future_conditions.append({key for node in source["nodes"].values()
                                  for row in node.get("lines", []) + node.get("options", [])
                                  for key in row.get("when", {})})
    for position in range(len(future_conditions) - 2, -1, -1):
        future_conditions[position] |= future_conditions[position + 1]
    previous_endings = [({}, 1, 0, 0)]
    for chapter_index, entry in enumerate(index["chapters"]):
        path = (ROOT / entry["path"].removeprefix("res://")).resolve()
        if not path.is_relative_to(ROOT):
            raise ValueError("Chapter path is outside project")
        graph = json.loads(path.read_text(encoding="utf-8"))
        native_rendered = rendered_sources.get(entry["id"]) == hashlib.sha256(path.read_text(encoding="utf-8").encode("utf-8")).hexdigest()
        nodes, strings = graph["nodes"], graph["strings"]
        body = {line["id"] for node in nodes.values() if node["type"] == "dialogue" for line in node["lines"]}
        body.update(node["text"] for node in nodes.values() if node["type"] == "end")
        weights = {}
        for line_id in sorted(body):
            if line_id in ids:
                errors.append(f"Duplicate line ID: {line_id}")
            ids.add(line_id)
            normalized = "".join(HAN.findall(strings[line_id]))
            if not normalized:
                errors.append(f"Empty chapter prose: {line_id}")
            if normalized in text_seen:
                errors.append(f"Repeated prose: {line_id} / {text_seen[normalized]}")
                weights[line_id] = 0
            else:
                text_seen[normalized] = line_id
                weights[line_id] = len(normalized)
        routes, reached, read_lines = [], set(), set()
        endings = []

        def matches(when, flags):
            return all(flags[key] == value for key, value in when.items())

        def walk(node_id, flags, lines, chain, weight, prefix_shortest, prefix_longest):
            if node_id in chain:
                raise ValueError(f"Chapter cycle: {node_id}")
            reached.add(node_id)
            node = nodes[node_id]
            chain = chain | {node_id}
            kind = node["type"]
            if kind == "dialogue":
                visible = {line["id"] for line in node["lines"] if matches(line.get("when", {}), flags)}
                read_lines.update(visible)
                walk(node["next"], flags, lines | visible, chain, weight, prefix_shortest, prefix_longest)
            elif kind == "choice":
                available = [o for o in node["options"] if matches(o.get("when", {}), flags)]
                if not available:
                    raise ValueError(f"No available choice: {node_id}")
                for option in available:
                    walk(option["next"], flags | option.get("set", {}), lines, chain, weight, prefix_shortest, prefix_longest)
            elif kind == "battle":
                walk(node["win"], flags | node.get("win_set", {}), lines, chain, weight, prefix_shortest, prefix_longest)
            elif kind == "end":
                read_lines.add(node["text"])
                length = sum(weights[line] for line in lines | {node["text"]})
                routes.append((length, weight))
                endings.append((flags, weight, prefix_shortest + length, prefix_longest + length))
            else:
                raise ValueError(f"Unknown chapter node: {node_id}")

        incoming = set()
        relevant_keys = future_conditions[chapter_index]
        groups = {}
        for previous, multiplicity, prefix_shortest, prefix_longest in previous_endings:
            inherited = {}
            for key in graph.get("inherits", []):
                if key not in previous or type(previous[key]) is not type(graph["defaults"][key]):
                    raise ValueError(f"Missing or mistyped inherited fact: {entry['id']} / {key}")
                inherited[key] = previous[key]
            relevant = {key: inherited[key] for key in relevant_keys if key in inherited}
            signature = json.dumps(relevant, sort_keys=True)
            incoming.add(signature)
            if signature in groups:
                facts, occurrences, shortest, longest = groups[signature]
                groups[signature] = (facts, occurrences + multiplicity, min(shortest, prefix_shortest), max(longest, prefix_longest))
            else:
                groups[signature] = (inherited, multiplicity, prefix_shortest, prefix_longest)
        for inherited, multiplicity, prefix_shortest, prefix_longest in groups.values():
            walk(graph["start"], graph["defaults"] | inherited, set(), set(), multiplicity, prefix_shortest, prefix_longest)
        previous_endings = endings
        if read_lines != body:
            errors.append(f"Unreachable chapter body: {sorted(body - read_lines)}")
        if reached != nodes.keys():
            errors.append(f"Unreachable chapter nodes: {sorted(nodes.keys() - reached)}")
        if native_rendered and entry["id"] in ("chapter_17", "chapter_18"):
            status = "Native rendering covers every new body page. Both relay openings have legal-action wins and all three final pages can be reached and reloaded. See the 0.41 validation report for the continuous route."
        elif native_rendered and entry["id"] == "chapter_16":
            status = "All authored pages rendered in native Godot, and two earned prior endings entered this chapter. The new battle has a separate legal-action AI diagnostic; full sixteen-chapter continuous play and human review remain open."
        elif native_rendered and entry["id"] == "chapter_15":
            status = "All authored pages rendered in native Godot. Twelve structural inherited outcomes and two separately earned channel-win endings read and saved both repair choices. No new battle, full campaign route, human editorial acceptance or balance proof."
        elif native_rendered and entry["id"] == "chapter_14":
            status = "All authored pages rendered in native Godot. Two separate earned night-watch saves won the channel battle through legal actions and resumed after a midbattle reload. Human difficulty and broad branch win rates remain unchecked."
        elif native_rendered and entry["id"] == "chapter_13":
            status = "All conditional pages rendered in native Godot. Three separate earned depot-win saves entered the chapter and each reached both night-watch endings, with cross-process save checks. No new tactical battle or human playtest."
        elif native_rendered and entry["id"] == "chapter_12":
            status = "Every conditional page rendered in native Godot. Three earned chapter-eleven saves advanced through real depot battles with legal actions, battle reload and both custody choices represented across plans. Other routes and human balance remain unchecked."
        elif native_rendered and entry["id"] == "chapter_11":
            status = "Every conditional page rendered in Godot. Three actual prior gate-win saves entered and finished this witness chapter; each ending resumed in a separate native process. Earlier battle paths and human play remain unchecked."
        elif native_rendered and entry["id"] == "chapter_10":
            status = "Every conditional page rendered in Godot. A native battle from actual prior ten-win saves reached this chapter end on three plans; other openings and human play remain unchecked."
        elif native_rendered and entry["id"] == "chapter_09":
            status = "Every conditional page rendered in Godot. A ten-battle route reached this chapter; other battle paths and human play remain unchecked."
        elif native_rendered:
            status = f"Native page rendering checked in {evidence.get('milestone', 'unknown')}; fixture victories provide all-page access. A later eleven-battle route has separate native evidence."
        else:
            status = "Source differs from native rendering evidence or has not been rendered; native UI check pending."
        reports.append({
            "id": entry["id"], "body_paragraphs": len(body), "all_string_entries": len(strings),
            "authored_unique_characters": sum(weights.values()),
            "graph_reachable_unique_characters": sum(weights[line] for line in read_lines),
            "route_count": sum(weight for _, weight in routes), "shortest_route_characters": min(length for length, _ in routes),
            "incoming_fact_combinations": len(incoming),
            "longest_route_characters": max(length for length, _ in routes), "nodes": len(nodes),
            "native_rendered_source_matches": native_rendered,
            "status": status,
        })
    route_lengths = {
        "shortest_campaign_route_han": min(shortest for _, _, shortest, _ in previous_endings),
        "longest_campaign_route_han": max(longest for _, _, _, longest in previous_endings),
    }
    return reports, route_lengths


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
    chapters, route_lengths = chapter_audit(ids, text_seen, errors)
    candidate = sum(chapter["graph_reachable_unique_characters"] for chapter in chapters)
    rendered = sum(chapter["graph_reachable_unique_characters"] for chapter in chapters if chapter["native_rendered_source_matches"])
    return {
        "scope": "All registered chapter graphs, including the three endings, and the separately readable archive. Native source hashes identify rendered page catalogues.",
        "counting_method": "Counts distinct Han characters in authored body paragraphs, excluding punctuation, summaries, headings, UI, plans and prompts. Equivalent inherited facts retain route multiplicity and the shortest and longest prefixes. Campaign route lengths include chapter endings and exclude the archive.",
        "entries": len(entries), "paragraphs": paragraphs,
        "unique_chinese_characters": count, "by_category": by_category,
        "release_target": 100000, "remaining_to_target": max(0, 100000 - count - candidate),
        "chapter_candidates": chapters,
        **route_lengths,
        "authored_total_characters": count + candidate,
        "native_rendered_chapter_characters": rendered,
        "pending_ui_verification_characters": candidate - rendered,
        "limitations": "Graph enumeration assumes victories and models only authored choices. A separate 0.41 playthrough uses legal actions to earn one complete campaign ending. Human editorial review, difficulty and the 100,000-character target on a single route remain open.",
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
