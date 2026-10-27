class_name WorldMap
extends Control
## Level select: one page per world, its levels as nodes along a path.
##
## Worlds are campaigns, so a pack that adds a campaign gets a page here with
## no code - and `order`, `unlock_after` and `map_color` on the campaign decide
## where it sits, when it opens and how it looks. Levels open one at a time as
## the one before is cleared.

signal level_chosen(level_id: StringName)
signal back_requested

const NODE_SIZE := Vector2(76, 76)
## Levels per row before the path doubles back.
const PER_ROW := 8
const MAP_MARGIN := Vector2(110, 90)

## Node colour by state: locked, open, cleared, or part-played.
const STATE_COLORS := {
	&"locked": Color(0.32, 0.32, 0.32),
	&"open": Color(0.42, 0.75, 0.98),   # PVZGE's blue level domes
	&"cleared": Color(1.0, 0.82, 0.25),
	&"saved": Color(0.55, 0.85, 1.0),
}

## World to show first. Empty picks the furthest open world.
var start_campaign: StringName = &""

var _worlds: Array[CampaignDef] = []
var _index: int = 0
var _selected: StringName = &""

var _title: Label
var _progress: Label
var _coins: Label
var _gems: Label
var _prev: Button
var _next: Button
var _map: ColorRect
var _path: Line2D
var _nodes: Dictionary = {}     ## level id -> Button
var _lock_label: Label
var _card_title: Label
var _card_status: Label
var _play: Button
var _restart: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_worlds = Data.world_campaigns()
	_build()
	_index = _initial_index()
	_show_world()
	MenuUI.music(&"music.worldmap")


# --- progress -----------------------------------------------------------

## A world opens once the campaign it names in `unlock_after` is finished.
## Naming a campaign that is not loaded (its mod is off) leaves it open
## rather than stranding the player.
static func is_world_open(campaign: CampaignDef) -> bool:
	if campaign.unlock_after == &"":
		return true
	var gate := Data.campaign(campaign.unlock_after)
	return gate == null or gate.is_complete(Saves.is_cleared)


static func is_level_open(campaign: CampaignDef, level_id: StringName) -> bool:
	return is_world_open(campaign) and campaign.is_level_unlocked(level_id, Saves.is_cleared)


func current_world() -> CampaignDef:
	return _worlds[_index] if _index < _worlds.size() else null


func selected_level() -> StringName:
	return _selected


func level_button(level_id: StringName) -> Button:
	return _nodes.get(level_id)


func _initial_index() -> int:
	for i in _worlds.size():
		if _worlds[i].id == start_campaign:
			return i
	# The furthest open world that still has something left to play.
	var pick := 0
	for i in _worlds.size():
		if is_world_open(_worlds[i]):
			pick = i
			if not _worlds[i].is_complete(Saves.is_cleared):
				break
	return pick


# --- building -----------------------------------------------------------

