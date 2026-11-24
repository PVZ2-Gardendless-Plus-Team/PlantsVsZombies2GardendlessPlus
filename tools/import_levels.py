#!/usr/bin/env python3
"""Convert PopCap-format PVZGE levels into the clean native level schema.

The PopCap format expresses a level as a flat pool of objects tagged with
`objclass`, wired together by `RTID(alias@scope)` strings. Reading one wave
means walking LevelDefinition -> Modules -> WaveManagerModuleProperties ->
WaveManagerProperties -> Waves[[RTID]] -> SpawnZombiesJitteredWaveActionProps.

The native format drops that indirection: a level is an object, waves are a
list, and a wave's zombies are a list. PopCap's GridX/GridY become col/row.
Anything not modelled yet is kept verbatim under "extra" so an import never
silently loses data - `coverage.py` reports how much that still is.
"""
import json, os, re, sys, glob, collections

RTID_RE = re.compile(r'^RTID\(([^@]+)@([^)]+)\)$')
LOCAL_SCOPES = (".", "CurrentLevel")


def parse_rtid(value):
    if not isinstance(value, str):
        return None
    m = RTID_RE.match(value.strip())
    return (m.group(1), m.group(2)) if m else None


def strip_rtid(value):
    """Reduce an RTID to its bare alias; pass other values through."""
    ref = parse_rtid(value)
    return ref[0] if ref else value


def num(value, fallback=None):
    """PopCap writes numbers as strings often enough ("GroupSize": "2") that
    every numeric field is read through this."""
    try:
        f = float(value)
    except (TypeError, ValueError):
        return fallback
    return int(f) if f == int(f) else f


def span(value):
    """A {Min, Max} range -> {min, max}; a bare number is both ends."""
    if isinstance(value, dict):
        return {"min": num(value.get("Min"), 0), "max": num(value.get("Max"), 0)}
    n = num(value)
    return None if n is None else {"min": n, "max": n}


def placement(p, extra_keys=()):
    """PopCap GridX/GridY placement -> {col,row,...}."""
    out = {}
    if p.get("GridX") is not None:
        out["col"] = p["GridX"]
    if p.get("GridY") is not None:
        out["row"] = p["GridY"]
    for k in extra_keys:
        if p.get(k) is not None:
            out[k.lower()] = strip_rtid(p[k])
    return out


## Every spelling PopCap uses for "what goes in this cell".
TYPE_KEYS = ("TypeName", "PlantType", "Type")


def cell_entry(p):
    """A pre-placed thing -> {type,row,col,...}, 0-based like GridX/GridY.

    Unlike `placement`, the type always lands under `type` whichever key the
    source used, and the optional flags keep their meaning."""
    out = placement(p)
    for k in TYPE_KEYS:
        if p.get(k):
            out["type"] = strip_rtid(p[k])
            break
    if p.get("Condition"):
        out["condition"] = p["Condition"]
    if p.get("Plantfood"):
        out["plantfood"] = True
    if p.get("Level") is not None and p["Level"] != -1:
        out["level"] = p["Level"]
    return out


def matrix_cells(matrices):
    """InitialGridItemMatrixes -> cell entries. Each matrix is one row string
    per lane, with a non-zero character marking a cell that gets the item."""
    out = []
    for m in matrices or []:
        kind = strip_rtid(m.get("TypeName") or m.get("Type") or "")
        for row, line in enumerate(m.get("GridMatrix") or []):
            for col, ch in enumerate(str(line)):
                if ch not in "0 ":
                    out.append({"type": kind, "row": row, "col": col})
    return out


class Level:
    """Index of one PopCap level file, with RTID resolution over its aliases."""

    def __init__(self, payload, source):
        self.source = source
        self.comment = payload.get("#comment", "")
        self.objects = payload.get("objects", [])
        self.by_alias = {}
        for o in self.objects:
            for alias in (o.get("aliases") or []):
                self.by_alias[alias] = o
        self.definition = next(
            (o for o in self.objects if o.get("objclass") == "LevelDefinition"), None
        )
        self.consumed = set()

    def resolve(self, value):
        """Follow an RTID into this level's own objects; None if external."""
        ref = parse_rtid(value)
        if not ref:
            return None
        alias, scope = ref
        if scope in LOCAL_SCOPES:
            return self.take(alias)
        return None

    def take(self, alias):
        """Fetch a local object by alias and mark it folded in."""
        obj = self.by_alias.get(alias)
        if obj is not None:
            self.consumed.add(id(obj))
        return obj

    def external(self, value):
        """-> 'alias@scope' for references pointing outside this file."""
        ref = parse_rtid(value)
        if not ref:
            return None
        alias, scope = ref
        return None if scope in LOCAL_SCOPES else f"{alias}@{scope}"


