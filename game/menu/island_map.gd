class_name IslandMap
extends Control
## One world drawn the way PVZGE draws it: floating islands strung along a
## path that scrolls sideways, with level nodes standing on them.
##
## The layout is data - data/native/worldmaps/<world>.json, written by
## tools/extract_worldmaps.py from PVZGE's WorldMap prefabs - so the island
## art, where each level sits and which island leads to which all come from
## PVZGE. A pack can ship a layout of its own and name it in its campaign's
## `world_map`.
##
## What PVZGE does and this follows (WorldMap.ts):
## - The map scrolls along x only. Islands and level nodes move 1:1, the
##   `Far` pieces behind them less and the `Near` ones in front more, each
##   by its own factor; the backdrop stays put.
## - Dragging flings the map and it coasts to a stop (velocity / 1.05 a
##   frame), the wheel nudges it, and the arrow buttons add a push of 20.
## - It stops when the first or the last island reaches the screen centre.
## - A level node shows IdleUnopen while locked, IdleUnfinish while open and
##   IdleFinished once cleared. A path is thin until the island it leaves is
##   finished, and an island's own pieces (Zomboss podiums) play
##   Idle_Locked, Idle_Unlock or Idle_Finished to match.
##
## Levels find their islands by id: a campaign that uses PVZGE's level ids
## (`egypt1`, `egypt2`...) lands on PVZGE's islands. One that does not has
## its levels laid on the level islands in path order instead, so a pack's
## five-level world still gets five islands.

signal node_pressed(level_id: StringName)

const LAYOUT_DIR := "res://data/native/worldmaps"
const NODES_FILE := "res://data/native/worldmaps/level_nodes.json"
## PVZGE's path piece is 330 units long at scale 1 (WorldMap.init).
const PATH_LENGTH := 330.0
## How far past the screen edge pieces keep animating (PVZGE setIslandActive).
const ACTIVE_SPAN := 1.5
const FRICTION := 1.05
const PUSH := 20.0

var layout: Dictionary = {}
var campaign: CampaignDef = null
## Scroll in PVZGE units, as WorldMap.mapX: 0 puts the map origin mid-screen.
var map_x: float = 0.0:
	set(value):
		map_x = clampf(value, -_max_x, -_min_x)
		_place_layers()
var velocity: float = 0.0

var _root: Node2D
var _layers: Array = []          ## [{node, factor, origin, pieces: [[node, x]]}]
var _islands: Dictionary = {}    ## island id -> layout entry
var _assigned: Dictionary = {}   ## island id -> level id
var _pieces_by_id: Dictionary = {}
var _level_islands: Array = []   ## island ids holding a campaign level, in order
var _paths: Node2D
var _nodes: Node2D
var _node_art: Dictionary = {}   ## level id -> Armature
var _buttons: Dictionary = {}    ## level id -> Button
var _min_x: float = 0.0
var _max_x: float = 0.0
var _dragging: bool = false
var _drag_moved: float = 0.0


## The layout a campaign names, or {} when it names none or it is missing.
static func layout_for(c: CampaignDef) -> Dictionary:
	if c == null or c.world_map == "":
		return {}
	var path := c.world_map
	if not path.ends_with(".json"):
		path = LAYOUT_DIR.path_join(path + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _level_nodes() -> Dictionary:
	if not FileAccess.file_exists(NODES_FILE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NODES_FILE))
	return parsed if parsed is Dictionary else {}


func _init(world: CampaignDef = null, data: Dictionary = {}) -> void:
	campaign = world
	layout = data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true


func _ready() -> void:
	_root = Node2D.new()
	_root.name = "Map"
	add_child(_root)
	for island in (layout.get("islands", []) as Array):
		_islands[String(island["id"])] = island
	_assign_levels()
	_build_layers()
	_build_levels()
	_measure()
	resized.connect(_on_resized)
	_on_resized()


func level_button(level_id: StringName) -> Button:
	return _buttons.get(level_id)


func has_level(level_id: StringName) -> bool:
	return _buttons.has(level_id)


## Puts a level's island in the middle of the screen.
func focus(level_id: StringName) -> void:
	for id in _assigned:
		if _assigned[id] == level_id:
			velocity = 0.0
			map_x = -float(_islands[id]["position"][0])
			return


