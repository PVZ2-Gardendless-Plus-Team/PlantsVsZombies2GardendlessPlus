class_name ZenGardenScreen
extends Control
## The Zen Garden (PVZGE's zenGardenScene): four gardens of pots, beds and
## floaters to grow sprouts in, with the tool column down the left - next
## garden, glove, wheelbarrow, shovel - and the sprout, coin and gem counters
## under it.
##
## Click an empty slot to plant a sprout, click what a plant asks for to give
## it, click a price tag to buy the slot. The glove moves a plant within a
## garden, the wheelbarrow carries one to another garden, and the shovel digs
## one up - a fully grown one leaves a boost behind. Scroll to zoom, drag with
## the right or middle button to look around.
##
## The rules live in ZenGarden; this only shows them and turns clicks into
## calls on it.

signal back_requested

## When each prop's animation reaches PVZGE's "grow" and "die" frame events,
## in seconds (ZenGardenAnimate runs at 30 fps).
const PROP_TIMING := {
	&"water": {"grow": 0.0, "die": 50.0 / 30.0},
	&"fertilizer": {"grow": 50.0 / 30.0, "die": 102.0 / 30.0},
	&"jukebox": {"grow": 105.0 / 30.0, "die": 125.0 / 30.0},
	&"pesticide": {"grow": 42.0 / 30.0, "die": 60.0 / 30.0},
}
## The sprout's Grow says "grow" 22 frames in.
const SPROUT_GROW_AT := 22.0 / 30.0
## Seconds between catching the plants up with the clock.
const TICK := 0.5
## PVZGE clamps the zoom to between filling the screen and ten times that.
const MAX_ZOOM := 10.0
## A slot answers clicks within this many garden units of its centre.
const SLOT_REACH := 150.0
## PVZGE's drop: 60 units up, 15 units a frame outwards, 2.22 a frame down.
const DROP_HEIGHT := 60.0
const DROP_SPEED := 15.0 * 60.0
const DROP_GRAVITY := 2.22 * 3600.0

enum Tool { NONE, SHOVEL, GLOVE, CART }

var model: ZenGarden
var garden_index: int = 0
var tool: int = Tool.NONE
var fast_shovel: bool = false
## Slot the glove has picked a plant up from, or -1.
var glove_from: int = -1

var _world: Node2D
var _layers: Dictionary = {}
var _views: Array[ZenSlotView] = []
var _zoom: float = 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _tick_left := TICK

var _sprouts: Label
var _coins: Label
var _gems: Label
var _tool_buttons: Dictionary = {}
var _tool_icons: Dictionary = {}
var _cursor: Node2D
var _cursor_art: Dictionary = {}
var _cart_plant: Node2D
var _quick: CheckBox
var _shovel_window: Control = null
var _help: Control = null


func _init(garden_model: ZenGarden = null) -> void:
	model = garden_model


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if model == null:
		model = ZenGarden.new()
	model.tick()
	var back := ColorRect.new()
	back.color = Color(0.08, 0.12, 0.08)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_world = Node2D.new()
	_world.name = "Garden"
	add_child(_world)
	_build_ui()
	show_garden(0)
	Saves.currency_changed.connect(_on_currency_changed)
	resized.connect(_place_world)
	MenuUI.music(&"music.zengarden")


func _exit_tree() -> void:
	# Coins left on the ground are the player's: PVZGE collects them all
	# when the garden closes.
	for drop in get_tree().get_nodes_in_group(&"zen_drops"):
		if drop is ZenDrop and not drop.is_collected():
			drop.bank()


# --- the garden ----------------------------------------------------------

