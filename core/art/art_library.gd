extends Node
## Loads extracted art and hands out armatures. Autoload singleton `Art`.
##
## Everything heavy is cached per bundle and shared: a lane of zombies is many
## nodes over one parsed skeleton, one texture and one set of atlas regions.
## Adding an entity costs nodes, not memory.
##
## Art is optional. When a bundle is missing - nothing extracted, or a mod
## shipping none - every call returns null and entities keep their placeholder
## drawing, so the game runs the same with or without it.

const ART_ROOT := "res://art"
const INDEX := "res://art/_index.json"
const MAP_DIRS := ["res://data/native/art"]

## bundle -> ArmatureSet, built on first use.
var _sets: Dictionary = {}
## bundle -> texture filename, from the extractor's index.
var _textures: Dictionary = {}
## "<kind>:<id>" -> mapping dictionary.
var _map: Dictionary = {}
var _available: bool = false


func _ready() -> void:
	_load_index()
	for dir_path in MAP_DIRS:
		load_mappings(dir_path)
	apply_font()


func is_available() -> bool:
	return _available


func _load_index() -> void:
	if not FileAccess.file_exists(INDEX):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not (parsed is Dictionary):
		return
	for bundle in (parsed as Dictionary):
		var entry: Dictionary = parsed[bundle]
		var textures := entry.get("textures", []) as Array
		if not textures.is_empty():
			_textures[StringName(bundle)] = String(textures[0])
	_available = not _textures.is_empty()


## Loads every mapping file in a directory. A mod calls this with its own
## `art/` directory and its entries win, which is how a pack reskins a plant.
func load_mappings(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var added := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var parsed: Variant = JSON.parse_string(
					FileAccess.get_file_as_string(dir_path.path_join(fname)))
			if parsed is Dictionary:
				for key in (parsed as Dictionary):
					if not String(key).begins_with("//"):
						_map[StringName(key)] = parsed[key]
						added += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return added


## One line for the boot log: how much art there is, and which mapped art is
## missing its extracted bundle. A missing bundle is why something still
## shows its placeholder, so the log names the bundles to extract.
func summary() -> String:
	var missing := {}
	for key in _map:
		var entry: Variant = _map[key]
		if not (entry is Dictionary) or not (entry as Dictionary).has("bundle"):
			continue
		var bundle := StringName(entry["bundle"])
		if not _textures.has(bundle):
			missing[bundle] = true
	var line := "art: %d bundles, %d mappings" % [_textures.size(), _map.size()]
	if not missing.is_empty():
		var names := missing.keys()
		names.sort()
		line += "  missing (see docs/ART.md): %s" % ", ".join(names)
	return line


## Makes the `font:ui` mapping's font - PVZGE's own text face - the one every
## control and every `draw_string` gets when it asks the theme. Without the
## art, Godot's default stays. Returns whether the font was found.
func apply_font() -> bool:
	var file := String(mapping(&"font", &"ui").get("file", ""))
	var path := ART_ROOT.path_join(file)
	if file == "" or not ResourceLoader.exists(path):
		return false
	var font := load(path) as Font
	if font == null:
		return false
	# Controls read the default theme's font; `draw_string` callers that ask
	# for the fallback directly read the other one.
	ThemeDB.get_default_theme().default_font = font
	ThemeDB.fallback_font = font
	return true


func mapping(kind: StringName, id: StringName) -> Dictionary:
	return _map.get(StringName("%s:%s" % [kind, id]), {})


func has_art(kind: StringName, id: StringName) -> bool:
	return not mapping(kind, id).is_empty()


## The shared data for one extracted bundle, or null if it is not there.
func set_for(bundle: StringName) -> ArmatureSet:
	if _sets.has(bundle):
		return _sets[bundle]
	var texture: String = _textures.get(bundle, "")
	var built: ArmatureSet = null
	if texture != "":
		built = ArmatureSet.load_from(ART_ROOT.path_join(String(bundle)),
				ART_ROOT.path_join("_textures").path_join(texture))
	_sets[bundle] = built    # cached even when null, so a miss is asked once
	return built


## Builds the armature for one entity, already scaled and offset, or null.
func make(kind: StringName, id: StringName) -> Armature:
	return make_from(mapping(kind, id))


## Builds an armature from a mapping entry directly. Scenery and the HUD use
## this: a lawn is several rigs from one entry, not one rig per key.
func make_from(entry: Dictionary, armature_override: StringName = &"") -> Armature:
	if entry.is_empty():
		return null
	if armature_override != &"":
		entry = entry.duplicate()
		entry["armature"] = armature_override
	var source := set_for(StringName(entry.get("bundle", "")))
	if source == null:
		return null
	var armature_name := StringName(entry.get("armature", ""))
	var node := Armature.new()
	if not node.setup(source, armature_name, entry.get("sockets", {})):
		node.free()
		return null
	_fit(node, source.bounds(armature_name), entry)
	for slot in (entry.get("hide_slots", []) as Array):
		node.hide_slot(StringName(slot))
	return node


## Sizes and places the art against its own bounding box.
##
## `fit_height` is how tall it should end up in pixels and `foot_y` where its
## feet sit relative to the entity, which is what a lawn cell actually cares
## about. Both are derived rather than hand-tuned, because a rig's origin is
## at its feet and its art is rarely centred on that - the peashooter's box
## runs from -50 to +85 in X, so centring it needs its own number.
##
## An explicit `scale`, `offset_x` or `offset_y` still wins, for art that
## wants placing by hand.
func _fit(node: Armature, box: Rect2, entry: Dictionary) -> void:
	var scale_value := float(entry.get("scale", 0.0))
	if scale_value <= 0.0 and box.size.y > 0.0:
		scale_value = float(entry.get("fit_height", 96.0)) / box.size.y
	if scale_value <= 0.0:
		scale_value = 1.0
	node.scale = Vector2(scale_value, scale_value)

	var centred := -(box.position.x + box.size.x * 0.5) * scale_value
	var footed := -(box.position.y + box.size.y) * scale_value \
			+ float(entry.get("foot_y", 0.0))
	node.fitted_x = float(entry.get("offset_x", centred))
	node.position = Vector2(node.fitted_x, float(entry.get("offset_y", footed)))


## One image out of a bundle's atlas, for art that is a picture rather than
## a rig - a seed packet's portrait and backing. Null when it is not there.
func region(bundle: StringName, name: StringName) -> AtlasTexture:
	var source := set_for(bundle)
	return source.region(name) if source != null else null


## The animation an entity should play for a state, as its mapping names it.
## Returns "" when the mapping says nothing, so the caller leaves it be.
func animation_for(kind: StringName, id: StringName, state: StringName) -> StringName:
	var names: Dictionary = mapping(kind, id).get("animations", {})
	return StringName(names.get(String(state), ""))
