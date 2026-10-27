# Modding Guide

Everything in this game is data. Every entity and level is a file, and every
behaviour is a named component you can replace with your own GDScript. A pack
never has to copy content it does not change.

Definitions can be authored two ways, and both load identically:

- **`.tres`** - a typed Godot resource, edited in the inspector with real
  fields, dropdowns and validation.
- **`.json`** - plain text, easy to diff and generate, and what the PVZGE
  importer emits.

Use whichever suits you; a pack can mix them freely.

## Pack layout

A pack is a folder under `mods/`:

```
mods/my_pack/
  mod.json            id, name, version
  zombies/*.json      add a zombie, or replace one by reusing its id
  plants/*.json       .tres works anywhere .json does
  graves/*.json
  objects/*.json
  projectiles/*.json
  armors/*.json
  levels/*.json
  campaigns/*.json    ordered runs of levels
  audio/events.json   add or replace sounds
  components/*.gd     new behaviours, or overrides of built-in ones
  init.gd             optional startup hook
```

## The four entity kinds

Keeping these separate matters, because conflating them is what breaks level
generation:

| Kind | What it is | Notes |
|---|---|---|
| **plant** | what the player grows | the only kind that belongs in a normal seed bank |
| **zombie** | the opposition | can be charmed to fight for the player |
| **grave** | destroyable board object | plants can break it; may fire grid-item events such as summoning |
| **object** | everything else on the grid | slider and trap tiles, liquids, mold, and the zombie-side potions |

PVZGE files evil potions (`zombiepotion_*`) under plants. They are objects
here, so they can never leak into a seed bank or a plant roll.

Only `mod.json` is required, and every folder is optional. Drop the folder into
`mods/` and it loads on the next run.

## Load order

Order is declared in `mods/load_order.json`, **highest priority first**, with
the base game implicitly at the bottom:

```json
{ "order": ["my_overrides", "some_content_pack"],
  "disabled": ["pack_i_am_not_using"] }
```

A pack higher in the list wins over everything below it. Packs you do not list
are appended underneath the listed ones, alphabetically. Packaged `.pck` files
in `mods/` are mounted before folders and load the same way.

### Turning a pack off

A pack named in `disabled`, or whose own `mod.json` says `"enabled": false`,
stays installed and listed but contributes no data and no scripts. This
matters for packs that override built-in behaviour: such a pack changes the
base game for everything using that component, so it should usually ship
disabled and be opted into. `mods/example_override/` is exactly that case.

## Adding a zombie

```json
{
 "id": "sprinter",
 "extends": "normal",
 "stats": { "toughness": 120, "speed": 0.55, "eat_dps": 80, "wave_cost": 150 },
 "tags": { "add": ["fast"], "remove": ["swallowable", "grabbable"] }
}
```

`extends` names an archetype (`normal`, `gargantuar`, `zomboss`) or another
zombie, and you inherit its stats, tags and components. `tags.add` and
`tags.remove` are applied on top, so you only write the differences.

### What an archetype carries

An archetype is not just a tag bundle - it holds the stats and whole
components its members agree on. Every world's gargantuar is the same
3600-health smasher that throws an imp at half health, so that lives in
`data/native/archetypes/gargantuar.json` and each world's entry says only
which imp:

```json
{
 "id": "beach_gargantuar",
 "extends": "gargantuar",
 "components": [{ "type": "imp_thrower", "imp": "beach_imp", "throw_at": [0.5] }]
}
```

Naming a component type the archetype already has **replaces** it, which is
how that entry keeps the shared smasher and swaps only the imp. Naming the
same type twice in one list means **another** of it - a poncho zombie wears a
plate over a poncho and both have to be chewed through.

To drop something the archetype gave you, use the delta form, which mirrors
how tags work. Kung-Fu's bronze statue is a gargantuar that does not smash:

```json
{
 "id": "bronze_statue",
 "extends": "gargantuar",
 "stats": { "toughness": 9000, "speed": 0 },
 "components": {
  "remove": ["smasher"],
  "add": [{ "type": "summoner", "zombies": ["bronze_hook"], "once": true, "each": true },
          { "type": "lifespan", "duration": 25, "duration_max": 35 }]
 }
}
```

### What a zombie does

Behaviour comes from components, the same as for plants. Built-in zombie
behaviours:

| Component | What it does |
| --- | --- |
| `smasher` | Flattens what blocks it in one blow instead of biting, then rests |
| `imp_thrower` | Throws a rider past the defences as it is worn down |
| `spawn_inside` | Lets out whatever was riding inside when it dies |
| `escort` | Brings a column of identical zombies along from one spawn |
| `summoner` | Calls more zombies onto the lane, once or on a timer |
| `enrage` | Gets faster and hits harder once its armor is gone |
| `lifespan` | Dies of its own accord after a while |
| `armor` | A pool destroyed before the body takes a hit |
| `zomboss` | A staged boss fight: per-stage health and weighted actions |

A component returning `true` from `claims_movement()` moves the zombie itself,
so a boss holds its own column instead of walking in a lane at a time. One
returning `true` from `prevent_death()` can refuse a death outright, which is
how a boss advances a stage instead of dying - useful for a plant with a second
wind too.

