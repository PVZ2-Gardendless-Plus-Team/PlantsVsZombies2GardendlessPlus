class_name AlmanacScreen
extends Control
## PVZGE's almanac: a Plants page and a Zombies page, each a scrolling grid of
## cards beside the chosen entry's portrait, stat rows, description, special
## notes and chat.
##
## Pages are data (AlmanacData), so a pack's plant or zombie gets its page by
## shipping one JSON file. Locked plants are listed greyed, as PVZGE does;
## zombies stay hidden until met on a lawn, show "???" until a level they were
## in is won, and are fully described after that.
##
## A third tab appears when an `UpgradesPage` class exists: any Control by
## that name that builds itself and fills its parent.

signal back_requested

const BACKGROUND := Color(0.16, 0.3, 0.14)
## Card grid columns and PVZGE's card size (239x151 at 0.4).
const COLUMNS := 6
const PACKET := Vector2(96, 61)
const ZOMBIE_CARD := Vector2(96, 72)
const RED := Color("c80000")
## A locked plant's portrait, PVZGE's 122/255 grey.
const LOCKED_TINT := Color(0.48, 0.48, 0.48)

## Which page is open: &"plants", &"zombies" or &"upgrades".
var page: StringName = &""
var current_plant: StringName = &""
var current_zombie: StringName = &""

var _tabs: Dictionary = {}       ## page -> Button
var _pages: Dictionary = {}      ## page -> Control
var _plant_cards: Dictionary = {}    ## id -> Button
var _zombie_cards: Dictionary = {}   ## id -> Button
var _plant_view: Dictionary = {}
var _zombie_view: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuUI.backdrop(BACKGROUND))

	var back := MenuUI.icon_button("ReturnUp", "ReturnDown", Vector2(67, 67),
			back_requested.emit, "Back")
	back.name = "Back"
	back.position = Vector2(45, 43) - back.custom_minimum_size * 0.5
	add_child(back)

	var title := MenuUI.title(tr("Almanac"), MenuUI.TITLE_SIZE)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 8
	title.offset_bottom = 60
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tabs.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tabs.offset_top = 14
	tabs.offset_right = -20
	add_child(tabs)

	var area := Control.new()
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.offset_top = 88
	area.offset_left = 16
	area.offset_right = -16
	area.offset_bottom = -16
	add_child(area)

	_add_page(tabs, area, &"plants", tr("Plants"), _build_plant_page())
	_add_page(tabs, area, &"zombies", tr("Zombies"), _build_zombie_page())
	var upgrades := _upgrades_page()
	if upgrades != null:
		_add_page(tabs, area, &"upgrades", tr("Upgrades"), upgrades)

	switch_to(&"plants")
	var first_plant := AlmanacData.plant_order()
	if not first_plant.is_empty():
		show_plant(first_plant[0])
	var first_zombie := _first_known_zombie()
	if first_zombie != &"":
		show_zombie(first_zombie)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()


## Opens a page by name. Returns false when there is no such page.
func switch_to(next: StringName) -> bool:
	if not _pages.has(next):
		return false
	if next == page:
		return true
	page = next
	for key in _pages:
		(_pages[key] as Control).visible = key == next
		MenuUI.skin_button(_tabs[key], &"purple" if key == next else &"green", 0.4)
	Audio.play(&"ui.seed.select")
	return true


func _add_page(tabs: HBoxContainer, area: Control, key: StringName,
		text: String, content: Control) -> void:
	var b := MenuUI.button(text, switch_to.bind(key), Vector2(150, 54), &"green", 0.4)
	b.name = "Tab_%s" % key
	b.focus_mode = Control.FOCUS_NONE
	tabs.add_child(b)
	_tabs[key] = b
	content.name = String(key).capitalize()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.visible = false
	area.add_child(content)
	_pages[key] = content


## The upgrades thread's page, when that code is in the build.
func _upgrades_page() -> Control:
	for entry in ProjectSettings.get_global_class_list():
		if String(entry.get("class", "")) == "UpgradesPage":
			var script: Script = load(String(entry["path"]))
			if script != null and script.can_instantiate():
				var node = script.new()
				if node is Control:
					return node
				if node is Node:
					node.free()
	return null


# --- plants ----------------------------------------------------------------

func _build_plant_page() -> Control:
	var parts := _split_page()
	var grid: GridContainer = parts[1]
	for id in AlmanacData.plant_order():
		var b := SeedPacketView.new()
		var def := Data.plant(id)
		b.setup(&"plant", id, int(def.stat(&"sun_cost", 0)) if def else 0, "")
		b.custom_minimum_size = PACKET
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = AlmanacData.plant_name(id)
		if not b.has_art():
			b.text = AlmanacData.plant_name(id)
		if not Saves.is_plant_unlocked(id):
			b.modulate = LOCKED_TINT
		b.pressed.connect(show_plant.bind(id))
		grid.add_child(b)
		_plant_cards[id] = b
	_plant_view = _build_details(parts[2])
	return parts[0]


