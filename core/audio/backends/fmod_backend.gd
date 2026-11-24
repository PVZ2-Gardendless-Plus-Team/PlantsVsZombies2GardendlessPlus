extends AudioBackend
## Routes events to FMOD Studio.
##
## Inactive until an FMOD integration is installed - `is_available()` looks for
## the singleton the GDExtension registers, so this file can sit in the project
## harmlessly until then. Banks are loaded from `res://audio/banks/`.
##
## Written against utopia-rise's fmod-gdextension, whose `FmodServer` is the
## API used here: `play_one_shot`, `create_event_instance`, `get_bus`,
## `update`. Install it with `tools/install_fmod.py` (docs/AUDIO.md). Banks
## from any FMOD Studio 2.03.x load on the addon's 2.03 engine.
##
## An event the built banks do not have yet (a cue added to events.json, or
## banks older than the catalog) is handed to the Godot backend instead, so a
## stale bank build costs fidelity rather than silence.

const SINGLETON := "FmodServer"
const BANK_DIR := "res://audio/banks"
## The plugin's own autoload, which pumps `FmodServer.update()` every frame.
const MANAGER := ^"/root/FmodManager"
## FMOD_STUDIO_LOAD_BANK_NORMAL.
const LOAD_BANK_NORMAL := 0
## FMOD_STUDIO_STOP_ALLOWFADEOUT, so music ends on its own fade rather than a cut.
const STOP_ALLOW_FADEOUT := 0

var _server: Object = null
var _banks: Array = []
## The playing music instance, held so it can be stopped and steered. A
## one-shot cannot be: FMOD releases it the moment it starts.
var _music: Object = null
var _music_event: StringName = &""
var _music_path: String = ""
## Parameters the game has set, so a music cue started later picks them up.
var _parameters: Dictionary = {}
var _pump: Node = null
## Plays what the banks cannot. Built in `setup`; tests may leave it null.
var fallback: AudioBackend = null
## fmod path -> whether a loaded bank has that event.
var _resolves: Dictionary = {}
## fmod path -> the parameter names that event has.
var _event_params: Dictionary = {}
## Names of the project's global parameters, or null where the server
## cannot list them (then every name is tried).
var _globals: Variant = null


func backend_name() -> String:
	return "fmod"


func is_available() -> bool:
	return _find_server() != null


func _find_server() -> Object:
	if Engine.has_singleton(SINGLETON):
		return Engine.get_singleton(SINGLETON)
	return null


func setup(catalog: AudioCatalog) -> void:
	attach(_find_server())
	var script = load("res://core/audio/backends/godot_backend.gd")
	if script != null:
		fallback = script.new()
		fallback.setup(catalog)


## Starts driving `server`. Split from `setup` so tests can hand in a
## stand-in for FmodServer.
func attach(server: Object) -> void:
	_server = server
	if _server == null:
		return
	_load_banks()
	_ensure_pump()
	if _server.has_method("get_global_parameter_desc_list"):
		_globals = _server.get_global_parameter_desc_list().map(func(d): return d.get_name())


## Loads every bank in the bank directory, strings banks first. FMOD needs
## the master bank and its strings bank before any event path resolves.
func _load_banks() -> void:
	var dir := DirAccess.open(BANK_DIR)
	if dir == null:
		push_warning("FMOD: no bank directory at %s" % BANK_DIR)
		return
	var names := Array(dir.get_files()).filter(func(f): return f.ends_with(".bank"))
	names.sort_custom(func(a, b): return a.ends_with(".strings.bank") and not b.ends_with(".strings.bank"))
	if names.is_empty():
		push_warning("FMOD: no banks in %s - build them from the Music project" % BANK_DIR)
	for fname in names:
		var bank = _server.load_bank(BANK_DIR.path_join(fname), LOAD_BANK_NORMAL)
		if bank != null:
			_banks.append(bank)


## FMOD only advances when `update()` is called. The plugin's autoload does
## that when the plugin is enabled; when it is not, this does, so a project
## with the extension but not the editor plugin still makes sound.
func _ensure_pump() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.has_node(MANAGER) or not _server.has_method("update"):
		return
	_pump = FmodPump.new()
	_pump.server = _server
	tree.root.add_child.call_deferred(_pump)