# --------------------------------------------------------------------------
# wave actions
# --------------------------------------------------------------------------

def conv_zombie_entry(z):
    out = {"type": strip_rtid(z.get("Type"))}
    row = z.get("Row")
    if row not in (None, ""):
        try:
            out["row"] = int(row)
        except (TypeError, ValueError):
            out["row"] = row
    if z.get("Column") not in (None, ""):
        out["col"] = z["Column"]
    return out


def conv_wave_action(lvl, obj):
    cls = obj.get("objclass", "")
    d = obj.get("objdata") or {}

    if cls == "SpawnZombiesJitteredWaveActionProps":
        act = {"kind": "spawn", "zombies": [conv_zombie_entry(z) for z in d.get("Zombies", [])]}
        if d.get("AdditionalPlantfood"):
            act["plantfood"] = d["AdditionalPlantfood"]
        if d.get("DynamicPlantfood"):
            act["dynamic_plantfood"] = d["DynamicPlantfood"]
        if d.get("NotificationEvents"):
            act["notify"] = d["NotificationEvents"]
        if d.get("MustKillAllToNextWave"):
            act["must_clear"] = True
        if d.get("ZombieSpawnPattern"):
            act["pattern"] = d["ZombieSpawnPattern"]
        return act

    if cls == "ModifyConveyorWaveActionProps":
        act = {"kind": "conveyor"}
        if d.get("Add"):
            act["add"] = [{"type": a.get("PlantType"), "weight": a.get("Weight"),
                           "max": a.get("MaxCount")} for a in d["Add"]]
        if d.get("Remove"):
            act["remove"] = [a.get("PlantType") for a in d["Remove"]]
        return act

    if cls == "SpawnGravestonesWaveActionProps":
        # A pool of {type,count} filled into shuffled candidate cells. A pool
        # entry with no type takes one of the world's own gravestones.
        act = {"kind": "gravestones"}
        act["pool"] = [{"type": strip_rtid(g.get("Type")) if g.get("Type") else None,
                        "count": g.get("Count", 1)}
                       for g in (d.get("GravestonePool") or []) if g]
        act["positions"] = [{"col": p.get("mX"), "row": p.get("mY")}
                            for p in (d.get("SpawnPositionsPool") or []) if p]
        if d.get("DisplacePlants") is False:
            act["displace_plants"] = False
        return act

    if cls == "StormZombieSpawnerProps":
        # Zombies arrive inside a sand- or snowstorm, already on the lawn,
        # rather than walking on from the right.
        act = {"kind": "storm", "style": d.get("Type") or "sandstorm",
               "zombies": [strip_rtid(z.get("Type")) for z in (d.get("Zombies") or [])
                           if z and z.get("Type")]}
        for src, dst, default in [("ColumnStart", "col_start", 4), ("ColumnEnd", "col_end", 8),
                                  ("RowStart", "row_start", 0), ("RowEnd", "row_end", 4),
                                  ("GroupSize", "group_size", 2),
                                  ("TimeBetweenGroups", "group_interval", 2)]:
            act[dst] = num(d.get(src), default)
        return act

    if cls == "RaidingPartyZombieSpawnerProps":
        act = {"kind": "raiding_party",
               "type": strip_rtid(d.get("ZombieType")) or "swashbuckler",
               "count": num(d.get("SwashbucklerCount"), 1),
               "group_size": num(d.get("GroupSize"), 5),
               "group_interval": num(d.get("TimeBetweenGroups"), 1)}
        return act

    if cls == "BeachStageEventZombieSpawnerProps":
        # Big Wave Beach's low tide: zombies rise out of the receding water.
        act = {"kind": "low_tide", "type": strip_rtid(d.get("ZombieName")),
               "count": num(d.get("ZombieCount"), 0),
               "group_size": num(d.get("GroupSize"), 1),
               "group_interval": num(d.get("TimeBetweenGroups"), 0.25),
               "delay": num(d.get("TimeBeforeFullSpawn"), 0.1),
               "col_start": num(d.get("ColumnStart"), 0),
               "col_end": min(num(d.get("ColumnEnd"), 8), 8)}
        return act

    if cls == "TidalChangeWaveActionProps":
        # ChangeAmount counts water columns from the right edge, so the
        # shoreline - the first wet column - is 9 minus it.
        change = d.get("TidalChange") or {}
        amount = num(change.get("ChangeAmount"))
        if amount is None:
            return {"kind": "tide"}
        return {"kind": "tide", "water_from": max(0, min(9, 9 - amount))}

    if cls == "FrostWindWaveActionProps":
        return {"kind": "frost_wind",
                "blasts": num(d.get("BlastCount"), 1),
                "winds": [{"row": num(w.get("Row")),
                           "direction": w.get("Direction") or "right"}
                          for w in (d.get("Winds") or [])
                          if w and num(w.get("Row")) is not None]}

    if cls == "SpawnModernPortalsWaveActionProps":
        act = {"kind": "portal", "row": num(d.get("PortalRow")),
               "col": num(d.get("PortalColumn"))}
        act["portal"] = conv_portal(lvl, d.get("PortalType") or "modern")
        if num(d.get("ZombiesToSpawn")) is not None:
            act["limit"] = num(d.get("ZombiesToSpawn"))
        return act

    if cls == "DinoWaveActionProps":
        return {"kind": "dino", "dino": strip_rtid(d.get("DinoType")) or "raptor",
                "row": num(d.get("DinoRow"), 0),
                "delay": num(d.get("DinoWaveDuration"), 0)}

    if cls == "WaveSchedulerProps":
        act = {"kind": "schedule"}
        for src, dst in [("TimeBeforeFirst", "delay"), ("TimeBetween", "interval"),
                         ("Repeat", "repeat"), ("EndingWave", "ending_wave")]:
            if d.get(src) is not None:
                v = d[src]
                act[dst] = ({"min": v.get("Min"), "max": v.get("Max")}
                            if isinstance(v, dict) else v)
        if d.get("Events"):
            act["events"] = [conv_wave_action(lvl, lvl.resolve(e)) if lvl.resolve(e)
                             else {"kind": "ref", "ref": lvl.external(e) or e}
                             for e in d["Events"]]
        return act

    return {"kind": cls, "data": d}


