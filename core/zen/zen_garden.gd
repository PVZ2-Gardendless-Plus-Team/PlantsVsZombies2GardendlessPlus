class_name ZenGarden
extends RefCounted
## The Zen Garden's rules, ported from PVZGE's ZenGarden.ts: sprouts grow into
## plants over real time, and each stage waits on the player to water it three
## times and then feed it (fertilizer, or a jukebox or pesticide once grown),
## paying out coins and gems as it grows.
##
## This is only the rules and the saved state - no nodes - so the garden can
## be tested headless and the screen (ZenGardenScreen) is only a view of it.
## Times are milliseconds of wall-clock time, as PVZGE keeps them, so plants
## keep growing while the game is closed.
##
## The gardens themselves - where the slots are, what ground each has, which
## art draws it - come from data/native/zen_gardens.json, so a pack can add a
## garden without code.

signal changed

## What a plant is waiting for. PVZGE's PlantInZenGardenRequirementEnum, in
## its order, so saved numbers mean the same thing.
enum Need { NONE = -1, WATER = 0, FERTILIZER = 1, JUKEBOX = 2, PESTICIDE = 3 }

const NEED_NAMES := {
	Need.WATER: &"water", Need.FERTILIZER: &"fertilizer",
	Need.JUKEBOX: &"jukebox", Need.PESTICIDE: &"pesticide",
}
const CONFIG_PATH := "res://data/native/zen_gardens.json"
const SAVE_SECTION := &"zen_garden"
const SECOND := 1000
## Waterings a stage wants before its feed (PVZGE's waterLeftTime of 3).
const WATERINGS := 3
## PVZGE waters every neighbour that is also thirsty with one pour: the can's
## 180 px square against each slot's 300-unit one, at the garden's 0.33.
const WATER_REACH := 422.7
## A plant at least this grown pays a boost when shoveled.
const BOOST_STAGE := 3
## The coins and gem a stage pays out (PVZGE's ZenGarden.drop).
const SILVER := 10
const GOLD := 50
const COINS_PER_DROP := 5
## One sprout in twenty grows into a Marigold the player does not own yet.
const MARIGOLD := &"marigold"
const MARIGOLD_CHANCE := 0.05

## Debug: when above zero, how long a plant takes to grow fully instead of the
## configured day. PVZGE's Ctrl+Shift+Alt+P.
static var fast_full_time_ms: int = 0

var config: Dictionary = {}
## Garden config entries, in order.
var gardens: Array = []
var rng := RandomNumberGenerator.new()
## Seconds-resolution clock, swappable so tests can move time.
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)

var _state: Dictionary = {}


func _init(config_path: String = CONFIG_PATH) -> void:
	rng.randomize()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	config = parsed if parsed is Dictionary else {}
	gardens = config.get("gardens", [])
	load_state()


# --- state --------------------------------------------------------------

func load_state() -> void:
	_state = Saves.section(SAVE_SECTION)
	for key in ["plants", "unlocked"]:
		if not _state.has(key):
			_state[key] = [] if key == "plants" else {}


func save() -> void:
	Saves.store_section(SAVE_SECTION, _state)
	changed.emit()


## Whether the player has opened the garden: PVZGE gives it for clearing
## egypt5. A build without that level has nothing to win it from, so it is
## open, as a world gated on a missing campaign is.
static func is_open() -> bool:
	if Saves.has_feature(&"zengarden") or Saves.is_cleared(&"egypt5"):
		return true
	return Data.level(&"egypt5").is_empty()


func garden_count() -> int:
	return gardens.size()


func garden(index: int) -> Dictionary:
	return gardens[index] if index >= 0 and index < gardens.size() else {}


func garden_id(index: int) -> String:
	return String(garden(index).get("id", str(index)))


func slots(index: int) -> Array:
	return garden(index).get("slots", [])


func slot_price() -> int:
	return int(config.get("slot_price", 4000))


func full_time() -> int:
	if fast_full_time_ms > 0:
		return fast_full_time_ms
	return int(float(config.get("full_grow_hours", 24)) * 3600.0 * SECOND)