func show_garden(index: int) -> void:
	var count := model.garden_count()
	if count == 0:
		return
	garden_index = posmod(index, count)
	_set_tool(Tool.NONE)
	for child in _world.get_children():
		child.queue_free()
	_views.clear()
	_layers.clear()
	var g := model.garden(garden_index)
	for layer in ["back", "pots", "shades", "plants", "upper", "ui", "drops"]:
		var n := Node2D.new()
		n.name = layer.capitalize()
		_world.add_child(n)
		_layers[layer] = n
	for entry in g.get("layers", []):
		var art := Art.make_from({"bundle": entry.get("bundle", ""),
				"armature": entry.get("armature", ""), "scale": float(entry.get("scale", 1.0)),
				"offset_x": float(entry.get("x", 0.0)), "offset_y": float(entry.get("y", 0.0))})
		if art == null:
			continue
		var anim := StringName(entry.get("animation", ""))
		if anim != &"":
			art.play(anim)
		var tint: Variant = entry.get("tint")
		if tint is Array and tint.size() >= 3:
			art.modulate = Color(float(tint[0]), float(tint[1]), float(tint[2]))
		_layers["upper" if entry.get("above_plants", false) else "back"].add_child(art)
	for i in model.slots(garden_index).size():
		var view := ZenSlotView.new()
		view.name = "Slot%02d" % i
		view.setup(model, garden_index, i, _layers["pots"], _layers["shades"], _layers["ui"])
		_layers["plants"].add_child(view)
		_views.append(view)
	_sort_plants()
	_zoom = 1.0
	_pan = Vector2.ZERO
	_place_world()
	_refresh(false)


## Plants further down the screen are nearer, so they draw over the ones
## behind them.
func _sort_plants() -> void:
	var ordered := _views.duplicate()
	ordered.sort_custom(func(a, b): return a.position.y < b.position.y)
	for i in ordered.size():
		_layers["plants"].move_child(ordered[i], i)


func current_garden() -> Dictionary:
	return model.garden(garden_index)


func slot_view(index: int) -> ZenSlotView:
	return _views[index] if index >= 0 and index < _views.size() else null


## Garden units to screen pixels at zoom 1: PVZGE's garden scale on its
## 1024x640 canvas, in our pixels.
func base_scale() -> float:
	return float(current_garden().get("scale", 0.33)) * MenuUI.PX


func _min_zoom() -> float:
	var b: Array = current_garden().get("bounds", [])
	if b.size() < 4 or size.x <= 0.0:
		return 0.1
	var w := (float(b[2]) - float(b[0])) * base_scale()
	var h := (float(b[3]) - float(b[1])) * base_scale()
	return maxf(size.x / w, size.y / h) if w > 0.0 and h > 0.0 else 0.1


## Places the garden from the zoom and pan, keeping its edges off the screen
## as PVZGE's ZenScalar does.
func _place_world() -> void:
	if _world == null:
		return
	_zoom = clampf(_zoom, _min_zoom(), MAX_ZOOM)
	var s := base_scale() * _zoom
	var centre := size * 0.5
	var b: Array = current_garden().get("bounds", [])
	if b.size() >= 4:
		_pan.x = _clamp_axis(_pan.x, float(b[0]) * s, float(b[2]) * s, size.x)
		_pan.y = _clamp_axis(_pan.y, float(b[1]) * s, float(b[3]) * s, size.y)
	_world.position = centre + _pan
	_world.scale = Vector2(s, s)


static func _clamp_axis(pan: float, low: float, high: float, extent: float) -> float:
	var most := -extent * 0.5 - low     # garden's left edge at the screen's
	var least := extent * 0.5 - high    # garden's right edge at the screen's
	if least >= most:
		return (least + most) * 0.5
	return clampf(pan, least, most)


func zoom_by(factor: float, around: Vector2) -> void:
	var before := _world.to_local(around)
	_zoom *= factor
	_place_world()
	_pan += around - _world.to_global(before)
	_place_world()


func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK
		if model.tick():
			_refresh()
	_update_hover()
	_update_cursor()


func _refresh(animate: bool = true) -> void:
	for view in _views:
		view.refresh(animate)
		# PVZGE greys locked slots too; their price tag stays live.
		view.set_disabled(not _usable(view.index)
				or not model.is_unlocked(garden_index, view.index))
	_update_counters()
	_update_cart()