def conv_portal(lvl, ref):
    """A portal type -> the name of a shared one, or its spec inlined when the
    level defines its own (PortalType -> PortalProps, both local)."""
    ptype = lvl.resolve(ref)
    if ptype is None:
        return strip_rtid(ref)
    props = lvl.resolve((ptype.get("objdata") or {}).get("Properties"))
    if props is None:
        return strip_rtid((ptype.get("objdata") or {}).get("Properties")) or "modern"
    return portal_spec(props.get("objdata") or {})


def portal_spec(d):
    """PortalProps -> {world, first, interval, zombies:[{type, weight}]}."""
    out = {"world": d.get("World", "modern")}
    if d.get("TimeBeforeFirst") is not None:
        out["first"] = span(d["TimeBeforeFirst"])
    if d.get("TimeBetween") is not None:
        out["interval"] = span(d["TimeBetween"])
    out["zombies"] = [{"type": z.get("ZombieTypeName"), "weight": num(z.get("Weight"), 1)}
                      for z in (d.get("ZombieTypesToSpawn") or []) if z]
    return out


# BoardGridMaps is a shared sheet, not part of any level. The few maps the
# star challenges point at are copied here, so a mold colony lands on the same
# cells without the importer needing the sheet. "ColumnA_To_ColumnB" maps are
# generated from their name.
BOARD_GRID_MAPS = {
    "Nothing": [],
    "Future34": ["101010111", "110101111", "101010111", "110101111", "101010111"],
    "Pirate27": ["011110000", "101110000", "011010000", "101110000", "011110000"],
    "Dino38": ["000000000", "011111000", "000000000", "011111000", "000000000"],
    "Cowboy31": ["010000110", "010000110", "010000110", "010000110", "010000110"],
}


def grid_map_cells(lvl, ref):
    """A BoardGridMap reference -> [{row, col}] of its set cells."""
    local = lvl.resolve(ref)
    if local is not None:
        rows = [[int(bool(v)) for v in r] for r in ((local.get("objdata") or {}).get("Values") or [])]
    else:
        name = strip_rtid(ref) or ""
        m = re.match(r"^Column(\d+)(?:_To_Column(\d+))?$", name)
        if m:
            lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
            rows = [[int(lo <= c <= hi) for c in range(9)] for _ in range(5)]
        elif name in BOARD_GRID_MAPS:
            rows = [[int(ch) for ch in line] for line in BOARD_GRID_MAPS[name]]
        else:
            return None
    return [{"row": r, "col": c} for r, line in enumerate(rows)
            for c, v in enumerate(line) if v]


