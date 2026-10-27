class_name SettingsMenu
extends Control
## The options screen, opened over the main menu or the pause menu.
##
## Every control writes straight through to `Settings`, which applies and
## saves the change at once, so there is no Apply button to forget.

signal closed

## PVZGE's tints for an on and an off row.
const ON := Color("14ff00")
const OFF := Color("ff0000")

## Offer "Reset progress". Off in-level, where wiping the save under a
## running level would leave it in a confusing state.
var allow_reset_progress: bool = true

var _controls: Dictionary = {}   ## setting key -> Range or BaseButton
var _confirm: ConfirmationDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Usable from the pause menu, which runs while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(MenuUI.backdrop(Color(0, 0, 0, 0.6)))

	# PVZGE's settings window (scale 0.4): a gold title, a scrolling two-column
	# list of cream rows, on/off rows lit green or red, a round close button.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var window := MenuUI.window(0.4, 28.0)
	window.custom_minimum_size = Vector2(940, 530)
	center.add_child(window)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	window.add_child(stack)

	var head := HBoxContainer.new()
	stack.add_child(head)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 48
	head.add_child(spacer)
	var title := MenuUI.title("Settings", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(MenuUI.icon_button("CloseRoundUp", "CloseRoundDown",
			Vector2(48, 48), close, "X"))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var deep := MenuUI.stylebox("windowDeep", 0.12)
	if deep != null:
		deep.set_content_margin_all(8)
		scroll.add_theme_stylebox_override("panel", deep)
	stack.add_child(scroll)
	var rows := GridContainer.new()
	rows.columns = 2
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("h_separation", 6)
	rows.add_theme_constant_override("v_separation", 6)
	scroll.add_child(rows)

	_add_slider(rows, "Master", &"master_volume", 0.0, 1.0, 0.05, true)
	_add_slider(rows, "Music", &"music_volume", 0.0, 1.0, 0.05, true)
	_add_slider(rows, "Sound FX", &"sfx_volume", 0.0, 1.0, 0.05, true)
	_add_slider(rows, "Fast Forward", &"fast_forward_scale", 1.5, 4.0, 0.5)
	_add_toggle(rows, "Fullscreen", &"fullscreen")
	_add_toggle(rows, "VSync", &"vsync")
	_add_toggle(rows, "Pause When Unfocused", &"pause_on_focus_loss")
	_add_toggle(rows, "Unlock Every Plant", &"unlock_all_plants")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(row)
	var size := Vector2(180, 56)
	row.add_child(MenuUI.button("DEFAULTS", _on_defaults, size))
	if allow_reset_progress:
		row.add_child(MenuUI.button("RESET PROGRESS", _ask_reset, Vector2(220, 56), &"red"))
	var back := MenuUI.button("BACK", close, size, &"brown")
	back.name = "Back"
	row.add_child(back)
	back.grab_focus.call_deferred()

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Reset progress"
	_confirm.dialog_text = ("Forget every cleared level and part-played save?\n"
			+ "Settings are kept.")
	_confirm.ok_button_text = "Reset"
	_confirm.confirmed.connect(_on_reset_confirmed)
	add_child(_confirm)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## One of PVZGE's cream rows: its name on the left, the control on the right.
func _row(parent: Control, text: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuUI.row_box())
	panel.custom_minimum_size = Vector2(430, 58)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var name_label := MenuUI.label(text, 26)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	return row


func _add_slider(parent: Control, text: String, key: StringName,
		lo: float, hi: float, step: float, percent: bool = false) -> void:
	var row := _row(parent, text)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(170, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	MenuUI.skin_slider(slider)

	var value_label := MenuUI.label("", 22)
	value_label.custom_minimum_size.x = 56
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show := func(v: float) -> void:
		value_label.text = ("%d%%" % roundi(v * 100.0)) if percent else ("x%.1f" % v)
	slider.value = Settings.get_value(key)
	show.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		show.call(v)
		Settings.set_value(key, v))
	row.add_child(slider)
	row.add_child(value_label)
	_controls[key] = slider


## An on/off setting is the whole row, as in PVZGE: green when on, red when
## off, clicked to flip.
func _add_toggle(parent: Control, text: String, key: StringName) -> void:
	var box := Button.new()
	box.toggle_mode = true
	box.text = text
	box.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.custom_minimum_size = Vector2(430, 58)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_font_size_override("font_size", 26)
	var on := MenuUI.row_box(ON)
	var off := MenuUI.row_box(OFF)
	box.add_theme_stylebox_override("normal", off)
	box.add_theme_stylebox_override("hover", off)
	box.add_theme_stylebox_override("pressed", on)
	box.add_theme_stylebox_override("hover_pressed", on)
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color"]:
		box.add_theme_color_override(state, MenuUI.TEXT)
	box.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_theme_constant_override("outline_size", 4)
	box.button_pressed = Settings.get_value(key)
	box.toggled.connect(func(on_now: bool) -> void:
		MenuUI.click()
		Settings.set_value(key, on_now))
	parent.add_child(box)
	_controls[key] = box


func _on_defaults() -> void:
	Settings.reset_to_defaults()
	for key in _controls:
		var c = _controls[key]
		if c is Range:
			c.set_value_no_signal(Settings.get_value(key))
			# The value label follows value_changed, which no_signal skips.
			c.value_changed.emit(c.value)
		else:
			c.set_pressed_no_signal(Settings.get_value(key))


func _ask_reset() -> void:
	_confirm.popup_centered()


func _on_reset_confirmed() -> void:
	Saves.reset_progress()
