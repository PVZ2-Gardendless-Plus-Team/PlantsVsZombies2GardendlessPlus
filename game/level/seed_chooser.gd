class_name SeedChooser
extends Control
## The pre-level screen where the player picks which plants to bring.
##
## A view over SeedChooserRules: the rules decide what may be picked and how
## many, this only shows them and collects the picks. Plants the level
## pre-picks start in the hand and cannot be put back. Ready-made decks fill
## the hand in one click. "Let's Rock!" is enabled once the hand is full, or
## exactly matches a challenging deck.

## The player is done. `hand` is what they picked, in slot order, with the
## Imitater as itself; `SeedChooserRules.seeds_for` turns it into a bank.
signal confirmed(hand: Array[StringName])

@export var columns: int = 5
## PVZGE's card: 239x151 at scale 0.4.
@export var packet_size := Vector2(108, 68)
@export var font_size: int = 16

var rules: SeedChooserRules
## Plant ids in the hand, in slot order.
var chosen: Array[StringName] = []

var _hand: HFlowContainer
var _grid: GridContainer
var _decks: HBoxContainer
var _info: Label
var _start: Button
var _title: Label
## Plant id -> its button in the grid.
var _buttons: Dictionary = {}


## Shows the chooser for `chooser_rules`, starting from `remembered` picks
## where the rules still allow them.
func open(chooser_rules: SeedChooserRules, remembered: Array = []) -> void:
	rules = chooser_rules
	chosen = rules.locked.duplicate()
	if not rules.challenging_locked:
		for id in remembered:
			var sid := StringName(id)
			if chosen.size() >= rules.slots:
				break
			if _can_add(sid):
				chosen.append(sid)
	if _grid == null:
		_build()
	_fill_grid()
	_fill_decks()
	_refresh()
	# A newly won plant is marked the first time a chooser shows it.
	Saves.mark_plants_seen(rules.candidates)
	show()
	Audio.play(&"ui.chooseseeds.open")


## Adds `id` to the hand. Returns false when it cannot go in.
func pick(id: StringName) -> bool:
	if not _can_add(id):
		Audio.play(&"ui.seed.refuse")
		return false
	chosen.append(id)
	Audio.play(&"ui.seed.select")
	_refresh()
	return true


func _can_add(id: StringName) -> bool:
	if chosen.has(id) or chosen.size() >= rules.slots or not rules.can_pick(id):
		return false
	if id == SeedChooserRules.IMITATER:
		return rules.can_imitate(chosen[-1] if not chosen.is_empty() else &"")
	return true


## Takes `id` back out of the hand, unless the level put it there. An
## Imitater copying it goes with it.
func unpick(id: StringName) -> bool:
	if not chosen.has(id) or rules.locked.has(id):
		return false
	var at := chosen.find(id)
	chosen.remove_at(at)
	if at < chosen.size() and chosen[at] == SeedChooserRules.IMITATER:
		chosen.remove_at(at)
	Audio.play(&"ui.chooseseeds.remove")
	_refresh()
	return true


## Replaces the hand with a deck's plants.
func use_deck(deck: Dictionary) -> void:
	chosen = rules.deck_picks(deck)
	Audio.play(&"ui.seed.select")
	_refresh()


func clear_hand() -> void:
	chosen = rules.locked.duplicate()
	_refresh()


func can_start() -> bool:
	return rules != null and rules.can_start(chosen)


## Confirms the hand. Returns false when it is not ready.
func lets_rock() -> bool:
	if not can_start():
		Audio.play(&"ui.seed.refuse")
		return false
	hide()
	confirmed.emit(chosen.duplicate())
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		lets_rock()
		get_viewport().set_input_as_handled()


# --- view ------------------------------------------------------------------
#
# PVZGE's SeedChooser, scaled from its 1024x640 canvas: the hand fills the
# HUD's own packet slots along the top, a brown window (scale 0.4) holds the
# lime info panel over a scrolling grid of packets, the clear and reload
# buttons sit to the right, and "Let's Rock!" bottom right.

## Where the hand's first packet goes: the HUD seed bar's spot.
const HAND_AT := Vector2(396, 9)
const HAND_PER_ROW := 4

