extends Minigame
## Beghouled: the lawn is a matching board. Every square holds a plant; the
## player swaps two neighbours to line up three or more of a kind, which
## vanish and are replaced. Zombies walk in all the while, and the level is
## won after enough matches.
##
## The seed bank holds upgrades instead of seeds: buying one, for its
## beghouled_cost in sun, turns every plant of its base kind on the board into
## the upgrade (peashooter into repeater) and keeps dealing the upgrade from
## then on. Each match drops sun to pay for them.
##
## Config (PVZGE's three Beghouled modules, folded together):
## matches_to_win, initial_plants, upgrade_map [{base_plant, upgraded_plant}],
## preset_plant_list [{plant_type}], stages [{spawn_delay, types
## [{zombie_type}]}], match_counts_to_stage_advance [{match_count,
## stage_number}].

## PVZGE's board is the first eight columns; the ninth is left for zombies
## to walk onto.
const BOARD_COLS := 8
const SUN_PER_MATCH := 50

var matches: int = 0
var goal: int = 100
## The kinds dealt onto the board: the initial plants, with upgrades bought
## replacing their base.
var dealing: Array[StringName] = []
var stage: int = 0

var _selected: Vector2i = Vector2i(-1, -1)
var _spawn_timer: float = 0.0
var _highlight: Node2D


func setup() -> void:
	goal = maxi(int(cfg(&"matches_to_win", 100)), 1)
	dealing.clear()
	for id in (cfg(&"initial_plants", []) as Array):
		if Data.plant(StringName(id)) != null:
			dealing.append(StringName(id))
	if dealing.is_empty():
		dealing = [&"peashooter", &"wallnut", &"sunflower"]
	_highlight = Node2D.new()
	_highlight.name = "BeghouledCursor"
	_highlight.z_index = 50
	_highlight.draw.connect(_draw_cursor)
	board.add_child(_highlight)
	_fill_board()
	_spawn_timer = _spawn_delay()


func _exit_tree() -> void:
	if is_instance_valid(_highlight):
		_highlight.queue_free()


func _cols() -> int:
	return mini(BOARD_COLS, board.cols)


func _cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in board.rows:
		if not board.is_row_plantable(row):
			continue
		for col in _cols():
			out.append(Vector2i(col, row))
	return out


## Fills every empty square, picking for each a kind that does not already
## line up with its neighbours, so the board starts with no free matches.
func _fill_board() -> void:
	for cell in _cells():
		if board.plant_at(cell.y, cell.x) == null:
			board.place_preset_plant(_deal_for(cell), cell.y, cell.x)


func _deal_for(cell: Vector2i) -> StringName:
	var options := dealing.duplicate()
	options.shuffle()
	for id in options:
		if not _would_match(cell, id):
			return id
	return options[0]


func _would_match(cell: Vector2i, id: StringName) -> bool:
	for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
		var run := 1
		for step in [1, -1]:
			var at: Vector2i = cell + dir * step
			while _kind_at(at) == id:
				run += 1
				at += dir * step
		if run >= 3:
			return true
	return false


func _kind_at(cell: Vector2i) -> StringName:
	if cell.x < 0 or cell.x >= _cols() or cell.y < 0 or cell.y >= board.rows:
		return &""
	var p = board.plant_at(cell.y, cell.x)
	return p.def.id if p != null and not p.is_dead else &""


# --- the player's swaps ---------------------------------------------------

## First click picks a plant up, a click on a neighbour swaps them. A swap
## that makes no match is refused and the plants stay put.
func handle_click(row: int, col: int) -> bool:
	if not started or col < 0 or col >= _cols():
		return false
	var cell := Vector2i(col, row)
	if _selected == Vector2i(-1, -1):
		if _kind_at(cell) == &"":
			return false
		_select(cell)
		return true
	if cell == _selected:
		_select(Vector2i(-1, -1))
		return true
	var from := _selected
	_select(Vector2i(-1, -1))
	if absi(cell.x - from.x) + absi(cell.y - from.y) != 1:
		if _kind_at(cell) != &"":
			_select(cell)
		return true
	try_swap(from, cell)
	return true


## Swaps two neighbouring squares if that lines up a match, then clears and
## refills until the board settles. Returns whether the swap happened.
func try_swap(a: Vector2i, b: Vector2i) -> bool:
	board.swap_plants(a.y, a.x, b.y, b.x)
	if _find_matches().is_empty():
		board.swap_plants(a.y, a.x, b.y, b.x)
		return false
	_resolve()
	return true


func _select(cell: Vector2i) -> void:
	_selected = cell
	_highlight.queue_redraw()


func _draw_cursor() -> void:
	if _selected == Vector2i(-1, -1):
		return
	var centre: Vector2 = board.grid_to_world(_selected.y, _selected.x)
	var size: Vector2 = board.cell_size
	_highlight.draw_rect(Rect2(centre - size * 0.5, size), Color(1, 0.9, 0.2), false, 4.0)