## Marks the chosen node: it stands a little taller, as PvZ2's does.
func select(level_id: StringName) -> void:
	for id in _node_art:
		var art: Node2D = _node_art[id]
		art.get_parent().scale = Vector2.ONE * (1.15 if id == level_id else 1.0)


func scroll_by(amount: float) -> void:
	if (velocity < 0.0) != (amount < 0.0):
		velocity = 0.0
	velocity += amount


# --- levels on islands ----------------------------------------------------

## Which island holds which level. Islands are walked in path order from
## the world's first island, so both a matched and an ordered campaign come
## out in play order.
func _assign_levels() -> void:
	var order := _path_order()
	var by_level := {}
	for id in order:
		for level_id in (_islands[id].get("levels", []) as Array):
			if _islands[id]["kind"] == "level":
				by_level[StringName(level_id)] = id
	var matched := false
	for level_id in campaign.levels:
		if by_level.has(level_id):
			matched = true
			break
	if matched:
		for level_id in campaign.levels:
			if by_level.has(level_id) and not _assigned.has(by_level[level_id]):
				_assigned[by_level[level_id]] = level_id
	else:
		var i := 0
		for id in order:
			if i >= campaign.levels.size():
				break
			if _islands[id]["kind"] == "level":
				_assigned[id] = campaign.levels[i]
				i += 1
	for id in order:
		if _assigned.has(id):
			_level_islands.append(id)


## Island ids, breadth first along `next` from the starting island.
func _path_order() -> Array:
	var start := ""
	var starting: Array = layout.get("starting_levels", [])
	var pointed_at := {}
	for id in _islands:
		for n in (_islands[id].get("next", []) as Array):
			pointed_at[String(n)] = true
	for id in _islands:
		var island: Dictionary = _islands[id]
		if starting.any(func(l): return (island.get("levels", []) as Array).has(l)):
			start = id
			break
	if start == "":
		for id in _islands:
			if not pointed_at.has(id):
				start = id
				break
	var out: Array = []
	var seen := {}
	var queue: Array = [start] if start != "" else []
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if seen.has(id) or not _islands.has(id):
			continue
		seen[id] = true
		out.append(id)
		for n in (_islands[id].get("next", []) as Array):
			queue.append(String(n))
	# Islands nothing leads to (side areas) go last, left to right.
	var rest := _islands.keys().filter(func(id): return not seen.has(id))
	rest.sort_custom(func(a, b): return _islands[a]["position"][0] < _islands[b]["position"][0])
	return out + rest


## The islands that are part of this campaign's run: everything along the
## path up to the island of its last level.
func _in_play() -> Dictionary:
	var out := {}
	if _level_islands.is_empty():
		return out
	var last: String = _level_islands[-1]
	for id in _path_order():
		out[id] = true
		if id == last:
			break
	return out


func _state(id: String) -> StringName:
	if _assigned.has(id):
		var level_id: StringName = _assigned[id]
		if Saves.is_cleared(level_id):
			return &"finished"
		return &"unlocked" if WorldMap.is_level_open(campaign, level_id) else &"locked"
	# An island with no level of its own follows the one that leads to it.
	for other in _islands:
		if (_islands[other].get("next", []) as Array).has(id):
			return &"finished" if _state(other) == &"finished" else &"locked"
	return &"locked"


# --- building -------------------------------------------------------------

func _build_layers() -> void:
	for spec in (layout.get("layers", []) as Array):
		if spec.get("kind", "") == "levels":
			_paths = Node2D.new()
			_paths.name = "Paths"
			_root.add_child(_paths)
			_nodes = Node2D.new()
			_nodes.name = "Nodes"
			_root.add_child(_nodes)
			_layers.append({"node": null, "factor": 1.0, "origin": Vector2.ZERO, "pieces": [],
					"levels": true})
			continue
		var node := Node2D.new()
		_root.add_child(node)
		var layer := {"node": node, "factor": float(spec.get("factor", 0.0)),
				"origin": _vec(spec.get("origin", [0, 0])), "pieces": []}
		for p in (spec.get("pieces", []) as Array):
			var art := _piece(p)
			if art == null:
				continue
			node.add_child(art)
			layer["pieces"].append([art, art.position.x])
			_pieces_by_id[String(p.get("id", ""))] = art
		_layers.append(layer)
	if _nodes == null:
		_paths = Node2D.new()
		_root.add_child(_paths)
		_nodes = Node2D.new()
		_root.add_child(_nodes)
	_apply_island_states()


