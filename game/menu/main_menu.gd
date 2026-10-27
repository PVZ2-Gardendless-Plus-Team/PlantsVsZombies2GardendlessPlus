class_name MainMenu
extends Control
## The title screen: play, continue a part-played level, settings, quit.
##
## It never loads anything itself - it asks the App, which owns which screen
## is showing.

signal play_requested
signal continue_requested(level_id: StringName)
signal quit_requested

const BACKGROUND := Color(0.16, 0.3, 0.14)
## PVZGE's title painting (mainScreenBg); SPL10 is its other one.
const SPLASH := "SPL9"

var _settings: SettingsMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuUI.backdrop(BACKGROUND))
	# PVZGE's title screen: one big painting with the logo in it, Play at
	# the bottom, small square buttons in the corners.
	var splash := MenuUI.texture(SPLASH)
	if splash != null:
		var bg := TextureRect.new()
		bg.texture = splash
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	else:
		var title := MenuUI.label(String(ProjectSettings.get_setting(
				"application/config/name", "PVZ2")), MenuUI.TITLE_SIZE)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		title.offset_top = 180
		title.grow_horizontal = Control.GROW_DIRECTION_BOTH
		add_child(title)

	# Bottom centre, as PVZGE's PlayButton (scale 0.7) under its player box.
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.offset_bottom = -20
	add_child(stack)

	var resume := latest_save()
	if resume != &"":
		var b := MenuUI.button("Continue: %s" % level_name(resume),
				continue_requested.emit.bind(resume), Vector2(372, 54), &"purple")
		b.name = "Continue"
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		stack.add_child(b)

	var play := MenuUI.button("Play", play_requested.emit, Vector2(180, 92),
			&"purple_big", 0.7)
	play.name = "Play"
	play.add_theme_font_size_override("font_size", 46)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(play)

	# PVZGE's 50x50 corner buttons: close bottom-left, settings bottom-right.
	var corner := Vector2(56, 56)
	var settings := MenuUI.icon_button("SettingUp", "SettingDown", corner,
			_open_settings, "Settings")
	settings.name = "Settings"
	settings.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_corner(settings, Vector2(-11 - corner.x, -11 - corner.y), corner)
	add_child(settings)
	# The web build has nothing to quit to.
	if OS.get_name() != "Web":
		var quit := MenuUI.icon_button("CloseSquareUp", "CloseSquareDown",
				corner, quit_requested.emit, "Quit")
		quit.name = "Quit"
		quit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_corner(quit, Vector2(11, -11 - corner.y), corner)
		add_child(quit)

	var mods := Data.mod_order().size() - 1    # "base" is not a mod
	var footer := MenuUI.label("Unofficial fan work - not affiliated with "
			+ "PopCap Games or Electronic Arts.    %d mod(s) enabled" % mods, 14)
	footer.modulate.a = 0.8
	footer.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	footer.offset_top = 6
	footer.offset_left = 12
	add_child(footer)

	(stack.get_node("Continue") if stack.has_node("Continue") else play) \
			.grab_focus.call_deferred()
	MenuUI.music(&"music.menu")


## Pins a corner button: anchored by the caller, then offset from it.
func _corner(c: Control, offset: Vector2, size: Vector2) -> void:
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


## The part-played level saved most recently, or &"" when there is none.
static func latest_save() -> StringName:
	var best := &""
	var best_time := -1
	for level_id in Saves.saved_levels():
		if Data.level(level_id).is_empty():
			continue    # left behind by a mod that is no longer enabled
		var t := FileAccess.get_modified_time(Saves.slot_path(level_id))
		if t > best_time:
			best_time = t
			best = level_id
	return best


static func level_name(level_id: StringName) -> String:
	var level := Data.level(level_id)
	return str(level.get("name", level_id))


func _open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsMenu.new()
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)


## Settings can reset progress, which takes the saved level with it.
func _on_settings_closed() -> void:
	_settings = null
	var resume := find_child("Continue", true, false)
	if resume != null and latest_save() == &"":
		resume.queue_free()
		(find_child("Play", true, false) as Button).grab_focus()
