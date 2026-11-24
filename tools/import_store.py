#!/usr/bin/env python3
"""Convert PVZGE's store catalog (StoreCommodityFeatures) into data/native/store.json.

PVZGE keeps its store in one JsonAsset named StoreCommodityFeatures, with a list
per tab: Plants, Upgrade, Gem, Coin, Zen. Each row is a StoreCommodityProps:

    CommodityType     plant | upgrade | gem | coin | sprout
    CommodityName     plant codename or upgrade id (plants, upgrades)
    CommodityCount    how many gems/coins/sprouts a pack holds
    CurrencyType      coin | gem | ticket - what it costs
    CurrencyRequired  the price
    UnlockLevel       level that must be won before the plant is offered
    PlantWeekDiscount price factor while the plant is the plant of the week
    StackLevel        which pile picture a pack shows
    CommodityDisplayName {en, zh}

The native file gives every ware an id, names its page, and spells currencies
the way Saves does (coins, gems, tickets, sprouts).

Usage:
    import_store.py <pvzge build root or a JSON file> [out=data/native/store.json]

The build root is a PVZGE web/desktop build (the folder holding assets/); every
JSON under assets/resources/import is searched for the catalog.
"""
import json, os, sys

CURRENCY = {"coin": "coins", "gem": "gems", "ticket": "tickets", "sprout": "sprouts"}
PAGES = [
    # PVZGE tab key, native page id, title, icon sprite
    ("Plants", "plants", {"en": "Plants", "zh": "植物"}, "PlayerIcon"),
    ("Upgrade", "upgrades", {"en": "Upgrades", "zh": "升级"}, "MedalIcon"),
    ("Coin", "coins", {"en": "Coins", "zh": "金币"}, "CoinIcon"),
    ("Gem", "gems", {"en": "Gems", "zh": "钻石"}, "GemIcon"),
    ("Zen", "zen", {"en": "Zen Garden", "zh": "禅境花园"}, "ZenTag"),
]


def find_catalog(node):
    """Cocos packs a JsonAsset as [type, name, payload]; find ours."""
    if isinstance(node, list):
        if len(node) >= 3 and node[1] == "StoreCommodityFeatures" and isinstance(node[2], dict):
            return node[2]
        for x in node:
            hit = find_catalog(x)
            if hit:
                return hit
    elif isinstance(node, dict):
        if "Plants" in node and "Gem" in node and "Coin" in node:
            return node
        for x in node.values():
            hit = find_catalog(x)
            if hit:
                return hit
    return None


def load_catalog(path):
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            return find_catalog(json.load(f))
    root = os.path.join(path, "assets", "resources", "import")
    for dirpath, _, files in os.walk(root):
        for name in files:
            if not name.endswith(".json"):
                continue
            full = os.path.join(dirpath, name)
            with open(full, encoding="utf-8") as f:
                text = f.read()
            if "StoreCommodityFeatures" not in text:
                continue
            hit = find_catalog(json.loads(text))
            if hit:
                return hit
    return None


def convert_row(row, page):
    kind = row.get("CommodityType", "plant")
    item = {"page": page}
    if kind in ("plant", "upgrade"):
        item["id"] = "%s_%s" % (kind, row["CommodityName"]) if kind == "plant" else row["CommodityName"]
        item["type"] = kind
        item["param"] = row["CommodityName"]
    else:
        currency = CURRENCY.get(kind, kind)
        item["id"] = "%s_%d" % (currency, row.get("CommodityCount", 1))
        item["type"] = "currency"
        item["param"] = currency
        item["count"] = row.get("CommodityCount", 1)
        item["stack"] = row.get("StackLevel", 0)
    item["currency"] = CURRENCY.get(row.get("CurrencyType", "coin"), row.get("CurrencyType"))
    item["price"] = row.get("CurrencyRequired", 0)
    if row.get("UnlockLevel"):
        item["unlock_level"] = row["UnlockLevel"]
    if row.get("PlantWeekDiscount") is not None:
        item["weekly_discount"] = row["PlantWeekDiscount"]
    if row.get("CommodityDisplayName"):
        item["name"] = row["CommodityDisplayName"]
    return item


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    out_path = sys.argv[2] if len(sys.argv) > 2 else "data/native/store.json"
    catalog = load_catalog(sys.argv[1])
    if not catalog:
        sys.exit("no StoreCommodityFeatures found under %s" % sys.argv[1])
    out = {
        "//": "The store, converted from PVZGE's StoreCommodityFeatures by tools/import_store.py. "
              "Pages are the tabs, in order. Items: type plant (param = plant id), upgrade (param = "
              "upgrade id) or currency (param = coins/gems/tickets/sprouts, `count` of it); `currency` "
              "and `price` are what it costs; `unlock_level` hides a plant until that level is won; "
              "`weekly_discount` marks a plant that can be plant of the week, sold at that fraction of "
              "its price that week. A pack's store.json replaces items with the same id, adds new ones "
              "and drops the ids it lists in `remove`.",
        "pages": [],
        "items": [],
    }
    for key, page, title, icon in PAGES:
        out["pages"].append({"id": page, "title": title, "icon": icon})
        for row in catalog.get(key, []):
            out["items"].append(convert_row(row, page))
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("wrote %d items on %d pages to %s" % (len(out["items"]), len(out["pages"]), out_path))


if __name__ == "__main__":
    main()