func _build() -> void:
	# PVZGE's worldMapScene: the teal sky, its square buttons along the top
	# left, the coin and gem counters top right, and purple arrows in the
	# bottom corners to step between worlds.
	add_child(MenuUI.space_backdrop())

	_map = ColorRect.new()
	_map.color = Color.TRANSPARENT
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.offset_top = 128
	_map.offset_bottom = -112
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	_path = Line2D.new()
	_path.width = 10.0
	_path.default_color = Color(0.75, 0.95, 1.0, 0.7)
	_path.joint_mode = Line2D.LINE_JOINT_ROUND
	_map.add_child(_path)
	_map.resized.connect(_layout_nodes)
	_lock_label = MenuUI.label("", MenuUI.HEADING_SIZE)
	_lock_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lock_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lock_box := StyleBoxFlat.new()
	lock_box.bg_color = Color(0, 0, 0, 0.6)
	lock_box.set_corner_radius_all(8)
	lock_box.set_content_margin_all(14)
	_lock_label.add_theme_stylebox_override("normal", lock_box)
	# Always in the tree and only hidden: a label taken out of it is never
	# freed with the map, and leaks.
	_lock_label.visible = false
	_map.add_child(_lock_label)

	# exitButton, 67 px squares 78 px apart from the top-left corner.
	var back := MenuUI.icon_button("ReturnUp", "ReturnDown", Vector2(67, 67),
			back_requested.emit, "Back")
	back.name = "Back"
	back.position = Vector2(45, 43) - back.custom_minimum_size * 0.5
	add_child(back)

	_title = MenuUI.label("", 44)
	_title.add_theme_color_override("font_color", Color("ffdd72"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 70
	_title.offset_bottom = 126
	add_child(_title)
	_progress = MenuUI.label("", 22)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_progress.offset_top = 116
	_progress.offset_bottom = 144
	add_child(_progress)

	# CoinCount, a counter whose value sits right of its coin.
	_coins = _counter("CoinCounter", Vector2(827, 37), Vector2(157, 51), 19.0)
	_gems = _counter("GemCounter", Vector2(971, 37), Vector2(137, 53), 19.0)

	_prev = _arrow(true)
	_next = _arrow(false)

	# The card for the selected level, like PvZ2's level popup.
	var card := MenuUI.window(0.4, 18.0)
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = 80
	card.offset_right = -80
	card.offset_top = -108
	card.offset_bottom = -10
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_card_title = MenuUI.label("", 28)
	_card_title.add_theme_color_override("font_color", MenuUI.LEVEL_NAME)
	text.add_child(_card_title)
	_card_status = MenuUI.label("", 18)
	text.add_child(_card_status)
	_restart = MenuUI.button("Restart", _on_restart, Vector2(140, 54), &"green")
	row.add_child(_restart)
	_play = MenuUI.button("Play", _on_play, Vector2(170, 60))
	_play.name = "Play"
	row.add_child(_play)


## A currency counter: PVZGE's backing art with the amount over it, or a
## plain gold label without the art.
func _counter(sprite: String, at: Vector2, size: Vector2, value_shift: float) -> Label:
	var value := MenuUI.label("", 27)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var back := MenuUI.texture(sprite)
	if back == null:
		value.add_theme_color_override("font_color", Color("f2c53d"))
		value.position = at - size * 0.5
		value.size = size
		add_child(value)
		return value
	var frame := TextureRect.new()
	frame.texture = back
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.position = at - size * 0.5
	frame.size = size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.offset_left = value_shift * 2.0
	frame.add_child(value)
	return value


## ButtonLeft and ButtonRight: small purple squares holding PVZGE's arrow,
## in the bottom corners.
func _arrow(left: bool) -> Button:
	var b := MenuUI.button("" if MenuUI.has_sprite("DeltaArrow") else ("<" if left else ">"),
			_step.bind(-1 if left else 1), Vector2(44, 44), &"purple_big", 0.3)
	b.set_anchors_and_offsets_preset(
			Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
	b.offset_left = 8.0 if left else -52.0
	b.offset_right = b.offset_left + 44.0
	b.offset_top = -52.0
	b.offset_bottom = -8.0
	var arrow := MenuUI.texture("DeltaArrow", 0.3)
	if arrow != null:
		# DeltaArrow points up; turn it to face its way.
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
	return b


func _show_world() -> void:
	var coins := Saves.currency(&"coins")
	_coins.text = _thousands(coins)
	_gems.text = _thousands(Saves.currency(&"gems"))
	for b in _nodes.values():
		b.queue_free()
	_nodes.clear()
	_lock_label.visible = false

	var world := current_world()
	_prev.disabled = _index <= 0
	_next.disabled = _index >= _worlds.size() - 1
	if world == null:
		_title.text = "No worlds"
		_progress.text = ""
		_select(&"")
		return

	_title.text = world.display_name
	_title.tooltip_text = world.description
	_path.default_color = world.map_color.lightened(0.6)
	var cleared := 0
	for level_id in world.levels:
		if Saves.is_cleared(level_id):
			cleared += 1
	_progress.text = "%d / %d cleared" % [cleared, world.levels.size()]

	for i in world.levels.size():
		var level_id := world.levels[i]
		var b := Button.new()
		b.name = "Level_%s" % level_id
		b.text = str(i + 1)
		b.custom_minimum_size = NODE_SIZE
		b.size = NODE_SIZE
		b.add_theme_font_size_override("font_size", 26)
		b.tooltip_text = MainMenu.level_name(level_id)
		var open := is_level_open(world, level_id)
		b.disabled = not open
		_style_node(b, _node_state(level_id, open))
		b.pressed.connect(_on_node_pressed.bind(level_id))
		_map.add_child(b)
		_nodes[level_id] = b

	if not is_world_open(world):
		var gate := Data.campaign(world.unlock_after)
		_lock_label.text = "Finish %s to open this world" % (
				gate.display_name if gate != null else world.unlock_after)
		_lock_label.visible = true
		_lock_label.move_to_front()

	_layout_nodes()
	_select(world.next_unplayed(Saves.is_cleared) if is_world_open(world) else &"")


static func _thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


func _node_state(level_id: StringName, open: bool) -> StringName:
	if not open:
		return &"locked"
	if Saves.has_save(level_id):
		return &"saved"
	if Saves.is_cleared(level_id):
		return &"cleared"
	return &"open"


## Round, solid nodes, so the path runs behind them rather than through.
func _style_node(b: Button, state: StringName) -> void:
	b.set_meta(&"state", state)
	var base: Color = STATE_COLORS[state]
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(int(NODE_SIZE.x / 2))
		box.bg_color = base.lightened(0.15) if style == "hover" else base
		box.set_border_width_all(5 if style == "focus" else 3)
		box.border_color = Color.WHITE if style == "focus" else base.darkened(0.45)
		if style == "focus":
			box.draw_center = false
		b.add_theme_stylebox_override(style, box)
	var ink := Color(0.15, 0.15, 0.1)
	for c in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6))


## Lays the nodes out as a path that snakes back and forth across the map,
## so a long world wraps into rows instead of running off the side.
func _layout_nodes() -> void:
	var world := current_world()
	_path.clear_points()
	if world == null or _nodes.is_empty():
		return
	var count := world.levels.size()
	var per_row := mini(count, PER_ROW)
	var rows := ceili(float(count) / per_row)
	var area := _map.size - MAP_MARGIN * 2.0
	var step_x := area.x / maxf(per_row - 1, 1)
	var step_y := area.y / maxf(rows, 1)
	for i in count:
		var row := i / per_row
		var col := i % per_row
		if row % 2 == 1:
			col = per_row - 1 - col
		# A gentle wave inside each row, so it reads as a path, not a grid.
		var wave := sin(col * 1.3) * step_y * 0.18
		var center := MAP_MARGIN + Vector2(
				col * step_x if per_row > 1 else area.x * 0.5,
				step_y * (row + 0.5) + wave)
		var b: Button = _nodes[world.levels[i]]
		b.position = center - NODE_SIZE * 0.5
		_path.add_point(center)


# --- selection ----------------------------------------------------------

func _step(direction: int) -> void:
	var to := clampi(_index + direction, 0, _worlds.size() - 1)
	if to == _index:
		return
	_index = to
	_show_world()


func _on_node_pressed(level_id: StringName) -> void:
	# A second press on the selected node plays it, so mouse players can
	# double-click straight in.
	if _selected == level_id:
		_on_play()
	else:
		_select(level_id)


func _select(level_id: StringName) -> void:
	_selected = level_id
	for id in _nodes:
		var b: Button = _nodes[id]
		b.scale = Vector2.ONE * (1.15 if id == level_id else 1.0)
		b.pivot_offset = NODE_SIZE * 0.5
	if level_id == &"":
		_card_title.text = current_world().display_name if current_world() else ""
		_card_status.text = current_world().description if current_world() else ""
		_play.disabled = true
		_restart.visible = false
		return

	var world := current_world()
	var level := Data.level(level_id)
	_card_title.text = "%d. %s" % [world.index_of(level_id) + 1,
			MainMenu.level_name(level_id)]
	var saved := Saves.has_save(level_id)
	var status: Array[String] = []
	if saved:
		status.append("In progress")
	elif Saves.is_cleared(level_id):
		status.append("Cleared")
	else:
		status.append("Not yet cleared")
	var waves := (level.get("waves", []) as Array).size()
	if waves > 0:
		status.append("%d waves" % waves)
	# Like PvZ2's level popup, the prize still to be won.
	var prize := LevelReward.for_level(level, not Saves.is_cleared(level_id))
	if prize.is_award():
		status.append("Reward: %s" % prize.item_name())
	_card_status.text = "  -  ".join(status)
	_play.disabled = level.is_empty()
	_play.text = "Resume" if saved else "Play"
	_restart.visible = saved
	_play.grab_focus.call_deferred()


func _on_play() -> void:
	if _selected != &"" and not _play.disabled:
		level_chosen.emit(_selected)


## Drops the part-played run and starts the level fresh.
func _on_restart() -> void:
	if _selected == &"":
		return
	Saves.clear_save(_selected)
	level_chosen.emit(_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
	elif event.is_action_pressed(&"ui_page_up"):
		_step(-1)
	elif event.is_action_pressed(&"ui_page_down"):
		_step(1)
