#!/usr/bin/env python3
"""Turn a tools/dump_worldmaps.js dump into world map layouts and art.

    python3 tools/extract_worldmaps.py <dump dir> <art dir> <data dir> \\
        --native <native dir>

Writes, into `<data dir>` (normally data/native/worldmaps):

- `<codename>.json` per PVZGE world map: its background layers, its islands
  and which level each island holds, in Godot's coordinates (y down, PVZGE
  pixels, origin at the screen centre when the map is scrolled to 0).
- `chooser.json`: the world globes of PVZGE's world chooser.
- `level_nodes.json`: the level node, path, gift box, portal and Zomboss
  head that the map puts on the islands.

and, into `<art dir>`, one bundle per DragonBones export the maps use,
`wm_<skeleton>_<first 8 of its uuid>/` with skeleton.json and atlas.json, its
image under `_textures/`, and an entry in `_index.json`. Each world ships two
or three exports that share the name `WorldmapAnimate`, so the uuid is what
tells them apart. The images come from `--native` (a desktop build's
assets/resources/native, which has PNGs where the web build has AVIF); one
already in `<art>/_textures` is reused.

A layout is a list of layers drawn back to front. Each layer drifts by
`factor` times the map's scroll, which is PVZGE's parallax: the islands and
level nodes move 1:1, `Far` pieces less and `Near` pieces more (WorldMap's
`farIslands` and their `offsetScale`), and the backdrop not at all. A layer of
kind `levels` marks where the level paths and nodes are drawn.
"""
import json, os, shutil, sys

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
# WorldMap.ts islandDisplayEnum and LevelIsland.levelNodeAppearance.
ISLAND_KINDS = ["level", "plant", "giftbox", "upgrade", "epic_portal"]
APPEARANCES = ["normal", "minigame", "gargantuar", "zomboss"]


# --- transforms ----------------------------------------------------------
# Cocos is y-up with counter-clockwise angles. A 2x3 matrix [a, b, c, d, tx, ty]
# maps (x, y) to (a x + c y + tx, b x + d y + ty), like Godot's Transform2D.

def local_matrix(node):
    import math
    r = math.radians(node.get("angle", 0) or 0)
    sx, sy = node["scale"]
    cos, sin = math.cos(r), math.sin(r)
    x, y = node["pos"]
    return [cos * sx, sin * sx, -sin * sy, cos * sy, x, y]


def mul(p, q):
    a, b, c, d, tx, ty = p
    return [a * q[0] + c * q[1], b * q[0] + d * q[1],
            a * q[2] + c * q[3], b * q[2] + d * q[3],
            a * q[4] + c * q[5] + tx, b * q[4] + d * q[5] + ty]


IDENTITY = [1, 0, 0, 1, 0, 0]


def to_godot(m):
    """Flip a y-up matrix into y-down: F M F with F = diag(1, -1)."""
    a, b, c, d, tx, ty = m
    return [round(v, 4) for v in (a, -b, -c, d, tx, -ty)]


def point(m):
    return [round(m[4], 2), round(-m[5], 2)]


# --- rigs ----------------------------------------------------------------