A component returning `true` from `claims_attack()` takes the zombie's attack
over: the zombie still stops at whatever blocks it, but deals no bite damage
and the component does the damage on its own schedule. That is the whole of
what makes a gargantuar not a biter, and `Zombie` never mentions gargantuars.

Anything that brings more zombies marks what it spawns **before** the new
zombie initializes, so the spawned one's own components see it during setup -
`escorting` for an escort's members, `summoned` for a summoner's. That is what
stops an abbot, whose summon list contains abbots, from turning one wave into
every wave.

### Bosses

Zomboss is the one zombie whose entire fight is written down rather than coded,
and the `zomboss` component reads it as-is. A boss is a list of **stages**, each
with its own health pool and a weighted list of actions:

```json
{ "type": "zomboss", "missile": "my_missile", "idle_column": 6,
  "stages": [
   { "health": 4000, "idle": 0.5, "idle_max": 1.0,
     "stun_time": 4, "stun_damage_scale": 1.5,
     "stagger": 1, "stagger_time": 0.4, "chill_from_freeze": 10,
     "actions": [
      { "action": "summon", "weight": 12, "repeat": 2,
        "zombies": ["mummy", "tomb_raiser"], "points": 300, "points_max": 1600 },
      { "action": "shoot", "weight": 9, "repeat": 1, "repeat_max": 2 },
      { "action": "rush",  "weight": 3, "repeat": 1 }
     ],
     "tuning": { "RushDPS": 400, "RoarStunDuration": 7.5 } } ] }
```

Exhausting a stage's health **does not kill the boss** - it advances to the
next stage, through `prevent_death()`, so nothing outside the component knows
a boss has stages. The last stage kills it.

The eight action names are `summon`, `shoot`, `rush`, `rush2`, `walk`, `jump`,
`imps` and `roar`. A `weight` of 0 retires an action in a later stage. A
`summon` spends its point budget on its `zombies` list priced by `wave_cost`,
so a bigger budget buys either more zombies or tougher ones. An action name
the component does not know idles instead of erroring, so a world whose
special move is not implemented yet still fights with the rest of its list.

`tuning` is whatever the world's own actions need (`RushDPS`,
`RoarStunDuration`, `ThunderCount`, `TurnsIntoShipInThisStage`) passed through
untouched. Inventing a schema for twenty one-off fields would only hide them.

**A boss cannot be stunned by a plant** - every one in the source data says so.
What its stage describes instead is a **stagger**, earned by hurting it hard
and fast: burst past 8% of the stage's pool in one window and it reels for
`stun_time`, shoved back `stagger` lanes and taking `stun_damage_scale` extra
damage the whole time. That is what makes burst damage the counter to a boss
rather than steady chip.

### Resistance

Two stats on a zombie change how plants land on it:

- `stun_scale` - how long a stun lasts here. `0` is immunity, which is what
  every zombie in PopCap's data that carries the field actually says; a
  fraction gives partial resistance. An immune zombie gets a `stun_immune` tag
  so the reason is visible.
- `water_speed_scale` - speed multiplier while standing on water. A ducky-tube
  zombie swims at twice its walking pace.

The `chill_only` tag makes ice slow a zombie without ever holding it: a
troglobite is cooled, not set in a block.

A `.tres` works the same way, except that it is already complete when it
loads - its parent only fills in what the resource left unset, rather than
overwriting what you authored. `mods/example_pack/zombies/brute.tres` is a
working example.

### Charmed zombies

A zombie's `allegiance` decides which way it walks and what it attacks.
Hypnotised (zomboid) zombies walk away from the house, attack hostile zombies,
are ignored by plant weapons, and do not count toward the level's remaining
zombies. Call `zombie.charm()` to switch sides at runtime - no respawn needed.

### Tags, and why they matter

A zombie declares **what it is**. A plant declares **what it does**. Tags are
the contract between them.

The original game stored interactions the other way round, as plant-named
booleans on every zombie (`CannotBeSwallowedByChomper`,
`CannotBeGrabbedByPtero`, and 23 more). Adding one plant meant editing hundreds
of zombie entries. Here, Chomper asks for the `swallowable` tag, and any zombie
that has it can be swallowed. **Your new plant needs zero edits to zombie
files** - ask for a tag that already exists, or invent your own and tag the
zombies you ship.

Capability tags currently in use include `swallowable`, `grabbable`, `tossable`,
`draggable`, `hypnotizable`, `knockbackable`, `shrinkable`, `transformable`,
`pushable`, `carriable`, `gummable`, `chompable`, `divertable`, `attractable`,
`sporeable`, `flickable`, `lane_movable`, and `plantfood_carrier`. Descriptive
tags such as `metal` and `deep_water` sit alongside them.

## Adding a plant

What a plant **does** comes from the fields it carries, not its `family`.
PopCap's Family is a damage type - Shadow and Poison each contain both
shooters and lobbers, Sharp contains shooters and melee - so matching on it
mislabels plants. The importer reads the data instead, and `family` stays on
as a tag you can query.