# --- input --------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_by(1.1, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_by(1.0 / 1.1, mb.position)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_set_tool(Tool.NONE)
				_dragging = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var slot := slot_at(mb.position)
					if slot >= 0:
						click_slot(slot)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan += (event as InputEventMouseMotion).relative
		_place_world()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _shovel_window != null or _help != null:
		if key.keycode == KEY_ESCAPE:
			_close_windows()
			get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_ESCAPE:
			back_requested.emit()
		KEY_S:
			_toggle_tool(Tool.SHOVEL)
		KEY_G:
			_toggle_tool(Tool.GLOVE)
		KEY_C:
			_toggle_tool(Tool.CART)
		KEY_N, KEY_TAB:
			show_garden(garden_index + 1)
		KEY_SPACE:
			tend_all()
		KEY_P:
			# PVZGE's Ctrl+Shift+Alt+P: plants grow in minutes, for testing.
			if key.ctrl_pressed and key.shift_pressed and key.alt_pressed:
				ZenGarden.fast_full_time_ms = 0 if ZenGarden.fast_full_time_ms > 0 \
						else 4 * 60 * ZenGarden.SECOND
		_:
			return
	get_viewport().set_input_as_handled()


## The slot under a point on the screen, topmost first, or -1.
func slot_at(screen_point: Vector2) -> int:
	var local := _world.get_global_transform().affine_inverse() * (get_global_transform() * screen_point)
	for i in range(_views.size() - 1, -1, -1):
		var d := local - _views[i].position
		if absf(d.x) <= SLOT_REACH and absf(d.y) <= SLOT_REACH:
			return i
	return -1


func _update_hover() -> void:
	var over := -1
	if get_global_rect().has_point(get_global_mouse_position()) and _shovel_window == null:
		over = slot_at(get_local_mouse_position())
	for view in _views:
		view.set_hovered(view.index == over)


## What a click on a slot does, with the tool in hand or without.
func click_slot(slot: int) -> void:
	var g := garden_index
	if tool != Tool.NONE and not _usable(slot):
		return
	match tool:
		Tool.SHOVEL:
			if fast_shovel:
				_shovel(slot)
			else:
				_open_shovel_window(slot)
			return
		Tool.GLOVE:
			if glove_from < 0:
				glove_from = slot
				MenuUI.cue(&"ui.seed.select")
				_refresh(false)
			else:
				if model.move(g, glove_from, slot):
					MenuUI.cue(&"plant.place")
					var moved := _views[glove_from]
					moved.refresh(false)
				_set_tool(Tool.NONE)
			return
		Tool.CART:
			if model.cart().is_empty():
				model.load_cart(g, slot)
			else:
				model.unload_cart(g, slot)
			MenuUI.cue(&"plant.place")
			_set_tool(Tool.NONE)
			return
	if not model.is_unlocked(g, slot):
		if model.buy_slot(g, slot):
			MenuUI.cue(&"coin.collect")
			_refresh(false)
		return
	var p := model.plant_at(g, slot)
	if p.is_empty():
		var planted := model.plant_sprout(g, slot)
		if planted != &"":
			_views[slot].play_birth()
			MenuUI.cue(&"zen.sprout.birth")
			_refresh(false)
		return
	tend(slot)


## Gives the plant in a slot what it is asking for.
func tend(slot: int) -> void:
	var view := _views[slot]
	if view.acting:
		return
	var before := model.stage(model.plant_at(garden_index, slot))
	var result := model.tend(garden_index, slot)
	if result.is_empty():
		return
	var need: int = result["need"]
	MenuUI.cue(StringName("zen.%s" % ZenGarden.NEED_NAMES[need]))
	view.play_tend(need, _grown.bind(slot, before, result))
	for other in result.get("watered", []):
		_views[other].play_tend(ZenGarden.Need.WATER, Callable())
	_refresh(false)