def conv_waves(lvl, wave_mgr_props):
    d = wave_mgr_props.get("objdata") or {}
    waves = []
    for entry in d.get("Waves", []):
        actions = []
        for ref in (entry if isinstance(entry, list) else [entry]):
            obj = lvl.resolve(ref)
            if obj is None:
                actions.append({"kind": "ref", "ref": lvl.external(ref) or ref})
            else:
                actions.append(conv_wave_action(lvl, obj))
        if len(actions) == 1 and actions[0].get("kind") == "spawn":
            waves.append(actions[0])
        else:
            waves.append({"kind": "multi", "actions": actions})

    settings = {}
    for src, dst in [("FlagWaveInterval", "flag_interval"),
                     ("WaveSpendingPoints", "points"),
                     ("WaveSpendingPointIncrement", "point_increment"),
                     ("SuppressFlagZombie", "suppress_flag"),
                     ("MinNextWaveHealthPercentage", "next_wave_health_min"),
                     ("MaxNextWaveHealthPercentage", "next_wave_health_max"),
                     ("SpawnColStart", "spawn_col_start"), ("SpawnColEnd", "spawn_col_end")]:
        if src in d:
            settings[dst] = d[src]
    return waves, settings


def attach_waves(lvl, out, d):
    """Wire up waves from a module that owns a WaveManagerProps reference.

    The reference is often omitted, in which case it defaults by convention to
    the local alias `WaveManagerProps`.
    """
    wm = lvl.resolve(d.get("WaveManagerProps", "")) or lvl.take("WaveManagerProps")
    if not wm:
        return
    waves, settings = conv_waves(lvl, wm)
    out["waves"] = waves
    if settings:
        out.setdefault("wave_pacing", {}).update(settings)


def conv_seedbank(obj):
    d = obj.get("objdata") or {}
    if obj.get("objclass") == "ConveyorSeedBankProperties":
        sb = {"mode": "conveyor"}
        if d.get("InitialPlantList"):
            sb["plants"] = [{"type": p.get("PlantType"), "weight": p.get("Weight"),
                             "max": p.get("MaxCount")} for p in d["InitialPlantList"]]
        if d.get("DropDelayConditions"):
            sb["drop_delay"] = [{"delay": c.get("Delay"), "max_packets": c.get("MaxPackets")}
                                for c in d["DropDelayConditions"]]
        if d.get("SpeedConditions"):
            sb["speed"] = [{"speed": c.get("Speed"), "max_packets": c.get("MaxPackets")}
                           for c in d["SpeedConditions"]]
        return sb

    sb = {"mode": "chooser"}
    if d.get("SelectionMethod"):
        sb["selection"] = d["SelectionMethod"]
    if d.get("PresetPlantList"):
        sb["preset"] = [conv_preset_plant(p) for p in d["PresetPlantList"]]
    for src, dst in [("PlantBlackList", "blacklist"), ("PlantExcludeList", "exclude"),
                     ("PlantIncludeList", "include"), ("SuggestPlantList", "suggest"),
                     ("OverrideSeedSlotsCount", "slots"), ("UnlockAll", "unlock_all"),
                     ("AlwaysUseChooser", "always_chooser"),
                     ("ExcludeListSunProducers", "exclude_sun_producers")]:
        if d.get(src) is not None:
            sb[dst] = [strip_rtid(x) for x in d[src]] if isinstance(d[src], list) else d[src]
    if d.get("CardDecks"):
        sb["decks"] = conv_card_decks(d["CardDecks"])
    return sb


def conv_card_decks(decks):
    """CardDecks -> ready-made loadouts the seed chooser can offer.

    Recommended decks are suggestions; challenging ones are harder picks that
    PVZGE rewards with gems. `ChallengingLocked` hides the recommended ones and
    stops the player straying from a challenging deck."""
    out = {}
    for src, dst in [("Recommended", "recommended"), ("Challenging", "challenging")]:
        kept = []
        for deck in decks.get(src) or []:
            plants = [strip_rtid(p) for p in (deck.get("Plants") or [])]
            if not plants:
                continue
            name = deck.get("Name")
            if isinstance(name, dict):
                name = name.get("en") or next(iter(name.values()), "")
            kept.append({"name": name or "", "plants": plants})
        if kept:
            out[dst] = kept
    if decks.get("ChallengingLocked"):
        out["challenging_locked"] = True
    return out


## Star challenge class -> (objective type, {source field: config key}).
## A star challenge IS an objective, so each becomes one directly.
CHALLENGE_OBJECTIVES = {
    "StarChallengeBeatTheLevelProps": ("survive_waves", {}),
    "StarChallengeZombieDistanceProps": ("zombie_distance", {"TargetDistance": "distance"}),
    "StarChallengeSunProducedProps": ("sun_produced", {"TargetSun": "amount"}),
    "StarChallengeSunUsedProps": ("sun_used", {"MaximumSun": "max"}),
    "StarChallengePlantsLostProps": ("no_plant_loss", {"MaximumPlantsLost": "allowed"}),
    "StarChallengeSimultaneousPlantsProps": ("simultaneous_plants", {"MaximumPlants": "max"}),
    "StarChallengeKillZombiesInTimeProps": ("kill_in_time", {"ZombiesToKill": "count",
                                                             "Time": "seconds"}),
    "StarChallengeSpendSunHoldoutProps": ("sun_holdout", {"HoldoutSeconds": "seconds"}),
}
## Challenges that live in a shared module sheet rather than the level.
EXTERNAL_CHALLENGES = {
    "SaveMowers": {"type": "save_mowers"},
    # Often named without being defined; it means the default goal anyway.
    "BeatTheLevel": {"type": "survive_waves"},
}


