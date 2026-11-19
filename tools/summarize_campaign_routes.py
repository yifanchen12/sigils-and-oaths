"""Count narrative prose actually encountered in completed continuous campaign runs."""
import argparse
from hashlib import sha256
import json
from pathlib import Path

from audit_narrative import HAN, ROOT


def load_json(file):
    return json.loads(file.read_text(encoding="utf-8-sig"))


def summarize(files):
    chapters = [load_json(ROOT / x["path"].removeprefix("res://"))
                for x in load_json(ROOT / "data/campaign.json")["chapters"]]
    all_prose = set()
    results = []
    for file in files:
        run = load_json(file)
        progress = run["progress"]
        if run["failures"] or run["stop"] != "authored_end" or not run["reached_authored_end"]:
            raise ValueError(f"Incomplete route in {file.name}")
        slots = progress["completed"] + [progress]
        if [s["chapter_id"] for s in slots] != [c["id"] for c in chapters]:
            raise ValueError(f"Chapter sequence differs in {file.name}")
        dialogue = set()
        prose = set()
        for chapter, slot in zip(chapters, slots):
            story = slot["story"]
            body = {row["id"] for node in chapter["nodes"].values() for row in node.get("lines", [])}
            read = body.intersection(story["history"])
            end = chapter["nodes"][story["node"]]
            if end["type"] != "end":
                raise ValueError(f"Unfinished {chapter['id']}")
            dialogue.update(read)
            for text_id in read | {end["text"]}:
                prose.add("".join(HAN.findall(chapter["strings"][text_id])))
        if dialogue != set(run["dialogue_ids"]):
            raise ValueError("The final saved text history disagrees with the live dialogue trace")
        all_prose.update(prose)
        games = run["games"]
        attempts = []
        for game in games:
            if len(game["trace"]) != game["actions"] or game["winner"] != game["final"]["winner"]:
                raise ValueError("Battle trace and saved result disagree")
            if game["winner"] != 0 and not game.get("review_reason"):
                raise ValueError("A lost attempt is missing its reloaded after-action report")
            attempts.append({k: game[k] for k in ("scenario","attempt","player_policy","winner","turn","actions",
                                                      "requisition","armory","review_reason") if k in game})
        results.append({
            "opening":run["route"], "priority":run["priority"], "escort":run["saltlane"], "difficulty":run["difficulty"],
            "ending":chapters[-1]["nodes"][progress["story"]["node"]]["ending"],
            "ending_title":chapters[-1]["nodes"][progress["story"]["node"]]["title"],
            "choices":{c["chapter"]+"."+c["node"]:c["option"] for c in run["choices"]},
            "wins":sum(g["winner"] == 0 for g in games),"losses":sum(g["winner"] == 1 for g in games),
            "draws":sum(g["winner"] == 2 for g in games),"actions":sum(g["actions"] for g in games),
            "dialogue_pages":len(dialogue),"observed_unique_han":sum(map(len,prose)),
            "checks":run["checks"],"battle_reloads":sum(g["reload_at_action"] >= 0 for g in games),
            "attempts":attempts,"raw_report_sha256":sha256(file.read_bytes()).hexdigest(),
        })
    return {"counting":"Only read dialogue and reached end pages; identical Han-only bodies counted once across runs. Choices, UI, lore archive and simulations from late saves are excluded.",
            "routes":results,"observed_unique_han_across_routes":sum(map(len,all_prose)),
            "total_actions":sum(r["actions"] for r in results)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = json.dumps(summarize(args.reports),ensure_ascii=False,indent=2)+"\n"
    if args.output:
        args.output.write_text(result,encoding="utf-8")
    else:
        print(result)
