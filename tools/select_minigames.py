#!/usr/bin/env python3
"""Ship the converted levels that are played as minigames, and list them for
the Minigames menu.

    python3 tools/select_minigames.py <native_dir> [levels_dest] [catalog]

Reads every level tools/import_levels.py converted, keeps the ones whose
`minigames` list names a mode the game has built (MODES below), copies them
into the game's levels folder under their PVZGE ids, and writes
data/native/minigames.json: one entry per mode with its levels in world
order, which is what the menu shows.

A level is filed under one mode only. An endless zone that bowls is an
endless zone first, so ENDLESS comes before the rest.
"""
import json, glob, os, re, sys

# Menu order. `name` and `description` are PVZGE's own English wording where
# it has any (InGameLyrics Challenge strings), so translations line up.
MODES = [
    {"id": "bowling", "name": "Wall-nut Bowling",
     "description": "Deliver bowling balls to grind the zombies"},
    {"id": "last_stand", "name": "Last Stand",
     "description": "Plan your defence and defeat the zombies"},
    {"id": "vasebreaker", "name": "Vasebreaker",
     "description": "Break the vases and beat whatever comes out"},
    {"id": "beghouled", "name": "Beghouled",
     "description": "Match three plants in a row to beat the zombies"},
    {"id": "cannon", "name": "Cannon Away",
     "description": "Reach the target score"},
    {"id": "camel", "name": "Camel Match",
     "description": "Match symbols to destroy the zombies"},
    {"id": "cowboy", "name": "Corral",
     "description": "Survive the zombie attack"},
    {"id": "fight_alone", "name": "Fight Alone",
     "description": "Survive with the only plant you've got"},
    {"id": "sun_bomb", "name": "Sun Bombs",
     "description": "Survive while Sun Bombs fall"},
    {"id": "rhythm", "name": "Rhythm",
     "description": "Smash the zombies to the beat"},
    {"id": "izombie", "name": "I, Zombie",
     "description": "Eat all the brains"},
    {"id": "endless", "name": "Endless Zones",
     "description": "Survive as many levels as you can"},
]
PRIORITY = ["endless", "beghouled", "vasebreaker", "bowling", "last_stand",
            "cannon", "camel", "cowboy", "fight_alone", "sun_bomb", "rhythm",
            "izombie"]

# World order on the map, so a mode's levels read Egypt first, Sky last, and
# the names PVZGE's map gives each one.
WORLDS = [("Tutorial", "Player's House"), ("Egypt", "Ancient Egypt"),
          ("Pirate", "Pirate Seas"), ("Cowboy", "Wild West"),
          ("Future", "Far Future"), ("Dark", "Dark Ages"),
          ("Beach", "Big Wave Beach"), ("Iceage", "Frostbite Caves"),
          ("LostCity", "Lost City"), ("Eighties", "Neon Mixtape Tour"),
          ("Dino", "Jurassic Marsh"), ("Modern", "Modern Day"),
          ("Kongfu", "Kongfu World"), ("Sky", "Sky City")]


def world_of(level):
    """Index into WORLDS. A minigame danger room is named after the world it
    imitates (beach_dangerroom_minigame_egypt), not the beach it is set on."""
    key = level["id"].split("_minigame_")[-1] if "_minigame_" in level["id"] \
        else (level.get("stage") or level["id"])
    for i, (w, _) in enumerate(WORLDS):
        if key.lower().startswith(w.lower()):
            return i
    return len(WORLDS)


def missing_entities(level, data_dir):
    """Plants and zombies a mode's settings name that the game does not have
    (Far Future's primal peashooter team, Lord of the Day guests)."""
    out = []
    for g in level.get("minigames") or []:
        for p in g.get("plant_upgrade_list") or []:
            if not os.path.exists(os.path.join(data_dir, "plants", p.get("type", "") + ".json")):
                out.append(p.get("type"))
        for z in g.get("zombies") or []:
            if not os.path.exists(os.path.join(data_dir, "zombies", z.get("type", "") + ".json")):
                out.append(z.get("type"))
    return out


def mode_of(level):
    kinds = {g.get("type") for g in level.get("minigames") or []}
    for m in PRIORITY:
        if m in kinds:
            return m
    return None


def label(mode, level, counts):
    if level.get("custom"):
        return level.get("name") or level["id"]
    return _world_label(mode, level, counts)


def _world_label(mode, level, counts):
    """"Big Wave Beach 2", "Ancient Egypt Minigame Zone": the world, then
    which of that world's levels in this mode it is."""
    w = world_of(level)
    world = WORLDS[w][1] if w < len(WORLDS) else "Bonus"
    if mode == "endless":
        game = next(g for g in level["minigames"] if g["type"] == "endless")
        world += " Minigame Zone" if game.get("minigame") else " Endless Zone"
    counts[world] = counts.get(world, 0) + 1
    return world if counts[world] == 1 and mode == "endless" else f"{world} {counts[world]}"


def main():
    src = sys.argv[1]
    dest = sys.argv[2] if len(sys.argv) > 2 else "data/native/levels"
    catalog_path = sys.argv[3] if len(sys.argv) > 3 else "data/native/minigames.json"
    by_mode = {m["id"]: [] for m in MODES}
    for path in sorted(glob.glob(os.path.join(src, "*.json"))):
        level = json.load(open(path, encoding="utf-8"))
        mode = mode_of(level)
        gaps = missing_entities(level, os.path.dirname(dest.rstrip("/")))
        if mode and gaps:
            print(f"skipping {level['id']}: no {', '.join(sorted(set(gaps)))}")
            continue
        if mode:
            by_mode[mode].append(level)

    # The project's own minigame levels ("custom": true) live in the levels
    # folder already; they are listed, not copied.
    for path in sorted(glob.glob(os.path.join(dest, "*.json"))):
        level = json.load(open(path, encoding="utf-8"))
        if level.get("custom") and mode_of(level):
            by_mode[mode_of(level)].append(level)

    os.makedirs(dest, exist_ok=True)
    catalog = {"//": "Generated by tools/select_minigames.py. The Minigames "
                     "menu lists each mode's levels in this order.",
               "modes": []}
    for m in MODES:
        levels = sorted(by_mode[m["id"]],
                        key=lambda l: (world_of(l), l.get("number") or 0, l["id"]))
        for level in levels:
            if level.get("custom"):
                continue
            with open(os.path.join(dest, level["id"] + ".json"), "w",
                      encoding="utf-8") as fh:
                json.dump(level, fh, ensure_ascii=False, indent=1)
        entry = dict(m)
        counts = {}
        entry["levels"] = [{"id": l["id"], "name": label(m["id"], l, counts)}
                           for l in levels]
        catalog["modes"].append(entry)
        print(f"{m['id']:12} {len(levels)} levels")
    with open(catalog_path, "w", encoding="utf-8") as fh:
        json.dump(catalog, fh, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