Built-in behaviours: `shooter`, `lobber`, `sun_producer`, `timed_shooter`,
`area_attacker`, `melee`, `instant_damage`, `explosive`, `freeze_burst`,
`stunner`, `wind_burst`, `blocker`, `tile_placer`, `mint_buff`, `armor`.

A plant can carry more than one - a Mint both attacks and buffs its family.

### Buffs and status

`Character.apply_buff(rate, resistance, seconds)` speeds an entity up and
toughens it. Components time themselves through `cfg_jittered()` / `scaled()`,
so a buff applies to anything without the component knowing a buff exists -
which is how Mints boost a whole family.

Zombies take `apply_stun(seconds)`, `apply_slow(factor, seconds)` and
`apply_freeze(seconds)`. Re-applying keeps the stronger effect and the longer
duration rather than compounding, so two slows do not stop a zombie dead.

A plant has no movement to stop, so `Plant.apply_stun(seconds)` suppresses
instead: `Character.apply_suppression(factor, seconds)` is the inverse of a
buff, and `scaled()` divides by it as well as by `attack_rate`. A stunned plant
therefore crawls through every one of its behaviours without a single component
knowing it can be stunned - which is how Zomboss's roar reaches all fifteen at
once.

## Adding a plant (schema)

```json
{
 "id": "splitpea_mk2",
 "family": "Peashooter",
 "world": "egypt",
 "stats": { "sun_cost": 175, "toughness": 300, "cooldown": 7 },
 "components": [
  { "type": "burst_shooter", "projectile": "pea", "interval": 2.0, "burst": 3 }
 ]
}
```

`stats` drive the seed packet as well as the plant: `sun_cost` is the price,
`cooldown` is the recharge in seconds, and `cooldown_from` is the share of
that recharge the packet starts with (1 is ready immediately, 0 means waiting
a full cycle before first use). A level listing the
`SeedPacketHalfTimeModule` feature halves every recharge.

`world` picks the packet's backing, as PVZGE's `OBTAINWORLD` does: a world's
name (`frontyard`, `egypt`, `pirate`, `cowboy`, `future`, `dark`, `beach`,
`ice`, `lostcity`, `eighties`, `dino`, `modern`, `kongfu`, `sky`), `water` for
the beach backing, or `market`, `mint`, `epic` and `lod` for the gold-tabbed
premium ones. Leaving it out gives the plain backing. `packet_portrait` names
the picture on the packet when it is not the plant's id, and `family` adds the
family badge in the corner.

`components` is the interesting part: each entry names a behaviour and
configures it. Built-in types are `shooter`, `lobber`, `sun_producer`, `melee`,
`explosive`, `blocker`, `armor`, `hit_rect` and `attack_rect`.

### Zombie seed packets

A seed bank is not plant-only. Setting `"kind": "zombie"` on a level's seedbank
hands the player zombies instead, which is how an I-Zombie style level works;
individual entries can override the kind too. Placement cost comes from the
entity's own `sun_cost`.

```json
"seedbank": { "mode": "chooser", "kind": "zombie",
			  "preset": ["tutorial", "tutorial_armor1"] }
```

Zombies placed this way drop into the lane and walk from there, so unlike a
plant they do not occupy their cell.

One thing is deliberately not configurable: **every sun is worth
`SunToken.VALUE` (50)**. `sun_producer` controls only the timing. The original
game's per-plant `SunValue` is kept in each plant's `extra` block for
reference, but nothing reads it - to change the amount, change the constant.
Sun is collected by hovering the cursor over it, not by clicking.

## Changing existing content

Reuse the id. A file at `mods/my_pack/zombies/tutorial.json` replaces the base
`tutorial` zombie outright, as long as your pack sits above the base game in
the load order (it always does).

## Adding a behaviour

Drop a `.gd` file in `components/`. **The filename is the component type**, so
`components/burst_shooter.gd` registers the type `burst_shooter`.

```gdscript
extends EntityComponent

var _cooldown: float = 0.0

func setup() -> void:
	_cooldown = float(cfg(&"interval", 2.0))

func _process(delta: float) -> void:
	if host.is_dead:
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		host.board.spawn_projectile(&"pea", host.row, host.position, host)
		_cooldown = float(cfg(&"interval", 2.0))
```

`host` is the plant or zombie, `cfg()` reads from the component's JSON entry,
and `host.board` is the lawn.

## Completely rewriting what a plant does

Name your file after an existing component type. A pack shipping
`components/sun_producer.gd` replaces the built-in one, and **every plant using
that component now runs your code** - no plant JSON and no core file changes.

To rewrite a single plant instead of all of them, give it a component type only
it uses, and point its JSON at that:

```json
{ "id": "meteorflower",
  "components": [{ "type": "my_meteor_behaviour", "damage": 900 }] }
```

The override is announced at startup so you can confirm it took effect:

```
[mod] 'example_override' overrides component 'sun_producer' (was from 'base')
```

Because this replaces the behaviour for *every* plant using that component,
`example_override` ships disabled. Remove it from `disabled` in
`load_order.json` to see it take over.

## Art

Entity art is a DragonBones armature, extracted with
`tools/extract_prefabs.py` and mapped to entities by a JSON file in
`data/native/art/`:

