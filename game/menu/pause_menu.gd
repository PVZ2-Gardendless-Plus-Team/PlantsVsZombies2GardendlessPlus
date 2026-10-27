class_name PauseMenu
extends CanvasLayer
## The in-level pause button and the menu it opens.
##
## Pausing stops the whole tree, so the lawn freezes exactly - timers,
## projectiles and recharge included - and this layer keeps running on its own.
## It only asks for things to happen; the level decides what restarting or
## leaving means, including saving first.

signal resumed
signal restart_requested
## `destination` is &"map" or &"menu".
signal exit_requested(destination: StringName)

## Asked before opening, so the level can refuse (between levels, say).
var can_open: Callable

const BUTTON_SIZE := Vector2(78, 78)

var _button: BaseButton
var _overlay: Control
var _panel: Control
var _settings: SettingsMenu
## setting key -> its slider, refreshed when the full settings close.
var _volumes: Dictionary = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	# PVZGE's pause button: top-right, beside fast forward, 139 px at 0.5.
	_button = MenuUI.icon_button("Pause", "PauseActive", BUTTON_SIZE, open, "II")
	_button.name = "PauseButton"
	_button.tooltip_text = "Pause (Esc)"
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -BUTTON_SIZE.x - 4
	_button.offset_right = -4
	_button.offset_top = 12
	_button.offset_bottom = 12 + BUTTON_SIZE.y
	add_child(_button)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	# PVZGE's MouseBlocker: black at 94/255.
	_overlay.add_child(MenuUI.backdrop(Color(0, 0, 0, 0.37)))

	_panel = _build_window()
	_overlay.add_child(_panel)


## PVZGE's pause window: "Game Paused" over the grass-and-sunflower crest,
## the two volume bars, then Exit Level, Restart and Resume.
func _build_window() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	center.add_child(column)

	var title := MenuUI.label("Game Paused", 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	# The crest hangs on the window's top edge, over its rim.
	var crest := RigIcon.new(&"pause_top", Vector2(0, 46))
	crest.z_index = 1
	crest.ready.connect(func() -> void:
		if not crest.has_art():
			crest.custom_minimum_size.y = 0)
	column.add_child(crest)

	var window := MenuUI.window(0.6, 30.0)
	window.custom_minimum_size = Vector2(742, 240)
	column.add_child(window)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	window.add_child(stack)

	var sliders := GridContainer.new()
	sliders.columns = 2
	sliders.add_theme_constant_override("h_separation", 14)
	sliders.add_theme_constant_override("v_separation", 10)
	sliders.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(sliders)
	_add_volume(sliders, "Music", &"music_volume")
	_add_volume(sliders, "Sound FX", &"sfx_volume")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 26)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(buttons)
	var size := Vector2(189, 71)
	buttons.add_child(MenuUI.button("EXIT LEVEL", _on_exit.bind(&"map"), size))
	buttons.add_child(MenuUI.button("RESTART", _on_restart, size))
	var resume := MenuUI.button("RESUME", close, size, &"brown")
	resume.name = "Resume"
	buttons.add_child(resume)

	# Not in PVZGE's pause window: the full settings and the title screen.
	var extras := HBoxContainer.new()
	extras.add_theme_constant_override("separation", 12)
	extras.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(extras)
	var small := Vector2(150, 44)
	extras.add_child(MenuUI.button("Settings", _open_settings, small, &"green"))
	extras.add_child(MenuUI.button("Main Menu", _on_exit.bind(&"menu"), small, &"green"))
	return center


func _add_volume(grid: GridContainer, text: String, key: StringName) -> void:
	var name_label := MenuUI.label(text, 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(284, 30)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	MenuUI.skin_slider(slider, 45.0)
	slider.value = Settings.get_value(key)
	slider.value_changed.connect(func(v: float) -> void: Settings.set_value(key, v))
	grid.add_child(slider)
	_volumes[key] = slider


func is_open() -> bool:
	return _overlay.visible


func open() -> void:
	if is_open() or (can_open.is_valid() and not can_open.call()):
		return
	_overlay.visible = true
	_button.visible = false
	get_tree().paused = true
	MenuUI.cue(&"ui.pause")
	_focus_first()


func close() -> void:
	if not is_open():
		return
	if _settings != null:
		_settings.close()
	_overlay.visible = false
	_button.visible = true
	get_tree().paused = false
	MenuUI.cue(&"ui.unpause")
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and _settings == null and (event.is_action_pressed(&"ui_cancel")
			or event.is_action_pressed(&"Pause")):
		get_viewport().set_input_as_handled()
		close()


func _focus_first() -> void:
	var resume := _overlay.find_child("Resume", true, false) as Button
	if resume != null:
		resume.grab_focus.call_deferred()


func _open_settings() -> void:
	_settings = SettingsMenu.new()
	_settings.allow_reset_progress = false
	# One panel at a time, so the two menus do not show through each other.
	_panel.visible = false
	_settings.closed.connect(func() -> void:
		_settings = null
		_panel.visible = true
		for key in _volumes:
			_volumes[key].set_value_no_signal(Settings.get_value(key))
		_focus_first())
	_overlay.add_child(_settings)


func _on_restart() -> void:
	_release()
	restart_requested.emit()


func _on_exit(destination: StringName) -> void:
	_release()
	exit_requested.emit(destination)


## Unpauses without the resume cue, for actions that leave the current run.
func _release() -> void:
	if _settings != null:
		_settings.close()
	_overlay.visible = false
	_button.visible = true
	get_tree().paused = false
