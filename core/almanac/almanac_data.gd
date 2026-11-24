class_name AlmanacData
extends RefCounted
## Lookups over the almanac pages Data loads from `almanac/plants`,
## `almanac/zombies` and `almanac.json`, as PVZGE's almanac reads them.
##
## A page is plain data: a pack adds one by shipping `almanac/plants/<id>.json`
## (or zombies), and replaces the base page by using the same id. Every text
## field is either a string or PVZGE's {"en": ..., "zh": ...} dictionary.
##
## Zombies are discovered as the player meets them, as in PVZGE: unmet ones are
## hidden, met ones show a silhouette with "???", and they become known once a
## level they appeared in is won. Saves keeps that progress.

## PVZGE's ZombieKillProgress.
const HIDDEN := 0
const MET := 1
const KNOWN := 2


## Whether the almanac button shows. PVZGE opens it with a level's
## GameFeaturesToUnlock; when no loaded level hands it out (only the
## tutorial ships so far) it is open from the start rather than unreachable.
static func is_unlocked() -> bool:
	if Saves.has_feature(&"almanac"):
		return true
	for level_id in Data.levels:
		if (Data.levels[level_id].get("unlocks_features", []) as Array).has("almanac"):
			return false
	return true


## The player's language out of a text field: the locale, then its language
## alone ("zh" for "zh_CN"), then English, then anything there is.
static func localized(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	if not (value is Dictionary) or value.is_empty():
		return ""
	var locale := TranslationServer.get_locale()
	for key in [locale, locale.get_slice("_", 0), "en"]:
		if value.has(key):
			return String(value[key])
	return String(value.values()[0])


static func plant_name(id: StringName) -> String:
	var text := localized(Data.almanac_plant(id).get("name", ""))
	return text if text != "" else String(id).capitalize()


static func zombie_name(id: StringName) -> String:
	var text := localized(Data.almanac_zombie(id).get("name", ""))
	return text if text != "" else String(id).capitalize()


## The plant page: every plant a seed chooser can list, in its order, then any
## other loaded plant that has a page of its own (a pack's, usually).
static func plant_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in (Data.seed_chooser_config().get("order", []) as Array):
		var sid := StringName(id)
		if Data.plant(sid) != null and not out.has(sid):
			out.append(sid)
	for sid in Data.almanac_plants:
		if Data.plant(sid) != null and not out.has(sid) \
				and Data.plant(sid).source_mod != &"base":
			out.append(sid)
	return out


## The zombie page: `almanac.json`'s order, then any loaded zombie with a page
## that the order leaves out.
static func zombie_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for sid in Data.almanac_zombie_order:
		if Data.almanac_zombies.has(sid) and Data.zombie(sid) != null:
			out.append(sid)
	for sid in Data.almanac_zombies:
		if Data.zombie(sid) != null and not out.has(sid):
			out.append(sid)
	return out


## The almanac entry a zombie counts towards: its own page, or the page that
## lists it as a variant (every holiday basic is the Basic Zombie). &"" when
## no page covers it.
static func entry_for_zombie(id: StringName) -> StringName:
	if Data.almanac_zombies.has(id):
		return id
	for page_id in Data.almanac_zombies:
		if (Data.almanac_zombies[page_id].get("variants", []) as Array).has(String(id)):
			return page_id
	return &""


## The stat rows of a plant's page, ready to show: [{type, label, value}].
## Sun cost, recharge, toughness and family come from the plant's own
## definition, so a pack that changes a plant's numbers changes its page.
static func plant_stats(id: StringName) -> Array[Dictionary]:
	var page := Data.almanac_plant(id)
	var def := Data.plant(id)
	var rows: Array = page.get("stats", [])
	if rows.is_empty():
		rows = [{"type": "sun_cost"}, {"type": "recharge"}, {"type": "toughness"},
				{"type": "family"}]
	var out: Array[Dictionary] = []
	for row in rows:
		if not (row is Dictionary):
			continue
		var type := String(row.get("type", "special"))
		var value := ""
		match type:
			"sun_cost":
				value = _number(def.stat(&"sun_cost", def.sun_cost)) if def else "???"
			"recharge":
				value = _number(def.stat(&"cooldown", def.cooldown)) if def else "???"
			"toughness":
				value = _number(def.stat(&"toughness", def.toughness)) if def else "???"
			"family":
				if def == null or def.family == &"":
					continue
				value = String(def.family).capitalize()
		if value == "":
			value = localized(row.get("text", ""))
		if value == "" and row.has("value"):
			value = _number(row["value"])
		var label := localized(row.get("name", ""))
		if label == "":
			label = stat_label(type)
		out.append({"type": type, "label": label, "value": value})
	return out


## Zombie stat rows: [{type, label, value, level}], `level` 0-1 for the bar.
static func zombie_stats(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in (Data.almanac_zombie(id).get("stats", []) as Array):
		if not (row is Dictionary):
			continue
		var type := String(row.get("type", ""))
		out.append({"type": type, "label": stat_label(type),
				"value": localized(row.get("text", "")),
				"level": clampf(float(row.get("level", 0.5)), 0.0, 1.0)})
	return out


## PVZGE's "Almanac" strings for each stat row, as translation keys.
static func stat_label(type: String) -> String:
	match type:
		"sun_cost": return TranslationServer.translate("Sun cost")
		"recharge": return TranslationServer.translate("Recharge")
		"toughness": return TranslationServer.translate("Toughness")
		"damage": return TranslationServer.translate("Damage")
		"family": return TranslationServer.translate("Family")
		"range": return TranslationServer.translate("Range")
		"area": return TranslationServer.translate("Area")
		"duration": return TranslationServer.translate("Duration")
		"plant_food": return TranslationServer.translate("Plant Food")
		"sun_production": return TranslationServer.translate("Sun production")
		"arming_time": return TranslationServer.translate("Arming time")
		"grow_time": return TranslationServer.translate("Grow time")
		"speed": return TranslationServer.translate("Speed")
	return TranslationServer.translate("Special")


## The page's special notes as "Name: text" lines.
static func specials(page: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for row in (page.get("special", []) as Array):
		if row is Dictionary:
			var n := localized(row.get("name", ""))
			var t := localized(row.get("text", ""))
			out.append("%s: %s" % [n, t] if n != "" else t)
	return out


static func _number(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.01))