```json
{
 "plant:peashooter": {
  "bundle": "plants_PeashooterPLANT", "armature": "Peashooter",
  "fit_height": 92, "foot_y": 26,
  "animations": {"idle": "Idle", "attack": "Shoot", "die": "Death"}
 }
}
```

`bundle` is a directory under `art/`, `armature` one of the rigs inside it,
and `animations` maps a game state to whatever that rig happens to call it -
so `Zombie` asks for `attack` and never has to know the rig says `Eat`. A mod
reskins an entity by shipping a file of the same shape and calling
`Art.load_mappings(<its art dir>)`; its entries win.

Size and position come from the rig's own bounding box, not from hand-tuned
numbers: `fit_height` is how tall the art should end up in pixels, `foot_y`
where its feet sit relative to the entity. Every rig puts its origin at the
feet and almost none is centred on it - the peashooter's box runs from -50 to
+85 in X - so centring has to be computed per rig. `scale`, `offset_x` and
`offset_y` still override if you want to place something by hand.

**Art is optional.** Where a mapping or a bundle is missing, `Character.art`
stays null and the entity keeps its placeholder drawing, so the game runs the
same with or without any of it.

**The animations are Godot's.** A rig is converted once, by `ArmatureBaker`,
into `Animation` resources driven by an `AnimationPlayer` - so easing,
blending, interpolation and timing are engine code, not ours. Nothing samples
a timeline at runtime.

Conversion is where DragonBones and Godot are reconciled, because three
things do not map onto a Node2D bone tree:

- A transform is built from **two** skew angles. Equal angles are a rotation;
  unequal ones are a mirror or a shear, which Godot expresses as `skew`.
- A bone can **refuse its parent's rotation or scale**, and several do - the
  basic zombie's head refuses both. Godot's nodes have no equivalent, so the
  chain is resolved at bake time and the sprites come out flat.
- Frames carry their **own easing**, as a cubic bezier or an easing factor.
  Sampling at the source frame rate bakes that in, so Godot's linear
  interpolation between samples reproduces it.

Everything heavy is shared. One `ArmatureSet` per bundle holds the parsed
skeleton, the texture, one `AtlasTexture` per region and one baked
`AnimationLibrary` per rig; a lane of zombies is many nodes over one copy of
all of it. The basic zombie and both its armors read the same bundle, which is
the point of PopCap's shared rigs.

A component says what it **did** - `host.play_art_once(&"attack")` - and the
entity decides how that looks. No component learns whether its host has art or
what a rig calls anything, which is what lets a mod reskin a plant without
touching behaviour.

`sockets` maps a name to a bone - `{"muzzle": "mouthhole"}` - and each becomes
a marker animated with everything else, so the game can ask where a rig's
mouth is this instant. A peashooter's pea leaves from its muzzle rather than
from the middle of the plant.

**A rig says when it acts.** The peashooter's Shoot animation carries a
`Shoot` event fifteen frames in, which is the frame the pea leaves its mouth.
Those are baked as method tracks, so `Armature.event` fires them and the
shooter spawns the pea then - not on the frame the animation started, which is
what made the shot look detached from the plant. A rig with no such event
fires immediately, so nothing waits forever.

`limbs` is what comes off, and when:

```json
"limbs": [
  {"name": "arm", "at_health": 0.5,
   "detach": ["arm_here_HAND", "hand_here_HAND"], "show": ["arm_here_ARM"]},
  {"name": "head", "on_death": true, "detach": ["head_HEAD", "jaw_HEAD"]}
]
```

PopCap draws the stump as its own slot sitting hidden under the whole limb, so
losing one is: stop drawing the whole, start drawing the stump, and hand what
came off to the board to fall. **When** it happens is the game's call, which is
why the thresholds are here and not in the rig.

`hide_slots` names slots the rig draws but the game should not. PvZ rigs carry
a detached-limb variant in its own slot - the basic zombie's `arm_here_ARM` is
the broken stump, sitting on top of the intact arm - because the game decides
when a limb comes off, not the rig.

Zombie art is drawn facing the house, which is where a hostile zombie is
already walking, so only a charmed one is mirrored. `Armature.set_facing`
owns that, because mirroring flips the fitted offset too.

`tools/preview_armature.py` renders a rig to a PNG without launching the game,
and `--anim NAME --frames N` samples an animation rather than the setup pose.
Use the animated form: a setup pose can look perfect while every animated
frame is wrong, which is exactly how three rendering bugs got past review.

### Lawns, mowers and the HUD

The rest of what is drawn uses the same mapping files, under other kinds -
see `data/native/art/scenery.json`:

```json
{
 "lawn:TutorialStage": {
  "bundle": "lawns_TutorialLAWN", "back": ["Lawn"], "there": ["UpperThere"], "front": ["Upper"],
  "open_rows": {"1": "row1", "3": "row3", "5": "row5"}, "mower": "mower_modern"
 },
 "mower:mower_modern": {
  "bundle": "projectiles_ModernMowerPRJ", "armature": "Mower", "scale": 0.512,
  "animations": {"idle": "Idle", "trigger": "Trans", "attack": "Attack"}
 },
 "collectable:sun": { "bundle": "rigs_SunAnimate", "armature": "Sun", "scale": 0.512,
  "animations": {"idle": "Normal"} }
}
```

