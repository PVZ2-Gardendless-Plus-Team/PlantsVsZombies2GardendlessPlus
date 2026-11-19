extends Node
## Per-level save states and campaign progress: cleared levels, unlocked
## plants, currency and the trophies, upgrades and notes rewards hand out.
##
## PvZ2 lets you leave a level and come back to it mid-run; PVZGE does not.
## Each level gets its own slot, so several can be part-played at once.
##
## The objects describe themselves - Board, LevelRunner, SeedBank, each
## objective and lawn component all have their own snapshot - so this only
## composes them and handles files. Adding something that needs remembering
## means giving it a `save_state`, not editing this.
##
## Registered as an autoload singleton named `Saves`.

signal level_saved(level_id: StringName)
signal level_loaded(level_id: StringName)
signal progress_changed
## A currency (coins, gems, world keys) moved to `total`.
signal currency_changed(kind: StringName, total: int)
signal plant_unlocked(plant_id: StringName)

const SAVE_DIR := "user://saves"
const PROGRESS_FILE := "user://saves/progress.json"
const FORMAT_VERSION := 1

var _progress: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_progress()


# --- level slots ---------------------------------------------------------

func slot_path(level_id: StringName) -> String:
	return SAVE_DIR.path_join("level_%s.json" % level_id)


func has_save(level_id: StringName) -> bool:
	return FileAccess.file_exists(slot_path(level_id))


## Everything needed to resume this level.
func capture(runner: Node, board: Node, seed_bank: Node = null) -> Dictionary:
	var data := {
		"version": FORMAT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"level": runner.snapshot(),
		"board": board.snapshot(),
	}
	if seed_bank != null and seed_bank.has_method("snapshot"):
		data["seed_bank"] = seed_bank.snapshot()
	return data


func save_level(runner: Node, board: Node, seed_bank: Node = null) -> bool:
	var data := capture(runner, board, seed_bank)
	var level_id := StringName(data["level"].get("level_id", &""))
	if level_id == &"":
		push_warning("Saves: refusing to save a level with no id")
		return false
	var f := FileAccess.open(slot_path(level_id), FileAccess.WRITE)
	if f == null:
		push_warning("Saves: cannot write %s" % slot_path(level_id))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	level_saved.emit(level_id)
	return true


