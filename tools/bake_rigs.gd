extends SceneTree
## Converts every DragonBones rig in the art into a Godot scene, once.
##
##     godot --headless --import                       # first, so textures load
##     godot --headless -s tools/bake_rigs.gd -- [bundle ...] [--all] [--force]
##
## Writes `art/<bundle>/<armature>.tscn` for every armature of the bundles the
## game's art mappings (`data/native/art/`) use, or the bundles named, or with
## `--all` every bundle in `art/_index.json`. Not every bundle is baked by
## default because the whole build bakes to most of a gigabyte of scenes; a
## bundle without one is converted when first drawn, and baking it is one
## command away when someone wants to edit it. The game loads these scenes
## instead of converting the export at startup, and they open in the Godot
## editor like any other scene - see docs/ART.md.
##
## Many bundles carry the very same export - every world's cone shares the
## basic zombie's skeleton and atlas. Such a group is baked once, in the
## bundle that sorts first, and every other bundle gets a one-line scene that
## inherits it. The paths stay `art/<bundle>/<armature>.tscn` either way, and
## an inherited scene can still be edited on its own; Godot saves only what
## differs.
##
## A scene whose root has `keep` ticked has been edited by hand, and is left
## alone unless `--force` is given.


func _initialize() -> void:
	ArmatureBaker.compact = true
	var args := OS.get_cmdline_user_args()
	var force := args.has("--force")
	var wanted: Array = []
	for a in args:
		if not a.begins_with("--"):
			wanted.append(a)
	if wanted.is_empty() and not args.has("--all"):
		wanted = _mapped_bundles()

	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(RigBuilder.ART_ROOT.path_join("_index.json")))
	if not (parsed is Dictionary):
		push_error("no art/_index.json - is the art submodule checked out?")
		quit(1)
		return
	var index := parsed as Dictionary
	var bundles := index.keys()
	bundles.sort()
	var written := 0
	var kept := 0
	var failed := 0
	var inherited := 0
	## export fingerprint -> the bundle baked for it
	var baked_for := {}
	for bundle in bundles:
		if not wanted.is_empty() and not wanted.has(bundle):
			continue
		var textures := (index[bundle] as Dictionary).get("textures", []) as Array
		if textures.is_empty():
			continue
		var dir := RigBuilder.ART_ROOT.path_join(bundle)
		var print_ := _fingerprint(dir, String(textures[0]))
		if print_ != "" and baked_for.has(print_):
			var shared := _inherit(StringName(baked_for[print_]), StringName(bundle), force)
			inherited += shared[0]
			kept += shared[1]
			failed += shared[2]
			continue
		var source := ArmatureSet.load_from(dir,
				RigBuilder.ART_ROOT.path_join("_textures").path_join(textures[0]))
		if source == null:
			push_warning("%s: could not load" % bundle)
			failed += 1
			continue
		var baker := _Bundle.new(source, StringName(bundle), force)
		for armature_name in source.armature_names():
			baker.bake(armature_name)
		written += baker.written
		kept += baker.kept
		failed += baker.failed
		if print_ != "":
			baked_for[print_] = bundle
		# Each set holds its atlas page; let it go before the next.
		source = null
	print("bake_rigs: %d written, %d inherited, %d kept, %d failed"
			% [written, inherited, kept, failed])
	quit(1 if failed > 0 else 0)


## Every bundle an art mapping names, however deep in the entry.
func _mapped_bundles() -> Array:
	var found := {}
	for dir_path in ["res://data/native/art"]:
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".json"):
				_collect_bundles(JSON.parse_string(
						FileAccess.get_file_as_string(dir_path.path_join(file))), found)
	return found.keys()


func _collect_bundles(value: Variant, found: Dictionary) -> void:
	if value is Dictionary:
		if (value as Dictionary).get("bundle") is String:
			found[value["bundle"]] = true
		for v in (value as Dictionary).values():
			_collect_bundles(v, found)
	elif value is Array:
		for v in value:
			_collect_bundles(v, found)