## One rig from a layout entry, placed by its transform and playing its
## animation. Null when the art is not there.
static func _piece(p: Dictionary) -> Armature:
	var art := Art.make_from({"bundle": p.get("bundle", ""), "armature": p.get("armature", ""),
			"scale": 1.0, "offset_x": 0.0, "offset_y": 0.0})
	if art == null:
		return null
	var x: Array = p.get("xform", [1, 0, 0, 1, 0, 0])
	art.transform = Transform2D(Vector2(x[0], x[1]), Vector2(x[2], x[3]), Vector2(x[4], x[5]))
	if p.has("color"):
		var c: Array = p["color"]
		art.modulate = Color(c[0], c[1], c[2], c[3])
	var anim := StringName(p.get("animation", ""))
	if anim == &"" and not art.animation_names().is_empty():
		anim = StringName(art.animation_names()[0])
	if anim != &"":
		art.play(anim, true, false, 0.0)
	var speed := float(p.get("time_scale", 1.0))
	if speed != 1.0:
		art.set_speed_scale(speed)
	return art


func _apply_island_states() -> void:
	for id in _islands:
		for piece_id in (_islands[id].get("displays", []) as Array):
			var art: Armature = _pieces_by_id.get(String(piece_id))
			if art == null:
				continue
			match _state(id):
				&"finished": art.play_first([&"Idle_Finished", &"Idle"])
				&"unlocked": art.play_first([&"Idle_Unlock", &"Idle"])
				_: art.play_first([&"Idle_Locked", &"Idle"])


func _build_levels() -> void:
	var prefabs := _level_nodes()
	var in_play := _in_play()
	# Paths first, so the nodes stand on them.
	for id in in_play:
		var from := _vec(_islands[id]["position"])
		var finished := _state(id) == &"finished"
		for n in (_islands[id].get("next", []) as Array):
			if not in_play.has(String(n)):
				continue
			var to := _vec(_islands[String(n)]["position"])
			for art in _prefab(prefabs.get("path", {}), _paths, from):
				var d := to - from
				var holder := art.get_parent() as Node2D
				holder.rotation = d.angle()
				# PVZGE sets the path's world scale, replacing the prefab's own.
				var own := maxf(art.transform.x.length(), 0.001)
				holder.scale = Vector2(d.length() / PATH_LENGTH / own, 1.0)
				art.play_first([&"Idle" if finished else &"Idle_Thin", &"Idle"])
	for id in in_play:
		var island: Dictionary = _islands[id]
		var at := _vec(island["position"])
		var state := _state(id)
		match String(island["kind"]):
			"level":
				if _assigned.has(id):
					_level_node(id, prefabs, at, state)
			"giftbox":
				for art in _prefab(prefabs.get("giftbox", {}), _nodes, at):
					art.play_first([&"Finished" if state == &"finished" else &"Idle"])
			"epic_portal":
				for art in _prefab(prefabs.get("epicPortal", {}), _nodes, at):
					art.play_first([&"Idle" if state == &"finished" else &"Idle_Locked", &"Idle"])


