extends Minigame
## I, Zombie: the sides swap. The plants stand on the left and a brain waits
## at the end of every row; the player buys zombies with sun and sets them
## down right of the red line. A zombie that gets through eats its row's
## brain, and the level is won once every brain is eaten. Eaten sunflowers
## leave sun behind to buy more. Run out of sun and zombies with brains
## still left, and the level is lost.
##
## This mode is the project's own, not a PVZGE module.
##
## Config: starting_sun (default 150), place_column (the red line: zombies
## go in this column or right of it, default 5), zombies (the packets, as ids
## or {type, cost}), plants ([{type, row, col}] placed as given) or
## plant_pool with plant_columns (random plants filling the left columns),
## sun_plants ({plant: sun it drops when eaten}, default sunflower 150).

const DEFAULT_ZOMBIES := ["tutorial", "tutorial_armor1", "tutorial_armor2"]
const DEFAULT_POOL := ["peashooter", "sunflower", "wallnut", "potatomine", "snowpea"]
const SUN_TOKEN := 50

## Rows whose brain is still there.
var brains: Array[int] = []
var _marks: Node2D


func setup() -> void:
	board.sun = int(cfg(&"starting_sun", 150))
	board.sun_changed.emit(board.sun)
	_lay_out_plants()
	brains.clear()
	for row in board.rows:
		if board.is_row_plantable(row):
			brains.append(row)
	board.plant_died.connect(_on_plant_died)
	_marks = Node2D.new()
	_marks.name = "IZombieMarks"
	_marks.z_index = 40
	_marks.draw.connect(_draw_marks)
	board.add_child(_marks)


func _exit_tree() -> void:
	if is_instance_valid(_marks):
		_marks.queue_free()


func _lay_out_plants() -> void:
	var given: Array = cfg(&"plants", [])
	for e in given:
		if e is Dictionary:
			board.place_preset_plant(StringName(e.get("type", "")),
					int(e.get("row", 0)), int(e.get("col", 0)))
	if not given.is_empty():
		return
	var pool: Array = cfg(&"plant_pool", DEFAULT_POOL)
	pool = pool.filter(func(id): return Data.plant(StringName(id)) != null)
	if pool.is_empty():
		return
	for row in board.rows:
		if not board.is_row_plantable(row):
			continue
		for col in mini(int(cfg(&"plant_columns", 4)), place_column()):
			board.place_preset_plant(StringName(pool.pick_random()), row, col)


func place_column() -> int:
	return clampi(int(cfg(&"place_column", 5)), 1, board.cols - 1)


## The packets: zombies, priced from their own sun cost unless told.
func seeds() -> Array:
	var out: Array = []
	for e in (cfg(&"zombies", DEFAULT_ZOMBIES) as Array):
		var id := StringName(e.get("type", "")) if e is Dictionary else StringName(e)
		var def := Data.zombie(id)
		if def == null:
			continue
		var cost := int(e.get("cost", def.stat(&"sun_cost", 100))) if e is Dictionary \
				else int(def.stat(&"sun_cost", 100))
		out.append({"kind": &"zombie", "id": id, "cost": cost})
	return out


## Zombies only, and only right of the red line.
func placement_refusal(kind: StringName, _id: StringName, _row: int, col: int) -> String:
	if not started:
		return ""
	if kind != &"zombie":
		return tr("Only zombies can be placed")
	if col < place_column():
		return tr("Place zombies right of the red line")
	return ""


func _on_plant_died(p: Plant) -> void:
	if p.def == null:
		return
	var sun_plants: Dictionary = cfg(&"sun_plants", {"sunflower": 150})
	var amount := int(sun_plants.get(String(p.def.id), 0))
	for i in amount / SUN_TOKEN:
		board.drop_sun(p.position + Vector2((i - 1) * 18.0, 0))


## A zombie at the house eats its row's brain and is done.
func handle_zombie_at_house(zombie: Node) -> bool:
	var row: int = zombie.row
	if brains.has(row):
		brains.erase(row)
		Audio.play(&"zombie.eat", zombie.position)
		_marks.queue_redraw()
		notify_progress()
	zombie.die()
	return true


func _draw_marks() -> void:
	# The red line, and a brain at the end of every row still holding one.
	var x: float = board.grid_to_world(0, place_column()).x - board.cell_size.x * 0.5
	var top: float = board.grid_to_world(0, 0).y - board.cell_size.y * 0.5
	var bottom: float = board.grid_to_world(board.rows - 1, 0).y + board.cell_size.y * 0.5
	_marks.draw_line(Vector2(x, top), Vector2(x, bottom), Color(0.9, 0.15, 0.15, 0.8), 4.0)
	for row in brains:
		var at := Vector2(board.house_x() + board.cell_size.x * 0.2, board.grid_to_world(row, 0).y)
		_marks.draw_circle(at, board.cell_size.x * 0.22, Color("f0a3b5"))
		_marks.draw_arc(at, board.cell_size.x * 0.22, 0.0, TAU, 20, Color("a8546a"), 2.0)


func cheapest() -> int:
	var low := 1 << 30
	for s in seeds():
		low = mini(low, int(s["cost"]))
	return low


func holds_waves() -> bool:
	return true


func skips_seed_chooser() -> bool:
	return true


func drops_sky_sun() -> bool:
	return false


func allows_shovel() -> bool:
	return false


func allows_plant_food() -> bool:
	return false


func is_met() -> bool:
	return brains.is_empty()


## No zombies left walking, no sun lying about, and not enough to buy one.
func is_failed() -> bool:
	if not started or brains.is_empty() or board.zombie_count() > 0:
		return false
	if board.sun >= cheapest():
		return false
	for s in board._suns.get_children():
		if s is SunToken and not s.is_collected():
			return false
	return true


func start_word() -> String:
	return tr("BRAINS!")


func intro_text() -> String:
	return tr("Eat all the brains")


func describe() -> String:
	return tr("Brains left %d") % brains.size()


func save_state() -> Dictionary:
	return {"brains": brains.duplicate()}


func load_state(state: Dictionary) -> void:
	brains.clear()
	for r in (state.get("brains", []) as Array):
		brains.append(int(r))
	if is_instance_valid(_marks):
		_marks.queue_redraw()
	notify_progress()