A `lawn:<stage>` entry is keyed by the level's `stage`. Its `back` rigs draw
under everything, its `there` rigs (the far fence, mailbox and street) over
the ground but under the characters, and its `front` rigs over the
characters, all placed where
PVZGE placed its lawn relative to the first cell, so the art's lanes line up
with the board's. `open_rows` picks the sod animation by how many lanes are
open, for the tutorial lawn's dirt rows. `mower:<id>` plays `trigger` in place
until the rig says `switchingFalse`, then `attack` while it drives.
`collectable:sun` and `collectable:plantfood` dress the pickups,
`effect:plant_dirt` is the puff when a plant goes in or comes out, and the
`hud:` entries are the sun counter, shovel, plant food slots and seed packet.
`font:ui` names the font every label and price is drawn in, a path under
`art/`; a mod ships its own entry to change it.
`hud:` states can chain with `"after": {"collecting": "filled"}`, the way a
DragonBones frame action does.

These rigs are placed by hand - `scale` and `offset_x`/`offset_y` rather than
`fit_height` - because their size comes from the original's own layout.

Rigs that are not a named prefab (the sun, the HUD pieces, particles) come
out by their DragonBones name with `tools/extract_rigs.py`; see
`docs/ART.md`.

## Adding a level

```json
{
 "id": "example_showdown",
 "name": "Sprinter Showdown",
 "stage": "TutorialStage",
 "seedbank": { "mode": "chooser", "selection": "preset",
			   "preset": ["peashooter", "sunflower"] },
 "waves": [
  { "kind": "spawn", "zombies": [ { "type": "tutorial", "row": 3 } ] },
  { "kind": "spawn", "zombies": [ { "type": "sprinter", "row": 2 } ] }
 ],
 "wave_settings": { "count": 2, "flag_interval": 2 }
}
```

Rows are 1-based; omit `row` to spawn in a random lane. `plantable_rows`
restricts where the player may plant - Tutorial 1 uses `[3]` to confine the
player to the middle lane, and locked lanes are dimmed on the board. Use
`"mode": "conveyor"` with a `plants` list for a conveyor level. A wave that
needs several things at once uses `{"kind": "multi", "actions": [...]}`.

### What is on the lawn at the start

A level can set the lawn up before the first wave. Cells here are 0-based
(`row` 0 is the top lane, `col` 0 the house column), matching PopCap's
GridX/GridY, unlike wave rows.

```json
"initial": {
 "grid_items": [ { "type": "slider_up", "row": 4, "col": 2 } ],
 "plants": [ { "type": "wallnut", "row": 1, "col": 3 },
			 { "type": "peashooter", "row": 0, "col": 0, "condition": "icecubed" } ],
 "zombies": [ { "type": "iceage_imp", "row": 3, "col": 6, "condition": "icecubed" } ]
},
"gravestones": { "count": 3, "col_start": 4, "col_end": 7,
				 "types": ["gravestone_dark"], "forced": [ { "row": 0, "col": 8 } ] }
```

A grid item is any grave or board object id; a plant id there is planted
instead, which is how PVZGE lays lily pads. `"condition": "icecubed"` freezes
a plant or zombie inside an ice block (`zombietarget_iceblock` /
`planttarget_iceblock`); it does nothing until the block breaks. Plants named
by a `protect_plants` objective are planted for it. Gravestones without a
type use the world's own (`gravestones` in the lawn data).

A wave can raise more mid-level:

```json
{ "kind": "gravestones", "pool": [ { "type": "gravestone_dark", "count": 2 } ],
  "positions": [ { "row": 1, "col": 3 }, { "row": 4, "col": 8 } ] }
```

Plants standing where a stone rises are knocked out unless the action sets
`"displace_plants": false`. Gravestones block planting, plants' shots break
them, and `SunValue` / `plantfood_count` on a grave pay out when it breaks.

### World mechanics

These level fields set up a world's own mechanics. Cells are 0-based.

```json
"tide": { "water_from": 6 },
"railcarts": { "rails": [ { "col": 4, "row_start": 0, "row_end": 4 } ],
               "carts": [ { "col": 4, "row": 1 } ], "type": "railcart_cowboy" },
"power_tiles": [ { "group": "beta", "row": 1, "col": 1, "delay": 0.25 } ],
"potions": { "initial": 4, "max": 30, "interval": { "min": 12, "max": 16 },
             "types": [ "zombiepotion_speed", "zombiepotion_toughness" ] }
```

- **Tide**: columns from `water_from` rightward are water. A tide wave moves
  the shoreline; plants the water reaches drown unless they can stand in it.
- **Rail carts**: plants only go on carts, and a cart is clicked to pick it up
  and clicked again on its rail to roll it there, carrying its plant. Carts
  cannot pass each other. Without a `type`, the world's `railcart` is used.
- **Power tiles**: plant food given to a plant on one tile reaches the plants on
  every other tile of its group after that tile's `delay`.
