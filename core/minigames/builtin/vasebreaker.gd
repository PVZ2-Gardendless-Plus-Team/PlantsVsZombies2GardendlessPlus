extends Minigame
## Vasebreaker: the right of the lawn is filled with vases. Clicking one
## breaks it open - a plant goes onto the belt to be planted, a zombie climbs
## out, or sun or plant food spills. The level is won once every vase is
## broken and no zombie is left standing.
##
## Green vases always hold a plant and purple ones a zombie (a gargantuar by
## default), so the player can plan; brown ones could be anything.
##
## Config (PVZGE's VaseBreakerPresetProperties): min_column_index,
## max_column_index, vases [{plant_type_name | zombie_type_name |
## collectable_type_name, count}], num_colored_plant_vases,
## num_colored_zombie_vases, zombie_vases_zombie_type, sun_vases_sun_value,
## plantfood_vases_plantfood_count.

## What a vase is drawn as when its rig is missing.
const COLORS := {&"brown": Color("8a5a2b"), &"green": Color("4e9a3a"),
		&"purple": Color("7b3fa0")}

## Vector2i(col, row) -> {color, drop, param, node}
var vases: Dictionary = {}


func setup() -> void:
	_fill()


## Lays the vases out as PVZGE's module_SetLevelVases does: every lawn cell
## in the column range, shuffled, filled from the list in order until it
## runs out. The coloured vases are dealt first.
func _fill() -> void:
	var cells: Array[Vector2i] = []
	for row in board.rows:
		if not board.is_row_plantable(row):
			continue
		for col in range(int(cfg(&"min_column_index", 4)), int(cfg(&"max_column_index", 8)) + 1):
			if board.in_bounds(row, col):
				cells.append(Vector2i(col, row))
	cells.shuffle()
	var contents: Array = (cfg(&"vases", []) as Array).duplicate(true)
	var green := int(cfg(&"num_colored_plant_vases", 0))
	var purple := int(cfg(&"num_colored_zombie_vases", 0))
	for cell in cells:
		var vase := {}
		if purple > 0:
			purple -= 1
			vase = {"color": &"purple", "drop": &"zombie",
					"param": String(cfg(&"zombie_vases_zombie_type", "vase_gargantuar"))}
		else:
			var entry: Dictionary = {}
			for e in contents:
				if e is Dictionary and int(e.get("count", 0)) > 0:
					entry = e
					break
			if entry.is_empty():
				break
			entry["count"] = int(entry["count"]) - 1
			vase = _vase_for(entry)
			if vase.is_empty():
				continue
			if vase["drop"] == &"plant" and green > 0:
				green -= 1
				vase["color"] = &"green"
		_add(cell, vase)


func _vase_for(entry: Dictionary) -> Dictionary:
	if entry.get("plant_type_name"):
		return {"color": &"brown", "drop": &"plant", "param": String(entry["plant_type_name"])}
	if entry.get("zombie_type_name"):
		return {"color": &"brown", "drop": &"zombie", "param": String(entry["zombie_type_name"])}
	match String(entry.get("collectable_type_name", "")):
		"sun":
			return {"color": &"brown", "drop": &"sun",
					"param": int(cfg(&"sun_vases_sun_value", 50))}
		"plantfood":
			return {"color": &"brown", "drop": &"plantfood",
					"param": int(cfg(&"plantfood_vases_plantfood_count", 1))}
	return {}


func _add(cell: Vector2i, vase: Dictionary) -> void:
	var node := Node2D.new()
	node.name = "Vase_%d_%d" % [cell.x, cell.y]
	node.position = board.grid_to_world(cell.y, cell.x)
	node.z_index = board.lane_z(cell.y, 0)
	var art: Node2D = Art.make(&"vase", StringName(vase["color"]))
	if art != null:
		node.add_child(art)
		if art.has_method("play"):
			art.play(&"Idle")
	else:
		var tint: Color = COLORS.get(StringName(vase["color"]), COLORS[&"brown"])
		node.draw.connect(func(): _draw_vase(node, tint))
	board.add_child(node)
	vase["node"] = node
	vases[cell] = vase
	notify_progress()


func _draw_vase(node: Node2D, tint: Color) -> void:
	var w: float = board.cell_size.x * 0.32
	var h: float = board.cell_size.y * 0.42
	node.draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.55, -h), Vector2(w * 0.55, -h), Vector2(w, -h * 0.35),
		Vector2(w * 0.8, h * 0.4), Vector2(-w * 0.8, h * 0.4), Vector2(-w, -h * 0.35)]), tint)
	node.draw_rect(Rect2(-w * 0.6, -h - 6, w * 1.2, 8), tint.darkened(0.3))


func _exit_tree() -> void:
	for vase in vases.values():
		if is_instance_valid(vase.get("node")):
			vase["node"].queue_free()


## Nothing grows where a vase stands.
func placement_refusal(_kind: StringName, _id: StringName, row: int, col: int) -> String:
	return "a vase is in the way" if vases.has(Vector2i(col, row)) else ""


func handle_click(row: int, col: int) -> bool:
	if not started:
		return false
	return break_vase(row, col)


## Breaks the vase in this cell and lets out what it holds.
func break_vase(row: int, col: int) -> bool:
	var cell := Vector2i(col, row)
	if not vases.has(cell):
		return false
	var vase: Dictionary = vases[cell]
	vases.erase(cell)
	var at: Vector2 = board.grid_to_world(row, col)
	if is_instance_valid(vase.get("node")):
		vase["node"].queue_free()
	match StringName(vase["drop"]):
		&"plant":
			var bank = runner.seed_bank
			if bank is ConveyorSeedBank:
				bank.add_packet(StringName(vase["param"]))
		&"zombie":
			board.spawn_zombie_at(StringName(vase["param"]), row, at.x)
		&"sun":
			for i in maxi(1, int(vase["param"]) / 25):
				board.drop_sun(at)
		&"plantfood":
			for i in maxi(1, int(vase["param"])):
				board.drop_plant_food(at)
	notify_progress()
	return true


func skips_seed_chooser() -> bool:
	return true


func uses_belt() -> bool:
	return true


func drops_sky_sun() -> bool:
	return false


func is_met() -> bool:
	return vases.is_empty()


func describe() -> String:
	return tr("Vases left: %d") % vases.size() if not vases.is_empty() else ""


func save_state() -> Dictionary:
	var out: Array = []
	for cell in vases:
		var v: Dictionary = vases[cell]
		out.append({"col": cell.x, "row": cell.y, "color": String(v["color"]),
				"drop": String(v["drop"]), "param": v["param"]})
	return {"vases": out}


func load_state(state: Dictionary) -> void:
	_exit_tree()
	vases.clear()
	for v in (state.get("vases", []) as Array):
		if v is Dictionary:
			_add(Vector2i(int(v.get("col", 0)), int(v.get("row", 0))), {
				"color": StringName(v.get("color", "brown")),
				"drop": StringName(v.get("drop", "sun")), "param": v.get("param")})