## Identifies an export by its skeleton, its atlas and its texture, so two
## bundles that would bake to the same scenes are recognised. "" when the
## files are not there.
func _fingerprint(dir: String, texture: String) -> String:
	var skeleton := dir.path_join("skeleton.json")
	var atlas := dir.path_join("atlas.json")
	if not FileAccess.file_exists(skeleton) or not FileAccess.file_exists(atlas):
		return ""
	return "%s|%s|%s" % [FileAccess.get_md5(skeleton), FileAccess.get_md5(atlas), texture]


const INHERITED := """[gd_scene format=3]

[ext_resource type="PackedScene" path="%s" id="1_base"]

[node name="%s" instance=ExtResource("1_base")]
"""


## The root node's name in a baked scene, which an inheriting one repeats.
static func _root_name(path: String) -> String:
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	if scene == null:
		return path.get_file().get_basename()
	return String(scene.get_state().get_node_name(0))


## Writes `bundle`'s scenes as inheriting `from`'s. Returns [written, kept,
## failed].
func _inherit(from: StringName, bundle: StringName, force: bool) -> Array:
	var counts := [0, 0, 0]
	var dir := DirAccess.open(RigBuilder.ART_ROOT.path_join(String(from)))
	if dir == null:
		return counts
	for file in dir.get_files():
		if not file.ends_with(".tscn"):
			continue
		var path := RigBuilder.ART_ROOT.path_join(String(bundle)).path_join(file)
		if not force and _Bundle._kept_scene(path):
			counts[1] += 1
			continue
		# Written as text: this is the whole of an inherited scene, and
		# GDScript has no call that makes PackedScene.pack produce one.
		var base := RigBuilder.ART_ROOT.path_join(String(from)).path_join(file)
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out == null:
			push_error("%s: could not save (%s)" % [path, error_string(FileAccess.get_open_error())])
			counts[2] += 1
			continue
		out.store_string(INHERITED % [base, _root_name(base)])
		out.close()
		counts[0] += 1
	return counts


## Bakes one bundle's armatures, each once. A child armature is baked before
## the rig that shows it, so the parent can instance the child's scene instead
## of carrying a copy.
class _Bundle:
	var source: ArmatureSet
	var bundle: StringName
	var force: bool
	var written := 0
	var kept := 0
	var failed := 0
	var _done := {}         ## armature -> its PackedScene, or null on failure

	func _init(from: ArmatureSet, name: StringName, overwrite: bool) -> void:
		source = from
		bundle = name
		force = overwrite

	func bake(armature_name: StringName) -> PackedScene:
		if _done.has(armature_name):
			return _done[armature_name]
		_done[armature_name] = null     # a rig that names itself stops here
		var path := RigBuilder.scene_path(bundle, armature_name)
		if not force and _kept_scene(path):
			kept += 1
			_done[armature_name] = ResourceLoader.load(path, "PackedScene")
			return _done[armature_name]
		var rig := Armature.new()
		rig.name = String(armature_name).validate_node_name()
		if not RigBuilder.populate(rig, source, armature_name, {}, 0, bake):
			rig.free()
			failed += 1
			return null
		RigBuilder.own(rig, rig)
		var scene := PackedScene.new()
		var err := scene.pack(rig)
		if err == OK:
			err = ResourceSaver.save(scene, path)
		rig.free()
		if err != OK:
			push_error("%s: could not save (%s)" % [path, error_string(err)])
			failed += 1
			return null
		written += 1
		# Loaded back from disk, so a parent instancing it refers to the file.
		_done[armature_name] = ResourceLoader.load(path, "PackedScene",
				ResourceLoader.CACHE_MODE_REPLACE)
		return _done[armature_name]

	## Whether a scene already there was marked as hand-edited.
	static func _kept_scene(path: String) -> bool:
		if not FileAccess.file_exists(path):
			return false
		var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) \
				as PackedScene
		if scene == null:
			return false
		var state := scene.get_state()
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"keep":
				return bool(state.get_node_property_value(0, i))
		return false
