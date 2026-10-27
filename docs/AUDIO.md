# Audio

Nothing in the game calls FMOD, or Godot's audio, directly. Game code raises a
named event:

```gdscript
Audio.play(&"plant.place", plant.position)
Audio.play_music(&"music.tutorial")
```

A **backend** decides what that means. Backends are tried in order and the
first available one wins:

| Backend | When it is used |
|---|---|
| `fmod` | an FMOD integration is installed |
| `godot` | otherwise, playing each event's clips from the `Music` submodule through Godot's audio |
| `silent` | last resort, so the game always runs |

The boot log says which one was picked:

```
[boot] audio: backend=godot events=26 playable=0
```

`playable` counts events that actually have an asset for the current backend.
`playable=0` under `godot` means the `Music` submodule is missing or its LFS
files were never pulled:

```sh
git submodule update --init Music
git -C Music lfs pull
```

## The Godot fallback

Without FMOD, the `godot` backend plays each event's clips straight from the
Music submodule (`res://Music/Assets/PVZGE/...`). Which clips is generated
from the Studio project, so the fallback plays exactly what FMOD would:

```sh
python3 tools/fmod_build_content.py Music --streams data/native/audio/streams.json
```

An event with several clips plays a random one, the same as FMOD's shuffled
multi instrument. Music has no phases here - a lawn plays its first wave's
loop - and is only loaded when it is first played. Regenerate the file after
changing events in Studio. A stream written into `events.json` by hand
(`"stream": "res://..."`, or a list) wins over the generated one.

## Installing FMOD

**Versions must match.** FMOD Studio and FMOD Engine ship as a pair, and a
Studio project will not load into a different Engine runtime.

The Studio project in this workspace reports `Studio.02.03.00`, so the pair is:

| | Version |
|---|---|
| FMOD Studio | **2.03.00** (installed) |
| FMOD Engine | **2.03.00** (must match) |