def conv_preset_plant(p):
    """A preset seed entry -> plant id, or {type, level} when a level is set."""
    if isinstance(p, dict):
        pid = strip_rtid(p.get("PlantType") or p.get("Type"))
        lvl_ = p.get("Level")
        return pid if lvl_ in (None, -1) else {"type": pid, "level": lvl_}
    return strip_rtid(p)


def conv_challenge(lvl, out, ref):
    """A star-challenge RTID -> an objective entry, or None when it is not
    one we model. Unmodelled ones are kept under `unmodelled_challenges`."""
    obj = lvl.resolve(ref)
    if obj is None:
        alias = strip_rtid(ref) if isinstance(ref, str) else None
        if alias in EXTERNAL_CHALLENGES:
            return dict(EXTERNAL_CHALLENGES[alias])
        out.setdefault("unmodelled_challenges", []).append(ref)
        return None
    cls = obj.get("objclass", "")
    d = obj.get("objdata") or {}
    if cls in CHALLENGE_OBJECTIVES:
        kind, fields = CHALLENGE_OBJECTIVES[cls]
        result = {"type": kind}
        for src, dst in fields.items():
            if num(d.get(src)) is not None:
                result[dst] = num(d[src])
        if d.get("Description"):
            result["description"] = d["Description"]
        return result
    if cls == "MoldColonyChallengeProps":
        # Mold makes cells unplantable for the whole level.
        cells = []
        if d.get("Locations"):
            cells += grid_map_cells(lvl, d["Locations"]) or []
        cells += [{"row": num(c.get("GridY")), "col": num(c.get("GridX"))}
                  for c in (d.get("MoldedSquares") or []) if c]
        for row, line in enumerate((d.get("MoldMatrix") or [])[:5]):
            cells += [{"row": row, "col": col} for col, ch in enumerate(str(line)[:9])
                      if ch not in "0 "]
        return {"type": "no_plant_zone", "cells": cells}
    # A module that is also listed as a challenge, such as protect-the-plant,
    # is folded in by its own handler.
    if handle_module(lvl, out, obj):
        return None
    out.setdefault("unmodelled_challenges", []).append({"objclass": cls, "objdata": d})
    return None


def challenge_refs(value):
    """Challenges come as a list of lists (one per difficulty); flatten."""
    if isinstance(value, list):
        for v in value:
            yield from challenge_refs(v)
    elif isinstance(value, str):
        yield value


# --------------------------------------------------------------------------
# module dispatch
# --------------------------------------------------------------------------

# Minigame modules: the level is played by different rules - nuts are bowled,
# vases are broken, plants are matched. Each becomes one entry in the level's
# `minigames` list, named by the mode that runs it (core/minigames/builtin/).
# The module's own settings are kept, in snake_case, because each mode reads
# its own; several modules that make up one mode (Beghouled's preset, seed
# bank and spawner) fold into a single entry.
MINIGAME_MODULES = {
    "BowlingMinigameProperties": "bowling",
    "LastStandMinigameProperties": "last_stand",
    "VaseBreakerPresetProperties": "vasebreaker",
    "BeghouledPresetProperties": "beghouled",
    "BeghouledSeedBankProperties": "beghouled",
    "BeghouledZombieSpawnerProperties": "beghouled",
    "DangerRoomModuleProperties": "endless",
    "DangerRoomMiniGameModuleProperties": "endless",
    "CannonMinigameProperties": "cannon",
    "CamelMinigameProperties": "camel",
    "CowboyMinigameProperties": "cowboy",
    "FutureMinigameProperties": "fight_alone",
    "SkyMiniGameProperties": "sky",
    "SunBombChallengeProperties": "sun_bomb",
    "RhythmGameProperties": "rhythm",
}


def snake(name):
    """PopCap's CamelCase key -> snake_case ("BowlingFoulLine" -> "bowling_foul_line")."""
    name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "_", name)
    return name.lower()