var _plant_name_label: Label
var _plant_stats: Label
var _display: Control
var _display_art: Node2D


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_hand = HFlowContainer.new()
	_hand.add_theme_constant_override("h_separation", 9)
	_hand.add_theme_constant_override("v_separation", 8)
	_hand.position = HAND_AT
	_hand.custom_minimum_size.x = HAND_PER_ROW * (packet_size.x + 9)
	add_child(_hand)

	var window := MenuUI.window(0.4, 22.0)
	window.position = Vector2(216, 172)
	window.size = Vector2(615, 560)
	add_child(window)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	window.add_child(root)

	_title = MenuUI.label("", font_size + 2)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	root.add_child(_build_info())

	_decks = HBoxContainer.new()
	_decks.add_theme_constant_override("separation", 6)
	root.add_child(_decks)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	_info = MenuUI.label("", font_size)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_info)

	# CardButtons: reload the last hand (purple), clear it (green).
	var reload := _square_button("BtnPurpleBigUp", "ReloadMemoryCards",
			"Last hand", _reload_hand)
	reload.position = Vector2(1041, 11)
	add_child(reload)
	var clear := _square_button("BtnGreenBigUp", "CleanAllCards", "Clear", clear_hand)
	clear.position = Vector2(1041, 90)
	add_child(clear)

	_start = MenuUI.button("Let's Rock!", lets_rock, Vector2(176, 65), &"purple", 0.5)
	_start.focus_mode = Control.FOCUS_NONE
	_start.add_theme_font_size_override("font_size", 30)
	_start.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_start.offset_left = -185
	_start.offset_right = -9
	_start.offset_top = -78
	_start.offset_bottom = -13
	add_child(_start)


## The lime panel: the plant on its lawn tile, its name and its numbers.
func _build_info() -> Control:
	var lime := PanelContainer.new()
	var box: StyleBox = MenuUI.stylebox("windowLime", 0.4)
	if box == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.35, 0.5, 0.2)
		flat.set_corner_radius_all(8)
		box = flat
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 12
	lime.add_theme_stylebox_override("panel", box)
	lime.custom_minimum_size.y = 200
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	lime.add_child(col)
	_plant_name_label = MenuUI.label("", 40)
	_plant_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_plant_name_label)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# PD: the plant standing on its world's tile, in a green frame.
	_display = Panel.new()
	_display.custom_minimum_size = Vector2(212, 128)
	_display.clip_contents = true
	var tile := MenuUI.stylebox("frontyard", 0.34)
	if tile != null:
		_display.add_theme_stylebox_override("panel", tile)
	var frame := MenuUI.stylebox("frame", 0.34, Color("146300"))
	if frame != null:
		_display.draw.connect(func() -> void:
			frame.draw(_display.get_canvas_item(), Rect2(Vector2.ZERO, _display.size)))
	body.add_child(_display)

	_plant_stats = MenuUI.label("", 24)
	MenuUI.style_label(_plant_stats, 24, MenuUI.DESCRIPTION_BROWN, 0, false)
	_plant_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plant_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_plant_stats)
	return lime


## PVZGE's square card buttons: a coloured tile with a white glyph.
func _square_button(tile: String, glyph: String, text: String,
		on_pressed: Callable) -> Control:
	var size := Vector2(68, 68)
	var face := MenuUI.texture(glyph)
	var b := Button.new()
	b.custom_minimum_size = size
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = text
	var look := &"purple_big" if tile.begins_with("BtnPurple") else &"green_big"
	MenuUI.skin_button(b, look, 0.4)
	if face != null:
		b.icon = face
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 40)
	else:
		b.text = text
	b.pressed.connect(MenuUI.click)
	b.pressed.connect(on_pressed)
	return b


## The hand the player last went in with, where the rules still allow it.
func _reload_hand() -> void:
	chosen = rules.locked.duplicate()
	if not rules.challenging_locked:
		for id in Saves.last_seed_choice():
			var sid := StringName(id)
			if chosen.size() < rules.slots and _can_add(sid):
				chosen.append(sid)
	Audio.play(&"ui.seed.select")
	_refresh()


func _fill_grid() -> void:
	for b in _buttons.values():
		b.queue_free()
	_buttons.clear()
	for id in rules.candidates:
		var b := _packet_button(id)
		var why := rules.refusal(id)
		if why != "":
			b.tooltip_text = "%s: %s" % [_plant_name(id), why]
		if Saves.is_plant_new(id):
			b.add_child(_new_badge())
		b.pressed.connect(pick.bind(id))
		b.mouse_entered.connect(_describe.bind(id))
		_grid.add_child(b)
		_buttons[id] = b