class Rigs:
    """Writes each DragonBones export once and names its bundle."""

    def __init__(self, dump_dir, art_dir, native_dir):
        self.dump_dir, self.art_dir, self.native_dir = dump_dir, art_dir, native_dir
        self.bundles = {}
        index_path = os.path.join(art_dir, "_index.json")
        self.index = json.load(open(index_path, encoding="utf-8")) if os.path.exists(index_path) else {}
        self.missing = []

    def bundle(self, uuid):
        if not uuid:
            return None
        if uuid in self.bundles:
            return self.bundles[uuid]
        path = os.path.join(self.dump_dir, "rigs", uuid + ".json")
        if not os.path.exists(path):
            self.bundles[uuid] = None
            return None
        rig = json.load(open(path, encoding="utf-8"))
        skeleton = json.loads(rig["skeleton"])
        atlas = json.loads(rig["atlas"])
        slug = "wm_%s_%s" % (skeleton.get("name", "rig"), uuid[:8])
        dest = os.path.join(self.art_dir, slug)
        os.makedirs(dest, exist_ok=True)
        json.dump(skeleton, open(os.path.join(dest, "skeleton.json"), "w", encoding="utf-8"),
                  ensure_ascii=False, separators=(",", ":"))
        json.dump(atlas, open(os.path.join(dest, "atlas.json"), "w", encoding="utf-8"),
                  ensure_ascii=False, separators=(",", ":"))
        texture = rig["texture"] + ".png"
        self._copy_texture(texture)
        self.index[slug] = {
            "path": "worldmap:%s" % uuid,
            "uuid": uuid,
            "skeleton": skeleton.get("name"),
            "frame_rate": skeleton.get("frameRate"),
            "armature": skeleton["armature"][0]["name"],
            "armatures": [
                {"name": a.get("name"), "bones": len(a.get("bone", [])),
                 "slots": len(a.get("slot", [])),
                 "animations": [an.get("name") for an in a.get("animation", [])]}
                for a in skeleton.get("armature", [])],
            "atlas": {"name": atlas.get("name"), "image": atlas.get("imagePath"),
                      "size": [atlas.get("width"), atlas.get("height")],
                      "regions": len(atlas.get("SubTexture", []))},
            "textures": [texture],
        }
        self.bundles[uuid] = slug
        return slug

    def _copy_texture(self, name):
        out = os.path.join(self.art_dir, "_textures", name)
        if os.path.exists(out):
            return
        src = os.path.join(self.native_dir or "", name[:2], name)
        if self.native_dir and os.path.exists(src) and open(src, "rb").read(8) == PNG_MAGIC:
            os.makedirs(os.path.dirname(out), exist_ok=True)
            shutil.copyfile(src, out)
        else:
            self.missing.append(name)

    def save(self):
        json.dump(self.index, open(os.path.join(self.art_dir, "_index.json"), "w", encoding="utf-8"),
                  indent=1, ensure_ascii=False)


# --- layouts -------------------------------------------------------------

def components(node, kind):
    return [c for c in node["comps"] if c["type"] == kind]


def piece(node, comp, xform, path, rigs):
    bundle = rigs.bundle(comp.get("rig"))
    if bundle is None or not comp.get("armature"):
        return None
    p = {"id": path, "bundle": bundle, "armature": comp["armature"],
         "animation": comp.get("animation") or "", "xform": to_godot(xform)}
    if comp.get("time_scale", 1) != 1:
        p["time_scale"] = comp["time_scale"]
    color = comp.get("color")
    if color and color != [255, 255, 255, 255]:
        p["color"] = [round(v / 255.0, 3) for v in color]
    if comp.get("play_times") not in (-1, 0, None):
        p["play_times"] = comp["play_times"]
    return p


def flatten(root, rigs, factors, levels_path=None):
    """-> layers, back to front.

    `factors` maps a node path to its parallax factor; a node's pieces drift
    with the nearest such ancestor, or not at all. A layer is cut wherever
    the factor changes, so draw order survives.
    """
    layers = []

    def current(factor, origin):
        if layers and layers[-1].get("kind") == "pieces" and layers[-1]["factor"] == factor \
                and layers[-1]["_origin"] == origin:
            return layers[-1]
        layer = {"kind": "pieces", "factor": factor, "origin": [0, 0], "_origin": origin,
                 "pieces": []}
        layers.append(layer)
        return layer

    def walk(node, path, world, group_world, factor, origin):
        if not node["active"]:
            return
        if path == levels_path:
            layers.append({"kind": "levels"})
            return
        m = mul(world, local_matrix(node)) if path else world
        if path in factors:
            factor, origin, group_world = factors[path], path, m
        for comp in components(node, "dragonBones.ArmatureDisplay"):
            # Relative to the layer's own node, which is what drifts.
            rel = mul(invert(group_world), m)
            p = piece(node, comp, rel, path, rigs)
            if p:
                layer = current(factor, origin)
                layer["origin"] = point(group_world)
                layer["pieces"].append(p)
        for child in node["children"]:
            walk(child, (path + "/" if path else "") + child["name"], m, group_world, factor, origin)

    walk(root, "", IDENTITY, IDENTITY, 0.0, "")
    for layer in layers:
        layer.pop("_origin", None)
    return layers


