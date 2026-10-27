# PVZ2 (Godot)

A moddable reimplementation of PVZGE in Godot 4.7, built around data-driven
content and composable behaviour rather than a 1:1 port of the original code.

> **Unofficial fan work.** Not developed, authorised or endorsed by PopCap
> Games or Electronic Arts. *Plants vs. Zombies* and all game assets belong to
> Electronic Arts / PopCap Games; see `Music/COPYRIGHT.md` and `art/COPYRIGHT.md`. PVZGE's own web
> build is GPL-3.0, and its User Agreement prohibits separately distributing
> game assets. Please support the official release.

## Why not a straight port

PVZGE is a Cocos Creator build whose `Zombie.ts` is a 92KB god-class with 331
methods, inherited by 173 zombie subclasses. Plant-specific logic is hardcoded
into the zombie base (`dealButter`, `dealHurrikale`, `CanBeChompedByTyranno`),
and the data mirrors it: 25 plant-named booleans on every zombie entry
(`CannotBeSwallowedByChomper` and friends). Adding one plant meant touching
hundreds of files.

This project inverts that. Zombies declare **what they are** as tags; plants
declare **what they do** as components that ask for tags. A new plant touches
zero zombie files.

## Layout

```
core/
  audio/        Audio - named events over a swappable backend (FMOD/Godot/silent)
  save/         Saves - per-level save slots, campaign progress, unlocks, coins
  rewards/      LevelReward - what winning a level hands out
  settings/     Settings - volumes, display and gameplay options
  lawn/         LawnComponent - world-level mechanics and abilities
  objectives/   Objective - a level's win and lose rules, as data
  data/         DataRegistry - loads entities, resolves inheritance, layers mods
  entity/       Character -> Plant / Zombie  (the inheritance spine)
  components/   EntityComponent + ComponentRegistry  (the composition half)
    builtin/    shooter, lobber, sun_producer, melee, explosive, blocker, armor
  mod/          ModLoader - discovery, load order, script registration
game/
  app.tscn      entry point: title -> world map -> level
  menu/         main menu, world map, pause and settings screens
  board/        Board (grid, input), Projectile, SunToken
  level/        LevelRunner - plays a level definition
  main.tscn     the level screen (runs on its own too, for testing)
data/
  pvzge/        raw prop sheets extracted from the PVZGE build
  native/       clean per-entity content the game actually loads
tools/          extraction and conversion scripts (Python)
tests/          headless test suite
docs/           MODDING.md
mods/           packs, plus example_pack as a working reference
```

## Content

Extracted from the PVZGE build and converted to the native schema: 473
zombies, 214 plants, 350 projectiles, 65 armors, 32 graves, 60 objects, and
1258 levels. The four Front Lawn tutorial levels are wired up in
`data/native/levels/`; the rest are converted and ready to add.

Entities come in four kinds - plants, zombies, graves and objects - because
conflating them breaks level generation. PVZGE files evil potions as plants;
they are objects here so they cannot reach a seed bank.

Definitions load from `.tres` (typed, inspector-editable) or `.json`
(text-friendly). Both produce the same typed resources.

## Running

```sh
godot --headless --import           # first time
godot                               # play
godot --headless tests/gameplay_test.tscn   # test suite
```

## Tools

Re-run these against the PVZGE Docker image to refresh content:

```sh
python3 tools/extract_desktop.py pvzge.exe <dir>  # or unpack a newer desktop build
python3 tools/extract_pvzge.py data/pvzge        # prop sheets out of the image
python3 tools/extract_levels.py <dir>            # all 1258 levels, raw
python3 tools/import_levels.py <raw> <native>    # PopCap format -> native
python3 tools/import_entities.py data/pvzge data/native
python3 tools/select_levels.py <native> data/native/levels TutorialStage Tutorial
python3 tools/extract_dragonbones.py <dir>        # skeletons (art pipeline)
godot --headless -s tools/bake_rigs.gd           # rigs -> Godot scenes in art/
```

`tools/import_levels.py` flattens PopCap's `objclass`/`objdata`/`RTID`
indirection into the native schema and keeps anything it does not model yet
under `extra`, so no import loses data. Coverage is currently ~89%.

## Status

Working: main menu with continue, world map (one page per campaign, levels
opening in order, gated worlds), pause menu (restart, leave and resume later),
settings (volumes, fullscreen, vsync, fast forward speed), data pipeline, mod system (data + script overrides), typed resource
definitions, data-driven objectives, world-level mechanics (passive and
player-triggered abilities, house health in place of mowers), shared terrain
rules covering Beach water and Sky air, campaign progression (clear a level to
advance, fail to retry),
per-level save slots with autosave and resume, I-Zombie placement costs,
15 plant behaviours covering 157 of 214 plants, 8 zombie behaviours
(smashing, imp throwing, riders, escorts, summoning, enrage, lifespan and
staged Zomboss fights read straight from the data) covering 249 of 473
zombies, archetypes that carry shared stats and whole components so a world's
gargantuar is a four-line delta, zombie status effects
(stun/slow/freeze), stun immunity and chill resistance, plant stun by
suppression, bidirectional projectiles, buffs,
grid and planting with per-lane restrictions,
seed packet costs and recharge,
lawn mowers, plant food (carriers, pickups, per-component boosts), conveyor
seed belts, shovel, fast forward, rebindable input actions, a named-event audio
layer ready for FMOD, sun economy with
hover collection, seed hotkeys, wave spawning with lane spacing, zombie
allegiance (charmed/hypnotised), zombie seed packets for I-Zombie style
levels, graves with summon events, peashooter/sunflower/wallnut/potato mine,
basic and armored zombies, armor absorption.

Mods can be enabled or disabled without uninstalling them; a pack that
overrides built-in behaviour ships disabled so it cannot silently change base
balance.

Placeholder art throughout - see `addons/dragonbones_import/` for the art
pipeline plan. Skeleton extraction works (43 armatures, 577 animations);
atlas pairing and the Godot conversion are still to do.

Audio is wired but silent: the game raises named events and a backend decides
what they mean, so installing FMOD is a one-file switch. See `docs/AUDIO.md`
for versions and setup.

See `docs/MODDING.md` for the mod format, `docs/AUDIO.md` for audio and
`docs/ART.md` for the art submodule.