- **Potions**: set out at the start and topped up to `max`. The first zombie to
  walk into one drinks it (faster, tougher or invisible, up to three of a kind).

Puddles act on the zombies standing in them through the `tile_liquid`
component: `goopuddle` hits for 10 every half second, `butter` stops the first
zombie for 8 seconds and is used up, `goo` poisons, sap slows, lava burns.

These wave actions start world events:

| Kind | Fields | What happens |
|---|---|---|
| `storm` | `zombies`, `style`, `col_start`/`col_end`, `row_start`/`row_end`, `group_size`, `group_interval` | sand- or snowstorm drops zombies partway up the quietest lanes |
| `raiding_party` | `type`, `count`, `group_size`, `group_interval` | swashbucklers swing in from the edge in groups |
| `low_tide` | `type`, `count`, `col_start`/`col_end`, `delay`, `group_size`, `group_interval` | zombies rise from the sand the tide left |
| `tide` | `water_from` | moves the shoreline |
| `frost_wind` | `winds: [{row, direction}]`, `blasts` | chills every plant in the lane; a second chill freezes it in ice |
| `portal` | `row`, `col`, `portal`, `limit` | opens a rift that lets its zombies through one at a time |
| `dino` | `dino`, `row`, `delay` | calls a dinosaur into the lane |

A `portal` names a shared portal from `data/native/portals` or gives its own
`{zombies: [{type, weight}], first, interval}` inline. Dinosaurs live in
`data/native/dinos`; each picks one of five behaviours (`kick`, `carry`,
`toss`, `fling`, `roar`), so a pack can add one with data alone.

## Campaigns

A campaign is an ordered list of levels, and each campaign is one world on
the world map. Levels open one at a time as the one before is cleared; winning
returns to the map, failing repeats the level.

```json
{
 "id": "tutorial",
 "name": "Player's House",
 "completion_message": "Front Lawn complete!",
 "levels": ["tutorial_1", "tutorial_2", "tutorial_3", "tutorial_4"]
}
```

Because a campaign is just data, a pack can ship its own, or replace an
existing one by reusing its id to splice levels in:

```json
{
 "id": "tutorial",
 "name": "Player's House",
 "levels": ["tutorial_1", "my_pack_interlude", "tutorial_2",
			"tutorial_3", "tutorial_4"]
}
```

These optional fields place the world on the map:

| field | meaning |
|---|---|
| `order` | position among worlds, lowest first (default 0) |
| `unlock_after` | campaign id that must be finished first; empty means open from the start. Naming a campaign whose mod is off leaves the world open |
| `description` | line shown under the world's name |
| `map_color` | page tint, as `"#rrggbb"`, until the map has art |
| `hidden` | keep it off the map (reachable only by id) |

```json
{
 "id": "neon",
 "name": "Neon District",
 "order": 10,
 "unlock_after": "tutorial",
 "map_color": "#6a3a8c",
 "levels": ["neon_1", "airspace_1"]
}
```

A level does not have to belong to a campaign. Opening `game/main.tscn` on its
own (F6) and setting `start_level` jumps straight to one, which is useful while
building it; run that way, clearing a level plays straight on to the next
instead of going back to the map.

## Plant food

Zombies whose data allows it (`plantfood_carrier`) can be marked as carriers by
a wave's `plantfood` count. Killing one drops a pickup, collected by hovering
like sun. Feeding a plant calls `on_plantfood()` on each of its components, and
the food is only spent if something responded - so feeding a plant with no
boosted behaviour costs nothing.

Give a component a boosted behaviour by overriding the hook:

```gdscript
func on_plantfood() -> bool:
	for z in host.board.hostile_zombies_in_row(host.row):
		z.take_damage(500.0, host)
	return true
```

Built-in boosts: `shooter` unloads a burst, `lobber` rains a volley,
`sun_producer` drops a handful of sun, `melee` lands a flurry, `explosive`
detonates immediately, and `blocker` repairs to full.

## Lawn mowers

A level whose `features` list ends in `Mowers` - `TutorialMowers`,
`FrontLawnMowers`, `ModernMowers` - parks one mower per lane. A zombie reaching
the house sets it off, clearing that lane. Each lane gets exactly one, so the
next zombie through a spent lane ends the level. Levels without a mower feature
lose on the first zombie through.

## Controls

Seed slots, plant food, the shovel and fast forward all come from the project's
InputMap, so they can be rebound - including to a controller - without code
changes. Conveyor levels have more slots and use the `Slot N (Convayor)`
actions from slot 5 upward. `Previous Slot` and `Next Slot` cycle the
selection, skipping packets that have not recharged.

## Level options

PopCap ships level options as a bag of module-name strings
(`FastSunDropper`, `TutorialMowers`, `ZombiesDeadWinCon`). Matching on those at
runtime is how a schema ends up a copy of someone else's, so the importer
translates them into explicit fields:

