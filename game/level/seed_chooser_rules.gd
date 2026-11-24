class_name SeedChooserRules
extends RefCounted
## What a level lets the player pick before it starts, and how many.
##
## Mirrors PVZGE's chooser: the level may narrow the list to an include list,
## ban plants outright, ban every sun producer, and pre-pick plants the player
## cannot remove. Water-only plants are only offered where there is water. The
## number of slots is the level's override or the base count, capped by how
## many plants are actually choosable.
##
## Only plants the player owns can be picked (see `Saves.is_plant_unlocked`).
## The default list leaves the rest out; a level's include list still shows
## them, refused, unless the level sets `unlock_all` as PVZGE's UnlockAll does.
##
## Kept apart from the chooser screen so the rules can be checked headless and
## reused by anything else that needs them (a deck editor, a randomiser).

## Copies the plant in the slot before it.
const IMITATER := &"imitater"

## Plants offered, in the order the chooser lists them.
var candidates: Array[StringName] = []
## Picked before the player arrives and not removable: the level's preset.
var locked: Array[StringName] = []
## How many plants the player takes into the level.
var slots: int = 0
## Ready-made loadouts as {name, plants, challenging}.
var decks: Array[Dictionary] = []
## When true only challenging decks are offered and the player's last picks
## are not restored, as PVZGE's ChallengingLocked does.
var challenging_locked: bool = false

var _excluded: Dictionary = {}
var _ban_sun_producers: bool = false
var _has_water: bool = false
var _unlock_all: bool = false


## True when `level` asks the player to choose plants before it starts.
static func level_uses_chooser(level: Dictionary) -> bool:
	var sb: Dictionary = level.get("seedbank", {})
	return String(sb.get("mode", "chooser")) == "chooser" \
			and String(sb.get("selection", "")) == "chooser"


## Builds the rules for `level`. `board` must already be set up, since water
## on the lawn decides whether water-only plants are offered.
static func from_level(level: Dictionary, board: Board) -> SeedChooserRules:
	var rules := SeedChooserRules.new()
	rules._read(level, board)
	return rules


func _read(level: Dictionary, board: Board) -> void:
	var sb: Dictionary = level.get("seedbank", {})
	var config := Data.seed_chooser_config()

	for id in (sb.get("exclude", []) as Array):
		_excluded[StringName(id)] = true
	# PVZGE treats any blacklist as a ban on sun producers as well.
	var blacklist: Array = sb.get("blacklist", [])
	for id in blacklist:
		_excluded[StringName(id)] = true
	_ban_sun_producers = _truthy(sb.get("exclude_sun_producers", false)) \
			or not blacklist.is_empty()
	_has_water = level_has_water(level, board)

	var include: Array = sb.get("include", [])
	if not include.is_empty():
		_unlock_all = _truthy(sb.get("unlock_all", false))
		for id in include:
			_offer(StringName(id))
	else:
		for id in default_order():
			if Saves.is_plant_unlocked(id):
				_offer(id)
	for entry in (sb.get("preset", []) as Array):
		var id := _entry_id(entry)
		if id == &"" or Data.plant(id) == null:
			continue
		_offer(id)
		if not locked.has(id):
			locked.append(id)

	var deck_data: Variant = sb.get("decks", {})
	if deck_data is Dictionary:
		challenging_locked = bool(deck_data.get("challenging_locked", false))
		if not challenging_locked:
			_read_decks(deck_data.get("recommended", []), false)
		_read_decks(deck_data.get("challenging", []), true)

	# A level's own slot count stands as it is; otherwise the base count
	# grows with the seed slot upgrades, as PVZGE's BaseSeedSlotcount does.
	var cap := int(config.get("max_slots", 8))
	var wanted := int(sb.get("slots", 0))
	if wanted <= 0:
		wanted = Upgrades.seed_slots(int(config.get("base_slots", 6)), cap)
	var choosable := 0
	for id in candidates:
		if refusal(id) == "":
			choosable += 1
	slots = maxi(mini(mini(wanted, cap), choosable), locked.size())