## The prop's grow moment: the sprout or plant takes its new size and pays.
func _grown(slot: int, before: int, result: Dictionary) -> void:
	if not is_inside_tree() or slot >= _views.size():
		return
	var view := _views[slot]
	var pay := func() -> void:
		if not is_inside_tree():
			return
		view.refresh(true)
		_drop(view.position, result.get("drops", []))
		MenuUI.cue(&"zen.plant.grow")
	if before == 0:
		get_tree().create_timer(view.play_sprout_grow()).timeout.connect(pay)
	else:
		pay.call()
	if StringName(result.get("unlocked", &"")) != &"":
		MenuUI.cue(&"reward.collect.unlock_plant")


## Answers every slot in the garden that is asking for something.
func tend_all() -> void:
	for view in _views:
		var p := model.plant_at(garden_index, view.index)
		if not p.is_empty() and model.need(p) != ZenGarden.Need.NONE:
			tend(view.index)


func _shovel(slot: int) -> void:
	if model.plant_at(garden_index, slot).is_empty():
		return
	var boosted := model.shovel(garden_index, slot)
	MenuUI.cue(&"plant.dig")
	if boosted:
		MenuUI.cue(&"zen.boost")
	if not fast_shovel:
		_set_tool(Tool.NONE)
	_refresh(false)


## Whether a slot can be clicked with the tool in hand (PVZGE's
## judgeSelection, which greys the rest out).
func _usable(slot: int) -> bool:
	var g := garden_index
	var p := model.plant_at(g, slot)
	match tool:
		Tool.SHOVEL:
			return not p.is_empty()
		Tool.GLOVE:
			if glove_from < 0:
				return model.can_lift(g, slot)
			var lifted := model.plant_at(g, glove_from)
			return slot == glove_from or model.can_receive(g, slot, StringName(lifted.get("plant", "")))
		Tool.CART:
			var carried := model.cart()
			if carried.is_empty():
				return model.can_lift(g, slot)
			return model.can_receive(g, slot, StringName(carried.get("plant", "")))
	return true


func _drop(at: Vector2, drops: Array) -> void:
	for d in drops:
		var token := ZenDrop.new()
		token.kind = StringName(d["kind"])
		token.value = int(d["value"])
		token.position = at
		token.add_to_group(&"zen_drops")
		token.collect_target = _counter_target(token.kind)
		token.collected.connect(func(t): (t as ZenDrop).bank())
		_layers["drops"].add_child(token)
		var dir := Vector2(randf_range(-1.0, 1.0), 1.0).normalized()
		token.toss(at.y, DROP_HEIGHT, Vector2(dir.x, dir.y) * DROP_SPEED, DROP_GRAVITY)
		MenuUI.cue(&"coin.drop")


func _counter_target(kind: StringName) -> Vector2:
	var label := _gems if kind == &"gems" else _coins
	return label.get_global_rect().get_center() if label != null else Vector2.ZERO


# --- tools --------------------------------------------------------------

func _toggle_tool(which: int) -> void:
	if tool == which:
		_set_tool(Tool.NONE)
		MenuUI.cue(&"ui.seed.cancel")
		return
	# PVZGE's cart button with a plant in the glove loads that plant at once.
	if which == Tool.CART and tool == Tool.GLOVE and glove_from >= 0 \
			and model.cart().is_empty() and model.load_cart(garden_index, glove_from):
		MenuUI.cue(&"plant.place")
		_set_tool(Tool.NONE)
		return
	_set_tool(which)
	MenuUI.cue(&"ui.shovel" if which == Tool.SHOVEL else &"ui.seed.select")


func _set_tool(which: int) -> void:
	tool = which
	glove_from = -1
	for key in _tool_icons:
		var icon: RigIcon = _tool_icons[key]
		icon.play(&"chosen" if key == which else &"idle")
	for key in _cursor_art:
		(_cursor_art[key] as Node2D).visible = key == which
	if is_inside_tree():
		_refresh(false)


func _update_cursor() -> void:
	if _cursor == null:
		return
	_cursor.position = get_local_mouse_position()
	var glove: Node2D = _cursor_art.get(Tool.GLOVE)
	if glove != null and tool == Tool.GLOVE and glove_from >= 0:
		# The glove holds on to the plant it picked up.
		glove.global_position = _views[glove_from].global_position + Vector2(0, -20)


