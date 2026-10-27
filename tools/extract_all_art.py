#!/usr/bin/env python3
"""Extract every DragonBones prefab and rig in the PVZGE build into the art repo.

extract_prefabs.py and extract_rigs.py take names; this feeds them all of
them. Every `cc.Prefab` in config.json goes through extract_prefabs.py, then
every rig extract_rigs.py can find that no prefab already brought in - the
sun, the HUD pieces, particles, seed packets and the rest of the scene art.
A rig name shared by several different exports is taken once per export, as
NAME:ARMATURE.

    python3 tools/extract_all_art.py <build resources dir> <art repo> [--commit] [--push]

`<build resources dir>` is `assets/resources` - the one holding `import/`,
`native/` and `config.json` - from the web build or a desktop build unpacked
with extract_desktop.py. `<art repo>` is a clone of MacksPVZ2-Again.Art (the
`art` submodule works too). Output is merged into whatever is there.

With --commit it starts an `extract-art` branch from the art repo's
origin/master first, then commits the result; --push also pushes the branch.
It refuses to commit more than 3 GB, which is about where Git LFS quotas start
to hurt.
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_prefabs  # noqa: E402
import extract_rigs  # noqa: E402

BRANCH = "extract-art"
LIMIT = 3 * 1024 ** 3


def git(repo, *args, capture=False):
    run = subprocess.run(["git", "-C", repo] + list(args), check=True,
                         capture_output=capture, text=True)
    return run.stdout if capture else None


def run_tool(module, argv):
    """Runs a tool's main() in-process: thousands of names overrun a command line."""
    saved = sys.argv
    sys.argv = [module.__file__] + argv
    try:
        return module.main()
    finally:
        sys.argv = saved


def prefab_names(build):
    return sorted(name for name, idx in build.by_name.items()
                  if build.type_of(idx) == "cc.Prefab")


def rig_specs(import_dir, extracted_skeletons):
    """-> NAME or NAME:ARMATURE for each distinct rig no prefab covered."""
    by_name = {}
    for ske, _, _, _ in extract_rigs.scan(import_dir):
        name = ske.get("name")
        if name is None or name in extracted_skeletons:
            continue
        distinct = by_name.setdefault(name, {})
        distinct.setdefault(json.dumps(ske, sort_keys=True), ske)
    specs, skipped = [], []
    for name in sorted(by_name, key=str):
        exports = list(by_name[name].values())
        if len(exports) == 1:
            specs.append(name)
            continue
        # extract_rigs.py keeps the exports holding the hinted armature, so
        # the hint has to be an armature no other export of the name has.
        for ske in exports:
            others = [a for o in exports if o is not ske
                      for a in extract_rigs.armature_names(o)]
            unique = [a for a in extract_rigs.armature_names(ske)
                      if a not in others]
            if unique:
                specs.append("%s:%s" % (name, unique[0]))
            else:
                skipped.append(name)
    return specs, skipped


def tree_size(root):
    total = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        total += sum(os.path.getsize(os.path.join(dirpath, f)) for f in filenames)
    return total


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        print(__doc__)
        return 2
    resources, art = (os.path.abspath(a) for a in args)
    commit = "--commit" in sys.argv or "--push" in sys.argv
    import_dir = os.path.join(resources, "import")
    native_dir = os.path.join(resources, "native")
    config = os.path.join(resources, "config.json")
    for path in (import_dir, native_dir, config):
        if not os.path.exists(path):
            print("missing %s - pass the build's assets/resources directory" % path)
            return 2
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("Pillow is needed to pair atlases with their images: pip install pillow")
        return 2

    if commit:
        git(art, "fetch", "origin", "master")
        git(art, "checkout", "-B", BRANCH, "origin/master")
        git(art, "lfs", "install", "--local")

    build = extract_prefabs.Build(import_dir, config)
    names = prefab_names(build)
    print("== %d prefabs" % len(names))
    run_tool(extract_prefabs, [import_dir, config, art, "--native", native_dir] + names)

    # A non-prefab asset whose name contains a prefab's is matched too, and
    # leaves an index entry with nothing behind it.
    index_path = os.path.join(art, "_index.json")
    index = json.load(open(index_path, encoding="utf-8"))
    index = {k: v for k, v in index.items() if "note" not in v or "skeleton" in v}
    json.dump(index, open(index_path, "w", encoding="utf-8"), indent=1,
              ensure_ascii=False)
    skeletons = {v.get("skeleton") for v in index.values()}

    specs, skipped = rig_specs(import_dir, skeletons)
    print("== %d rigs beyond the prefabs" % len(specs))
    if specs:
        run_tool(extract_rigs, [import_dir, config, art, "--native", native_dir] + specs)
    for name in skipped:
        print("   !! %-30s exports that share every armature name; not extracted" % name)

    index = json.load(open(index_path, encoding="utf-8"))
    pngs = len(os.listdir(os.path.join(art, "_textures")))
    size = tree_size(art)
    print("== %d bundles, %d textures, %.2f GB" % (len(index), pngs, size / 1024 ** 3))
    if not commit:
        return 0
    if size > LIMIT:
        print("over 3 GB - not committing. Check the sizes above first.")
        return 1

    git(art, "add", "-A")
    staged = git(art, "diff", "--cached", "--name-only", capture=True).split()
    lfs = set(git(art, "lfs", "ls-files", "-n", capture=True).split())
    missing = [p for p in staged if p.endswith(".png") and p not in lfs]
    if missing:
        print("these PNGs are not going through LFS: %s" % missing[:10])
        return 1
    if not staged:
        print("nothing new to commit")
        return 0
    git(art, "commit", "-q", "-m",
        "Extract every PVZGE prefab and rig\n\n%d bundles, %d textures."
        % (len(index), pngs))
    print(git(art, "log", "--oneline", "-1", capture=True).strip())
    if "--push" in sys.argv:
        git(art, "push", "-u", "origin", BRANCH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
