class_name Loot
extends RefCounted
## Rolls the drop tables in `loot.json`: coins, gems, tickets and sprouts that
## zombies, unused mowers and coin-producing plants leave on the lawn.
##
## A table is a Dictionary:
##   feature   only rolls once Saves.has_feature(feature)
##   one_of    [{drop, chance}...] - the first whose running total of chances
##             the roll falls under; at most one of these drops
##   also      [{drop, chance, feature?, lod_only?, per_level?}...] - each
##             rolled on its own
##   drop      a single sure drop (the mower table)
##
## Rolling only names drops; the board turns each name into a pickup with
## `info()`, so this stays testable without a lawn.

## Where a roll happens, so `lod_only` and `per_level` entries can be judged.
class Context:
	extends RefCounted
	## A Lawn of Doom level, the only kind PVZGE drops tickets in.
	var lod: bool = false
	## Drop id -> how many this level has handed out so far.
	var given: Dictionary = {}
	## Every drop comes this many times (PVZGE's ThreeTimesPrizes).
	var multiplier: int = 1


## A named table from loot.json: &"zombie", &"mower", &"marigold"...
static func table(name: StringName) -> Dictionary:
	var t: Variant = Data.loot.get(String(name), {})
	return t if t is Dictionary else {}


## What drop `id` is: {currency, value}. Empty for an unknown id.
static func info(id: StringName) -> Dictionary:
	var drops: Variant = Data.loot.get("drops", {})
	if not (drops is Dictionary):
		return {}
	var d: Variant = drops.get(String(id), {})
	return d if d is Dictionary else {}


static func _feature_open(entry: Dictionary) -> bool:
	var feature := str(entry.get("feature", ""))
	return feature == "" or Saves.has_feature(StringName(feature))


## Rolls `t` and returns the drop ids it gave, `multiplier` times each.
static func roll(t: Dictionary, rng: RandomNumberGenerator,
		context: Context = null) -> Array[StringName]:
	var out: Array[StringName] = []
	if t.is_empty() or not _feature_open(t):
		return out
	if context == null:
		context = Context.new()
	var picked: Array[StringName] = []
	if t.has("drop"):
		picked.append(StringName(str(t["drop"])))
	var one_of: Array = t.get("one_of", [])
	if not one_of.is_empty():
		var r := rng.randf()
		var total := 0.0
		for entry in one_of:
			if not (entry is Dictionary):
				continue
			total += float(entry.get("chance", 0.0))
			if r < total:
				if _feature_open(entry):
					picked.append(StringName(str(entry.get("drop", ""))))
				break
	for entry in (t.get("also", []) as Array):
		if not (entry is Dictionary) or not _feature_open(entry):
			continue
		if entry.get("lod_only", false) and not context.lod:
			continue
		var id := StringName(str(entry.get("drop", "")))
		var cap := int(entry.get("per_level", 0))
		if cap > 0 and int(context.given.get(id, 0)) >= cap:
			continue
		if rng.randf() < float(entry.get("chance", 0.0)):
			picked.append(id)
	for id in picked:
		if id == &"":
			continue
		context.given[id] = int(context.given.get(id, 0)) + 1
		for i in maxi(context.multiplier, 1):
			out.append(id)
	return out