| Field | Was |
|---|---|
| `"mowers": true` | any `*Mowers` feature |
| `"sun": {"interval": 5.0}` | `FastSunDropper` / `DefaultSunDropper` |
| `"seed_recharge": 0.5` | `SeedPacketHalfTimeModule` |
| `"objectives": [...]` | `ZombiesDeadWinCon`, star challenges |
| `"scripts": [...]` | narrative and tutorial hooks, kept as-is |
| `"wave_pacing"` | `wave_settings`, minus the count that duplicated `waves` |

A level has one `name` rather than a comment, a name and a description.

## Worlds

A world is a lawn file. It names its music track, its mower, its zombie
roster - and its own mechanics:

```json
{
 "id": "AerialStage",
 "display_name": "Assault Airspace",
 "music": "Sky",
 "components": [
  {"type": "auto_turret", "interval": 2.0, "damage": 8},
  {"type": "cannon_ability", "damage": 900, "cooldown": 25},
  {"type": "house_health", "max_health": 500, "use_zombie_weight": true},
  {"type": "terrain_layout", "columns": [{"terrain": "sky_gap", "from": 7, "to": 8}]}
 ]
}
```

`display_name` renames a world without touching the levels that reference its
stage id - which is how Aerial Fortress becomes Assault Airspace.

### Lawn components

Behaviour that belongs to the board rather than to any plant or zombie lives
here, shipped as `lawn_components/<type>.gd`. Built-ins:

| Type | What it does |
|---|---|
| `auto_turret` | the base fires on its own, no input needed |
| `cannon_ability` | a player-triggered world ability with a cooldown |
| `house_health` | the house has hit points **instead of** lawn mowers |
| `terrain_layout` | paints the world's terrain onto the grid |

A component with `is_ability` set is triggered by the player (bound to
`Lawn Ability`) and shows its charge in the HUD.

`house_health` is worth calling out: a lawn component can intercept a zombie
reaching the house via `handle_zombie_at_house()`, consuming it before mowers
or a loss are considered. That is how Sky replaces the lose condition rather
than decorating it - the world owns the rule, not the board.

## Drawing order

The lawn reads front to back. A plant in row 4 covers a zombie in row 0, and
within one row the zombie covers the plant it is eating - so the row picks the
band and the kind picks the place in it:

```gdscript
z_index = row * Board.ROW_BAND + Board.LAYER_ZOMBIE
```

Layers are `LAYER_PLANT`, `LAYER_OBJECT`, `LAYER_MOWER`, `LAYER_ZOMBIE` and
`LAYER_PROJECTILE`. Collectables sit on `LAYER_COLLECTABLE`, above the lot,
because a sun behind a gargantuar is a sun nobody clicks. A zombie that
changes lane changes band with it, which a boss does every time it walks.

Zombies also spawn a little off their lane's centre line, so a wave is a crowd
rather than a line of identical figures standing on one rail.

## Terrain

Cells can demand something before a plant goes in them. Big Wave Beach water
and Sky's open air are the same rule with different tags, so there is one
mechanism rather than two systems:

| Field on an object | Meaning |
|---|---|
| `blocks_planting` | nothing can be planted here (lava, deep water, craters) |
| `requires_tag` | a plant must carry this tag (`aquatic`, `airborne`) |
| `provides_tag` | placing this satisfies a cell's requirement (lily pad) |

A lily pad is `aquatic` and `provides:aquatic`, so it can go in water and makes
the cell viable for a land plant afterwards. Losing it takes the provision with
it. Pool tiles, lava and the endangered tile all carry these rules.

Slide tiles are not terrain - they are plantable, they just carry the plant
away - so they use a `slide_tile` component instead.

## Dialogue

Who speaks is data. A level names a speaker; the speaker supplies the name,
portrait and which box to use:

```json
"dialogue": {"speaker": "airspace_commander", "lines": ["..."]}
```

```json
{"id": "airspace_commander", "name": "Commander Vex",
 "portrait": "commander_vex", "dialogue_box": "boss"}
```

Nothing is tied to Zomboss, so a world can have its own character while reusing
the boss dialogue box.

## Objectives

A level's win and lose rules are objectives - named, configured from data, and
replaceable like components. A level listing none gets `survive_waves`, so
existing levels keep working.

```json
"objectives": [
 {"type": "survive_waves"},
 {"type": "no_plant_loss", "allowed": 2},
 {"type": "kill_count", "count": 20, "tags": ["metal"]}
]
```

Built-ins: `survive_waves`, `protect_plants`, `no_plant_loss`, `sun_produced`,
`kill_count`, and the star challenges:

| Type | Config | Rule |
|---|---|---|
| `zombie_distance` | `distance` | a zombie past this many columns from the house loses |
| `sun_used` | `max` | spending more sun than this loses |
| `simultaneous_plants` | `max` | no more plants than this at once (the extra one is refused) |
| `kill_in_time` | `count`, `seconds` | destroy this many within the window, at least once |
| `sun_holdout` | `seconds` | go this long without spending sun, at least once |
| `save_mowers` | | losing a lawn mower loses |
| `no_plant_zone` | `cells` | a mold colony: those cells cannot be planted |

`no_plant_loss` with `allowed` covers "lose no more than N plants". A goal
that has to be achieved during the level fails once the last wave is cleared
without it. An objective can also refuse a placement by adding a callable to
`board.placement_checks`.