1. Make an account at [fmod.com](https://www.fmod.com/download) and download
   **FMOD Engine 2.03.00** for Linux, matching the installed Studio.
2. Install a Godot integration. The GDExtension at
   [utopia-rise/fmod-gdextension](https://github.com/utopia-rise/fmod-gdextension)
   is the one to prefer: it targets FMOD 2.03 and installs as an addon, so
   Godot itself never has to be recompiled. The module-based integrations
   ([timoschwarzer](https://github.com/timoschwarzer/godot-fmod),
   [jordigulley](https://github.com/jordigulley/fmod_gd4)) require building
   Godot from source.
3. Drop the FMOD Engine libraries where the integration asks, and enable the
   plugin (Project Settings > Plugins). Its `FmodManager` autoload pumps FMOD
   every frame; if the plugin is off, `fmod_backend.gd` pumps it itself.
4. Export your banks from FMOD Studio to `res://audio/banks/`. The master bank
   and its `.strings` bank are both required before any event resolves.
   See "Running Studio under Proton" below if Studio is running through Wine.
   They are normally built and committed for you: see "Automated bank builds" below.
5. Restart. `fmod_backend.gd` looks for the `FmodServer` singleton and takes
   over automatically; the boot log should now read `backend=fmod`.
6. For an exported build, add `*.bank` to the export's non-resource filter, or
   the banks are left out and every event fails to resolve.

The backend is written against utopia-rise's `FmodServer` API:
`play_one_shot` for effects, `create_event_instance` for music (held, so it
can be stopped and steered), `set_global_parameter_by_name`, `get_bus`, and
`load_bank`. The test suite drives it against a stand-in for that API, so the
calls are checked even where FMOD is not installed.

**Compatibility:** the GDExtension declares `compatibility_minimum = 4.5`, and
GDExtensions load on later Godot minor versions, so a current release should
load in 4.7 as is. Only if it refuses to load does it need rebuilding against
4.7's headers - still much cheaper than rebuilding the engine for a module.

FMOD is free below its revenue threshold but the project must be registered.

### Running Studio under Proton

FMOD Studio here runs inside a Proton prefix, so it sees the filesystem through
Wine's drive mappings rather than Linux paths. The prefix maps `Z:` to `/`,
which makes the bank directory reachable from inside Studio as:

```
Z:\var\home\mackery\pvz-2\audio\banks
```

Set that as the build output in Studio so exporting lands banks directly in the
project. Without it they end up inside the prefix, where the game will not find
them - and the failure is silent, because a missing bank just means no event
resolves.

The Studio project itself lives at:

```
~/.local/share/Steam/steamapps/compatdata/4204175343/pfx/drive_c/
  users/steamuser/Documents/Music/PVZGE/PVZGE.fspro
```

That is inside a Proton prefix, which Steam can reset. Worth keeping the
project under version control somewhere outside the prefix.

### Automated bank builds

The banks in `audio/banks/` are built and committed automatically:

1. A push to the Music repo's `master` that touches the Studio project runs
   its **Build FMOD banks** workflow on a self-hosted Windows runner with FMOD
   Studio installed (`fmodstudiocl -build`). The banks go up as the
   `fmod-banks-Desktop` artifact.
2. That workflow then starts this repo's **Update FMOD banks** workflow
   (`.github/workflows/update-banks.yml`), which downloads the artifact,
   points the `Music` submodule at the commit the banks were built from, and
   pushes both straight to `master`. If nothing changed it commits nothing:
   the same project always builds byte-identical banks.

So after changing the Studio project, pull this repo to get its banks. Setup
is in the Music repo's `docs/BUILD_RUNNER.md`.

## Building the Studio project

`tools/fmod_event_list.py` prints the events to create, generated from the
catalog so the two cannot drift:

```sh
python3 tools/fmod_event_list.py          # the base game's 26 events
python3 tools/fmod_event_list.py --mods   # include installed packs
python3 tools/fmod_event_list.py --check  # fails if any event lacks a path
```

The event paths imply the folder structure - `event:/Plants/Place` means a
`Plants` folder containing a `Place` event. Music events want a looping event;
the rest are one-shots.

## Event types, and what the game does not decide

**Sound effects are action sheets; music is a timeline.** An effect has
nothing to lay out in time - it fires, plays and stops - so a timeline it only
ever scrubs from zero is overhead for nothing. Music wants the timeline, for
markers, loop regions and transitions. `tools/fmod_action_sheets.py` rebuilds
generated effects as action sheets and leaves music alone.

**Variations are FMOD's job.** Several clips of one sound go into a single
multi instrument with its playlist set to shuffle, so FMOD picks and the game
never knows a sound has variations. There is no variation handling in the
catalog and there should not be.

**Volume and routing are the mixer's job.** The catalog's `music` flag means
only that a cue is *exclusive* - starting it stops whatever held the same slot
- which is a playback rule, not a level. It does not pick a bus. Buses, VCAs
and snapshots in Studio decide how loud anything is, and they do it better
than a flag here could. `bus` stays in the schema for the one case that needs
it: a settings slider reaching a named bus directly.

## The event catalog

Events live in `audio/events.json` beside a pack's other content:

```json
{"events": [
  {"id": "plant.place", "fmod": "event:/Plants/Place"},
  {"id": "music.tutorial", "fmod": "event:/Music/Tutorial", "music": true}
]}
```

- `fmod` is the FMOD Studio event path.
- `stream` is a Godot resource path, used by the `godot` backend as a stopgap.
  An event can carry both; each backend reads the one it understands.
- `music: true` routes through the music channel rather than a one-shot voice.

Author the events in FMOD Studio with paths matching the `fmod` fields, and the
game needs no changes.

## Adding sounds from a mod

A pack adds `audio/events.json` like any other content. A new id adds a sound;
reusing an existing id replaces that sound everywhere the game raises it:

```json
{"events": [
  {"id": "example.burst", "fmod": "event:/ExamplePack/BurstShot"},
  {"id": "plant.shoot",   "fmod": "event:/ExamplePack/ReplacedShoot"}
]}
```

Raise your own events from a mod component with `Audio.play(&"example.burst")`.

## Events the game raises

Plants: `plant.place` `plant.place.water` `plant.dig` `plant.dig.water`
`plant.eaten` `plant.shoot` `plant.lob` `plant.produce` `plant.explode`
`plant.food`, and one per plant behaviour (`plant.squash`, `plant.chomp`...)

Projectiles: `projectile.hit`

Collectables: `sun.collect` `plantfood.drop` `plantfood.collect` `coin.drop`
`coin.collect` `reward.drop` `reward.land` `reward.collect`. Sun makes no
sound when it lands, as in PVZGE; the plant that made it plays `plant.produce`.

Zombies: `zombie.spawn` `zombie.eat` (every 0.6s while chewing) `zombie.die`
`zombie.armor.break` `zombie.smash` `zombie.imp.throw` `zombie.summon`
`zombie.enrage` `zombie.limb` `zombie.head` `zombie.boss.*`

Board: `mower.trigger` `wave.first` `wave.huge` `wave.final` (other waves
arrive in silence)
`lawn.turret` `lawn.cannon` `lawn.house.hit` `lawn.ability.refuse`

UI and flow: `level.ready` `ui.seed.select` `ui.seed.cancel` `ui.seed.refuse`
`ui.shovel` `ui.fastforward.on` `ui.fastforward.off` `level.win` `level.lose`

Music, per world (`beach`, `cowboy`, `dark`, `dino`, `egypt`, `eighties`,
`future`, `iceage`, `kongfu`, `lostcity`, `modern`, `pirate`, `sky`,
`tutorial`): `music.lawn.<world>` `music.victory.<world>`
`music.lose.<world>` `music.leave.<world>` `music.minigame.<world>`
`music.ultimate.<world>` `music.zomboss.intro.<world>`, where PVZGE has the
cue. Plus `music.zomboss` and `music.zengarden`.

### Variants

PVZGE gives each plant its own shoot, lob, produce and plant food sounds, each
projectile its own hit, each world its own mower and each kind of prize its
own pickup sounds. The game asks for those with `Audio.play_variant(cue,
variant)` (or `Audio.play_for(cue, entity)`, keyed on its definition id),
which plays `<cue>.<variant>` where the catalog has one and `<cue>` otherwise:
`plant.shoot.cactus`, `projectile.hit.cabbage`, `mower.trigger.mower_egypt`,
`reward.land.coinbag`. A plant's own plant food cue plays on top of the
shared `plant.food` sting (`Audio.play_extra`), as PVZGE layers them.

The clips come from PVZGE's prefabs themselves: each plant, projectile,
mower and pickup names its AudioClips, and those were matched to the Music
project's files by content hash. A plant whose sound is the same as the
shared cue's gets no variant.

A test asserts that every id the game raises exists in the catalog, so a
mistyped event fails the suite rather than going quietly silent.

## How PVZGE's music is built

Recovered from the build's own asset paths (`music/inGame/<world>/`), not from
guesswork:

| Cue | Files | Notes |
|---|---|---|
| Lawn phase 1 | `P1_LP_<World>` | **no intro** - starts on the loop |
| Lawn phases 2-4 | `P2_Start_<World>` + `P2_LP_<World>`, ... | intro then loop |
| Choose your seeds | `CYS_Start_<World>` + `CYS_LP_<World>` | |
| One-shots | `VIC_` `LOSE_` `LEAVE_` `UB_` `ZBI_` `MG_<World>` | |

Twelve worlds follow that four-phase shape. The phases are what makes the
music dynamic: it escalates as a level progresses, which is the whole reason
to drive it from FMOD rather than swapping files. The game pushes the phase to
the **`state`** parameter as waves advance, so one event per world covers all
four. `state` is a preset parameter, local to each event, so the backend sets
it on the playing music instance:

| `state` | plays |
|---|---|
| 0 | Choose Your Seeds |
| 1, 2, 3 | phases one to three |
| anything else | the final phase |

The game starts a level on 1. There is no seed chooser yet, so a world whose
timeline opens with a `CYS_` cue plays it once on the way in.

**Front Lawn is the exception.** The `tutorial` world ships a single
`LP_Tutorial` and no phases at all, so its music is a static loop - the `state`
parameter has nothing to switch.

**Eighties is the other one.** PVZGE scores its lawn with the Jam tracks
rather than phases, so its generated event is Choose Your Seeds and then
`Punk_Start` + `Punk_LP`. The per-tile jams are not modelled.

`data/native/audio/music_map.json` holds the full per-world cue map.

### Loop points

Because `LP_Tutorial` is a pure loop file - no intro baked in - its loop region
is the **whole file**, `0` to `186.012`. A region that starts partway in clips
the opening and drops the tail, and the seam is audible on every repeat.

The rule generalises: a `_LP` file loops end to end, and an intro belongs in
the matching `_Start` file rather than in the head of the loop.

## Generating the events

`tools/fmod_build_content.py` builds events straight from the clips already
in the Music project's `Assets/PVZGE/` - nothing is copied, extracted or
probed, so it runs anywhere Python does:

```sh
python3 tools/fmod_build_content.py Music --dry-run
python3 tools/fmod_build_content.py Music
```

- Effects come from `data/native/audio/fmod_content.json` (event path ->
  clips) and become action sheets; several clips make one shuffled multi
  instrument.
- Every world in `music_map.json` gets its lawn timeline, laid out like the
  hand-built Egypt event: each phase's intro, then its `_LP` under an
  unconditional loop region, with a named region around the phase carrying
  its `state` condition. It also gets its victory, lose, leave, Zomboss
  intro, minigame and ultimate battle cues.
- It assigns everything it touches to a bank - effects to Sound, music to
  Music - so a build picks them up without a trip through Studio.
- Existing events are left alone unless the content file says
  `"replace": true`; then the GUID, folder and bank are kept, and an event
  with hand-tuned properties is refused rather than overwritten.

Open the project in Studio once afterwards and audition a generated world
next to Egypt before building.

## Creating empty events

`tools/fmod_create_events.py` writes any missing event into the Studio project,
generated from the catalog:

```sh
python3 tools/fmod_create_events.py "<path to PVZGE.fspro dir>" --dry-run
python3 tools/fmod_create_events.py "<path to PVZGE.fspro dir>"
```

It copies the object graph from an event Studio wrote itself, minus the
content, so what lands on disk is a shape Studio accepts. Existing events are
never touched, so it is safe to re-run as the catalog grows. Events are created
**unassigned to a bank**, matching how the reference event is stored - select
them in Studio and assign them to the Sound bank in one go.

SFX live under `event:/SFX/`, music under `event:/Music/`.

## Source material

PVZGE has no `sound/` asset namespace, so its clips look anonymous - addressed
only by UUID. They are not. Cocos packs store, alongside the member UUID list,
an instance array carrying each asset's original file name and duration,
aligned by position. Reading the two together recovers all of them:

```sh
python3 tools/build_audio_index.py <import dir> <config.json> audio_index.json
# named audio assets: 4187  (2857 distinct names)
```

That is where `plant1`, `shovel0`, `plantFoodCollect`, `hugewave`, `groan0`
and the rest come from - the game's own sounds under their own names, not
lookalikes.

`data/native/audio/pvzge_sources.json` maps each event to its clip, and
`tools/fmod_populate.py` ties catalog, source map and index together to pull
the clips out of the build and attach them:

```sh
python3 tools/fmod_populate.py "<project dir>" audio_index.json --dry-run
python3 tools/fmod_populate.py "<project dir>" audio_index.json
```

It skips events that already have audio, so it is safe to re-run.

### Variants

PVZGE ships numbered variants for most effects - `death0..3`, `groan0..n`,
`chew0..3`, `shovel0..3`. The source map takes the first of each; the rest are
staged under `Assets/SFX/_library/` (625 clips) for building multi-sounds in
Studio, which is what the variants are for. Nothing references that folder, so
it costs nothing in a build.
