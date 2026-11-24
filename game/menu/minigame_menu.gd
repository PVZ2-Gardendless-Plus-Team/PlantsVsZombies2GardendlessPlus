class_name MinigameMenu
extends Control
## The Minigames screen: every special mode PVZGE plays inside its worlds -
## Wall-nut Bowling, Last Stand, Vasebreaker, Beghouled, the Endless Zones -
## gathered in one place, each with its levels.
##
## What is listed comes from data/native/minigames.json (written by
## tools/select_minigames.py); a pack can ship its own minigames.json to add
## modes or levels, which are merged in after the base ones. Every level is
## open: these are extras, not a campaign to work through.

signal level_chosen(level_id: StringName)
signal back_requested

const CATALOG := "minigames.json"
const LEVEL_BUTTON := Vector2(250, 52)

## Mode to show first; empty opens the first one.
var start_mode: StringName = &""

var _modes: Array = []
var _index: int = 0
var _title: Label
var _description: Label
var _tabs: VBoxContainer
var _grid: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modes = catalog()
	_build()
	for i in _modes.size():
		if StringName(_modes[i].get("id", "")) == start_mode:
			_index = i
	_show_mode()
	MenuUI.music(&"music.worldmap")


## Every mode with at least one level that is loaded, base first, then each
## enabled pack's additions.
static func catalog() -> Array:
	var modes: Array = []
	var by_id := {}
	var files: Array[String] = []
	for source in Mods.data_sources():
		files.append(String(source["root"]).path_join(CATALOG))
	for path in files:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		for mode in (parsed.get("modes", []) as Array):
			if not (mode is Dictionary) or not mode.has("id"):
				continue
			var id := String(mode["id"])
			if not by_id.has(id):
				by_id[id] = {"id": id, "name": mode.get("name", id),
						"description": mode.get("description", ""), "levels": []}
				modes.append(by_id[id])
			for level in (mode.get("levels", []) as Array):
				if level is Dictionary and not Data.level(StringName(level.get("id", ""))).is_empty():
					by_id[id]["levels"].append(level)
	return modes.filter(func(m): return not (m["levels"] as Array).is_empty())


func current_mode() -> Dictionary:
	return _modes[_index] if _index < _modes.size() else {}


func _build() -> void:
	add_child(MenuUI.space_backdrop())

	var back := MenuUI.icon_button("ReturnUp", "ReturnDown", Vector2(67, 67),
			back_requested.emit, "Back")
	back.name = "Back"
	back.position = Vector2(45, 43) - back.custom_minimum_size * 0.5
	add_child(back)

	# PVZGE's own title for its extra games window.
	var heading := MenuUI.label(tr("Extra Minigames!"), 44)
	heading.add_theme_color_override("font_color", Color("ffdd72"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	heading.offset_top = 18
	heading.offset_bottom = 74
	add_child(heading)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 60
	body.offset_right = -60
	body.offset_top = 96
	body.offset_bottom = -40
	add_child(body)

	_tabs = VBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 12)
	_tabs.custom_minimum_size.x = 280
	body.add_child(_tabs)
	for i in _modes.size():
		var b := MenuUI.button(str(_modes[i]["name"]), _pick.bind(i), Vector2(280, 60))
		b.name = "Mode_%s" % _modes[i]["id"]
		_tabs.add_child(b)

	var card := MenuUI.window(0.4, 22.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	card.add_child(stack)
	_title = MenuUI.label("", 32)
	_title.add_theme_color_override("font_color", MenuUI.LEVEL_NAME)
	stack.add_child(_title)
	_description = MenuUI.label("", 20)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_description)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

	if _modes.is_empty():
		_title.text = tr("No minigames installed")


func _pick(i: int) -> void:
	_index = i
	_show_mode()


func _show_mode() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var mode := current_mode()
	if mode.is_empty():
		return
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).modulate = Color.WHITE if i == _index \
				else Color(0.75, 0.75, 0.75)
	_title.text = tr(str(mode["name"]))
	_description.text = tr(str(mode["description"]))
	var first: Button = null
	for level in (mode["levels"] as Array):
		var id := StringName(level["id"])
		var text := tr(str(level.get("name", id)))
		if Saves.is_cleared(id):
			text += "  ✓"
		var b := MenuUI.button(text, level_chosen.emit.bind(id), LEVEL_BUTTON,
				&"green" if Saves.is_cleared(id) else &"purple")
		b.name = "Level_%s" % id
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var best := Saves.best(StringName("endless:%s" % id))
		if best > 0:
			b.tooltip_text = tr("Best %d") % best
		_grid.add_child(b)
		if first == null:
			first = b
	if first != null:
		first.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
