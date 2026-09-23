#!/usr/bin/env python3
"""Generate Data/<Class>.lua for SpellbookExtended.

Inputs
  --forever  Forever client class-spell export. Either the JSON blob or the
             docs/index.html of https://github.com/MAF2414/wow-forever-talents,
             which embeds SkillLineAbility + SpellLevels + Spell* rows decoded
             from the Forever client (wago.tools DB2 exports).
  --items    builds/<build>.json.gz of https://github.com/alcaras/forever-ref;
             tags spells taught by class books (AQ tomes, Dire Maul codices...).
  --wt       Classes/Vanilla folder of https://github.com/fusionpit/WhatsTraining
             (MIT). Supplies Classic trainer costs, race/faction limits and,
             by omission, which Classic spells are not sold by trainers.

The Forever client is the source of truth for which spells exist, their rank
and the level they are learned at. The addon re-reads the level from the live
client (C_Spell.GetSpellLevelLearned) and takes costs from an open trainer, so
the static values here are only a fallback.
"""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

CLASSES = {
    1: ("WARRIOR", "Warrior"), 2: ("PALADIN", "Paladin"), 3: ("HUNTER", "Hunter"),
    4: ("ROGUE", "Rogue"), 5: ("PRIEST", "Priest"), 7: ("SHAMAN", "Shaman"),
    8: ("MAGE", "Mage"), 9: ("WARLOCK", "Warlock"), 11: ("DRUID", "Druid"),
}

# Learned from class quests, not bought. Shown with a "Quest" tag instead of a cost.
QUEST_SPELLS = {
    5487, 1066, 6795, 6807,                  # Bear Form, Aquatic Form, Growl, Maul 1
    697, 712, 691, 23161,                    # Voidwalker, Succubus, Felhunter, Dreadsteed
    1515, 883, 2641, 6991, 982,              # Tame Beast, Call/Dismiss/Feed/Revive Pet
    71, 2458, 355,                           # Defensive Stance, Berserker Stance, Taunt
    7328, 23214,                             # Redemption, Summon Charger
    2842, 8681,                              # Poisons, Instant Poison 1
    5149,                                    # Beast Training
    8071, 3599, 5394,                        # Stoneskin, Searing, Healing Stream Totem 1
}

# Classic trainer spells missing from the WhatsTraining lists.
TRAINER_SPELLS = {8946, 18960, 5502, 6346, 2651}

# Forever changed which races learn these (foreverchanges.pro "Other races").
# None lifts the Classic restriction.
RACE_OVERRIDES = {"Desperate Prayer": None, "Devouring Plague": None, "Fear Ward": None, "Elune's Grace": 4}

# Skill lines that are not class trainer purchases.
SKIP_TABS = {"Beast Training", "Lockpicking"}

# Spells from a skipped skill line that still belong in the list, and the tab to show them on.
TAB_OVERRIDES = {5149: "Beast Mastery"}

# Rank-less companions of another spell, never a separate purchase.
SKIP_NAMES = re.compile(r"\((Passive|Bear|Cat)\)$")


def load_forever(path):
    text = Path(path).read_text(encoding="utf-8")
    if path.endswith(".html"):
        start = text.index("const DATA=") + len("const DATA=")
        data, _ = json.JSONDecoder().raw_decode(text, start)
        return data
    return json.loads(text)


def load_wt(folder):
    """class token -> spellID -> {cost, race, faction}"""
    out = {}
    entry = re.compile(r"\{\s*id\s*=\s*(\d+)((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\}", re.S)
    for f in Path(folder).glob("*.lua"):
        if f.stem in ("HunterPets", "WarlockTomes"):
            continue
        body = f.read_text(encoding="utf-8")
        body = body[body.find("SpellsByLevel"):]
        for m in entry.finditer(body):
            sid, rest = int(m.group(1)), m.group(2)
            rec = {}
            if c := re.search(r"cost\s*=\s*(\d+)", rest):
                rec["cost"] = int(c.group(1))
            if r := re.search(r"race\s*=\s*(\d+)", rest):
                rec["race"] = int(r.group(1))
            if fa := re.search(r'faction\s*=\s*"(\w+)"', rest):
                rec["faction"] = fa.group(1)
            if sk := re.search(r"skill\s*=\s*\d+\s*,\s*level\s*=\s*(\d+)", rest):
                if int(sk.group(1)) > 1:
                    rec["skill"] = int(sk.group(1))
            if rq := re.search(r"requiredIds\s*=\s*\{([^}]*)", rest):
                rec["needs"] = [int(x) for x in re.findall(r"\d+", rq.group(1))]
            if "requiredTalentId" in rest:
                rec["talentRank"] = True
            out.setdefault(f.stem.upper(), {})[sid] = rec
    return out