## Fills the plant page's right side. Locked plants are described too, with
## their portrait greyed, as in PVZGE.
func show_plant(id: StringName) -> void:
	if not _plant_cards.has(id):
		return
	if current_plant != &"":
		Audio.play(&"ui.seed.select")
	current_plant = id
	var page_data := Data.almanac_plant(id)
	var def := Data.plant(id)
	var unlocked := Saves.is_plant_unlocked(id)
	for card_id in _plant_cards:
		_mark_chosen(_plant_cards[card_id], card_id == id)
	var v := _plant_view
	(v["name"] as Label).text = AlmanacData.plant_name(id)
	(v["brief"] as Label).text = AlmanacData.localized(page_data.get("brief", "")) \
			if unlocked else tr("Not yet obtained")
	_fill_stats(v["stats"], AlmanacData.plant_stats(id))
	_fill_text(v, page_data, true)
	var rig := _portrait(v, &"plant", id, def.world if def else &"",
			page_data.get("display_offset", [0, 0]), 1.0)
	if rig != null and not unlocked:
		rig.modulate = LOCKED_TINT


# --- zombies ---------------------------------------------------------------

func _build_zombie_page() -> Control:
	var parts := _split_page()
	var grid: GridContainer = parts[1]
	for id in AlmanacData.zombie_order():
		var b := Button.new()
		b.custom_minimum_size = ZOMBIE_CARD
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 13)
		MenuUI.skin_button(b, &"brown", 0.3)
		b.pressed.connect(show_zombie.bind(id))
		grid.add_child(b)
		_zombie_cards[id] = b
	_refresh_zombie_cards()
	_zombie_view = _build_details(parts[2])
	return parts[0]


func _refresh_zombie_cards() -> void:
	for id in _zombie_cards:
		var b: Button = _zombie_cards[id]
		var progress := Saves.zombie_progress(id)
		b.disabled = progress <= AlmanacData.HIDDEN
		b.text = AlmanacData.zombie_name(id) if progress >= AlmanacData.KNOWN \
				else ("???" if progress == AlmanacData.MET else "?")
		b.tooltip_text = b.text
		b.modulate = Color.WHITE if progress >= AlmanacData.KNOWN else LOCKED_TINT


func _first_known_zombie() -> StringName:
	for id in _zombie_cards:
		if Saves.zombie_progress(id) > AlmanacData.HIDDEN:
			return id
	return &""


## Fills the zombie page. A zombie that is met but not yet beaten shows only
## its silhouette and "???", as PVZGE's met_unknown state does. Returns false
## for one the player has never met.
func show_zombie(id: StringName) -> bool:
	if not _zombie_cards.has(id):
		return false
	var progress := Saves.zombie_progress(id)
	if progress <= AlmanacData.HIDDEN:
		return false
	if current_zombie != &"":
		Audio.play(&"ui.seed.select")
	current_zombie = id
	var known := progress >= AlmanacData.KNOWN
	var page_data := Data.almanac_zombie(id)
	for card_id in _zombie_cards:
		_mark_chosen(_zombie_cards[card_id], card_id == id)
	var v := _zombie_view
	(v["name"] as Label).text = AlmanacData.zombie_name(id) if known else "???"
	(v["brief"] as Label).text = "" if known else tr("Defeat it in a level to learn more.")
	var rows := AlmanacData.zombie_stats(id)
	if not known:
		for row in rows:
			row["value"] = "???"
			row["level"] = 0.0
	_fill_stats(v["stats"], rows)
	_fill_text(v, page_data if known else {}, false)
	var scale := page_data.get("display_scale", [1, 1]) as Array
	var rig := _portrait(v, &"zombie", id, StringName(page_data.get("world", "")),
			page_data.get("display_offset", [0, 0]), 0.5 * float(scale[0]))
	if rig != null and not known:
		rig.modulate = Color(0, 0, 0, 0.85)
	return true


# --- shared layout -----------------------------------------------------------