## Every plant the player could ever pick, in chooser order: the configured
## order first, then any other plant a pack adds.
static func default_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in (Data.seed_chooser_config().get("order", []) as Array):
		out.append(StringName(id))
	var extra: Array[StringName] = []
	for id in Data.plants:
		var def: PlantDef = Data.plants[id]
		if def.source_mod != &"base" and not out.has(id):
			extra.append(id)
	extra.sort()
	out.append_array(extra)
	return out


## Water on the lawn: a tide, or any cell whose ground only aquatic plants
## can use.
static func level_has_water(level: Dictionary, board: Board) -> bool:
	if level.has("tide"):
		return true
	for module in (level.get("extra", []) as Array):
		if module is Dictionary and String(module.get("objclass", "")) == "TideProperties":
			return true
	if board == null:
		return false
	for r in board.rows:
		for c in board.cols:
			var ground := board.terrain_def(r, c)
			if ground == null:
				var item := board.object_at(r, c)
				if item != null and item.def is ObjectDef:
					ground = item.def
			if ground != null and ground.requires_tag == &"aquatic":
				return true
	return false


## Why `id` cannot be picked here, or "" when it can.
func refusal(id: StringName) -> String:
	var def := Data.plant(id)
	if def == null:
		return tr("unknown plant")
	if locked.has(id):
		return ""
	if not _unlock_all and not Saves.is_plant_unlocked(id):
		return tr("not unlocked yet")
	if _excluded.has(id):
		return tr("not allowed in this level")
	if _ban_sun_producers and def.has_tag(&"sun_producer"):
		return tr("sun producers are not allowed")
	if not _has_water and def.has_tag(&"water_only"):
		return tr("needs water")
	return ""


## Whether the Imitater may go after `prev`, the last plant in the hand. It
## copies that plant, so it needs one that allows copying.
func can_imitate(prev: StringName) -> bool:
	if prev == &"" or prev == IMITATER:
		return false
	var def := Data.plant(prev)
	return def != null and not def.has_tag(&"imitate_disallowed")


## The seed bank a hand becomes: each Imitater turns into a second packet of
## the plant before it.
func seeds_for(hand: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in hand:
		var sid := StringName(id)
		if sid == IMITATER:
			if not out.is_empty():
				out.append(out[-1])
		else:
			out.append(sid)
	return out


func can_pick(id: StringName) -> bool:
	return candidates.has(id) and refusal(id) == ""


## True when `chosen` is a full hand, or exactly a challenging deck - PVZGE
## lets a challenging deck start with fewer plants than there are slots.
func can_start(chosen: Array) -> bool:
	if chosen.size() == slots:
		return true
	for deck in decks:
		if deck["challenging"] and _same_set(deck["plants"], chosen):
			return true
	return false


## The plants of `deck` that can be picked here, without duplicates, locked
## plants first and capped at the slot count.
func deck_picks(deck: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = locked.duplicate()
	for id in (deck.get("plants", []) as Array):
		var sid := StringName(id)
		if out.size() >= slots:
			break
		if out.has(sid) or not can_pick(sid):
			continue
		if sid == IMITATER and not can_imitate(out[-1] if not out.is_empty() else &""):
			continue
		out.append(sid)
	return out


func _offer(id: StringName) -> void:
	if Data.plant(id) != null and not candidates.has(id):
		candidates.append(id)


func _read_decks(list: Variant, challenging: bool) -> void:
	if not (list is Array):
		return
	for deck in list:
		if deck is Dictionary and not (deck.get("plants", []) as Array).is_empty():
			decks.append({
				"name": String(deck.get("name", "")),
				"plants": deck["plants"],
				"challenging": challenging,
			})


static func _entry_id(entry: Variant) -> StringName:
	if entry is Dictionary:
		return StringName(entry.get("type", ""))
	return StringName(entry)


static func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not b.has(StringName(x)) and not b.has(String(x)):
			return false
	return true


## The source writes some flags as the string "true".
static func _truthy(value: Variant) -> bool:
	if value is String:
		return value.to_lower() == "true"
	return bool(value)
