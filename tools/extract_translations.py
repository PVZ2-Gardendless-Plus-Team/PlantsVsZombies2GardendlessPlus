#!/usr/bin/env python3
"""Pull PVZGE's UI text (English + Simplified Chinese) into data/native/i18n.

PVZGE keeps every UI string in one JsonAsset, `json/multilanguages/InGameLyrics`:
a tree whose leaves are {"en": ..., "zh": ...} pairs, read through its
MultiLanguage class (`getStringByProps("GamePaused", "Title")`). The tree is
copied as-is, so a path into it means the same thing here as in PVZGE's code.

    python3 tools/extract_translations.py <import dir> <res.config.json> [out file]

At startup the I18n autoload turns every pair into an English -> Chinese
message (English text is the translation key; see docs/TRANSLATING.md), and
`I18n.lyric("GamePaused/Title")` reads a leaf by its path.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_prefabs import Build, embedded  # noqa: E402

ASSET = "json/multilanguages/InGameLyrics"
MARKER = "SettingLyrics"    # a top-level key only this tree has


def count_pairs(node):
    if isinstance(node, dict):
        if isinstance(node.get("en"), str):
            return 1
        return sum(count_pairs(v) for v in node.values())
    if isinstance(node, list):
        return sum(count_pairs(v) for v in node)
    return 0


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    import_dir, config = sys.argv[1], sys.argv[2]
    dest = sys.argv[3] if len(sys.argv) > 3 else "data/native/i18n/pvzge_lyrics.json"
    build = Build(import_dir, config)
    index = build.by_name.get(ASSET)
    hits = embedded(build.instance(index), MARKER) if index is not None else []
    if not hits:
        sys.exit(f"  !! {ASSET}: not found")
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump(hits[0], fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print(f"  InGameLyrics {count_pairs(hits[0]):>5} strings -> {dest}")


if __name__ == "__main__":
    main()