def snake_data(value):
    """A module's objdata with every key in snake_case and RTIDs reduced to
    their alias. Comment keys ("#comment", "//") are dropped."""
    if isinstance(value, dict):
        return {snake(k): snake_data(v) for k, v in value.items()
                if not k.startswith(("#", "//"))}
    if isinstance(value, list):
        return [snake_data(v) for v in value]
    return strip_rtid(value)


def minigame_entry(out, mode):
    """The level's entry for `mode`, created on first use."""
    games = out.setdefault("minigames", [])
    for g in games:
        if g.get("type") == mode:
            return g
    g = {"type": mode}
    games.append(g)
    return g


def handle_minigame(lvl, out, obj):
    cls = obj.get("objclass", "")
    mode = MINIGAME_MODULES[cls]
    entry = minigame_entry(out, mode)
    data = snake_data(obj.get("objdata") or {})
    if mode == "endless":
        # The level's designers - wave generators, tide changers, conveyor
        # designers - are local objects the module points at. Pull them in
        # so the mode reads one entry; shared ones from LevelModules stay as
        # their names.
        designers = []
        for ref in (obj.get("objdata") or {}).get("LevelDesigners") or []:
            local = lvl.resolve(ref)
            if local is not None:
                lvl.consumed.add(id(local))
                d = snake_data(local.get("objdata") or {})
                d["type"] = snake(local.get("objclass", "").removeprefix("DangerRoom"))
                designers.append(d)
            else:
                designers.append({"type": "shared", "name": strip_rtid(ref)})
        data["level_designers"] = designers
        data["minigame"] = cls == "DangerRoomMiniGameModuleProperties"
    entry.update(data)