def invert(m):
    a, b, c, d, tx, ty = m
    det = a * d - b * c
    if abs(det) < 1e-12:
        return IDENTITY
    ia, ib, ic, id_ = d / det, -b / det, -c / det, a / det
    return [ia, ib, ic, id_, -(ia * tx + ic * ty), -(ib * tx + id_ * ty)]


def find(node, path):
    for name in path.split("/") if path else []:
        node = next((c for c in node["children"] if c["name"] == name), None)
        if node is None:
            return None
    return node


def world_of(root, path):
    m, node = IDENTITY, root
    for name in path.split("/"):
        node = next((c for c in node["children"] if c["name"] == name), None)
        if node is None:
            return None
        m = mul(m, local_matrix(node))
    return m


def ref(value):
    return value.get("node") if isinstance(value, dict) else None


def world_map(name, root, feature, rigs):
    comp = components(root, "WorldMap")[0]["fields"]
    factors = {}
    island_parent = ref(comp.get("islandParent")) or "Level_Islands"
    level_parent = ref(comp.get("levelParent")) or "Levels"
    factors[island_parent] = 1.0
    for far in comp.get("farIslands") or []:
        path = ref(far.get("islandNode"))
        if path:
            factors[path] = float(far.get("offsetScale", 1))
    layers = flatten(root, rigs, factors, level_parent)

    islands = []
    for isl in comp.get("levelIslands") or []:
        path = ref(isl.get("islandNode"))
        m = world_of(root, path) if path else None
        if m is None:
            continue
        nexts = [ref(isl.get("nextIsland"))] + [ref(n) for n in isl.get("otherNextIslands") or []]
        kind = ISLAND_KINDS[isl.get("islandDisplay", 0)]
        entry = {"id": path, "kind": kind, "position": point(m),
                 "next": [n for n in nexts if n]}
        if kind == "level":
            entry["levels"] = isl.get("levelJsonsID") or []
            entry["appearance"] = APPEARANCES[isl.get("levelNodeAppearance", 0)]
            entry["name"] = isl.get("levelNodeName") or ""
        elif kind == "epic_portal":
            entry["levels"] = isl.get("epicLevelJsonsID") or []
        elif kind == "plant":
            entry["plant"] = isl.get("plantDisplayed")
        elif kind == "upgrade":
            entry["upgrade"] = isl.get("upgradeDisplayed")
        if isl.get("affectsMaxX") is False:
            entry["affects_scroll"] = False
        shown = [ref(db) for db in isl.get("displayedIslandDBs") or []]
        if any(shown):
            entry["displays"] = [s for s in shown if s]
        islands.append(entry)

    out = {
        "codename": feature.get("CODENAME"),
        "res": feature.get("RESNAME"),
        "difficulty": feature.get("DIFFICULTY", 0),
        "at_night": bool(comp.get("atNight")),
        "epic_target": feature.get("EPIC_TARGET", ""),
        "intro": feature.get("INTRO", ""),
        "starting_levels": comp.get("startingLevels") or feature.get("STARTINGLEVELS") or [],
        "levels": feature.get("LEVELS", []),
        "plants": feature.get("PLANTS", []),
        "layers": layers,
        "islands": islands,
    }
    return out


