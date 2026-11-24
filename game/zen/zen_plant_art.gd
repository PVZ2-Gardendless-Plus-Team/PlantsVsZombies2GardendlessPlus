class_name ZenPlantArt
extends RefCounted
## A plant's rig for the Zen Garden, at a given size.
##
## Only a few plants have a `plant:<id>` art mapping yet, so a garden full of
## random plants would be mostly placeholders. PVZGE draws its garden plants
## from each plant's display prefab, `plants_<Res>DIS`, which the art repo
## holds for every plant; this finds that bundle by the plant's PlantFeatures
## RES name and builds it directly when there is no mapping.

const FEATURES := "res://data/pvzge/PlantFeatures.json"
const ART_INDEX := "res://art/_index.json"

static var _res: Dictionary = {}       ## plant id -> RES.Plant name
static var _names: Dictionary = {}     ## plant id -> {"en": ..., "zh": ...}
static var _armatures: Dictionary = {} ## bundle -> default armature
static var _loaded := false


## The rig for `plant_id` at `scale` rig units per garden unit, feet at its
## origin and lifted by `height`, or null when there is no art for it.
static func make(plant_id: StringName, scale: float, height: float = 0.0) -> Armature:
	var entry := entry_for(plant_id)
	if entry.is_empty():
		return null
	entry = entry.duplicate()
	entry["scale"] = scale
	entry["offset_x"] = 0.0
	entry["offset_y"] = -height
	entry.erase("shade")
	var art := Art.make_from(entry)
	if art == null:
		return null
	var idle := StringName((entry.get("animations", {}) as Dictionary).get("idle", ""))
	if idle == &"" or not art.play(idle):
		art.play_first(["Idle", "idle", "Normal"])
	return art


## The plant's name as PVZGE shows it, in the player's language when PVZGE
## has it.
static func display_name(plant_id: StringName) -> String:
	_load()
	var names: Dictionary = _names.get(String(plant_id), {})
	var lang := TranslationServer.get_locale().get_slice("_", 0)
	return String(names.get(lang, names.get("en", String(plant_id).capitalize())))


static func entry_for(plant_id: StringName) -> Dictionary:
	var mapped := Art.mapping(&"plant", plant_id)
	if not mapped.is_empty():
		return mapped
	_load()
	var res := String(_res.get(String(plant_id), ""))
	for bundle in ["plants_%sDIS" % res, "plants_%sPLANT" % res]:
		if res != "" and _armatures.has(bundle):
			return {"bundle": bundle, "armature": _armatures[bundle]}
	return {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var features: Variant = JSON.parse_string(FileAccess.get_file_as_string(FEATURES)) \
			if FileAccess.file_exists(FEATURES) else null
	if features is Dictionary:
		for key in features:
			var f: Dictionary = features[key]
			var res: Dictionary = f.get("RES", {})
			if f.has("CODENAME") and f.get("NAME") is Dictionary:
				_names[String(f["CODENAME"])] = f["NAME"]
			if f.has("CODENAME") and res.has("Plant"):
				_res[String(f["CODENAME"])] = String(res["Plant"])
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_INDEX)) \
			if FileAccess.file_exists(ART_INDEX) else null
	if index is Dictionary:
		for bundle in index:
			if String(bundle).begins_with("plants_"):
				_armatures[String(bundle)] = String(index[bundle].get("armature", ""))