def handle_module(lvl, out, obj):
    """Fold one resolved module into the native level. -> True if handled."""
    cls = obj.get("objclass", "")
    d = obj.get("objdata") or {}

    if cls in MINIGAME_MODULES:
        handle_minigame(lvl, out, obj)
        return True

    if cls in ("SeedBankProperties", "ConveyorSeedBankProperties"):
        out["seedbank"] = conv_seedbank(obj)

    elif cls == "WaveManagerModuleProperties":
        attach_waves(lvl, out, d)
        dyn = [x for x in (d.get("DynamicZombies") or []) if x]
        if dyn:
            out["dynamic_zombies"] = [
                {"start_wave": x.get("StartingWave"), "points": x.get("StartingPoints"),
                 "increment": x.get("PointIncrementPerWave"),
                 "pool": [strip_rtid(z) for z in x.get("ZombiePool", [])]} for x in dyn]

    elif cls == "LevelOfTheDayModuleProperties":
        attach_waves(lvl, out, d)
        lod = {}
        for src, dst in [("FlagCount", "flags"), ("WavesPerFlag", "waves_per_flag"),
                         ("StartingPoints", "points"),
                         ("PointIncrementPerWave", "point_increment"),
                         ("PlantfoodToSpawnCount", "plantfood")]:
            if d.get(src) is not None:
                lod[dst] = d[src]
        if d.get("ZombiePool"):
            lod["pool"] = [strip_rtid(z) for z in d["ZombiePool"]]
        if lod:
            out["level_of_the_day_config"] = lod

    elif cls == "StarChallengeModuleProperties":
        refs = list(challenge_refs(d.get("Challenges")))
        # ChallengesAlwaysAvailable is a flag; its misspelt twin sometimes
        # carries a list of extra challenges instead.
        refs += list(challenge_refs(d.get("ChallengeAlwaysAvailable")))
        seen = set()
        for ref in refs:
            if ref in seen:
                continue
            seen.add(ref)
            objective = conv_challenge(lvl, out, ref)
            if objective is not None:
                out.setdefault("objectives", []).append(objective)
        if d.get("Difficulties"):
            out["difficulties"] = d["Difficulties"]

    elif cls == "GravestoneProperties":
        # PopCap's columns here are 1-based and inclusive; rows are already
        # 0-based. Both come out 0-based to match every other cell.
        g = {}
        if d.get("GravestoneCount") is not None:
            g["count"] = d["GravestoneCount"]
        if d.get("SpawnColumnStart") is not None:
            g["col_start"] = d["SpawnColumnStart"] - 1
        if d.get("SpawnColumnEnd") is not None:
            g["col_end"] = d["SpawnColumnEnd"] - 1
        if d.get("SpawnRowStart") is not None:
            g["row_start"] = d["SpawnRowStart"]
        if d.get("SpawnRowEnd") is not None:
            g["row_end"] = d["SpawnRowEnd"]
        types = d.get("Types") or ([d["Type"]] if d.get("Type") else [])
        if types:
            g["types"] = [strip_rtid(t) for t in types]
        if d.get("ForceSpawnData"):
            g["forced"] = [cell_entry(p) for p in d["ForceSpawnData"]]
        out["gravestones"] = g

    elif cls == "InitialGridItemProperties":
        init = out.setdefault("initial", {})
        items = [cell_entry(p) for p in (d.get("InitialGridItemPlacements") or [])]
        items += matrix_cells(d.get("InitialGridItemMatrixes"))
        if items:
            init.setdefault("grid_items", []).extend(items)

    elif cls == "InitialPlantProperties":
        init = out.setdefault("initial", {})
        if d.get("InitialPlantPlacements"):
            init.setdefault("plants", []).extend(
                cell_entry(p) for p in d["InitialPlantPlacements"])
        if d.get("IsInitialIntensiveCarrotPlacements"):
            init["intensive_carrots"] = True

    elif cls == "InitialZombieProperties":
        init = out.setdefault("initial", {})
        if d.get("InitialZombiePlacements"):
            init.setdefault("zombies", []).extend(
                cell_entry(p) for p in d["InitialZombiePlacements"])

    elif cls == "ProtectThePlantChallengeProperties":
        obj_out = {"type": "protect_plants"}
        if d.get("MustProtectCount") is not None:
            obj_out["must_protect"] = d["MustProtectCount"]
        if d.get("Plants"):
            obj_out["plants"] = [cell_entry(p) for p in d["Plants"]]
        out.setdefault("objectives", []).append(obj_out)

    elif cls.startswith("TutorialLevel") and cls.endswith("Properties"):
        # Each tutorial level carries its own marker class. The number in the
        # class name identifies which scripted lesson it is.
        digits = "".join(ch for ch in cls if ch.isdigit())
        out["tutorial_script"] = "tutorial_%s" % digits if digits else "tutorial"
        if digits == "1":
            # Tutorial 1 teaches planting in a single lane, and every wave it
            # spawns targets row 3, so the restriction is derived here rather
            # than hand-edited into the level file.
            out["plantable_rows"] = [3]
        if d:
            out.setdefault("tutorial_params", {}).update(d)

    elif cls == "TideProperties":
        start = num(d.get("StartingWaveLocation"))
        if start is not None:
            out["tide"] = {"water_from": max(0, min(9, 9 - start))}

    elif cls == "PowerTileProperties":
        tiles = []
        for t in (d.get("LinkedTiles") or []):
            loc = (t or {}).get("Location") or {}
            if num(loc.get("mX")) is None or num(loc.get("mY")) is None:
                continue
            tile = {"group": t.get("Group") or "alpha",
                    "row": num(loc["mY"]), "col": num(loc["mX"])}
            if num(t.get("PropagationDelay")) is not None:
                tile["delay"] = num(t["PropagationDelay"])
            tiles.append(tile)
        if tiles:
            out["power_tiles"] = tiles

    elif cls == "ZombiePotionModuleProperties":
        out["potions"] = {
            "initial": num(d.get("InitialPotionCount"), 0),
            "max": num(d.get("MaxPotionCount"), 0),
            "interval": span(d.get("PotionSpawnTimer")) or {"min": 12, "max": 16},
            "types": [strip_rtid(t) for t in (d.get("PotionTypes") or [])],
        }

    elif cls == "RailcartProperties":
        rc = {}
        if d.get("Railcarts"):
            rc["carts"] = [{"col": r.get("Column"), "row": r.get("Row")}
                           for r in d["Railcarts"]]
        if d.get("Rails"):
            rc["rails"] = [{"col": r.get("Column"), "row_start": r.get("RowStart"),
                            "row_end": r.get("RowEnd")} for r in d["Rails"]]
        if d.get("RailcartType"):
            rc["type"] = strip_rtid(d["RailcartType"])
        if d.get("DynamicRailCarts"):
            rc["dynamic"] = d["DynamicRailCarts"]
        out["railcarts"] = rc

    else:
        return False
    return True


# PopCap ships level options as a bag of module name strings. Only a few mean
# anything mechanically, and matching on strings at runtime is how a schema
# ends up a 1:1 copy of someone else's. They are translated into explicit
# fields here; the rest are kept as `scripts` so nothing is lost.
SUN_INTERVALS = {"FastSunDropper": 5.0, "DefaultSunDropper": 10.0,
                 "SlowSunDropper": 15.0}
# Win conditions are objectives now, so these carry no information.
REDUNDANT_FEATURES = {"ZombiesDeadWinCon", "DefaultZombieWinCondition"}


