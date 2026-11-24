#!/usr/bin/env python3
"""List UI strings that have no translation yet, per language.

    python3 tools/check_translations.py [--strict]

Finds English strings the way docs/TRANSLATING.md asks code to mark them:
tr("...") / tr("...", "context") / TranslationServer.translate("..."), plus
literals handed to MenuUI.label/title/button and to text-like properties
(text, tooltip_text, dialog_text, title, ok_button_text). Each is checked
against what I18n loads for every locale file in data/native/i18n: PVZGE's
InGameLyrics column the file names with "pvzge", then the file's own
"strings" / "contexts".

It also flags translations whose %-placeholders differ from the English
ones, since Godot's `%` formats by position and a mismatch errors at runtime.
--strict exits non-zero on anything it reports, for CI.
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, "data", "native", "i18n")
SCAN = ["game", "core", "mods"]

STR = r'"((?:[^"\\\n]|\\.)*)"'
CALLS = [
    re.compile(r'\btr\(\s*' + STR + r'(?:\s*,\s*' + STR + r')?\s*\)'),
    re.compile(r'TranslationServer\.translate\(\s*' + STR + r'(?:\s*,\s*' + STR + r')?\s*\)'),
    re.compile(r'MenuUI\.(?:label|title|button)\(\s*' + STR),
    re.compile(r'\b(?:text|tooltip_text|dialog_text|title|ok_button_text)\s*=\s*\(?\s*' + STR),
]
PLACEHOLDER = re.compile(r'%[-+ 0#*]*\d*(?:\.\d+)?[sdifoxXc%]')


def unescape(s):
    return json.loads('"%s"' % s)


def joined_literals(src):
    """Adjacent "a" + "b" literals inside a call become one string, as GDScript sees them."""
    return re.sub(r'"\s*\n?\s*\+\s*"', "", src)


def used_strings():
    found = {}
    for top in SCAN:
        for path in glob.glob(os.path.join(ROOT, top, "**", "*.gd"), recursive=True):
            src = joined_literals(open(path, encoding="utf-8").read())
            for rx in CALLS:
                for m in rx.finditer(src):
                    text = unescape(m.group(1))
                    ctx = unescape(m.group(2)) if rx.groups > 1 and m.group(2) else ""
                    # Only text a player reads: words, not ids, paths or bare numbers.
                    if not re.search(r"[A-Za-z]{2}", text) or re.fullmatch(r"[\w./:]+", text) and "_" in text:
                        continue
                    line = src[:m.start()].count("\n") + 1
                    found.setdefault((text, ctx), f"{os.path.relpath(path, ROOT)}:{line}")
    return found


def lyric_pairs(node, column, out):
    if isinstance(node, dict):
        if isinstance(node.get("en"), str):
            if node["en"] and node.get(column):
                out.setdefault(node["en"], node[column])
            return
        for v in node.values():
            lyric_pairs(v, column, out)
    elif isinstance(node, list):
        for v in node:
            lyric_pairs(v, column, out)


def main():
    strict = "--strict" in sys.argv
    lyrics_path = os.path.join(I18N, "pvzge_lyrics.json")
    lyrics = json.load(open(lyrics_path, encoding="utf-8")) if os.path.exists(lyrics_path) else {}
    used = used_strings()
    problems = 0
    for path in sorted(glob.glob(os.path.join(I18N, "*.json"))):
        if os.path.basename(path) == "pvzge_lyrics.json":
            continue
        locale = os.path.splitext(os.path.basename(path))[0]
        spec = json.load(open(path, encoding="utf-8"))
        plain = {}
        if spec.get("pvzge"):
            lyric_pairs(lyrics, spec["pvzge"], plain)
        plain.update(spec.get("strings", {}))
        contexts = spec.get("contexts", {})

        missing = []
        for (text, ctx), where in sorted(used.items(), key=lambda kv: kv[1]):
            if text in contexts.get(ctx, {}) or text in plain:
                continue
            missing.append((where, text, ctx))
        bad = []
        for table in [spec.get("strings", {})] + list(contexts.values()):
            for en, xl in table.items():
                if sorted(PLACEHOLDER.findall(en)) != sorted(PLACEHOLDER.findall(xl)) \
                        or PLACEHOLDER.findall(en) != PLACEHOLDER.findall(xl):
                    bad.append((en, xl))

        print(f"{locale} ({spec.get('name', locale)}): {len(used) - len(missing)}/{len(used)} "
              f"marked strings translated")
        for where, text, ctx in missing:
            print(f"  missing  {where}  {text!r}" + (f"  [context {ctx!r}]" if ctx else ""))
        for en, xl in bad:
            print(f"  placeholders differ  {en!r} -> {xl!r}")
        problems += len(missing) + len(bad)
    if strict and problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
