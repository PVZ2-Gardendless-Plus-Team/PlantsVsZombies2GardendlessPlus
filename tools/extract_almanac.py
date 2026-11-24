#!/usr/bin/env python3
"""Pull PVZGE's almanac text into data/native/almanac.

PVZGE keeps its almanac in two JsonAssets, `json/Objects/PlantAlmanac` and
`json/Objects/ZombieAlmanac`: one objclass entry per plant or zombie with the
description, the funny "chat" paragraph, special notes and the stat rows the
almanac page lists. Names, the world a zombie belongs to and the order of the
zombie almanac live in `json/Features/PlantFeatures` and
`json/Features/ZombieFeatures`.

    python3 tools/extract_almanac.py <build resources dir> [data/native]

`<build resources dir>` is `assets/resources` from the web build or a desktop
build unpacked with extract_desktop.py. Writes, under the data dir:

    almanac/plants/<id>.json    one entry per plant
    almanac/zombies/<id>.json   one entry per zombie the almanac lists
    almanac.json                the zombie almanac's order

Every string stays PVZGE's {"en": ..., "zh": ...} dict, so the game can pick
the player's language. A pack can add or replace an entry by shipping a file
with the same id under its own almanac/ folder; plain strings work there too.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_prefabs import Build  # noqa: E402

ASSETS = {
    "plant_almanac": "json/Objects/PlantAlmanac",
    "zombie_almanac": "json/Objects/ZombieAlmanac",
    "plant_features": "json/Features/PlantFeatures",
    "zombie_features": "json/Features/ZombieFeatures",
}

# PVZGE's element TYPEs, as the stat names the port's almanac reads.
PLANT_STATS = {
    "SUNCOST": "sun_cost", "RECHARGE": "recharge", "TOUGHNESS": "toughness",
    "DAMAGE": "damage", "FAMILY": "family", "RANGE": "range", "AREA": "area",
    "DURATION": "duration", "PLANTFOOD": "plant_food",
    "SUNPRODUCTION": "sun_production", "ARMINGTIME": "arming_time",
    "GROWTIME": "grow_time", "SPECIAL": "special",
}
ZOMBIE_STATS = {"TOUGHNESS": "toughness", "SPEED": "speed"}


def find_json(node, key, depth=0):
    """The first dict under `node` that has `key` - a JsonAsset's payload sits
    a few lists deep in its envelope, and deeper still inside a pack."""
    if depth > 8:
        return None
    if isinstance(node, dict):
        if key in node:
            return node
        node = list(node.values())
    if isinstance(node, list):
        for item in node:
            hit = find_json(item, key, depth + 1)
            if hit is not None:
                return hit
    return None


def load(build, name, key):
    index = build.by_name.get(ASSETS[name])
    if index is None:
        sys.exit("%s is not in this build" % ASSETS[name])
    payload = find_json(build.instance(index), key)
    if payload is None:
        sys.exit("%s has no %s" % (ASSETS[name], key))
    return payload


def text(value):
    """A PVZGE MultiLanguage: a {lang: str} dict. Empty ones are dropped."""
    if isinstance(value, dict):
        out = {k: v for k, v in value.items() if isinstance(v, str) and v != ""}
        return out or None
    if isinstance(value, str) and value:
        return {"en": value}
    return None


def put(entry, key, value):
    if value not in (None, [], {}):
        entry[key] = value


def specials(rows):
    out = []
    for row in rows or []:
        item = {}
        put(item, "name", text(row.get("NAME")))
        put(item, "text", text(row.get("DESCRIPTION")))
        if item:
            out.append(item)
    return out


def offset(value, default):
    if not isinstance(value, dict):
        return None
    x, y = value.get("x", default), value.get("y", default)
    return None if (x, y) == (default, default) else [x, y]


def plant_entry(pid, data, feature):
    entry = {"id": pid}
    put(entry, "name", text((feature or {}).get("NAME")))
    put(entry, "brief", text(data.get("BriefIntroduction")))
    put(entry, "description", text(data.get("Introduction")))
    put(entry, "chat", text(data.get("Chat")))
    put(entry, "special", specials(data.get("Special")))
    stats = []
    for row in data.get("Elements", []):
        stat = {"type": PLANT_STATS.get(row.get("TYPE"), "special")}
        if "VALUE" in row:
            stat["value"] = row["VALUE"]
        put(stat, "text", text(row.get("SORT")))
        put(stat, "name", text(row.get("NAME")))
        stats.append(stat)
    put(entry, "stats", stats)
    put(entry, "display_offset", offset(data.get("DisplayOffset"), 0))
    return entry


def zombie_entry(zid, data, feature):
    entry = {"id": zid}
    feature = feature or {}
    put(entry, "name", text(feature.get("NAME")))
    put(entry, "world", feature.get("OBTAINWORLD"))
    put(entry, "description", text(data.get("Introduction")))
    put(entry, "chat", text(data.get("Chat")))
    put(entry, "special", specials(data.get("Special")))
    stats = []
    for row in data.get("Elements", []):
        stat = {"type": ZOMBIE_STATS.get(row.get("TYPE"), str(row.get("TYPE", "")).lower())}
        if "PROGRESS" in row:
            stat["level"] = row["PROGRESS"]
        put(stat, "text", text(row.get("SORT")))
        stats.append(stat)
    put(entry, "stats", stats)
    put(entry, "display_offset", offset(data.get("DisplayOffset"), 0))
    put(entry, "display_scale", offset(data.get("DisplayScale"), 1))
    # Reskins the almanac files under this zombie: the birthday and holiday
    # basics all count as meeting the Basic Zombie.
    put(entry, "variants", feature.get("SubZombieList"))
    return entry


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    res = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "native")
    build = Build(os.path.join(res, "import"), os.path.join(res, "config.json"))

    plant_alm = load(build, "plant_almanac", "objects")["objects"]
    zombie_alm = load(build, "zombie_almanac", "objects")["objects"]
    zf = load(build, "zombie_features", "ZOMBIES")
    zombie_features = {z["CODENAME"]: z for z in zf["ZOMBIES"]}
    plant_features = {}
    try:
        pf = load(build, "plant_features", "PLANTS")
        plant_features = {p["CODENAME"]: p for p in pf["PLANTS"]}
    except SystemExit:
        # Older builds: fall back to the prop sheet extract_features.py wrote.
        local = os.path.join(out, "..", "pvzge", "PlantFeatures.json")
        if os.path.exists(local):
            plant_features = json.load(open(local, encoding="utf-8"))

    plants_dir = os.path.join(out, "almanac", "plants")
    zombies_dir = os.path.join(out, "almanac", "zombies")
    native_plants = os.path.join(out, "plants")
    native_zombies = os.path.join(out, "zombies")
    written = [0, 0]
    for obj in plant_alm:
        for pid in obj.get("aliases", []):
            # Evil potions are filed as plants in PVZGE; here they are board
            # objects, which never reach an almanac.
            if os.path.isdir(native_plants) and not os.path.exists(
                    os.path.join(native_plants, pid + ".json")):
                continue
            write(os.path.join(plants_dir, pid + ".json"),
                  plant_entry(pid, obj["objdata"], plant_features.get(pid)))
            written[0] += 1
    for obj in zombie_alm:
        for zid in obj.get("aliases", []):
            # `empty` is a placeholder; PVZGE has no newspaper zombie data.
            if os.path.isdir(native_zombies) and not os.path.exists(
                    os.path.join(native_zombies, zid + ".json")):
                continue
            write(os.path.join(zombies_dir, zid + ".json"),
                  zombie_entry(zid, obj["objdata"], zombie_features.get(zid)))
            written[1] += 1
    order = [z for z in zf.get("ALMANAC", [])
             if os.path.exists(os.path.join(zombies_dir, z + ".json"))]
    write(os.path.join(out, "almanac.json"), {
        "comment": "The almanac's zombie page order, PVZGE's ZombieFeatures "
                   "ALMANAC list. Plants follow seed_chooser.json's order. "
                   "Entries a pack adds are listed after these.",
        "zombie_order": order,
    })
    print("almanac: %d plants, %d zombies, %d in the zombie order"
          % (written[0], written[1], len(order)))


if __name__ == "__main__":
    main()
