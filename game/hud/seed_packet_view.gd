class_name SeedPacketView
extends Button
## One seed packet, drawn the way PVZGE draws it: the world's packet backing,
## the plant's portrait, the price, the recharge shade and the selection rim.
##
## PVZGE builds a packet out of nested rigs (`SeedPacker`'s Card holds a
## background rig, a plant rig with one display per plant, a cooldown rig and
## so on), each switched by a zero-length animation. The pictures are all one
## atlas, so this draws them straight from it at the places the rigs put them,
## which keeps a packet a single control rather than eight armatures.
##
## Without the art it is an ordinary button with the plant's name and cost.

const PACKET := Vector2(239, 151)
## PVZGE's own colours: the packet darkens when it cannot be used, and the
## price turns red when the sun is short.
const DARK := Color8(140, 140, 140)
const SHORT := Color8(255, 100, 100)
## The price label on PVZGE's card prefab: its size, and the box it is
## right- and bottom-aligned in, in rig units from the packet centre.
const PRICE_SIZE := 66.1
const PRICE_LINE := 56.4
const PRICE_RIGHT := 115.9
const PRICE_BOTTOM := 80.0
## PVZGE's key tip: centred here, and grown when the packet is picked.
const KEY_AT := Vector2(-100, 55)
const KEY_SIZE := 40.0
## The prefab's Family node sits here, scaled 1.1, over the family rig.
const FAMILY_AT := Vector2(7.3, 2.1)
const FAMILY_SCALE := 1.1

## The bundle, from the `hud:seed_packet` mapping.
var bundle: StringName = &"rigs_SeedPacker_Card"

var kind: StringName = &"plant"
var id: StringName = &""
var cost: int = 0
var hotkey: String = ""
## 0 just planted, 1 ready.
var recharged: float = 1.0
var affordable: bool = true
var chosen: bool = false
## Recharged and paid for. An unusable packet still takes clicks, so that
## main can refuse it with PVZGE's sound and sun warning.
var usable: bool = true

var _source: ArmatureSet = null
var _portrait: AtlasTexture = null
var _portrait_at := Vector2.ZERO
var _hover: bool = false
## What each sub-rig shows for this plant, from `_shown`.
var _background: Dictionary = {}
var _price_tab: Dictionary = {}
var _family: Array[Dictionary] = []


func setup(packet_kind: StringName, packet_id: StringName, price: int, key: String) -> void:
	kind = packet_kind
	id = packet_id
	cost = price
	hotkey = key
	focus_mode = Control.FOCUS_NONE
	var entry := Art.mapping(&"hud", &"seed_packet")
	bundle = StringName(entry.get("bundle", bundle))
	_source = Art.set_for(bundle)
	var def := Data.plant(id) if kind == &"plant" else null
	_find_portrait(entry.get("portraits", {}), def.packet_portrait if def else &"")
	if _source != null:
		_dress(def)
	if has_art():
		text = ""
		flat = true
	else:
		text = "%s%s\n%d" % [key, String(id).capitalize(), cost]
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	queue_redraw()


func has_art() -> bool:
	return _source != null and _portrait != null


## Brings the packet up to date. Called whenever sun, recharge or the
## selection change.
func show_state(fraction: float, can_afford: bool, is_chosen: bool) -> void:
	recharged = clampf(fraction, 0.0, 1.0)
	affordable = can_afford
	chosen = is_chosen
	usable = recharged >= 1.0 and affordable
	if not has_art():
		# The plain button's old look: darker the more recharge is left.
		if chosen:
			modulate = Color(0.7, 1.0, 0.7)
		elif recharged < 1.0:
			modulate = Color.WHITE.darkened(0.55 * (1.0 - recharged))
		elif not affordable:
			modulate = Color(0.75, 0.75, 0.75)
		else:
			modulate = Color.WHITE
	queue_redraw()


