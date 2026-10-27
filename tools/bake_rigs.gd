extends SceneTree
## Converts every DragonBones rig in the art into a Godot scene, once.
##
##     godot --headless --import                       # first, so textures load
##     godot --headless -s tools/bake_rigs.gd -- [bundle ...] [--force]
##
## Writes `art/<bundle>/<armature>.tscn` for every armature of every bundle in
## `art/_index.json`, or just the bundles named. The game loads these scenes
## instead of converting the export at startup, and they open in the Godot
## editor like any other scene - see docs/ART.md.
##
## A scene whose root has `keep` ticked has been edited by hand, and is left
## alone unless `--force` is given.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var force := args.has("--force")
	var wanted: Array = []
	for a in args:
		if not a.begins_with("--"):
			wanted.append(a)

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
	for bundle in bundles:
		if not wanted.is_empty() and not wanted.has(bundle):
			continue
		var textures := (index[bundle] as Dictionary).get("textures", []) as Array
		if textures.is_empty():
			continue
		var source := ArmatureSet.load_from(RigBuilder.ART_ROOT.path_join(bundle),
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
	print("bake_rigs: %d written, %d kept, %d failed" % [written, kept, failed])
	quit(1 if failed > 0 else 0)


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
