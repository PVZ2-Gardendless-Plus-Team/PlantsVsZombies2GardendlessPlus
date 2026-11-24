extends Node
## Maps component type names to their implementing scripts.
##
## This is the seam that makes behaviour moddable. Core registers the built-in
## types at startup; a mod can then register a script under a NEW name to add a
## behaviour, or under an EXISTING name to replace one outright - which is how
## a mod completely changes what a plant does without touching core code.
##
## It also holds level objectives, which work the same way - a named,
## data-configured rule a pack can add or replace - so there is one override
## mechanism and one place to look.
##
## Registered as an autoload singleton named `Components`.

signal type_registered(type: StringName, source_mod: StringName)
signal type_overridden(type: StringName, old_mod: StringName, new_mod: StringName)

const BUILTIN_DIR := "res://core/components/builtin"
const OBJECTIVE_BUILTIN_DIR := "res://core/objectives/builtin"
const LAWN_BUILTIN_DIR := "res://core/lawn/builtin"
const MINIGAME_BUILTIN_DIR := "res://core/minigames/builtin"

var _scripts: Dictionary = {}   ## StringName -> GDScript
var _owners: Dictionary = {}    ## StringName -> StringName (mod that supplied it)
var _objectives: Dictionary = {}       ## StringName -> GDScript
var _objective_owners: Dictionary = {}
var _lawn: Dictionary = {}             ## StringName -> GDScript
var _lawn_owners: Dictionary = {}
var _minigames: Dictionary = {}         ## StringName -> GDScript
var _minigame_owners: Dictionary = {}


func _ready() -> void:
	load_builtins()


func load_builtins() -> void:
	_load_dir(BUILTIN_DIR, register)
	_load_dir(OBJECTIVE_BUILTIN_DIR, register_objective)
	_load_dir(LAWN_BUILTIN_DIR, register_lawn)
	_load_dir(MINIGAME_BUILTIN_DIR, register_minigame)