## Whether a loaded bank has `event`. Asked once per path: a miss is
## reported once and from then on goes to the fallback.
func in_banks(event: AudioEvent) -> bool:
	if _server == null or event.fmod_path == "":
		return false
	if not _resolves.has(event.fmod_path):
		var found: bool = not _server.has_method("check_event_path") \
				or _server.check_event_path(event.fmod_path)
		_resolves[event.fmod_path] = found
		if not found:
			print_verbose("FMOD: %s is not in the built banks, using the fallback" % event.fmod_path)
	return _resolves[event.fmod_path]


func can_play(event: AudioEvent) -> bool:
	return in_banks(event) or (fallback != null and fallback.can_play(event))


## Position is not used: the lawn is one screen with no listener to place,
## and a 2D panner keyed on board pixels would only pull sounds off-centre.
func play(event: AudioEvent, position: Variant = null) -> void:
	if in_banks(event):
		_server.play_one_shot(event.fmod_path)
	elif fallback != null:
		fallback.play(event, position)


func play_music(event: AudioEvent) -> void:
	if not in_banks(event):
		_stop_fmod_music()
		if fallback != null:
			fallback.play_music(event)
		return
	if fallback != null:
		fallback.stop_music()
	# The same cue again keeps playing, so its phase is not thrown away.
	if _music_event == event.id and _music != null and _music.is_valid():
		return
	_stop_fmod_music()
	var instance = _server.create_event_instance(event.fmod_path)
	if instance == null or not instance.is_valid():
		push_warning("FMOD: could not start %s" % event.fmod_path)
		return
	for name in _parameters:
		_set_event_parameter(instance, event.fmod_path, name, _parameters[name])
	instance.start()
	_music = instance
	_music_event = event.id
	_music_path = event.fmod_path


func stop_music() -> void:
	_stop_fmod_music()
	if fallback != null:
		fallback.stop_music()


func _stop_fmod_music() -> void:
	if _music != null and _music.is_valid():
		_music.stop(STOP_ALLOW_FADEOUT)
		_music.release()
	_music = null
	_music_event = &""
	_music_path = ""


## Sets `name` everywhere it lives: as a global parameter, and on the
## playing music event, where a preset parameter such as `state` is local.
## The extension logs an error for a name that does not exist, so each is
## only set where the banks say it is.
func set_parameter(name: StringName, value: float) -> void:
	_parameters[name] = value
	if _server == null:
		return
	if _globals == null or String(name) in _globals:
		_server.set_global_parameter_by_name(String(name), value)
	if _music != null and _music.is_valid():
		_set_event_parameter(_music, _music_path, name, value)


func _set_event_parameter(instance: Object, path: String, name: StringName, value: float) -> void:
	if not _event_params.has(path):
		_event_params[path] = _parameter_names(path)
	var names = _event_params[path]
	if names == null or String(name) in names:
		instance.set_parameter_by_name(String(name), value)


## The parameter names of the event at `path`, or null where the server
## cannot say (then every name is tried).
func _parameter_names(path: String) -> Variant:
	if path == "" or not _server.has_method("get_event"):
		return null
	var desc = _server.get_event(path)
	if desc == null or not desc.has_method("get_parameters"):
		return null
	return desc.get_parameters().map(func(d): return d.get_name())


func set_bus_volume(bus: StringName, linear: float) -> void:
	if fallback != null:
		fallback.set_bus_volume(bus, linear)
	if _server == null:
		return
	var path := String(bus) if String(bus).begins_with("bus:/") else "bus:/%s" % bus
	if not _server.check_bus_path(path):
		return
	var handle = _server.get_bus(path)
	if handle != null:
		handle.volume = linear


func shutdown() -> void:
	stop_music()
	if fallback != null:
		fallback.shutdown()
		fallback = null
	if _pump != null:
		_pump.queue_free()
		_pump = null
	_banks.clear()
	_server = null


## Calls `update()` each frame for an FmodServer nobody else is pumping.
class FmodPump extends Node:
	var server: Object

	func _init() -> void:
		name = "FmodPump"
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		if server != null:
			server.update()