func _fill_decks() -> void:
	for c in _decks.get_children():
		c.queue_free()
	if rules.decks.is_empty():
		_decks.hide()
		return
	_decks.show()
	_decks.add_child(MenuUI.label("Decks:", font_size + 2))
	for deck in rules.decks:
		var b := Button.new()
		MenuUI.skin_button(b, &"brown", 0.4)
		b.text = ("* " if deck["challenging"] else "") + String(deck["name"]).replace("\n", " ")
		b.tooltip_text = ", ".join(PackedStringArray(
				(deck["plants"] as Array).map(func(p): return _plant_name(StringName(p)))))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(use_deck.bind(deck))
		_decks.add_child(b)


func _refresh() -> void:
	for c in _hand.get_children():
		c.queue_free()
	for i in rules.slots:
		if i < chosen.size():
			var id := chosen[i]
			var b := _packet_button(id)
			if id == SeedChooserRules.IMITATER and i > 0:
				b.tooltip_text = "Imitater, copying %s" % _plant_name(chosen[i - 1])
				if not b.has_art():
					b.text = "%s\n(%s)" % [_plant_name(id), _plant_name(chosen[i - 1])]
			if rules.locked.has(id):
				b.tooltip_text = "Chosen by the level"
				b.modulate = Color(1.0, 0.95, 0.75)
			b.pressed.connect(unpick.bind(id))
			_hand.add_child(b)
		else:
			# PVZGE's emptyslot: a dim, sunken packet outline.
			var empty := Panel.new()
			var well := StyleBoxFlat.new()
			well.bg_color = Color(0, 0, 0, 0.35)
			well.border_color = Color(1, 1, 1, 0.25)
			well.set_border_width_all(2)
			well.set_corner_radius_all(6)
			empty.add_theme_stylebox_override("panel", well)
			empty.custom_minimum_size = packet_size
			_hand.add_child(empty)

	for id in _buttons:
		var b: Button = _buttons[id]
		var allowed := rules.refusal(id) == ""
		b.disabled = not allowed or chosen.has(id)
		# PVZGE greys out a packet once it is in the hand, or when it is refused.
		b.modulate = Color.WHITE if allowed and not chosen.has(id) else Color(0.45, 0.45, 0.45)

	_title.text = "Choose your seeds  (%d / %d)" % [chosen.size(), rules.slots]
	if _plant_name_label.text == "" and not rules.candidates.is_empty():
		_show_plant(rules.candidates[0])
	_start.disabled = not can_start()


func _describe(id: StringName) -> void:
	var why := rules.refusal(id)
	_info.text = _plant_name(id) + ("  -  " + why if why != "" else "")
	_show_plant(id)


## Fills the lime panel for a plant, as PVZGE does for the hovered packet.
func _show_plant(id: StringName) -> void:
	_plant_name_label.text = _plant_name(id)
	var def := Data.plant(id)
	var lines := PackedStringArray()
	if def != null:
		lines.append("Cost: %d sun" % int(def.stat(&"sun_cost", 0)))
		lines.append("Recharge: %ss" % str(def.stat(&"cooldown", 0)))
		if def.family != &"":
			lines.append("Family: %s" % String(def.family).capitalize())
	var why := rules.refusal(id) if rules != null else ""
	if why != "":
		lines.append(why)
	_plant_stats.text = "\n".join(lines)
	if _display_art != null:
		_display_art.queue_free()
		_display_art = null
	var rig := Art.make(&"plant", id)
	if rig != null:
		rig.position = Vector2(_display.custom_minimum_size.x * 0.5, 112)
		var idle := Art.animation_for(&"plant", id, &"idle")
		if idle != &"":
			rig.play(idle)
		_display.add_child(rig)
		_display_art = rig


## A packet drawn like the HUD's, falling back to name and cost without art.
func _packet_button(id: StringName) -> Button:
	var b := SeedPacketView.new()
	var def := Data.plant(id)
	b.setup(&"plant", id, int(def.stat(&"sun_cost", 0)) if def else 0, "")
	b.custom_minimum_size = packet_size
	b.clip_text = true
	b.tooltip_text = _plant_name(id)
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _new_badge() -> Label:
	var l := _label("NEW")
	l.add_theme_color_override("font_color", Color("ffe14d"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(4, 0)
	return l


func _plant_name(id: StringName) -> String:
	return String(id).capitalize()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size + 2)
	return l