## Loads every .gd in `dir`, registering each under its file name.
func _load_dir(dir_path: String, register_fn: Callable) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("ComponentRegistry: no builtin dir at %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".gd"):
			var script: GDScript = load(dir_path.path_join(fname))
			if script != null:
				# File name is the type name: shooter.gd -> &"shooter".
				register_fn.call(StringName(fname.get_basename()), script, &"base")
		fname = dir.get_next()
	dir.list_dir_end()


## Register `script` as the implementation of `type`. Registering an existing
## type replaces it, which is the supported way for a mod to override
## behaviour; the override is announced so it shows up in load logs.
func register(type: StringName, script: GDScript, source_mod: StringName = &"base") -> void:
	if script == null:
		push_error("ComponentRegistry: null script for type '%s'" % type)
		return
	if _scripts.has(type):
		var old_mod: StringName = _owners.get(type, &"base")
		if old_mod != source_mod:
			type_overridden.emit(type, old_mod, source_mod)
			print("[mod] '%s' overrides component '%s' (was from '%s')"
					% [source_mod, type, old_mod])
	else:
		type_registered.emit(type, source_mod)
	_scripts[type] = script
	_owners[type] = source_mod


## Instantiate the component a ComponentSpec describes.
## Returns null for unknown types so a bad mod degrades instead of crashing.
func create(spec: ComponentSpec, host: Node) -> EntityComponent:
	if spec == null:
		return null
	if not _scripts.has(spec.type):
		push_warning("ComponentRegistry: unknown component type '%s' on %s"
				% [spec.type, host.name if host else "<none>"])
		return null
	var comp: EntityComponent = _scripts[spec.type].new()
	comp.name = String(spec.type)
	comp.host = host
	comp.config = spec.config
	return comp


## Register `script` as the implementation of objective `type`. Same override
## semantics as components: reusing a name replaces that rule everywhere.
func register_objective(type: StringName, script: GDScript,
		source_mod: StringName = &"base") -> void:
	if script == null:
		push_error("ComponentRegistry: null objective script for '%s'" % type)
		return
	if _objectives.has(type):
		var old: StringName = _objective_owners.get(type, &"base")
		if old != source_mod:
			type_overridden.emit(type, old, source_mod)
			print("[mod] '%s' overrides objective '%s' (was from '%s')"
					% [source_mod, type, old])
	else:
		type_registered.emit(type, source_mod)
	_objectives[type] = script
	_objective_owners[type] = source_mod


## Instantiate the objective one level entry describes.
func create_objective(spec: Dictionary, runner: Node, board: Node) -> Objective:
	var type := StringName(spec.get("type", &""))
	if not _objectives.has(type):
		push_warning("ComponentRegistry: unknown objective type '%s'" % type)
		return null
	var obj: Objective = _objectives[type].new()
	obj.name = String(type)
	obj.runner = runner
	obj.board = board
	obj.config = spec.duplicate(true)
	obj.config.erase("type")
	return obj


func has_objective(type: StringName) -> bool:
	return _objectives.has(type)


func objective_owner_of(type: StringName) -> StringName:
	return _objective_owners.get(type, &"")


func objective_types() -> Array:
	var out := _objectives.keys()
	out.sort()
	return out


## Register `script` as the implementation of lawn component `type`. Same
## override semantics as the other two categories.
func register_lawn(type: StringName, script: GDScript,
		source_mod: StringName = &"base") -> void:
	if script == null:
		push_error("ComponentRegistry: null lawn script for '%s'" % type)
		return
	if _lawn.has(type):
		var old: StringName = _lawn_owners.get(type, &"base")
		if old != source_mod:
			type_overridden.emit(type, old, source_mod)
			print("[mod] '%s' overrides lawn component '%s' (was from '%s')"
					% [source_mod, type, old])
	else:
		type_registered.emit(type, source_mod)
	_lawn[type] = script
	_lawn_owners[type] = source_mod


## Instantiate the lawn component one lawn entry describes.
func create_lawn_component(spec: Dictionary, board: Node,
		runner: Node) -> LawnComponent:
	var type := StringName(spec.get("type", &""))
	if not _lawn.has(type):
		push_warning("ComponentRegistry: unknown lawn component '%s'" % type)
		return null
	var comp: LawnComponent = _lawn[type].new()
	comp.name = String(type)
	comp.board = board
	comp.runner = runner
	comp.config = spec.duplicate(true)
	comp.config.erase("type")
	return comp


func has_lawn_component(type: StringName) -> bool:
	return _lawn.has(type)


func lawn_owner_of(type: StringName) -> StringName:
	return _lawn_owners.get(type, &"")


func lawn_component_types() -> Array:
	var out := _lawn.keys()
	out.sort()
	return out


## Register `script` as the implementation of minigame `type`. Same override
## semantics as the other categories.
func register_minigame(type: StringName, script: GDScript,
		source_mod: StringName = &"base") -> void:
	if script == null:
		push_error("ComponentRegistry: null minigame script for '%s'" % type)
		return
	if _minigames.has(type):
		var old: StringName = _minigame_owners.get(type, &"base")
		if old != source_mod:
			type_overridden.emit(type, old, source_mod)
			print("[mod] '%s' overrides minigame '%s' (was from '%s')"
					% [source_mod, type, old])
	else:
		type_registered.emit(type, source_mod)
	_minigames[type] = script
	_minigame_owners[type] = source_mod


## Instantiate the minigame one level entry describes; null for a mode that
## has not been built, so the level still plays by the normal rules.
func create_minigame(spec: Dictionary, runner: Node, board: Node) -> Minigame:
	var type := StringName(spec.get("type", &""))
	if not _minigames.has(type):
		push_warning("ComponentRegistry: unknown minigame '%s'" % type)
		return null
	var game: Minigame = _minigames[type].new()
	game.name = String(type)
	game.runner = runner
	game.board = board
	game.config = spec.duplicate(true)
	game.config.erase("type")
	return game


func has_minigame(type: StringName) -> bool:
	return _minigames.has(type)


func minigame_types() -> Array:
	var out := _minigames.keys()
	out.sort()
	return out


func has_type(type: StringName) -> bool:
	return _scripts.has(type)


func owner_of(type: StringName) -> StringName:
	return _owners.get(type, &"")


func types() -> Array:
	var out := _scripts.keys()
	out.sort()
	return out


func summary() -> String:
	var by_mod := {}
	for t in _owners:
		by_mod[_owners[t]] = by_mod.get(_owners[t], 0) + 1
	var obj_by_mod := {}
	for t in _objective_owners:
		obj_by_mod[_objective_owners[t]] = obj_by_mod.get(_objective_owners[t], 0) + 1
	var lawn_by_mod := {}
	for t in _lawn_owners:
		lawn_by_mod[_lawn_owners[t]] = lawn_by_mod.get(_lawn_owners[t], 0) + 1
	return "components: %d types %s  objectives: %d %s  lawn: %d %s  minigames: %d" % [
			_scripts.size(), str(by_mod), _objectives.size(), str(obj_by_mod),
			_lawn.size(), str(lawn_by_mod), _minigames.size()]