func _update_cart() -> void:
	if _cart_plant == null:
		return
	for child in _cart_plant.get_children():
		child.queue_free()
	var p := model.cart()
	if p.is_empty():
		return
	var st := model.stage(p)
	var art := ZenPlantArt.make(StringName(p["plant"]), 0.3 * ZenGarden.scale_for(st))
	if art != null:
		_cart_plant.add_child(art)
	else:
		var l := MenuUI.label(String(p["plant"]), 14)
		l.position = Vector2(-40, -30)
		_cart_plant.add_child(l)


# --- the column and counters -----------------------------------------------

func _build_ui() -> void:
	# PVZGE's UI node on its 1024x640 canvas, at PX: the return button top
	# left, the tool column under it, the counters at the bottom.
	var back := MenuUI.icon_button("ReturnUp", "ReturnDown", Vector2(67, 67),
			back_requested.emit, "Back")
	back.name = "Back"
	back.position = Vector2(45, 42) - back.custom_minimum_size * 0.5
	add_child(back)
	var help := MenuUI.icon_button("QuestionRoundUp", "QuestionRoundDown", Vector2(56, 56),
			_open_help, "?")
	help.name = "Help"
	help.position = Vector2(112, 41) - help.custom_minimum_size * 0.5
	add_child(help)

	var column := {
		&"next": [Vector2(45, 118), Tool.NONE, "Next garden"],
		&"glove": [Vector2(45, 189), Tool.GLOVE, "Glove"],
		&"cart": [Vector2(45, 260), Tool.CART, "Wheelbarrow"],
		&"shovel": [Vector2(45, 331), Tool.SHOVEL, "Shovel"],
	}
	for id in column:
		var at: Vector2 = column[id][0]
		var which: int = column[id][1]
		var b := Button.new()
		b.name = String(id).capitalize()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = column[id][2]
		b.custom_minimum_size = Vector2(72, 66)
		b.size = b.custom_minimum_size
		b.position = at - b.size * 0.5
		var icon := RigIcon.new(StringName("zen_%s" % id), b.size)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(icon)
		add_child(b)
		if not icon.is_node_ready() or not icon.has_art():
			b.text = column[id][2]
			b.flat = false
		b.mouse_entered.connect(func() -> void:
			if tool != which or which == Tool.NONE:
				icon.play(&"pointed"))
		b.mouse_exited.connect(func() -> void:
			icon.play(&"chosen" if tool == which and which != Tool.NONE else &"idle"))
		if id == &"next":
			b.pressed.connect(func() -> void:
				MenuUI.click()
				show_garden(garden_index + 1))
		else:
			b.pressed.connect(_toggle_tool.bind(which))
			_tool_icons[which] = icon
		_tool_buttons[id] = b

	# QuickShovel: dig without being asked to confirm.
	_quick = CheckBox.new()
	_quick.name = "FastShovel"
	_quick.text = "Fast Shovel"
	_quick.focus_mode = Control.FOCUS_NONE
	_quick.add_theme_font_size_override("font_size", 14)
	_quick.add_theme_color_override("font_color", Color("6cff3a"))
	_quick.position = Vector2(14, 362)
	_quick.toggled.connect(func(on: bool) -> void: fast_shovel = on)
	add_child(_quick)

	_gems = _counter("GemCounter", Vector2(77, 549))
	_coins = _counter("CoinCounter", Vector2(88, 618))
	_sprouts = _counter("SproutCounter", Vector2(71, 680))

	# The plant riding in the wheelbarrow sits on its button.
	_cart_plant = Node2D.new()
	_cart_plant.position = (_tool_buttons[&"cart"] as Control).position \
			+ Vector2(36, 10)
	add_child(_cart_plant)

	_cursor = Node2D.new()
	_cursor.name = "ToolInHand"
	_cursor.z_index = 50
	add_child(_cursor)
	for pair in [[Tool.SHOVEL, &"zen_shovel_cursor"], [Tool.GLOVE, &"zen_glove_cursor"],
			[Tool.CART, &"zen_cart_cursor"]]:
		var art := Art.make(&"hud", pair[1])
		var holder := Node2D.new()
		holder.visible = false
		if art != null:
			holder.add_child(art)
			art.play(Art.animation_for(&"hud", pair[1], &"idle"))
		_cursor.add_child(holder)
		_cursor_art[pair[0]] = holder