A pack adds its own as `objectives/<type>.gd`, overriding `is_met()`,
`is_failed()` and whichever hooks it needs (`on_zombie_died`,
`on_plant_died`, `on_sun_collected`, `on_zombie_reached_house`,
`on_wave_started`, `on_all_waves_spawned`). An objective can key off a tag the
pack itself invented - core never needs to know about it.

## Conveyor levels

A level whose seedbank is `"mode": "conveyor"` hands out free packets on a
belt instead of fixed slots. Nothing costs sun and nothing recharges - a packet
is either on the belt or it is not, and placing one takes it off.

```json
"seedbank": {
 "mode": "conveyor",
 "plants": [{"type": "peashooter", "weight": 100, "max": 4}],
 "drop_delay": [{"delay": 3, "max_packets": 0},
				{"delay": 9, "max_packets": 4}],
 "speed": [{"speed": 100, "max_packets": 0}]
}
```

`weight` is the pick chance and `max` caps how many of that plant sit on the
belt at once (`null` for unlimited). `drop_delay` is keyed by how full the belt
is, so it refills quickly when empty and slows as it fills. A wave action of
kind `conveyor` with `add`/`remove` changes the pool mid-level.

## Audio

Sounds are named events, not file paths, so they survive a change of audio
backend. See `docs/AUDIO.md`.

## Save state

Every level keeps its own slot, so several can be part-played at once - which
the original game does and PVZGE does not. Autosave runs while a level is
going; clearing or failing a level retires its slot.

Each object describes itself rather than a saver reaching into it:
`Board.snapshot()`, `LevelRunner.snapshot()`, `SeedBank.snapshot()`, and a
`save_state()` / `load_state()` pair on every objective and lawn component.
So anything new that needs remembering gets a `save_state`, and the save
system needs no edit:

```gdscript
func save_state() -> Dictionary:
    return {"charge": _charge}

func load_state(state: Dictionary) -> void:
    _charge = float(state.get("charge", cooldown))
```

Projectiles and uncollected sun are deliberately not saved - they are in
flight, and restoring them mid-arc would be stranger than not.

## Rewards and unlocks

Winning a level drops a prize where its last zombie fell. The first win drops
the level's own `reward`; every later win, and any level without one, drops
a coin bag of five silver coins (50 coins). The prize is granted the moment
it drops, so leaving before picking it up loses nothing; the level ends once
the player sweeps over it.

```json
"reward": {"type": "unlock_plant", "param": "cabbagepult"},
"replay_reward": {"type": "collectable", "param": "endlevelreward"},
"unlocks_features": ["almanac"]
```

| `type` | `param` / `amount` | Effect |
|---|---|---|
| `unlock_plant` | plant id | the plant becomes choosable, marked NEW in the chooser |
| `upgrade` | upgrade id | kept in the `upgrades` collection |
| `worldtrophy` | trophy id | kept in `trophies`; `worldkey` adds a world key instead |
| `note` | note id | kept in `notes` |
| `coins` | `amount` | a coin bag worth that much |
| `gems` | `amount` | gems, straight into the wallet |

Anything else (PVZGE's `pinata`, `giftbox`, `collectable`) drops a coin bag,
as PVZGE does. `replay_reward` is imported and kept but not used yet: PVZGE
itself always drops coins on a replay. `unlocks_features` is recorded on the
first win (`Saves.has_feature`) for the screens that will need it.

The seed chooser only offers plants the player owns: the `base_unlocked`
list in `seed_chooser.json` (PVZGE's starting four), plants won from levels,
and any plant a pack adds. A level's include list still shows unowned plants,
refused, unless its seed bank sets `unlock_all`. The **Unlock every plant**
setting opens everything for testing.

Progress lives in `Saves`: `unlock_plant`, `is_plant_unlocked`,
`add_currency` / `currency` (`coins`, `gems`, `worldkeys`, or a pack's own),
and `grant_item` / `has_item` for named collections.

## I-Zombie costs

A zombie's `sun_cost` is what it costs to place from a seed packet. PopCap's
data has none - those costs are a PvZ1 mechanic - so it is derived from
`wave_cost`, the only strength signal present, and snapped to 25s:

```
basic 50 · conehead 75 · buckethead 100 · gargantuar 225
```

State `sun_cost` in a zombie file to override it. A mod zombie that says
nothing is still priced, because the derivation also runs at load.

## The init hook

For setup data cannot express, add `init.gd`:

```gdscript
extends RefCounted

func initialize(ctx: Dictionary) -> void:
	var data = ctx["data"]
	print("zombies tagged fast: %d" % data.query(&"zombie", [&"fast"]).size())
```

It runs after every pack's data has loaded, lowest priority first. `ctx` carries
`mod`, `data` and `components`.

## Checking your work

Startup prints what loaded and what got overridden. Errors are collected rather
than fatal, so a broken file degrades instead of crashing the game:

```
[boot] zombies=474 plants=218 levels=5 mods=[base, example_pack] errors=0
[boot] components: 10 types { base: 8, example_pack: 2 }
```

`mods/example_pack/` is a working reference covering every case above.
