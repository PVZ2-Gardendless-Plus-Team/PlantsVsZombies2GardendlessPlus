class_name WorldChooser
extends Control
## PVZGE's world chooser: the worlds as globes in a row that slides
## sideways, the one in the middle full size over a turning glow and the
## rest shrinking with their distance from it (WorldMapChooser.ts).
##
## Each globe is a world campaign. One whose `world_map` is a PVZGE world
## shows that world's globe, anything else shows PVZGE's "Unknown" one. A
## world that is not open yet is greyed out and cannot be entered.

signal world_chosen(campaign_id: StringName)
signal back_requested

const LAYOUT := "res://data/native/worldmaps/chooser.json"
## Globe spacing and the shrink curve, in PVZGE canvas pixels.
const SHRINK_SPAN := 600.0
const MIN_SCALE := 0.3
const SLIDE_TIME := 0.25

var start_campaign: StringName = &""

var _worlds: Array[CampaignDef] = []
var _layout: Dictionary = {}
var _index: int = 0
var _x: float = 0.0          ## slide position, in globe steps
var _tween: Tween
var _root: Node2D
var _row: Node2D
var _globes: Array = []      ## Node2D per world
var _name: Label
var _hint: Label
var _spacing: float = 264.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_worlds = Data.world_campaigns()
	if FileAccess.file_exists(LAYOUT):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
		if parsed is Dictionary:
			_layout = parsed
	_build()
	for i in _worlds.size():
		if _worlds[i].id == start_campaign:
			_index = i
	_x = _index
	_update()
	MenuUI.music(&"music.worldmap")


func current_world() -> CampaignDef:
	return _worlds[_index] if _index < _worlds.size() else null


func _build() -> void:
	add_child(MenuUI.space_backdrop())
	_root = Node2D.new()
	add_child(_root)
	var mid: Variant = _layout.get("mid")
	if mid is Dictionary:
		var glow := IslandMap._piece(mid)
		if glow != null:
			_root.add_child(glow)
	_row = Node2D.new()
	_root.add_child(_row)

	var icons := {}
	var unknown: Dictionary = {}
	var layout_scale := float(_layout.get("scale", 0.4))
	var icon_list: Array = _layout.get("icons", [])
	if icon_list.size() > 1:
		_spacing = absf(float(icon_list[1]["x"]) - float(icon_list[0]["x"])) * layout_scale
	for icon in icon_list:
		if String(icon.get("world", "")) != "":
			icons[String(icon["world"])] = icon
		if String(icon.get("id", "")) == "Unknown":
			unknown = icon

	for i in _worlds.size():
		var world := _worlds[i]
		var holder := Node2D.new()
		_row.add_child(holder)
		var icon: Dictionary = icons.get(world.world_map, unknown)
		var piece: Variant = icon.get("piece")
		var art: Armature = IslandMap._piece(piece) if piece is Dictionary else null
		if art != null:
			art.transform = Transform2D.IDENTITY.scaled(Vector2(layout_scale, layout_scale))
			holder.add_child(art)
		else:
			var dot := ColorRect.new()
			dot.color = world.map_color
			dot.size = Vector2(160, 160)
			dot.position = -dot.size * 0.5
			holder.add_child(dot)
		if not WorldMap.is_world_open(world):
			# WorldMapIcon.judgeIsUnlocked: 150/255 grey.
			holder.modulate = Color(0.59, 0.59, 0.59)
		var hit := Button.new()
		hit.name = "World_%s" % world.id
		hit.flat = true
		hit.size = Vector2(220, 220)
		hit.position = -hit.size * 0.5
		for style in ["normal", "hover", "pressed", "focus", "disabled"]:
			hit.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		hit.pressed.connect(_on_globe.bind(i))
		holder.add_child(hit)
		_globes.append(holder)

	_name = MenuUI.label("", 40)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_color_override("font_color", MenuUI.TITLE_GOLD)
	_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	add_child(_name)
	_hint = MenuUI.label("", MenuUI.BODY_SIZE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)

	var back := MenuUI.icon_button("ReturnUp", "ReturnDown", Vector2(67, 67),
			back_requested.emit, "Back")
	back.name = "Back"
	back.position = Vector2(45, 43) - back.custom_minimum_size * 0.5
	add_child(back)
	for left in [true, false]:
		var b := MenuUI.button("" if MenuUI.has_sprite("DeltaArrow") else ("<" if left else ">"),
				_move.bind(-1 if left else 1), Vector2(44, 44), &"purple_big", 0.3)
		b.set_anchors_and_offsets_preset(
				Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
		b.offset_left = 8.0 if left else -52.0
		b.offset_right = b.offset_left + 44.0
		b.offset_top = -52.0
		b.offset_bottom = -8.0
		var arrow := MenuUI.texture("DeltaArrow", 0.3)
		if arrow != null:
			var img := arrow.get_image()
			img.rotate_90(COUNTERCLOCKWISE if left else CLOCKWISE)
			var icon := TextureRect.new()
			icon.texture = ImageTexture.create_from_image(img)
			icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			icon.grow_horizontal = Control.GROW_DIRECTION_BOTH
			icon.grow_vertical = Control.GROW_DIRECTION_BOTH
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(icon)
		add_child(b)
	resized.connect(_update)


func _move(direction: int) -> void:
	_go_to(clampi(_index + direction, 0, _worlds.size() - 1))


func _go_to(i: int) -> void:
	if i == _index and _tween == null:
		return
	_index = i
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_x = v
		_update(), _x, float(i), SLIDE_TIME).set_trans(Tween.TRANS_SINE)
	_tween.finished.connect(func() -> void: _tween = null)
	MenuUI.click()


func _on_globe(i: int) -> void:
	if i != _index:
		_go_to(i)
		return
	enter()


## Opens the world in the middle, if it is open.
func enter() -> bool:
	var world := current_world()
	if world == null or not WorldMap.is_world_open(world):
		return false
	world_chosen.emit(world.id)
	return true


func _update() -> void:
	if _root == null:
		return
	var s := size.y / 640.0 if size.y > 0.0 else MenuUI.PX
	_root.scale = Vector2(s, s)
	_root.position = size * 0.5
	for i in _globes.size():
		var globe: Node2D = _globes[i]
		var dx := (i - _x) * _spacing
		globe.position = Vector2(dx, 0)
		var k := maxf(1.0 - absf(dx) / SHRINK_SPAN, MIN_SCALE)
		globe.scale = Vector2(k, k)
	# Nearer globes over farther ones.
	var order := range(_globes.size())
	order.sort_custom(func(a, b): return absf(a - _x) > absf(b - _x))
	for n in order.size():
		_row.move_child(_globes[order[n]], n)
	var world := current_world()
	if world == null:
		_name.text = "No worlds"
		return
	_name.text = tr(world.display_name)
	# Under the globe rather than on it, clear of the corner arrows.
	var name_y := size.y - 150.0
	_name.position = Vector2(0, name_y)
	_name.size = Vector2(size.x, 56)
	var hint := tr(world.description)
	if not WorldMap.is_world_open(world):
		var gate := Data.campaign(world.unlock_after)
		hint = tr("Finish %s to open this world") % (
				tr(gate.display_name) if gate != null else world.unlock_after)
	_hint.text = hint
	_hint.position = Vector2(size.x * 0.2, name_y + 54)
	_hint.size = Vector2(size.x * 0.6, 60)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
	elif event.is_action_pressed(&"ui_left"):
		_move(-1)
	elif event.is_action_pressed(&"ui_right"):
		_move(1)
	elif event.is_action_pressed(&"ui_accept"):
		enter()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(1)