## Clears every line of three or more, counts each as a match, drops sun,
## refills, and repeats while the refill made new lines.
func _resolve() -> void:
	var combo := 0
	var found := _find_matches()
	while not found.is_empty() and combo < 20:
		for run in found:
			matches = mini(matches + 1, goal)
			var mid: Vector2i = run[run.size() / 2]
			board.drop_sun(board.grid_to_world(mid.y, mid.x))
			for cell in run:
				board.vanish_plant(cell.y, cell.x)
		combo += 1
		_fill_board()
		found = _find_matches()
	_update_stage()
	notify_progress()


## Every run of three or more of a kind, as lists of cells.
func _find_matches() -> Array:
	var runs: Array = []
	for row in board.rows:
		_scan(runs, Vector2i(0, row), Vector2i(1, 0))
	for col in _cols():
		_scan(runs, Vector2i(col, 0), Vector2i(0, 1))
	return runs


func _scan(runs: Array, start: Vector2i, dir: Vector2i) -> void:
	var run: Array[Vector2i] = []
	var kind := &""
	var at := start
	while at.x < _cols() and at.y < board.rows:
		var here := _kind_at(at)
		if here != &"" and here == kind:
			run.append(at)
		else:
			if run.size() >= 3:
				runs.append(run)
			run = [at]
			kind = here
		at += dir
	if run.size() >= 3 and kind != &"":
		runs.append(run)


# --- upgrades ------------------------------------------------------------

func seeds() -> Array:
	var out: Array = []
	for e in (cfg(&"preset_plant_list", []) as Array):
		var id := StringName(e.get("plant_type", "")) if e is Dictionary else StringName(e)
		var def := Data.plant(id)
		if def != null:
			out.append({"kind": &"plant", "id": id,
					"cost": int(def.stat(&"beghouled_cost", 1000))})
	return out


func use_seed(id: StringName) -> bool:
	var base := _base_of(id)
	if base == &"":
		return false
	# Bought once; the bank charges and recharges it like a planted packet.
	var i := dealing.find(base)
	if i >= 0:
		dealing[i] = id
	elif not dealing.has(id):
		dealing.append(id)
	for cell in _cells():
		if _kind_at(cell) == base:
			board.vanish_plant(cell.y, cell.x)
			board.place_preset_plant(id, cell.y, cell.x)
	_resolve()
	return true


## The plant `upgrade` replaces on the board, from the level's upgrade map.
func _base_of(upgrade: StringName) -> StringName:
	for e in (cfg(&"upgrade_map", []) as Array):
		if e is Dictionary and StringName(e.get("upgraded_plant", "")) == upgrade:
			var base := StringName(e.get("base_plant", ""))
			if dealing.has(base):
				return base
	return &""


# --- zombies -------------------------------------------------------------

func tick(delta: float) -> void:
	if not started or matches >= goal:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _spawn_delay()
	var types: Array = _stage().get("types", [])
	if types.is_empty():
		return
	var pick = types.pick_random()
	var id := StringName(pick.get("zombie_type", "")) if pick is Dictionary else StringName(pick)
	board.spawn_zombie(id, randi() % board.rows)


func _stage() -> Dictionary:
	var stages: Array = cfg(&"stages", [])
	if stages.is_empty():
		return {}
	return stages[clampi(stage, 0, stages.size() - 1)]


func _spawn_delay() -> float:
	return maxf(float(_stage().get("spawn_delay", 4.0)), 0.5)


func _update_stage() -> void:
	for e in (cfg(&"match_counts_to_stage_advance", []) as Array):
		if e is Dictionary and matches >= int(e.get("match_count", 0)):
			stage = maxi(stage, int(e.get("stage_number", 0)))


# --- rules ----------------------------------------------------------------

## The zombies keep coming until the goal is reached; then the lawn only has
## to be cleared.
func holds_waves() -> bool:
	return matches < goal


func skips_seed_chooser() -> bool:
	return true


func drops_sky_sun() -> bool:
	return false


func allows_shovel() -> bool:
	return false


func start_word() -> String:
	return tr("SWAP!")


func intro_text() -> String:
	return tr("Match three plants in a row to beat the zombies")


func is_met() -> bool:
	return matches >= goal


func describe() -> String:
	return tr("Matches %d / %d") % [matches, goal]


func save_state() -> Dictionary:
	return {"matches": matches, "stage": stage, "dealing": dealing.map(func(i): return String(i))}


func load_state(state: Dictionary) -> void:
	matches = int(state.get("matches", 0))
	stage = int(state.get("stage", 0))
	var saved: Array = state.get("dealing", [])
	if not saved.is_empty():
		dealing.clear()
		for id in saved:
			dealing.append(StringName(id))
	notify_progress()
