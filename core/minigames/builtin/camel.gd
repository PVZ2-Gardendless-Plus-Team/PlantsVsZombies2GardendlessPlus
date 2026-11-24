extends Minigame
## Ancient Egypt's camel matching game: every touch camel carries a plank with
## a symbol on its back, face down. Tapping a camel turns its plank over; turn
## over two with the same symbol and both camels fall, while two that differ
## turn back after a moment. The mummies inside walk on.
##
## Config (CamelMinigameProperties): card_types_used (how many symbols),
## card_matching_time (seconds before a match clears), card_no_match_time
## (seconds before a miss turns back), combo_counter (three matches in a row
## blast four squares).

const SYMBOL_COLORS: Array[Color] = [
	Color("e8483f"), Color("3f8de8"), Color("f2d23a"), Color("4fc95a"),
	Color("b25ae0"), Color("f28a2e"), Color("ffffff"), Color("2fd6d0"),
]

## The camels turned face up and waiting to be compared.
var flipped: Array = []
var matches: int = 0
var combo: int = 0
## Seconds until the face-up pair is settled.
var _settle: float = 0.0
## camel -> its plank
var _planks: Dictionary = {}


func symbol_count() -> int:
	return clampi(int(cfg(&"card_types_used", 8)), 1, SYMBOL_COLORS.size())


static func is_touch_camel(z: Node) -> bool:
	return z is Zombie and z.def != null and String(z.def.id).ends_with("_touch") \
			and String(z.def.id).contains("camel")


func tick(delta: float) -> void:
	for z in board.all_hostile_zombies():
		if not _planks.has(z) and is_touch_camel(z):
			_deal(z)
	for z in _planks.keys():
		if not is_instance_valid(z) or z.is_dead:
			_planks.erase(z)
			flipped.erase(z)
	if flipped.size() >= 2:
		_settle -= delta
		if _settle <= 0.0:
			_settle_pair()


## Gives a camel its face-down plank and a symbol.
func _deal(z: Zombie) -> void:
	var plank := Node2D.new()
	plank.name = "CamelPlank"
	plank.set_meta(&"symbol", randi() % symbol_count())
	plank.set_meta(&"face_up", false)
	plank.position = Vector2(0, -board.cell_size.y * 0.55)
	plank.draw.connect(_draw_plank.bind(plank))
	z.add_child(plank)
	_planks[z] = plank


func symbol_of(z: Zombie) -> int:
	var plank: Node2D = _planks.get(z)
	return int(plank.get_meta(&"symbol")) if plank != null else -1


## For tests and mods: deal a camel a known symbol.
func set_symbol(z: Zombie, symbol: int) -> void:
	if not _planks.has(z):
		_deal(z)
	_planks[z].set_meta(&"symbol", symbol)


func is_face_up(z: Zombie) -> bool:
	var plank: Node2D = _planks.get(z)
	return plank != null and bool(plank.get_meta(&"face_up"))


func _set_face(z: Zombie, up: bool) -> void:
	var plank: Node2D = _planks.get(z)
	if plank != null:
		plank.set_meta(&"face_up", up)
		plank.queue_redraw()


func _draw_plank(plank: Node2D) -> void:
	var size := Vector2(board.cell_size.x * 0.6, board.cell_size.y * 0.35)
	var rect := Rect2(-size * 0.5, size)
	plank.draw_rect(rect, Color("8a5a2b"))
	plank.draw_rect(rect, Color("4a2e12"), false, 2.0)
	if bool(plank.get_meta(&"face_up")):
		var color: Color = SYMBOL_COLORS[int(plank.get_meta(&"symbol")) % SYMBOL_COLORS.size()]
		plank.draw_circle(Vector2.ZERO, size.y * 0.38, color)


## A tap on a camel turns its plank over.
func handle_click(row: int, col: int) -> bool:
	if not started:
		return false
	var best: Zombie = null
	var best_d := INF
	var x: float = board.grid_to_world(row, col).x
	for z in _planks:
		if z.row != row or is_face_up(z):
			continue
		var d := absf(z.position.x - x)
		if d < best_d and d <= board.cell_size.x * 0.75:
			best = z
			best_d = d
	if best == null:
		return false
	return flip(best)


## Turns `z` face up. Two face up are compared once the pair settles.
func flip(z: Zombie) -> bool:
	if flipped.size() >= 2 or not _planks.has(z) or is_face_up(z):
		return false
	_set_face(z, true)
	flipped.append(z)
	if flipped.size() == 2:
		var same := symbol_of(flipped[0]) == symbol_of(flipped[1])
		_settle = float(cfg(&"card_matching_time", 0.5)) if same \
				else float(cfg(&"card_no_match_time", 1.5))
	return true


func _settle_pair() -> void:
	var a: Zombie = flipped[0]
	var b: Zombie = flipped[1]
	flipped.clear()
	if symbol_of(a) == symbol_of(b):
		for z in [a, b]:
			_planks.erase(z)
			z.die()
		matches += 1
		_add_combo()
	else:
		_set_face(a, false)
		_set_face(b, false)
		combo = 0
	notify_progress()


## With the combo counter on, three matches in a row blast four squares:
## the second and fourth rows' first squares and two random ones further up.
func _add_combo() -> void:
	if not bool(cfg(&"combo_counter", false)):
		return
	combo += 1
	if combo < 3:
		return
	combo = 0
	var cells: Array[Vector2i] = []
	for col in range(2, mini(9, board.cols)):
		for row in board.rows:
			cells.append(Vector2i(col, row))
	cells.shuffle()
	for cell in [Vector2i(0, 1), Vector2i(0, 3)] + cells.slice(0, 2):
		var at: Vector2 = board.grid_to_world(cell.y, cell.x)
		for z in board.all_hostile_zombies():
			if absi(z.row - cell.y) <= 1 and absf(z.position.x - at.x) <= board.cell_size.x * 1.5:
				z.take_damage(1800.0)


func start_word() -> String:
	return tr("MATCH!")


func intro_text() -> String:
	return tr("Match symbols to destroy the zombies")


func describe() -> String:
	return tr("Matches %d") % matches if matches > 0 else ""


func save_state() -> Dictionary:
	return {"matches": matches}


func load_state(state: Dictionary) -> void:
	matches = int(state.get("matches", 0))
	notify_progress()
