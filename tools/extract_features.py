#!/usr/bin/env python3
"""Pull PVZGE's PlantFeatures table into data/pvzge/PlantFeatures.json.

PlantFeatures is the game's own per-plant registry, separate from the PopCap
prop sheets: it is where a plant's world (`OBTAINWORLD`, which picks the seed
packet's backing), its packet portrait (`_CARDSPRITENAME`), its names and its
almanac entry live. It is a JsonAsset packed with other assets, so it is found
by name through the same graph extract_prefabs.py walks.

    python3 tools/extract_features.py <import dir> <res.config.json> [out dir]

The output is keyed by CODENAME, the name the prop sheets use too.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_prefabs import Build, embedded  # noqa: E402

FEATURES = {
    "PlantFeatures": ("json/Features/PlantFeatures", "PLANTS"),
}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    import_dir, config = sys.argv[1], sys.argv[2]
    out_dir = sys.argv[3] if len(sys.argv) > 3 else "data/pvzge"
    build = Build(import_dir, config)
    for name, (path, key) in FEATURES.items():
        index = build.by_name.get(path)
        hits = embedded(build.instance(index), key) if index is not None else []
        if not hits:
            print(f"  !! {name}: not found", file=sys.stderr)
            continue
        table = {row["CODENAME"]: row for row in hits[0][key] if row.get("CODENAME")}
        dest = os.path.join(out_dir, f"{name}.json")
        with open(dest, "w", encoding="utf-8") as fh:
            json.dump(table, fh, ensure_ascii=False, indent=1, sort_keys=True)
        print(f"  {name:16} {len(table):>5} entries -> {dest}")


if __name__ == "__main__":
    main()