func sprouts() -> int:
	return Saves.currency(&"sprouts")


# --- slots --------------------------------------------------------------

func is_unlocked(g: int, slot: int) -> bool:
	var list: Array = slots(g)
	if slot < 0 or slot >= list.size():
		return false
	if bool(list[slot].get("unlocked", false)):
		return true
	return (_state["unlocked"].get(garden_id(g), []) as Array).has(slot)


func can_buy_slot(g: int, slot: int) -> bool:
	return not is_unlocked(g, slot) and Saves.currency(&"coins") >= slot_price()


## Buys a locked slot for its price in coins. False when it cannot be bought.
func buy_slot(g: int, slot: int) -> bool:
	if not can_buy_slot(g, slot):
		return false
	Saves.add_currency(&"coins", -slot_price())
	var unlocked: Dictionary = _state["unlocked"]
	var list: Array = unlocked.get(garden_id(g), [])
	list.append(slot)
	unlocked[garden_id(g)] = list
	save()
	return true


## The plant record in a slot, or an empty dictionary.
func plant_at(g: int, slot: int) -> Dictionary:
	var id := garden_id(g)
	for p in _state["plants"]:
		if String(p.get("garden", "")) == id and int(p.get("slot", -1)) == slot:
			return p
	return {}


func plants() -> Array:
	return _state["plants"]


## PVZGE's ZenGarden.judgePlantableInSlot.
func fits(g: int, slot: int, plant_id: StringName) -> bool:
	var list: Array = slots(g)
	if slot < 0 or slot >= list.size() or plant_id == &"":
		return false
	var place := place_of(plant_id)
	if place == &"none" or place == &"":
		return false
	match String(list[slot].get("ground", "any")):
		"any":
			return true
		"deck", "grass":
			return place == &"dirt" or place == &"fly"
		"ground":
			return place == &"solid" or place == &"dirt" or place == &"fly"
	return false


static func place_of(plant_id: StringName) -> StringName:
	var def := Data.plant(plant_id)
	return def.zen_place if def != null else &"none"


# --- growth -------------------------------------------------------------

## 0 is a sprout, 1 small, 2 grown, 3 and on fully grown.
func stage(p: Dictionary) -> int:
	return stage_of(float(p.get("grown", 0)))


func stage_of(grown_ms: float) -> int:
	return int(floor(4.0 * maxf(grown_ms, 0.0) / float(full_time())))


## PVZGE's getPlantScale.
static func scale_for(stage_value: int) -> float:
	match stage_value:
		1: return 0.7
		2: return 1.0
	return 1.3


func need(p: Dictionary) -> int:
	return int(p.get("need", Need.NONE))


## Whether the plant is waiting on the player rather than growing.
func is_stuck(p: Dictionary) -> bool:
	return bool(p.get("stuck", false))


## Advances every plant to now (PVZGE's ZenGardenSlot.dealPlant). Returns
## whether anything changed that the screen should redraw.
func tick() -> bool:
	var now: int = clock.call()
	var any := false
	for p in _state["plants"]:
		if _deal(p, now):
			any = true
	if any:
		save()
	return any


func _deal(p: Dictionary, now: int) -> bool:
	var dt := now - int(p.get("old_time", now))
	p["old_time"] = now
	var before := stage(p)
	var before_need := need(p)
	if is_stuck(p):
		if before_need == Need.NONE:
			p["water_cd"] = int(p.get("water_cd", 0)) - dt
			if int(p["water_cd"]) <= 0:
				p["water_cd"] = 0
				var next := Need.WATER
				if int(p.get("water_left", 0)) < 0:
					next = _feed_for(before)
				p["need"] = next
	else:
		p["grown"] = int(p.get("grown", 0)) + dt
	var after := mini(stage(p), before + 1)
	if after != before and not is_stuck(p):
		_stage_reached(p, after)
		p["grown"] = int(after / 4.0 * full_time()) - 1
		return true
	return need(p) != before_need