## A currency counter: PVZGE's backing at scale 0.45 with the amount right of
## its icon, or a plain label without the art.
func _counter(sprite: String, centre: Vector2) -> Label:
	var value := MenuUI.label("", 26)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tex := MenuUI.texture(sprite)
	var box := MenuUI.sprite_size(sprite, 0.45 * MenuUI.PX) if tex != null else Vector2(150, 50)
	if tex != null:
		var frame := TextureRect.new()
		frame.texture = tex
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.size = box
		frame.position = centre - box * 0.5
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
	value.size = Vector2(box.x * 0.6, box.y)
	value.position = centre - box * 0.5 + Vector2(box.x * 0.38, 0)
	add_child(value)
	return value


func _update_counters() -> void:
	_sprouts.text = thousands(model.sprouts())
	_coins.text = thousands(Saves.currency(&"coins"))
	_gems.text = thousands(Saves.currency(&"gems"))


func _on_currency_changed(_kind: StringName, _total: int) -> void:
	_update_counters()
	for view in _views:
		view.refresh(false)


static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


# --- windows --------------------------------------------------------------

## PVZGE's ShovelWindow: "Remove <plant>?", and a fully grown plant warns
## that it leaves a boost behind.
func _open_shovel_window(slot: int) -> void:
	var p := model.plant_at(garden_index, slot)
	if p.is_empty():
		return
	var boost := model.boosts_on_shovel(garden_index, slot)
	var shade := MenuUI.backdrop(Color(0, 0, 0, 0.45))
	add_child(shade)
	_shovel_window = shade
	var parts := MenuUI.panel(420.0)
	shade.add_child(parts[0])
	var stack: VBoxContainer = parts[1]
	stack.add_child(MenuUI.title("Remove Plant"))
	var name := _plant_name(StringName(p["plant"]))
	var text := MenuUI.label((tr("Shovel %s out of the garden? It will leave a boost behind.")
			if boost else tr("Shovel %s out of the garden?")) % name)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 360
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	var cancel := MenuUI.button("Cancel", _close_windows, Vector2(150, 50), &"brown")
	cancel.name = "Cancel"
	row.add_child(cancel)
	var confirm := MenuUI.button("Confirm", func() -> void:
		_close_windows()
		_shovel(slot), Vector2(150, 50), &"green")
	confirm.name = "Confirm"
	row.add_child(confirm)
	stack.add_child(row)


func _open_help() -> void:
	if _help != null:
		return
	var shade := MenuUI.backdrop(Color(0, 0, 0, 0.45))
	add_child(shade)
	_help = shade
	var parts := MenuUI.panel(560.0)
	shade.add_child(parts[0])
	var stack: VBoxContainer = parts[1]
	stack.add_child(MenuUI.title("Zen Garden"))
	for line in [
		"Sprouts drop from zombies once the garden is open. Click an empty pot to plant one.",
		"Plants grow over real time. At each stage they stop and ask for water, then fertilizer - or music or pesticide once grown. Click what they ask for.",
		"Each stage pays out coins, and a fully grown plant pays a gem.",
		"Shovel a fully grown plant to bank a boost for it.",
		"The glove moves a plant within a garden; the wheelbarrow carries one to another garden. Some plants only grow in water or on bare ground.",
		"Locked pots can be bought with coins.",
	]:
		var l := MenuUI.label(line, 17)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
		stack.add_child(l)
	var close := MenuUI.button("OK", _close_windows, Vector2(150, 50))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(close)


func _close_windows() -> void:
	for w in [_shovel_window, _help]:
		if w != null:
			w.queue_free()
	_shovel_window = null
	_help = null


func _plant_name(id: StringName) -> String:
	return ZenPlantArt.display_name(id)