func _level_node(id: String, prefabs: Dictionary, at: Vector2, state: StringName) -> void:
	var island: Dictionary = _islands[id]
	var level_id: StringName = _assigned[id]
	var key := "normalNode"
	match String(island.get("appearance", "normal")):
		"gargantuar", "zomboss": key = "gargantuarNode"
		"minigame": key = "minigameNode"
	var prefab: Dictionary = prefabs.get(key, prefabs.get("normalNode", {}))
	var holder := Node2D.new()
	holder.name = "Node_%s" % level_id
	holder.position = at
	_nodes.add_child(holder)
	var arts := _prefab(prefab, holder, Vector2.ZERO)
	if not arts.is_empty():
		var art: Armature = arts[0]
		match state:
			&"finished": art.play_first([&"IdleFinished"])
			&"unlocked": art.play_first([&"IdleUnfinish"])
			_: art.play_first([&"IdleUnopen"])
		_node_art[level_id] = art
	else:
		_node_art[level_id] = holder

	if prefab.has("title"):
		var t: Dictionary = prefab["title"]
		var x: Array = t["xform"]
		var size := int(round(float(t.get("font_size", 40)) * absf(x[0])))
		var name_text := String(island.get("name", ""))
		if name_text == "" or not (island.get("levels", []) as Array).has(String(level_id)):
			name_text = str(campaign.index_of(level_id) + 1)
		var label := MenuUI.label(name_text, size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(size * 4, size * 2)
		label.position = Vector2(x[4], x[5]) - label.size * 0.5
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(label)

	var hit: Array = prefab.get("hit", [-28, -29, 56, 40])
	var b := Button.new()
	b.name = "Level_%s" % level_id
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.position = Vector2(hit[0], hit[1])
	b.size = Vector2(hit[2], hit[3])
	b.tooltip_text = MainMenu.level_name(level_id)
	var open := WorldMap.is_level_open(campaign, level_id)
	b.disabled = not open
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open else Control.CURSOR_ARROW
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	b.set_meta(&"state", _button_state(level_id, open))
	b.pressed.connect(func() -> void:
		if _drag_moved < 8.0:
			node_pressed.emit(level_id))
	holder.add_child(b)
	_buttons[level_id] = b


static func _button_state(level_id: StringName, open: bool) -> StringName:
	if not open:
		return &"locked"
	if Saves.has_save(level_id):
		return &"saved"
	if Saves.is_cleared(level_id):
		return &"cleared"
	return &"open"


## Instances a level-node prefab's rigs under `parent` at `at`, each in a
## holder of its own so callers can turn or stretch it. -> the rigs.
func _prefab(prefab: Dictionary, parent: Node2D, at: Vector2) -> Array:
	var out: Array = []
	for p in (prefab.get("pieces", []) as Array):
		var art := _piece(p)
		if art == null:
			continue
		var holder := Node2D.new()
		holder.position = at
		parent.add_child(holder)
		holder.add_child(art)
		out.append(art)
	return out


## Scroll limits: PVZGE lets every island that counts reach mid-screen.
func _measure() -> void:
	var xs: Array = []
	for id in _in_play():
		if _islands[id].get("affects_scroll", true):
			xs.append(float(_islands[id]["position"][0]))
	if xs.is_empty():
		for id in _islands:
			xs.append(float(_islands[id]["position"][0]))
	_min_x = xs.min() if not xs.is_empty() else 0.0
	_max_x = xs.max() if not xs.is_empty() else 0.0


# --- scrolling ------------------------------------------------------------

func _on_resized() -> void:
	# PVZGE's 1024x640 canvas, centred and scaled to fit the height.
	var s := size.y / 640.0 if size.y > 0.0 else MenuUI.PX
	_root.scale = Vector2(s, s)
	_root.position = size * 0.5
	_place_layers()


func _place_layers() -> void:
	if _root == null:
		return
	var reach := (size.x * 0.5 / maxf(_root.scale.x, 0.01)) * (ACTIVE_SPAN * 2.0)
	for layer in _layers:
		var x: float = map_x * float(layer["factor"])
		if layer.get("levels", false):
			_paths.position.x = x
			_nodes.position.x = x
			continue
		var node: Node2D = layer["node"]
		node.position = Vector2(layer["origin"].x + x, layer["origin"].y)
		# Only what is near the screen animates, as in PVZGE.
		for entry in layer["pieces"]:
			var art: Node2D = entry[0]
			var on: bool = absf(node.position.x + float(entry[1])) < reach or layer["factor"] == 0.0
			art.visible = on
			art.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _process(_delta: float) -> void:
	if velocity != 0.0 and not _dragging:
		map_x += velocity
		velocity /= FRICTION
		if absf(velocity) < 0.05:
			velocity = 0.0


func _gui_input(event: InputEvent) -> void:
	_scroll_input(event)


## Drags and wheel turns. Buttons on the nodes pass drags through, so a
## drag that starts on a node still scrolls.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var inside := get_global_rect().has_point(event.position)
		if event is InputEventMouseMotion and _dragging:
			_scroll_input(event)
		elif event is InputEventMouseButton and (inside or not event.pressed):
			_scroll_input(event)


func _scroll_input(event: InputEvent) -> void:
	var s := _root.scale.x if _root != null else 1.0
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _dragging:
				_dragging = true
				_drag_moved = 0.0
				velocity = 0.0
			elif not mb.pressed:
				_dragging = false
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
			velocity = 0.0
			map_x += 24.0
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
			velocity = 0.0
			map_x -= 24.0
	elif event is InputEventMouseMotion and _dragging:
		var dx: float = event.relative.x / s
		_drag_moved += absf(event.relative.x)
		velocity = dx
		map_x += dx


static func _vec(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO
