extends Node
## Discovers mods, decides load order, and registers their scripts.
##
## Ordering follows Minecraft datapack semantics: the list is authored with the
## HIGHEST priority pack at the TOP and the base game implicitly at the bottom.
## A pack higher in the list overrides everything below it.
##
## Internally that means applying the list bottom-up - base game first, then
## each pack in ascending priority - so the last write wins and the top pack
## ends up authoritative. `priority_list()` returns the authored (top-first)
## view for UI; `data_sources()` returns the applied (base-first) view.
##
## Load order is read from `mods/load_order.json`:
##
##     { "order": ["my_overrides", "some_content_pack"],
##       "disabled": ["pack_i_am_not_using"] }
##
## Packs not listed in `order` are appended below the listed ones,
## alphabetically, so dropping a folder in still works without editing the
## file. A pack is skipped entirely if it is named in `disabled`, or if its own
## mod.json says `"enabled": false` - it stays installed and listed, but
## contributes no data and no scripts.
##
## A mod directory is laid out like the base content:
##
##     mods/my_mod/
##       mod.json            id, name, version
##       zombies/*.json      add a new zombie, or replace one by reusing its id
##       plants/*.json
##       levels/*.json
##       components/*.gd     new behaviours, or overrides of built-in ones
##       objectives/*.gd     new win/lose rules, or overrides
##       lawn_components/*.gd  world-level behaviours and abilities
##       minigames/*.gd      level modes (bowling, vasebreaker...), or overrides
##       init.gd             optional hook, run after all data has loaded
##
## Registered as an autoload singleton named `Mods`, loaded before `Data`.

signal mods_registered(mods: Array)
signal mods_initialized(mods: Array)

const MODS_DIR := "res://mods"
const USER_MODS_DIR := "user://mods"
const BASE_DIR := "res://data/native"
const ORDER_FILE := "res://mods/load_order.json"

## Highest priority first, matching how the order is authored. Enabled only.
var _priority: Array[Dictionary] = []
## Installed but switched off, kept so a UI can list and re-enable them.
var _disabled: Array[Dictionary] = []
var _errors: Array[String] = []


func _ready() -> void:
	_mount_packs()
	_priority = _resolve_order(_read_manifests())
	# Components must exist before Data reads entities that reference them.
	for m in _apply_order():
		_register_components(m)
		_register_objectives(m)
		_register_lawn_components(m)
		_register_scripts(m, "minigames", Components.register_minigame)
	mods_registered.emit(_priority)
	if not _errors.is_empty():
		for e in _errors:
			push_warning("[mod] " + e)
	# Data loads on its own _ready, which runs after this autoload.
	_run_init_hooks.call_deferred()


# --- ordering ------------------------------------------------------------

## Authored view: highest priority first, base game excluded.
func priority_list() -> Array[Dictionary]:
	return _priority


## Installed packs that are switched off, for a mod-management UI.
func disabled_list() -> Array[Dictionary]:
	return _disabled


func is_enabled(mod_id: StringName) -> bool:
	for m in _priority:
		if StringName(m["id"]) == mod_id:
			return true
	return false


func is_installed(mod_id: StringName) -> bool:
	if is_enabled(mod_id):
		return true
	for m in _disabled:
		if StringName(m["id"]) == mod_id:
			return true
	return false


## Applied view: content roots in the order they should be read, base game
## first so that later (higher priority) sources override it.
func data_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"id": &"base", "root": BASE_DIR}]
	for m in _apply_order():
		out.append(m)
	return out


## The priority list reversed, so the top pack is applied last and wins.
func _apply_order() -> Array[Dictionary]:
	var out := _priority.duplicate()
	out.reverse()
	return out


func _resolve_order(manifests: Array[Dictionary]) -> Array[Dictionary]:
	# Split off anything switched off before ordering the rest.
	var turned_off := _read_disabled()
	var by_id := {}
	_disabled.clear()
	for m in manifests:
		var mid := String(m["id"])
		if turned_off.has(mid) or not bool(m.get("enabled", true)):
			_disabled.append(m)
			print("[mod] '%s' is installed but disabled" % mid)
			continue
		by_id[mid] = m

	var ordered: Array[Dictionary] = []
	var taken := {}
	for id in _read_order_file():
		if by_id.has(id):
			ordered.append(by_id[id])
			taken[id] = true
		else:
			_errors.append("load_order.json lists '%s', which is not installed" % id)

	# Anything not listed sits below the listed packs, alphabetically.
	var rest: Array[String] = []
	for id in by_id:
		if not taken.has(id):
			rest.append(id)
	rest.sort()
	for id in rest:
		ordered.append(by_id[id])
	return ordered


func _read_order_file() -> Array[String]:
	return _read_order_field("order")


func _read_disabled() -> Array[String]:
	return _read_order_field("disabled")


func _read_order_field(field: String) -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(ORDER_FILE):
		return out
	var f := FileAccess.open(ORDER_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		if parsed.get(field) is Array:
			for id in parsed[field]:
				out.append(String(id))
	elif parsed is Array and field == "order":
		for id in parsed:
			out.append(String(id))
	else:
		_errors.append("load_order.json is not a valid order list")
	return out


# --- discovery -----------------------------------------------------------

func _mount_packs() -> void:
	var roots: Array[String] = [MODS_DIR, USER_MODS_DIR]
	for dir_path in roots:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".pck"):
				var path: String = dir_path.path_join(fname)
				if ProjectSettings.load_resource_pack(path):
					print("[mod] mounted pack %s" % fname)
				else:
					_errors.append("failed to mount pack %s" % path)
			fname = dir.get_next()
		dir.list_dir_end()


func _read_manifests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(MODS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			var root := MODS_DIR.path_join(name)
			var manifest := {"id": name, "name": name, "version": "0.0.0", "root": root}
			var mf := root.path_join("mod.json")
			if FileAccess.file_exists(mf):
				var f := FileAccess.open(mf, FileAccess.READ)
				var parsed = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary:
					manifest.merge(parsed, true)
					manifest["root"] = root
					manifest["id"] = parsed.get("id", name)
				else:
					_errors.append("%s: invalid mod.json" % name)
			out.append(manifest)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _register_components(manifest: Dictionary) -> void:
	_register_scripts(manifest, "components", Components.register)


func _register_objectives(manifest: Dictionary) -> void:
	_register_scripts(manifest, "objectives", Components.register_objective)


func _register_lawn_components(manifest: Dictionary) -> void:
	_register_scripts(manifest, "lawn_components", Components.register_lawn)


## Registers every .gd in a pack's `subdir` under its file name.
func _register_scripts(manifest: Dictionary, subdir: String,
		register_fn: Callable) -> void:
	var script_dir: String = String(manifest["root"]).path_join(subdir)
	var dir := DirAccess.open(script_dir)
	if dir == null:
		return
	var mod_id := StringName(manifest["id"])
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".gd"):
			var script = load(script_dir.path_join(fname))
			if script is GDScript:
				register_fn.call(StringName(fname.get_basename()), script, mod_id)
			else:
				_errors.append("%s/%s/%s is not a GDScript" % [mod_id, subdir, fname])
		fname = dir.get_next()
	dir.list_dir_end()


## Runs each mod's optional `init.gd`, lowest priority first, after all data is
## loaded. The script may define `initialize(ctx: Dictionary) -> void`.
func _run_init_hooks() -> void:
	for manifest in _apply_order():
		var path: String = String(manifest["root"]).path_join("init.gd")
		if not FileAccess.file_exists(path):
			continue
		var script = load(path)
		if not (script is GDScript):
			_errors.append("%s: init.gd is not a GDScript" % manifest["id"])
			continue
		var inst = script.new()
		if inst.has_method("initialize"):
			inst.initialize({"mod": manifest, "components": Components, "data": Data})
		else:
			_errors.append("%s: init.gd has no initialize()" % manifest["id"])
	mods_initialized.emit(_priority)


func errors() -> Array[String]:
	return _errors


func summary() -> String:
	var names := []
	for m in _priority:
		names.append("%s@%s" % [m["id"], m.get("version", "?")])
	var text := ("mods: none (base game only)" if names.is_empty()
			else "mods (highest priority first): %s" % str(names))
	if not _disabled.is_empty():
		var off := []
		for m in _disabled:
			off.append(String(m["id"]))
		text += "  |  disabled: %s" % str(off)
	return text