## The portrait is one display among 258 on the `plants` rig's body slot;
## its own transform says where it sits on the packet.
func _find_portrait(overrides: Dictionary, named: StringName) -> void:
	if _source == null:
		return
	var wanted: Array[String] = []
	if overrides.has(String(id)):
		wanted.append(String(overrides[String(id)]))
	if named != &"":
		wanted.append(String(named))
	wanted.append(String(id))
	wanted.append(String(id).replace("_", ""))
	var displays := {}
	for skin in (_source.armature(&"plants").get("skin", []) as Array):
		for slot in (skin.get("slot", []) as Array):
			if slot.get("name", "") != "plant_body":
				continue
			for d in (slot.get("display", []) as Array):
				displays[String(d.get("name", ""))] = d
	for name in wanted:
		var region := _source.region(StringName(name))
		if region == null:
			continue
		_portrait = region
		var xf: Dictionary = (displays.get(name, {}) as Dictionary).get("transform", {})
		_portrait_at = Vector2(float(xf.get("x", 0.0)), float(xf.get("y", 0.0))) \
				+ _source.region_offset(StringName(name))
		return


## Picks the backing, price tab and family badge the way PVZGE's
## `getBGAnm` and `cardGrouperPlant` do: the backing from the plant's world,
## gold for the store and mint plants, and the badge from its Family.
func _dress(def: PlantDef) -> void:
	var world := String(def.world) if def else ""
	var anim := "homeless"
	var tab := "dotPrice"
	match world:
		"egypt", "pirate", "cowboy", "kongfu", "future", "dark", "beach", "ice", \
				"lostcity", "eighties", "sky", "dino", "modern", "frontyard":
			anim = world
		"water":
			anim = "beach"
		"market":
			anim = "prenium"
			tab = "dotsPricePremium"
		"mint", "epic":
			anim = world
			tab = "dotsPricePremium"
		"lod":
			anim = "lod"
			tab = "dotsPriceLod"
	_background = _shown(&"background", StringName(anim), &"bk")
	_price_tab = _shown(&"upper_dots", StringName(tab), &"bk_price_tab")
	_family.clear()
	if def and def.family != &"":
		for slot in [&"mintfam_banner", &"mintfam_cold"]:
			var shown := _shown(&"family", def.family, slot)
			if not shown.is_empty():
				shown["at"] = FAMILY_AT + shown["at"] * FAMILY_SCALE
				shown["stretch"] = shown["stretch"] * FAMILY_SCALE
				_family.append(shown)


## What one of the packet's sub-rigs shows on `slot` once the zero-length
## `animation` has switched it: the image, where it sits from the packet
## centre (its bone included), its scale and the slot's colour. Empty when
## the animation hides the slot or the rig is not there.
func _shown(armature: StringName, animation: StringName, slot: StringName) -> Dictionary:
	var arm := _source.armature(armature)
	var index := 0
	var bone := ""
	for s in (arm.get("slot", []) as Array):
		if s.get("name", "") == slot:
			index = int(s.get("displayIndex", 0))
			bone = String(s.get("parent", ""))
	var tint := Color.WHITE
	var found := false
	for a in (arm.get("animation", []) as Array):
		if a.get("name", "") != String(animation):
			continue
		found = true
		for s in (a.get("slot", []) as Array):
			if s.get("name", "") != slot:
				continue
			var frames := s.get("displayFrame", []) as Array
			if not frames.is_empty():
				index = int((frames[0] as Dictionary).get("value", 0))
			var colours := s.get("colorFrame", []) as Array
			if not colours.is_empty():
				var c: Dictionary = (colours[0] as Dictionary).get("value", {})
				tint = Color(c.get("rM", 100) / 100.0, c.get("gM", 100) / 100.0,
						c.get("bM", 100) / 100.0, c.get("aM", 100) / 100.0)
	var displays: Array = []
	for skin in (arm.get("skin", []) as Array):
		for s in (skin.get("slot", []) as Array):
			if s.get("name", "") == slot:
				displays = s.get("display", [])
	if not found or index < 0 or index >= displays.size():
		return {}
	var at := Vector2.ZERO
	for b in (arm.get("bone", []) as Array):
		if b.get("name", "") == bone:
			var bxf: Dictionary = b.get("transform", {})
			at = Vector2(float(bxf.get("x", 0.0)), float(bxf.get("y", 0.0)))
	var d: Dictionary = displays[index]
	var xf: Dictionary = d.get("transform", {})
	var image := StringName(d.get("name", ""))
	var stretch := Vector2(float(xf.get("scX", 1.0)), float(xf.get("scY", 1.0)))
	at += Vector2(float(xf.get("x", 0.0)), float(xf.get("y", 0.0))) \
			+ _source.region_offset(image) * stretch
	return {"image": image, "at": at, "stretch": stretch, "tint": tint}


