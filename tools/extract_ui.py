#!/usr/bin/env python3
"""Pull PVZGE's flat UI sprites and fonts into the art repo.

The menus, windows, buttons and counters are not DragonBones rigs but plain
Cocos SpriteFrames - mostly regions of one big UI atlas - so neither
extract_prefabs.py nor extract_rigs.py sees them. A SpriteFrame is serialized
as a small object with a name, a rect inside its texture, a rotated flag and
nine-slice `capInsets`; the texture is the last uuid reference of its
instance. That is all this needs:

    python3 tools/extract_ui.py <build resources dir> <art dir> [name ...]

`<build resources dir>` is `assets/resources` (holding `import/`, `native/` and
`config.json`) from the web build or a desktop build unpacked with
extract_desktop.py. With no names, every SpriteFrame in the bundle is written.

Writes, under `<art dir>`:

    ui/<name>.png      the frame, cut out and un-rotated (its trimmed rect)
    ui/_index.json     name -> size, original size, offset and nine-slice
                       insets (left, top, right, bottom), in pixels
    fonts/<name>.ttf   the two Latin faces: FBUSV8C5EI (labels, buttons,
                       prices) and HOUSEOFTERROR (the red lawn warnings).
                       The build's other three fonts are Chinese and pixel
                       faces for its other languages.

Two frames sharing a name (the seed chooser's world backdrops and the world
map's both say `egypt`) keep the first under the plain name and the rest as
`<name>@<texture>`; the index records every one.
"""
import json, os, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_prefabs import decode_uuid, safe_name  # noqa: E402

try:
    from PIL import Image
except ImportError:  # pragma: no cover - only the tool needs it
    sys.exit("extract_ui.py needs Pillow: pip install pillow")


FONTS = ("FBUSV8C5EI.ttf", "HOUSEOFTERROR.ttf")


def frames_in(path):
    """-> (frame dict, texture uuid) for every SpriteFrame in one import file."""
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return []
    if not (isinstance(data, list) and len(data) > 5 and isinstance(data[3], list)):
        return []
    classes = [c[0] if isinstance(c, list) else c for c in data[3]]
    if "cc.SpriteFrame" not in classes:
        return []
    shared = data[1] if isinstance(data[1], list) else []
    instances = data[5]
    # A standalone asset is one instance; a pack is a list of them.
    if instances and isinstance(instances[0], list) and instances[0] \
            and isinstance(instances[0][0], dict):
        instances = [instances]
    out = []
    for inst in instances:
        if not (isinstance(inst, list) and inst and isinstance(inst[0], list)
                and inst[0] and isinstance(inst[0][0], dict)):
            continue
        frame = inst[0][0]
        if "rect" not in frame or "originalSize" not in frame:
            continue
        refs = inst[-1] if isinstance(inst[-1], list) else []
        texture = None
        if refs and isinstance(refs[0], int) and refs[0] < len(shared):
            texture = decode_uuid(shared[refs[0]]).split("@")[0]
        out.append((frame, texture))
    return out


def cut(native_dir, texture, frame):
    """-> the frame's pixels, upright, or None when its texture is missing."""
    png = os.path.join(native_dir, texture[:2], texture + ".png")
    if not os.path.exists(png):
        return None
    r = frame["rect"]
    x, y, w, h = int(r["x"]), int(r["y"]), int(r["width"]), int(r["height"])
    image = Image.open(png).convert("RGBA")
    if frame.get("rotated"):
        # Packed a quarter turn clockwise: the region is h wide and w tall.
        return image.crop((x, y, x + h, y + w)).rotate(90, expand=True)
    return image.crop((x, y, x + w, y + h))


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    build, art = sys.argv[1], sys.argv[2]
    wanted = set(sys.argv[3:])
    import_dir = os.path.join(build, "import")
    native_dir = os.path.join(build, "native")
    ui_dir = os.path.join(art, "ui")
    os.makedirs(ui_dir, exist_ok=True)

    index_path = os.path.join(ui_dir, "_index.json")
    index = json.load(open(index_path)) if os.path.exists(index_path) else {}
    taken = {}
    written = missing = 0
    for sub in sorted(os.listdir(import_dir)):
        folder = os.path.join(import_dir, sub)
        if not os.path.isdir(folder):
            continue
        for fname in sorted(os.listdir(folder)):
            if not fname.endswith(".json"):
                continue
            for frame, texture in frames_in(os.path.join(folder, fname)):
                name = str(frame.get("name", ""))
                if name == "" or texture is None or (wanted and name not in wanted):
                    continue
                key = safe_name(name, "frame")
                if key in taken and taken[key] != texture:
                    key = "%s@%s" % (key, texture[:9])
                if key in taken:
                    continue    # the same frame, seen again in another pack
                taken[key] = texture
                pixels = cut(native_dir, texture, frame)
                if pixels is None:
                    missing += 1
                    continue
                pixels.save(os.path.join(ui_dir, key + ".png"))
                o, off = frame["originalSize"], frame.get("offset", {})
                insets = frame.get("capInsets", [0, 0, 0, 0])
                index[key] = {
                    "size": list(pixels.size),
                    "original": [o["width"], o["height"]],
                    "offset": [off.get("x", 0), off.get("y", 0)],
                    # Cocos keeps them left, top, right, bottom like Godot.
                    "insets": [int(v) for v in insets],
                    "texture": texture,
                }
                written += 1
    json.dump(index, open(index_path, "w"), indent=1, sort_keys=True)

    fonts = 0
    fonts_dir = os.path.join(art, "fonts")
    for root, _, files in os.walk(native_dir):
        for fname in files:
            if fname in FONTS:
                os.makedirs(fonts_dir, exist_ok=True)
                shutil.copyfile(os.path.join(root, fname), os.path.join(fonts_dir, fname))
                fonts += 1
    print("ui: %d frames written, %d with no texture on disk; %d fonts"
          % (written, missing, fonts))


if __name__ == "__main__":
    main()