func load_save(level_id: StringName) -> Dictionary:
	if not has_save(level_id):
		return {}
	var f := FileAccess.open(slot_path(level_id), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("Saves: %s is not valid save data" % level_id)
		return {}
	if int(parsed.get("version", 0)) != FORMAT_VERSION:
		push_warning("Saves: %s is version %s, expected %d - ignoring"
				% [level_id, parsed.get("version"), FORMAT_VERSION])
		return {}
	return parsed


## Applies a save to a level that has already been started.
func restore(data: Dictionary, runner: Node, board: Node,
		seed_bank: Node = null) -> bool:
	if data.is_empty():
		return false
	# Board first: the runner's objectives inspect the lawn as they restore.
	board.apply_snapshot(data.get("board", {}))
	if seed_bank != null and seed_bank.has_method("apply_snapshot"):
		seed_bank.apply_snapshot(data.get("seed_bank", []))
	runner.apply_snapshot(data.get("level", {}))
	level_loaded.emit(StringName(data.get("level", {}).get("level_id", &"")))
	return true


func clear_save(level_id: StringName) -> void:
	if has_save(level_id):
		DirAccess.remove_absolute(slot_path(level_id))


## Levels with a save in progress.
func saved_levels() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("level_") and name.ends_with(".json"):
			out.append(StringName(name.substr(6, name.length() - 11)))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# --- campaign progress --------------------------------------------------

func mark_cleared(level_id: StringName) -> void:
	# Finishing a level ends its run, so the part-played state goes with it -
	# done first, because a level cleared twice still has a slot to retire.
	clear_save(level_id)
	var cleared: Array = _progress.get("cleared", [])
	if cleared.has(String(level_id)):
		return
	cleared.append(String(level_id))
	_progress["cleared"] = cleared
	_save_progress()
	progress_changed.emit()


func is_cleared(level_id: StringName) -> bool:
	return (_progress.get("cleared", []) as Array).has(String(level_id))


func cleared_count() -> int:
	return (_progress.get("cleared", []) as Array).size()


## The plants the player last took into a chooser level, so the next chooser
## starts from them as PVZGE's does.
func last_seed_choice() -> Array:
	return _progress.get("last_seed_choice", [])


func remember_seed_choice(seeds: Array) -> void:
	_progress["last_seed_choice"] = seeds.map(func(s): return String(s))
	_save_progress()


# --- plants ---------------------------------------------------------------

## Whether the player may pick `plant_id` in a seed chooser.
##
## A plant is theirs when it is on the base list every player starts with
## (PVZGE's BASEUNLOCKLIST, `base_unlocked` in seed_chooser.json), when a
## reward has given it to them, or when a pack added it - a pack's plant has no
## level in the base campaign to win it from. The `unlock_all_plants` setting
## opens everything, for testing.
func is_plant_unlocked(plant_id: StringName) -> bool:
	if Settings.get_value(&"unlock_all_plants"):
		return true
	if (_progress.get("plants", {}) as Dictionary).has(String(plant_id)):
		return true
	if base_unlocked_plants().has(plant_id):
		return true
	var def := Data.plant(plant_id)
	return def != null and def.source_mod != &"base"


func base_unlocked_plants() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in (Data.seed_chooser_config().get("base_unlocked", []) as Array):
		out.append(StringName(id))
	return out


## Gives the player `plant_id`. It counts as new until a chooser has shown it,
## as PVZGE's obtained_toBeUnlocked does. Returns false if they had it already.
func unlock_plant(plant_id: StringName) -> bool:
	var plants: Dictionary = _progress.get("plants", {})
	if plants.has(String(plant_id)):
		return false
	plants[String(plant_id)] = {"new": true}
	_progress["plants"] = plants
	_save_progress()
	plant_unlocked.emit(plant_id)
	progress_changed.emit()
	return true


## Plants a reward gave the player, in the order they were won.
func unlocked_plants() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in (_progress.get("plants", {}) as Dictionary):
		out.append(StringName(id))
	return out


func is_plant_new(plant_id: StringName) -> bool:
	var entry: Variant = (_progress.get("plants", {}) as Dictionary).get(String(plant_id))
	return entry is Dictionary and bool(entry.get("new", false))


## Clears the new mark once the player has seen these plants.
func mark_plants_seen(plant_ids: Array) -> void:
	var plants: Dictionary = _progress.get("plants", {})
	var changed := false
	for id in plant_ids:
		var entry: Variant = plants.get(String(id))
		if entry is Dictionary and entry.get("new", false):
			entry["new"] = false
			changed = true
	if changed:
		_save_progress()


# --- currency -------------------------------------------------------------

## How much of `kind` the player holds: &"coins", &"gems", &"worldkeys", or
## any currency a pack invents.
func currency(kind: StringName) -> int:
	return int((_progress.get("currency", {}) as Dictionary).get(String(kind), 0))


## Adds `amount` (negative to spend) and returns the new total, never below 0.
func add_currency(kind: StringName, amount: int) -> int:
	var wallet: Dictionary = _progress.get("currency", {})
	var total := maxi(int(wallet.get(String(kind), 0)) + amount, 0)
	wallet[String(kind)] = total
	_progress["currency"] = wallet
	_save_progress()
	currency_changed.emit(kind, total)
	return total


## Whether the player holds at least `amount` of `kind`.
func can_afford(kind: StringName, amount: int) -> bool:
	return currency(kind) >= amount


## Takes `amount` of `kind` if the player has it all; spends nothing and
## returns false otherwise, so a purchase never leaves a wallet short.
func spend_currency(kind: StringName, amount: int) -> bool:
	if amount < 0 or not can_afford(kind, amount):
		return false
	if amount > 0:
		add_currency(kind, -amount)
	return true


## Sets `kind` to exactly `total`, for a currency that resets - PVZGE's
## tickets are cleared when a new week starts.
func set_currency(kind: StringName, total: int) -> void:
	add_currency(kind, maxi(total, 0) - currency(kind))


# --- sections -------------------------------------------------------------

## A system's own corner of the progress file (the store's weekly plant, say),
## for state that is not a currency, a collection or a plant. The copy is the
## caller's; hand it back with `set_section` to keep changes.
func section(name: StringName) -> Dictionary:
	var value: Variant = _progress.get("section_" + String(name), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func set_section(name: StringName, data: Dictionary) -> void:
	_progress["section_" + String(name)] = data.duplicate(true)
	_save_progress()


# --- collections ----------------------------------------------------------

## Records `item_id` in a named collection - &"trophies", &"upgrades",
## &"notes" - so later screens (almanac, upgrades, the world map) can ask what
## the player owns. Returns false if it was already there.
func grant_item(collection: StringName, item_id: StringName) -> bool:
	var items: Array = _progress.get(String(collection), [])
	if items.has(String(item_id)):
		return false
	items.append(String(item_id))
	_progress[String(collection)] = items
	_save_progress()
	progress_changed.emit()
	return true


func has_item(collection: StringName, item_id: StringName) -> bool:
	return (_progress.get(String(collection), []) as Array).has(String(item_id))


func items(collection: StringName) -> Array:
	return (_progress.get(String(collection), []) as Array).duplicate()


## Game features a level opens up when it is first won (PVZGE's
## GameFeaturesToUnlock: shovel, coins, almanac, zen garden...).
func unlock_feature(feature: StringName) -> void:
	grant_item(&"features", feature)


## Whether `feature` is open: a level handed it out, or the level that
## `features.json` ties it to is cleared - PVZGE opens the store once egypt6
## is won, whatever that level's own data says.
func has_feature(feature: StringName) -> bool:
	if has_item(&"features", feature):
		return true
	var gate := StringName(str(Data.feature_levels().get(String(feature), "")))
	return gate != &"" and is_cleared(gate)


func reset_progress() -> void:
	_progress = {}
	for level_id in saved_levels():
		clear_save(level_id)
	_save_progress()
	progress_changed.emit()


func _load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_FILE):
		_progress = {}
		return
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_progress = parsed if parsed is Dictionary else {}


func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if f == null:
		push_warning("Saves: cannot write progress")
		return
	f.store_string(JSON.stringify(_progress, "\t"))
	f.close()


func summary() -> String:
	return "saves: %d level(s) in progress, %d cleared, %d coins" % [
			saved_levels().size(), cleared_count(), currency(&"coins")]