func _draw() -> void:
	if not has_art():
		return
	var k := minf(size.x / PACKET.x, size.y / PACKET.y)
	var centre := size * 0.5
	var back := Color.WHITE if usable and not chosen else DARK
	var face := Color.WHITE if usable else DARK

	_draw_shown(_background, k, centre, back)
	_blit_texture(_portrait, _portrait_at, Vector2.ONE, k, centre, face)
	_blit(&"bk_top", Vector2(-2.25, 7.1), k, centre, back)
	_draw_shown(_price_tab, k, centre, back)

	# Recharge: PVZGE pulls a translucent shade up off the packet. Drawn as
	# the share still to go, from the top.
	if recharged < 1.0:
		var shade := Rect2(Vector2.ZERO, Vector2(size.x, size.y * (1.0 - recharged)))
		draw_rect(shade, Color(0, 0, 0, 0.45), true)

	for part in _family:
		_draw_shown(part, k, centre, Color.WHITE)

	# The price, set like PVZGE's label: right- and bottom-aligned in its box,
	# outlined, with a drop shadow.
	var font := get_theme_default_font()
	var price := str(cost)
	var fs := maxi(8, roundi(PRICE_SIZE * k))
	var w := font.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var line_mid := (PRICE_BOTTOM - PRICE_LINE * 0.5) * k
	var baseline := centre + Vector2(PRICE_RIGHT * k - w, line_mid
			+ (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	var outline := maxi(1, roundi(4 * k))
	draw_string_outline(font, baseline + Vector2(4, 4) * k, price,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color.BLACK)
	draw_string(font, baseline + Vector2(4, 4) * k, price,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
	draw_string_outline(font, baseline, price,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color.BLACK)
	draw_string(font, baseline, price,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if affordable else SHORT)

	if chosen:
		_blit(&"bk_select", Vector2(-2.17, -0.54), k, centre, Color.WHITE)
	elif _hover and usable and not disabled:
		_blit(&"bk_pointed", Vector2(-2.17, -0.54), k, centre, Color.WHITE)

	# The hotkey, where PVZGE's key tip sits: off the packet's lower left
	# corner, coloured by what pressing it would do.
	if hotkey != "":
		var key := hotkey.strip_edges()
		var ks := maxi(9, roundi(KEY_SIZE * k * (1.4 if chosen else 1.0)))
		var kw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
		var at := centre + KEY_AT * k + Vector2(-kw * 0.5,
				(font.get_ascent(ks) - font.get_descent(ks)) * 0.5)
		var colour := Color8(255, 100, 100)
		if chosen:
			colour = Color8(100, 255, 100)
		elif recharged < 1.0:
			colour = Color8(150, 150, 255)
		elif affordable:
			colour = Color8(245, 255, 0)
		draw_string_outline(font, at, key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks,
				maxi(2, roundi(6 * k)), Color.BLACK)
		draw_string(font, at, key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, colour)


## Draws one atlas image centred at `at` (rig units from the packet centre).
func _blit(name: StringName, at: Vector2, k: float, centre: Vector2, tint: Color) -> void:
	var region := _source.region(name)
	if region != null:
		_blit_texture(region, at + _source.region_offset(name), Vector2.ONE, k, centre, tint)


## Draws what `_shown` found, tinted by both its slot colour and `tint`.
func _draw_shown(shown: Dictionary, k: float, centre: Vector2, tint: Color) -> void:
	if shown.is_empty():
		return
	var region := _source.region(shown["image"])
	if region != null:
		_blit_texture(region, shown["at"], shown["stretch"], k, centre, tint * shown["tint"])


func _blit_texture(tex: Texture2D, at: Vector2, stretch: Vector2, k: float, centre: Vector2,
		tint: Color) -> void:
	var s := tex.get_size() * stretch * k
	draw_texture_rect(tex, Rect2(centre + at * k - s * 0.5, s), false, tint)