def level_nodes(nodes, rigs):
    out = {}
    for key, root in nodes.items():
        root = dict(root, pos=[0, 0], name="node")     # placed on an island, scale kept
        holder = {"name": "", "active": True, "pos": [0, 0], "scale": [1, 1], "angle": 0,
                  "comps": [], "children": [root]}
        entry = {"pieces": []}
        for layer in flatten(holder, rigs, {}):
            entry["pieces"] += layer.get("pieces", [])
        title = find(root, "title")
        if title:
            m = mul(local_matrix(root), local_matrix(title))
            label = components(title, "cc.Label")[0]
            entry["title"] = {"xform": to_godot(m), "font_size": label["font_size"]}
        listener = find(root, "listener")
        if listener:
            m = mul(local_matrix(root), local_matrix(listener))
            size = components(listener, "cc.UITransform")[0]["size"]
            sx, sy = abs(m[0]), abs(m[3])
            entry["hit"] = [round(m[4] - size[0] * sx / 2, 2), round(-m[5] - size[1] * sy / 2, 2),
                            round(size[0] * sx, 2), round(size[1] * sy, 2)]
        out[key] = entry
    return out


def chooser(root, features, rigs):
    comp = components(root, "WorldMapChooser")[0]["fields"]
    icons = []
    layout = find(root, "Layout")
    for icon in comp.get("icons") or []:
        path = ref(icon.get("node"))
        node = find(root, path) if path else None
        if node is None:
            continue
        db = components(node, "dragonBones.ArmatureDisplay")
        p = piece(node, db[0], IDENTITY, path, rigs) if db else None
        to = icon.get("enterTo", 0) if icon.get("enterable", True) else None
        icons.append({
            "id": node["name"],
            "x": node["pos"][0],
            "world": features[to]["CODENAME"] if to is not None and to < len(features) else "",
            "at_night": bool(icon.get("atNight")),
            "piece": p,
        })
    mid = find(root, "Mid")
    mid_db = components(mid, "dragonBones.ArmatureDisplay") if mid else []
    labels = find(root, "Labels")
    name = find(root, "Labels/name")
    return {
        "scale": layout["scale"][0] if layout else 1,
        "icons": icons,
        "mid": piece(mid, mid_db[0], local_matrix(mid), "Mid", rigs) if mid_db else None,
        "name_y": -(name["pos"][1] * labels["scale"][1]) if name and labels else 0,
    }


def main():
    args = [a for a in sys.argv[1:]]
    native = None
    if "--native" in args:
        i = args.index("--native")
        native = args[i + 1]
        del args[i:i + 2]
    if len(args) < 3:
        print(__doc__)
        return 2
    dump_dir, art_dir, data_dir = args[:3]
    dump = json.load(open(os.path.join(dump_dir, "layouts.json"), encoding="utf-8"))
    features = dump["features"]["WORLDMAPS"]
    by_res = {f["RESNAME"]: f for f in features}
    rigs = Rigs(dump_dir, art_dir, native)
    os.makedirs(data_dir, exist_ok=True)

    for key, root in dump["layouts"].items():
        if "error" in root:
            print("   !! %s: %s" % (key, root["error"]))
            continue
        res = key.split("/")[-1][:-len("WORLDMAP")]
        if res == "WorldmapChooser":
            data = chooser(root, features, rigs)
            name = "chooser"
        else:
            feature = by_res.get(res, {"CODENAME": res.lower(), "RESNAME": res})
            data = world_map(res, root, feature, rigs)
            name = data["codename"]
        json.dump(data, open(os.path.join(data_dir, name + ".json"), "w", encoding="utf-8"),
                  indent=1, ensure_ascii=False)
        pieces = sum(len(l.get("pieces", [])) for l in data.get("layers", []))
        print("   %-24s -> %s.json (%d pieces, %d islands)"
              % (key, name, pieces, len(data.get("islands", data.get("icons", [])))))

    json.dump(level_nodes(dump["nodes"], rigs),
              open(os.path.join(data_dir, "level_nodes.json"), "w", encoding="utf-8"),
              indent=1, ensure_ascii=False)
    rigs.save()
    print("%d rig bundles" % len([b for b in rigs.bundles.values() if b]))
    if rigs.missing:
        print("   !! no PNG for %d images: %s" % (len(rigs.missing), ", ".join(rigs.missing)))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