## A stage was reached: the plant stops until it is looked after. Floating
## plants skip the watering and go straight to their feed.
func _stage_reached(p: Dictionary, reached: int) -> void:
	p["stuck"] = true
	if place_of(StringName(p.get("plant", ""))) == &"float":
		p["water_left"] = -1
		p["need"] = _feed_for(reached)
	else:
		p["water_left"] = WATERINGS
		p["need"] = Need.WATER


## Fertilizer while young; a jukebox or pesticide, at random, once grown.
func _feed_for(stage_value: int) -> int:
	if stage_value > 2:
		return Need.JUKEBOX if rng.randf() > 0.5 else Need.PESTICIDE
	return Need.FERTILIZER


## The player answers what a slot's plant wants. Returns what happened, for
## the screen to animate: `need` (what was given), `watered` (other slots the
## same pour reached), and for a feed `grew_to` with the `drops` it pays.
func tend(g: int, slot: int) -> Dictionary:
	var p := plant_at(g, slot)
	if p.is_empty() or need(p) == Need.NONE:
		return {}
	var given := need(p)
	var result := {"need": given, "watered": [] as Array[int], "drops": []}
	if given == Need.WATER:
		_water(p)
		var here: Dictionary = slots(g)[slot]
		for other in slots(g).size():
			if other == slot:
				continue
			var q := plant_at(g, other)
			if q.is_empty() or need(q) != Need.WATER:
				continue
			var there: Dictionary = slots(g)[other]
			if absf(float(there["x"]) - float(here["x"])) < WATER_REACH \
					and absf(float(there["y"]) - float(here["y"])) < WATER_REACH:
				_water(q)
				result["watered"].append(other)
	else:
		p["need"] = Need.NONE
		var grew := grow(p)
		result["grew_to"] = grew
		result["drops"] = drops_for(grew)
		result["unlocked"] = _maybe_unlock(p)
	save()
	return result


func _water(p: Dictionary) -> void:
	p["need"] = Need.NONE
	p["water_left"] = int(p.get("water_left", 0)) - 1
	p["water_cd"] = int((7.0 + 3.0 * rng.randf()) * SECOND)


## Moves the plant up a stage and frees it to grow on (PVZGE's grow()).
func grow(p: Dictionary) -> int:
	var reached := stage(p) + 1
	p["stuck"] = false
	p["grown"] = int(reached / 4.0 * full_time()) + 1
	return reached


## What a plant reaching `reached` pays: five silver coins, five gold from the
## second stage, and a gem from the third.
static func drops_for(reached: int) -> Array:
	if reached >= 3:
		return [{"kind": &"gems", "value": 1}]
	var value := GOLD if reached >= 2 else SILVER
	var out := []
	for i in COINS_PER_DROP:
		out.append({"kind": &"coins", "value": value})
	return out


## A Marigold that comes up gives the player the plant, if they lacked it.
func _maybe_unlock(p: Dictionary) -> StringName:
	var id := StringName(p.get("plant", ""))
	if id == MARIGOLD and stage(p) >= 1 and not Saves.unlocked_plants().has(id) \
			and Data.plant(id) != null:
		Saves.unlock_plant(id)
		return id
	return &""


# --- sprouts ------------------------------------------------------------

## Plants a sprout in an empty, unlocked slot. Returns the plant it will grow
## into, or "" when it cannot.
func plant_sprout(g: int, slot: int) -> StringName:
	if sprouts() <= 0 or not is_unlocked(g, slot) or not plant_at(g, slot).is_empty():
		return &""
	var pick := pick_sprout(g, slot)
	if pick == &"":
		return &""
	Saves.add_currency(&"sprouts", -1)
	_state["plants"].append(new_plant(pick, g, slot))
	save()
	return pick


func new_plant(plant_id: StringName, g: int, slot: int) -> Dictionary:
	return {
		"plant": String(plant_id), "garden": garden_id(g), "slot": slot,
		"grown": 0, "old_time": clock.call(), "stuck": true,
		"water_cd": 0, "water_left": -1 if place_of(plant_id) == &"float" else WATERINGS,
		"need": Need.NONE,
	}


