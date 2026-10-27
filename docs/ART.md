# Art

The extracted PVZGE art lives in its own repository,
[MacksPVZ2-Again.Art](https://github.com/Mackery6969/MacksPVZ2-Again.Art),
mounted here as the `art` submodule (`res://art`) - the same shape the audio
takes with `Music`. It is PopCap's and EA's, not this repository's, so it is
kept apart and **private**; see `art/COPYRIGHT.md`. The images go through Git
LFS.

## Getting it

```sh
git submodule update --init art
git -C art lfs pull
```

The repository is private, so this needs an account with access to it.
Without the art the game still runs on placeholders, and the boot log names
every mapped bundle it could not find - all of them when the submodule is not
checked out, or just the ones nobody has extracted yet:

```
[boot] art: 0 bundles, 82 mappings  missing (see docs/ART.md): ...
```

A clone that had the old gitignored `art/` folder has to move it aside first,
because `git submodule update` will not check out over a non-empty directory.

## Updating it

Regenerate with `tools/extract_prefabs.py` and `tools/extract_rigs.py` from
this repository's root, writing into `art/` - `art/README.md` has the full
commands. To take everything in the build at once - every prefab, then every
rig no prefab covers - use `tools/extract_all_art.py`:

```sh
python3 tools/extract_all_art.py <build>/assets/resources art --commit
```

`--commit` starts an `extract-art` branch from the art repository's `master`
and commits there; `--push` also pushes it. Open the project in Godot once so new images get their `.import`
files, then commit inside `art/`, push to a branch of the art repository and
merge it there.

Then point the submodule at the art repository's `master`:

```sh
git -C art fetch origin master
git -C art checkout origin/master
git add art
```

Only ever commit the submodule at a commit on the art repository's `master`,
never at an unmerged branch - a squash merge throws that commit away.
