extends Minigame
## Far Future's "fight alone": the lawn holds one plant and nothing else. The
## damage it deals fills a bar, and a full bar turns it into the next plant on
## the list, stronger and faster than the last.
##
## Config (FutureMinigameProperties): position {m_x: column, m_y: row},
## plant_upgrade_list [{type, full_point, upgrade_details {damage_scale,
## shoot_interval_scale}}]. The last plant on the list has no bar.

var stage: int = 0
var points: float = 0.0
var plant: Plant = null
var _cell: Vector2i = Vector2i(0, 2)
## Zombies whose damage is already being counted.
var _watched: Dictionary = {}


func setup() -> void:
	var at: Dictionary = cfg(&"position", {})
	_cell = Vector2i(int(at.get("m_x", 0)), int(at.get("m_y", 2)))
	if _list().is_empty() or not board.in_bounds(_cell.y, _cell.x):
		push_warning("Fight alone: nothing to plant in %s" % runner.level.get("id", "?"))
		return
	_grow_into(0)


func _list() -> Array:
	return cfg(&"plant_upgrade_list", [])


## Replaces the plant with list entry `index`, scaled by its upgrade.
func _grow_into(index: int) -> void:
	var entry: Dictionary = _list()[index]
	if is_instance_valid(plant) and not plant.is_dead:
		board.vanish_plant(_cell.y, _cell.x)
	plant = board.place_preset_plant(StringName(entry.get("type", "peashooter")),
			_cell.y, _cell.x)
	stage = index
	points = 0.0
	if plant != null:
		var details: Dictionary = entry.get("upgrade_details", {})
		plant.damage_scale = float(details.get("damage_scale", 1.0))
		var interval := float(details.get("shoot_interval_scale", 1.0))
		plant.fire_rate_scale = 1.0 / maxf(interval, 0.01)
	notify_progress()


## Points needed to grow, or 0 on the last plant.
func full_point() -> float:
	if stage >= _list().size() - 1:
		return 0.0
	return maxf(float((_list()[stage] as Dictionary).get("full_point", 1)), 1.0)


func add_points(amount: float) -> void:
	var need := full_point()
	if need <= 0.0:
		return
	points += amount
	if points >= need:
		_grow_into(stage + 1)
	else:
		notify_progress()


func tick(_delta: float) -> void:
	for z in board.all_hostile_zombies():
		if not _watched.has(z):
			_watched[z] = true
			z.damaged.connect(_on_zombie_damaged)
			z.tree_exiting.connect(_watched.erase.bind(z))


func _on_zombie_damaged(_who: Character, amount: float, _remaining: float) -> void:
	add_points(amount)


## The lone plant cannot be dug up or joined by another.
func allows_shovel() -> bool:
	return false


func skips_seed_chooser() -> bool:
	return true


func placement_refusal(kind: StringName, _id: StringName, _row: int, _col: int) -> String:
	return tr("Survive with the only plant you've got") if kind == &"plant" else ""


## Losing the plant loses the level.
func is_failed() -> bool:
	return started and (plant == null or not is_instance_valid(plant) or plant.is_dead)


func start_word() -> String:
	return tr("FIGHT!")


func intro_text() -> String:
	return tr("Survive with the only plant you've got")


func describe() -> String:
	var need := full_point()
	if need <= 0.0:
		return ""
	return tr("Upgrade: ") + "%d%%" % int(100.0 * points / need)


func save_state() -> Dictionary:
	return {"stage": stage, "points": points}


func load_state(state: Dictionary) -> void:
	var saved := int(state.get("stage", 0))
	if saved != stage and saved < _list().size():
		_grow_into(saved)
	points = float(state.get("points", 0.0))
	notify_progress()