def load_books(path):
    """spellID -> itemID of an uncommon-or-better class book that teaches it."""
    if not path:
        return {}
    import gzip
    items = json.load(gzip.open(path))["items"]
    out = {}
    for item_id, item in items.items():
        if item.get("c") != 9 or item.get("q", 0) < 2:
            continue
        for trigger, spell in item.get("fx", []):
            if trigger == 6:
                out.setdefault(int(spell), int(item_id))
    return out


def talent_tree(cls, key="trees"):
    ids, names = set(), set()
    for tree in cls[key]:
        for node in tree["talents"]:
            for e in node["entries"]:
                ids.add(e["spellID"])
                names.add(e["name"])
    return ids, names


def rank_of(subtext):
    m = re.search(r"(\d+)", subtext or "")
    return int(m.group(1)) if m else 0


def build_class(cls, wt, books):
    token, label = CLASSES[cls["id"]]
    wt = wt.get(token, {})
    tree_ids, tree_names = talent_tree(cls)
    _, classic_tree_names = talent_tree(cls, "classicTrees")
    families = defaultdict(list)
    dropped = []

    for group in cls["spells"]:
        if group["status"] == "removed":
            continue
        for pair in group["pairs"]:
            f = pair["forever"]
            if not f:
                continue
            level = f["metrics"]["Level"]
            skill = TAB_OVERRIDES.get(f["spellID"], f["skill"])
            if level == 0 or SKIP_NAMES.search(f["name"]) or skill in SKIP_TABS:
                continue
            in_tree = f["spellID"] in tree_ids or f["name"] in tree_names
            # Classic talents Forever moved to the trainer (Omen of Clarity...).
            old_talent = f["name"] in classic_tree_names and not in_tree
            if f["passive"] and f["spellID"] not in wt and not old_talent:
                continue
            families[f["name"]].append({
                "id": f["spellID"], "name": f["name"], "rank": rank_of(f["subtext"]),
                "level": level, "tab": skill, "extra": bool(group.get("extra")),
                "classic": pair["classic"] is not None, "passive": f["passive"],
                "oldTalent": old_talent,
            })

    rows = []
    for name, members in families.items():
        # Inherited Season of Discovery rows only count when they fill a rank the
        # regular Forever rows leave open (Revive 1, Lacerate 1...).
        regular = [m for m in members if not m["extra"]]
        taken = {m["rank"] for m in regular}
        keep = regular + [m for m in members if m["extra"] and regular and m["rank"] not in taken]
        if not regular:
            keep = [m for m in members if m["id"] in tree_ids]
        for m in members:
            if m not in keep:
                dropped.append((name, m["rank"], m["id"], "seasonal record"))

        # One row per rank: proc and NPC copies share the name.
        if any(m["rank"] for m in keep):
            keep = [m for m in keep if m["rank"]]
        by_rank = {}
        for m in sorted(keep, key=lambda m: (m["id"] not in wt, not m["classic"], m["id"])):
            by_rank.setdefault(m["rank"], m)
        keep = sorted(by_rank.values(), key=lambda m: (m["rank"], m["level"], m["id"]))
        if not keep:
            continue

        family_wt = [wt[m["id"]] for m in keep if m["id"] in wt]
        race = next((w["race"] for w in family_wt if "race" in w), None)
        race = RACE_OVERRIDES.get(name, race)
        faction = next((w["faction"] for w in family_wt if "faction" in w), None)
        root = next((m["id"] for m in keep if m["id"] in tree_ids), None)

        family_ids = {m["id"] for m in members}
        prev = None
        for m in keep:
            sid = m["id"]
            # Talent spells come from the tree; level 1 holds starting spells and
            # talent/proc records. Neither is sold, but they still anchor the ranks.
            if sid in tree_ids or (m["level"] <= 1 and sid not in wt):
                prev = sid
                continue
            row = {"id": sid, "name": name, "rank": m["rank"], "level": m["level"], "tab": m["tab"]}
            if root:
                row["requires"] = root
            if sid in QUEST_SPELLS:
                row["quest"] = True
            elif sid in books:
                row["book"] = books[sid]
            elif sid in wt and "cost" in wt[sid]:
                # Classic priced talent ranks far below normal spells; that price
                # no longer applies once Forever sells the spell without the talent.
                if root or not wt[sid].get("talentRank"):
                    row["cost"] = wt[sid]["cost"]
            elif (m["classic"] and m["level"] > 1 and not family_wt and not root
                  and not m["oldTalent"] and sid not in TRAINER_SPELLS):
                dropped.append((name, m["rank"], sid, "classic spell no trainer sells"))
                continue
            if "skill" in wt.get(sid, {}):
                row["skill"] = wt[sid]["skill"]
            if race:
                row["race"] = race
            if faction:
                row["faction"] = faction
            if prev:
                row["prev"] = prev
            needs = [n for n in wt.get(sid, {}).get("needs", []) if n != prev and n not in family_ids]
            if needs:
                row["needs"] = needs
            prev = sid
            rows.append(row)

    rows.sort(key=lambda r: (r["level"], r["tab"], r["name"], r["rank"]))
    return token, label, rows, dropped, [t["name"] for t in cls["trees"]]


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit(token, label, rows, build, trees):
    # Spellbook order: talent tree order first (skill lines may carry a longer
    # name, "Shadow Magic" for the Shadow tree), then anything else.
    def order(skill):
        for i, tree in enumerate(trees):
            if skill.startswith(tree) or tree.startswith(skill):
                return (i, skill)
        return (len(trees), skill)
    tabs = sorted({r["tab"] for r in rows}, key=order)
    out = [
        "-- Generated by tools/build_data.py. Do not edit by hand.",
        f"-- Forever client build {build}.",
        "local _, SBE = ...",
        "",
        f"SBE.Data.{token} = {{",
        f"    tabs = {{ {', '.join(lua_string(t) for t in tabs)} }},",
        "    spells = {",
    ]
    for r in rows:
        fields = [f"id = {r['id']}", f"level = {r['level']}", f"tab = {tabs.index(r['tab']) + 1}"]
        if r["rank"]:
            fields.append(f"rank = {r['rank']}")
        for key in ("cost", "book", "prev", "requires", "race", "skill"):
            if key in r:
                fields.append(f"{key} = {r[key]}")
        if "needs" in r:
            fields.append(f"needs = {{ {', '.join(str(n) for n in r['needs'])} }}")
        if "faction" in r:
            fields.append(f"faction = {lua_string(r['faction'])}")
        for key in ("quest",):
            if r.get(key):
                fields.append(f"{key} = true")
        rank = f" {r['rank']}" if r["rank"] else ""
        out.append(f"        {{ {', '.join(fields)} }}, -- {r['name']}{rank}")
    out += ["    },", "}", ""]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--forever", required=True)
    ap.add_argument("--wt", required=True)
    ap.add_argument("--items", help="forever-ref builds/<build>.json.gz, to tag class books")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "Data"))
    ap.add_argument("--report", action="store_true", help="list rows that were dropped")
    args = ap.parse_args()

    data = load_forever(args.forever)
    wt = load_wt(args.wt)
    books = load_books(args.items)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for cls in data["classes"]:
        token, label, rows, dropped, tabs = build_class(cls, wt, books)
        (out / f"{label}.lua").write_text(emit(token, label, rows, data["build"], tabs), encoding="utf-8")
        print(f"{label:8} {len(rows):4} spells, {len(dropped):3} dropped")
        if args.report:
            for d in sorted(set(dropped), key=str):
                print("    -", *d)


if __name__ == "__main__":
    main()
