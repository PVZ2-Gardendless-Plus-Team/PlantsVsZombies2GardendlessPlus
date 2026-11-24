extends Node
## Player preferences: volumes, display and gameplay options.
##
## Kept apart from Saves because settings belong to the machine, not to a
## playthrough - resetting progress must not reset the volume.
##
## Every option has a default here, so an old or hand-edited file can never
## leave one missing. Screens read and write through get_value/set_value and
## listen for `changed`; nothing else needs to know where the file lives.
##
## Registered as an autoload singleton named `Settings`.

signal changed(key: StringName, value: Variant)

const SETTINGS_FILE := "user://settings.cfg"
const SECTION := "settings"

## Audio buses the volume sliders drive, by setting key.
const VOLUME_BUSES := {
	&"master_volume": &"Master",
	&"music_volume": &"Music",
	&"sfx_volume": &"SFX",
}

const DEFAULTS := {
	&"master_volume": 1.0,
	&"music_volume": 0.8,
	&"sfx_volume": 1.0,
	&"fullscreen": false,
	&"vsync": true,
	&"fast_forward_scale": 2.5,
	&"pause_on_focus_loss": true,
	## Every plant is choosable whether or not a reward has given it yet.
	&"unlock_all_plants": false,
	## A locale from I18n.languages(), or "" to follow the operating system.
	&"language": "",
}

var _values: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_all()


func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


## Stores, applies and saves one option.
func set_value(key: StringName, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown option '%s'" % key)
		return
	# Keep the default's type, so a slider's float cannot turn a bool option
	# into a number in the file.
	value = type_convert(value, typeof(DEFAULTS[key]))
	if _values.get(key) == value:
		return
	_values[key] = value
	_apply(key)
	save_settings()
	changed.emit(key, value)


func reset_to_defaults() -> void:
	for key in DEFAULTS:
		set_value(key, DEFAULTS[key])


func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	for key in DEFAULTS:
		if cfg.has_section_key(SECTION, String(key)):
			_values[key] = type_convert(cfg.get_value(SECTION, String(key)),
					typeof(DEFAULTS[key]))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value(SECTION, String(key), _values[key])
	if cfg.save(SETTINGS_FILE) != OK:
		push_warning("Settings: cannot write %s" % SETTINGS_FILE)


func apply_all() -> void:
	for key in _values:
		_apply(key)


func _apply(key: StringName) -> void:
	var value = _values[key]
	if VOLUME_BUSES.has(key):
		Audio.set_bus_volume(VOLUME_BUSES[key], value)
		return
	match key:
		&"language":
			I18n.set_language(value)
		&"fullscreen":
			var mode := (DisplayServer.WINDOW_MODE_FULLSCREEN if value
					else DisplayServer.WINDOW_MODE_WINDOWED)
			# Only on a change: a headless run has no window to resize, and
			# setting the mode it already has would still un-maximise it.
			if _has_window() and DisplayServer.window_get_mode() != mode:
				DisplayServer.window_set_mode(mode)
		&"vsync":
			var vsync := (DisplayServer.VSYNC_ENABLED if value
					else DisplayServer.VSYNC_DISABLED)
			if _has_window() and DisplayServer.window_get_vsync_mode() != vsync:
				DisplayServer.window_set_vsync_mode(vsync)


func _has_window() -> bool:
	return DisplayServer.get_name() != "headless"


func summary() -> String:
	return "settings: %s" % SETTINGS_FILE