## Which plant a sprout in this slot grows into (PVZGE's MouseDown on an
## empty slot). Each owned plant that fits is weighted by how many the player
## has: 8 for none, 32 for one, 128 for two, and 1 from three on - boosts
## count as having one. A plant's own `zen_weight` overrides that.
func pick_sprout(g: int, slot: int) -> StringName:
	var weights := {}
	for id in owned_plants():
		if not fits(g, slot, id):
			continue
		weights[id] = sprout_weight(id)
	if weights.is_empty():
		return &""
	if rng.randf() < MARIGOLD_CHANCE and not weights.has(MARIGOLD) \
			and Data.plant(MARIGOLD) != null:
		return MARIGOLD
	var total := 0
	for w in weights.values():
		total += w
	if total <= 0:
		return &""
	var roll := rng.randi_range(1, total)
	for id in weights:
		roll -= weights[id]
		if roll <= 0:
			return id
	return weights.keys()[0]


func sprout_weight(plant_id: StringName) -> int:
	var def := Data.plant(plant_id)
	if def != null and def.zen_weight >= 0:
		return def.zen_weight
	var have := mini(Saves.plant_boosts(plant_id), 3)
	if have < 3:
		have = mini(have + count_of(plant_id), 3)
	match have:
		0: return 8
		1: return 32
		2: return 128
	return 1


## How many of a plant are in the gardens and the wheelbarrow.
func count_of(plant_id: StringName) -> int:
	var n := 0
	for p in _state["plants"]:
		if StringName(p.get("plant", "")) == plant_id:
			n += 1
	var cart: Variant = _state.get("cart")
	if cart is Dictionary and StringName(cart.get("plant", "")) == plant_id:
		n += 1
	return n


func owned_plants() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Data.plants:
		if Saves.is_plant_unlocked(id):
			out.append(StringName(id))
	return out


# --- tools --------------------------------------------------------------

## Whether shoveling this plant would bank a boost for it.
func boosts_on_shovel(g: int, slot: int) -> bool:
	var p := plant_at(g, slot)
	return not p.is_empty() and not is_stuck(p) and stage(p) >= BOOST_STAGE


## Digs a plant up. A fully grown one that is not waiting on anything leaves
## a boost behind. Returns whether it did.
func shovel(g: int, slot: int) -> bool:
	var p := plant_at(g, slot)
	if p.is_empty():
		return false
	var boosted := boosts_on_shovel(g, slot)
	if boosted:
		Saves.add_plant_boost(StringName(p["plant"]))
	_state["plants"].erase(p)
	save()
	return boosted


## Whether a plant may be picked up by the glove or the wheelbarrow: grown
## past a sprout and not waiting on the player.
func can_lift(g: int, slot: int) -> bool:
	var p := plant_at(g, slot)
	return not p.is_empty() and not is_stuck(p) and stage(p) > 0


func can_receive(g: int, slot: int, plant_id: StringName) -> bool:
	return is_unlocked(g, slot) and plant_at(g, slot).is_empty() and fits(g, slot, plant_id)


## The glove: moves a plant to another slot in the same garden.
func move(g: int, from: int, to: int) -> bool:
	var p := plant_at(g, from)
	if p.is_empty() or from == to or not can_receive(g, to, StringName(p["plant"])):
		return false
	p["slot"] = to
	save()
	return true


func cart() -> Dictionary:
	var c: Variant = _state.get("cart")
	return c if c is Dictionary else {}


## The wheelbarrow: lifts a plant out of its garden to carry to another.
## It holds one plant.
func load_cart(g: int, slot: int) -> bool:
	if not cart().is_empty() or not can_lift(g, slot):
		return false
	var p := plant_at(g, slot)
	_state["plants"].erase(p)
	p.erase("garden")
	p.erase("slot")
	_state["cart"] = p
	save()
	return true


func unload_cart(g: int, slot: int) -> bool:
	var p := cart()
	if p.is_empty() or not can_receive(g, slot, StringName(p.get("plant", ""))):
		return false
	p["garden"] = garden_id(g)
	p["slot"] = slot
	_state["plants"].append(p)
	_state.erase("cart")
	save()
	return true