## [page, card grid, details box]: cards in a brown window on the left, the
## entry on the right.
func _split_page() -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var left := MenuUI.window(0.4, 18.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	row.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	# A packet's family badge pokes above its top edge.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_child(grid)
	scroll.add_child(pad)

	var right := MenuUI.window(0.4, 18.0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	right.add_child(details)
	return [row, grid, details]


## The right-hand side: name, portrait beside the stat rows, then a scrolling
## lime panel with the description, special notes and chat.
func _build_details(box: VBoxContainer) -> Dictionary:
	var v := {}
	var name := MenuUI.title("", 34)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name)
	v["name"] = name

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	var display := Panel.new()
	display.custom_minimum_size = Vector2(212, 170)
	display.clip_contents = true
	top.add_child(display)
	v["display"] = display
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stats)
	v["stats"] = stats

	var brief := MenuUI.label("", 18)
	brief.add_theme_color_override("font_color", MenuUI.TIP_YELLOW)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(brief)
	v["brief"] = brief

	var lime := PanelContainer.new()
	var panel: StyleBox = MenuUI.stylebox("windowLime", 0.4)
	if panel == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.82, 0.86, 0.55)
		flat.set_corner_radius_all(8)
		panel = flat
	panel.content_margin_left = 14
	panel.content_margin_right = 10
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	lime.add_theme_stylebox_override("panel", panel)
	lime.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(lime)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lime.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("default_color", MenuUI.DESCRIPTION_BROWN)
	text.add_theme_font_size_override("normal_font_size", 19)
	var font := MenuUI.font()
	if font != null:
		text.add_theme_font_override("normal_font", font)
	scroll.add_child(text)
	v["text"] = text
	v["scroll"] = scroll
	return v


func _fill_stats(box: VBoxContainer, rows: Array[Dictionary]) -> void:
	for c in box.get_children():
		c.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var label := MenuUI.label(String(row["label"]) + ":", 18)
		label.add_theme_color_override("font_color", MenuUI.LEVEL_NAME)
		line.add_child(label)
		var value := MenuUI.label(String(row["value"]), 18)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(value)
		box.add_child(line)
		if row.has("level"):
			# PVZGE's zombie rows carry a bar for how tough or fast it is.
			var bar := ProgressBar.new()
			bar.max_value = 1.0
			bar.step = 0.01
			bar.value = float(row["level"])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 12)
			box.add_child(bar)


func _fill_text(v: Dictionary, page_data: Dictionary, plant: bool) -> void:
	var parts := PackedStringArray()
	var description := AlmanacData.localized(page_data.get("description", ""))
	if description != "":
		parts.append(_escape(description))
	var special := AlmanacData.specials(page_data)
	if not special.is_empty():
		var lines := PackedStringArray()
		for s in special:
			lines.append("[color=#%s]%s[/color]" % [RED.to_html(false), _escape(s)])
		parts.append("\n".join(lines))
	var chat := AlmanacData.localized(page_data.get("chat", ""))
	if chat != "":
		parts.append("[i]%s[/i]" % _escape(chat))
	if parts.is_empty():
		parts.append(tr("Nothing is known about this zombie yet.") if not plant else "")
	(v["text"] as RichTextLabel).text = "\n\n".join(parts)
	(v["scroll"] as ScrollContainer).scroll_vertical = 0


## The entry standing on its world's tile, as PVZGE's display shows it.
func _portrait(v: Dictionary, kind: StringName, id: StringName, world: StringName,
		offset: Variant, scale: float) -> Node2D:
	var display: Panel = v["display"]
	var tile := MenuUI.stylebox(String(world), 0.34) if world != &"" else null
	if tile == null:
		tile = MenuUI.stylebox("frontyard", 0.34)
	if tile != null:
		display.add_theme_stylebox_override("panel", tile)
	for c in display.get_children():
		c.queue_free()
	var rig := _make_rig(kind, id)
	if rig == null:
		return null
	var shift := Vector2.ZERO
	if offset is Array and (offset as Array).size() >= 2:
		# PVZGE's offsets are in its y-up canvas units.
		shift = Vector2(float(offset[0]), -float(offset[1])) * 0.4
	rig.position = Vector2(display.custom_minimum_size.x * 0.5,
			display.custom_minimum_size.y - 30) + shift
	rig.scale = Vector2.ONE * scale
	display.add_child(rig)
	return rig


func _make_rig(kind: StringName, id: StringName) -> Armature:
	var rig := Art.make(kind, id)
	if rig == null:
		return null
	var idle := Art.animation_for(kind, id, &"idle")
	if idle != &"":
		rig.play(idle)
	if kind == &"zombie":
		_dress_zombie(rig, id)
	return rig


## Hangs the zombie's armour on its head, as Zombie does on the lawn.
func _dress_zombie(rig: Armature, id: StringName) -> void:
	var def := Data.zombie(id)
	var socket := rig.socket(&"armor")
	if def == null or socket == null:
		return
	for spec in def.components:
		if spec.type != &"armor":
			continue
		var armor_id := StringName(spec.cfg(&"armor", &""))
		var piece := Art.make(&"armor", armor_id)
		if piece == null:
			continue
		var state := Art.animation_for(&"armor", armor_id, &"intact")
		if state != &"":
			piece.play(state)
		socket.add_child(piece)


func _mark_chosen(b: Control, chosen: bool) -> void:
	if b is SeedPacketView:
		(b as SeedPacketView).chosen = chosen
		b.queue_redraw()
	elif b is Button:
		(b as Button).button_pressed = false
		b.self_modulate = Color(1.3, 1.25, 0.8) if chosen else Color.WHITE


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