def translate_features(features):
    """-> (explicit option fields, leftover script hooks)."""
    options = {}
    scripts = []
    for name in features:
        if name in REDUNDANT_FEATURES:
            continue
        if name.endswith("Mowers"):
            options["mowers"] = True
            continue
        if name in SUN_INTERVALS:
            options["sun"] = {"interval": SUN_INTERVALS[name]}
            continue
        if name == "SeedPacketHalfTimeModule":
            options["seed_recharge"] = 0.5
            continue
        # Narrative and tutorial hooks are behaviour, not options.
        scripts.append(name)
    return options, scripts


def conv_reward(kind, param):
    """FirstRewardType/Param -> {type, param}: the prize dropped the first time
    a level is won (unlock_plant, upgrade, worldtrophy, note, pinata...).
    "none" is PopCap's way of saying there is no prize, so it is dropped."""
    if not kind or kind == "none":
        return None
    out = {"type": kind}
    if param and param != "none":
        out["param"] = param
    return out


def convert(payload, source):
    lvl = Level(payload, source)
    if not lvl.definition:
        return None
    dd = lvl.definition.get("objdata") or {}
    lvl.consumed.add(id(lvl.definition))

    out = collections.OrderedDict()
    out["id"] = os.path.basename(source).replace(".json", "")
    # One name, not three. The comment is the human-readable one where there
    # is one; the localisation key is kept as `name_key`.
    name_key = dd.get("Name")
    out["name"] = lvl.comment or name_key or out["id"]
    if name_key and name_key != out["name"]:
        out["name_key"] = name_key
    if dd.get("Description"):
        out["description"] = dd["Description"]
    if dd.get("WrittenBy"):
        out["author"] = dd["WrittenBy"]
    if dd.get("LevelNumber") is not None:
        out["number"] = dd["LevelNumber"]

    stage = lvl.external(dd.get("StageModule", "")) or strip_rtid(dd.get("StageModule", ""))
    if stage:
        out["stage"] = stage.split("@")[0]

    for src, dst in [("PlantToIntroduce", "introduces_plant"),
                     ("IsVasebreaker", "vasebreaker"),
                     ("IsLevelOfTheDay", "level_of_the_day"),
                     ("FirstIntroNarrative", "intro_narrative"),
                     ("DraperPromo", "promo_plant")]:
        if dd.get(src) is not None:
            out[dst] = dd[src]

    reward = conv_reward(dd.get("FirstRewardType"), dd.get("FirstRewardParam"))
    if reward:
        out["reward"] = reward
    replay = conv_reward(dd.get("ReplayRewardType"), dd.get("ReplayRewardParam"))
    if replay:
        out["replay_reward"] = replay
    if dd.get("GameFeaturesToUnlock"):
        out["unlocks_features"] = [f.removeprefix("feature_")
                                   for f in dd["GameFeaturesToUnlock"]]

    features, unmodelled = [], []
    for ref in (dd.get("Modules") or []):
        obj = lvl.resolve(ref)
        if obj is None:
            ext = lvl.external(ref)
            if ext:
                features.append(ext.split("@")[0])
            continue
        if not handle_module(lvl, out, obj):
            unmodelled.append({"objclass": obj.get("objclass"),
                               "aliases": obj.get("aliases"),
                               "objdata": obj.get("objdata") or {}})
    options, scripts = translate_features(sorted(set(features)))
    out.update(options)
    if scripts:
        out["scripts"] = scripts

    # Sweep any remaining top-level modules the Modules list did not name.
    for o in lvl.objects:
        if id(o) in lvl.consumed:
            continue
        if handle_module(lvl, out, o):
            lvl.consumed.add(id(o))

    leftovers = [o for o in lvl.objects if id(o) not in lvl.consumed]
    extra = unmodelled + leftovers
    if extra:
        out["extra"] = extra
    # Every PvZ2 level is won by outlasting its waves; star challenges and
    # protect-the-plant goals are conditions on top of that, not instead of
    # it. Listing objectives replaces the runner's default, so say so here.
    objs = out.get("objectives")
    if objs and not any(o.get("type") == "survive_waves" for o in objs):
        objs.insert(0, {"type": "survive_waves"})
    return out


def main():
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    ok = fail = 0
    for f in sorted(glob.glob(os.path.join(src_dir, "*.json"))):
        try:
            native = convert(json.load(open(f, encoding="utf-8")), f)
            if native is None:
                fail += 1
                continue
            open(os.path.join(out_dir, os.path.basename(f)), "w", encoding="utf-8").write(
                json.dumps(native, ensure_ascii=False, indent=1))
            ok += 1
        except Exception as e:
            print(f"  !! {os.path.basename(f)}: {type(e).__name__}: {e}", file=sys.stderr)
            fail += 1
    print(f"converted {ok} levels ({fail} failed)")


if __name__ == "__main__":
    main()
