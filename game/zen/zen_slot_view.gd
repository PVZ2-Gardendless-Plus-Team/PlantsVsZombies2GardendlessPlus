class_name ZenSlotView
extends Node2D
## One slot of a Zen Garden on screen: its pot or floater, the sprout or
## plant in it, what the plant is asking for, the highlight ring and, while it
## is locked, its price tag.
##
## PVZGE draws a garden in layers - every pot, then every shadow, then every
## plant, then the rings and tags - so a tall plant overlaps the pot in front
## of it. This node lives in the plant layer and puts its other pieces into
## the layers it is handed. Everything is in garden units.

## Seconds for a plant to grow into its new size (PVZGE's 0.7 backInOut).
const GROW_TIME := 0.7
const DISABLED := Color(0.48, 0.48, 0.48)
## How far apart a placeholder plant's lettering sits, in garden units.
const FALLBACK_RADIUS := 95.0

var garden: ZenGarden
var g: int = 0
var index: int = 0
var slot: Dictionary = {}

var holder: Armature = null
var sprout: Armature = null
var plant_art: Armature = null
var need_art: Armature = null
var shade: Armature = null
var selection: Armature = null
var price_tag: Node2D = null

## What is drawn now, so a refresh only rebuilds what changed.
var shown_plant: StringName = &""
var shown_stage: int = -1
var shown_need: int = ZenGarden.Need.NONE
## A feed being played out: the slot keeps showing the old stage until the
## prop's "grow" moment.
var acting: bool = false
var disabled: bool = false
var hovered: bool = false

var _pots: Node2D
var _shades: Node2D
var _ui: Node2D


func setup(model: ZenGarden, garden_index: int, slot_index: int,
		pots: Node2D, shades: Node2D, ui: Node2D) -> void:
	garden = model
	g = garden_index
	index = slot_index
	slot = model.slots(g)[slot_index]
	_pots = pots
	_shades = shades
	_ui = ui
	position = Vector2(float(slot["x"]), float(slot["y"]))
	match String(slot.get("holder", "none")):
		"pot":
			holder = _rig(&"pot", pots)
		"floater":
			holder = _rig(&"floater", pots)
	selection = _rig(&"selection", ui)
	_play(selection, &"selection", &"none")


func _rig(id: StringName, layer: Node2D) -> Armature:
	var art := Art.make(&"zen", id)
	if art == null:
		return null
	var host := Node2D.new()
	host.position = position
	host.add_child(art)
	layer.add_child(host)
	return art


func _play(art: Armature, id: StringName, state: StringName, loop := true) -> void:
	if art == null:
		return
	var anim := Art.animation_for(&"zen", id, state)
	if anim != &"":
		art.play(anim, loop, true)


## Brings the slot in line with the garden. `animate` lets a plant that has
## moved up a stage grow into its size instead of jumping.
func refresh(animate: bool = true) -> void:
	var p := garden.plant_at(g, index)
	var unlocked := garden.is_unlocked(g, index)
	_show_price(not unlocked)
	if p.is_empty():
		_clear_plant()
		if sprout == null:
			sprout = _own_rig(&"sprout")
		_play(sprout, &"sprout", &"empty" if unlocked and garden.sprouts() > 0 else &"none")
		_holder_state(&"", false)
		_show_need(ZenGarden.Need.NONE)
	else:
		var id := StringName(p["plant"])
		var st := garden.stage(p)
		if not acting:
			_show_plant(id, st, animate)
		_holder_state(id, garden.is_stuck(p))
		if not acting:
			_show_need(garden.need(p))
	_tint()
	queue_redraw()


func _own_rig(id: StringName) -> Armature:
	var art := Art.make(&"zen", id)
	if art != null:
		add_child(art)
	return art


func _show_plant(id: StringName, st: int, animate: bool) -> void:
	if id == shown_plant and st == shown_stage:
		return
	var was_stage := shown_stage if id == shown_plant else -1
	shown_plant = id
	shown_stage = st
	if st <= 0:
		_drop_plant_art()
		if sprout == null:
			sprout = _own_rig(&"sprout")
		_play(sprout, &"sprout", &"idle")
		return
	var target := ZenGarden.scale_for(st)
	if plant_art == null or was_stage < 0:
		_drop_plant_art()
		var def := Data.plant(id)
		plant_art = ZenPlantArt.make(id, 1.0, def.zen_height if def != null else 0.0)
		if plant_art != null:
			add_child(plant_art)
			plant_art.scale = Vector2.ONE * (0.0 if animate and was_stage == 0 else target)
		_ensure_shade()
	if sprout != null:
		sprout.queue_free()
		sprout = null
	if plant_art != null:
		if animate:
			var t := create_tween()
			t.tween_property(plant_art, "scale", Vector2.ONE * target, GROW_TIME) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		else:
			plant_art.scale = Vector2.ONE * target
	if shade != null:
		shade.get_parent().scale = Vector2.ONE * target


func _ensure_shade() -> void:
	if shade == null:
		shade = _rig(&"shade", _shades)
		if shade != null:
			_play(shade, &"shade", &"idle")
			shade.get_parent().modulate.a = 0.5


func _drop_plant_art() -> void:
	if plant_art != null:
		plant_art.queue_free()
		plant_art = null
	if shade != null:
		shade.get_parent().queue_free()
		shade = null


func _clear_plant() -> void:
	_drop_plant_art()
	shown_plant = &""
	shown_stage = -1


## PVZGE's pot: plain while the plant waits on the player, golden while it
## grows; wet for plants that live in water.
func _holder_state(id: StringName, stuck: bool) -> void:
	if holder == null:
		return
	var watery := false
	if id != &"":
		var place := ZenGarden.place_of(id)
		watery = place == &"float" or place == &"sink" \
				or (place == &"fly" and String(slot.get("holder", "")) == "floater")
	var state := &"idle"
	if id != &"":
		state = (&"water" if watery else &"idle") if stuck \
				else (&"water_golden" if watery else &"golden")
	var holder_id := &"pot" if String(slot.get("holder", "")) == "pot" else &"floater"
	_play(holder, holder_id, state)


func _show_need(need: int) -> void:
	if need == shown_need and (need == ZenGarden.Need.NONE or need_art != null):
		return
	shown_need = need
	if need_art != null:
		need_art.queue_free()
		need_art = null
	if need == ZenGarden.Need.NONE:
		return
	var id: StringName = ZenGarden.NEED_NAMES[need]
	need_art = _own_rig(id)
	_play(need_art, id, &"idle")


## Plays the player answering the plant's need. `on_grow` runs at the prop's
## grow moment, when the plant should take its new size; the prop removes
## itself when its animation ends. Returns the seconds until the grow.
func play_tend(need: int, on_grow: Callable) -> float:
	var id: StringName = ZenGarden.NEED_NAMES[need]
	var timing: Dictionary = ZenGardenScreen.PROP_TIMING[id]
	var art := need_art
	need_art = null
	shown_need = ZenGarden.Need.NONE
	if art == null:
		art = _own_rig(id)
	_play(art, id, &"play", false)
	if art != null:
		get_tree().create_timer(float(timing["die"])).timeout.connect(art.queue_free)
	if need == ZenGarden.Need.WATER:
		return 0.0
	acting = true
	var grow_at := float(timing["grow"])
	get_tree().create_timer(grow_at).timeout.connect(func() -> void:
		acting = false
		on_grow.call())
	return grow_at


## The sprout's own Grow, before its first plant comes up.
func play_sprout_grow() -> float:
	if sprout == null:
		return 0.0
	_play(sprout, &"sprout", &"grow", false)
	return ZenGardenScreen.SPROUT_GROW_AT


func play_birth() -> void:
	if sprout == null:
		sprout = _own_rig(&"sprout")
	_play(sprout, &"sprout", &"birth", false)


func set_hovered(value: bool) -> void:
	if value == hovered:
		return
	hovered = value
	_play(selection, &"selection", &"yellow" if value else &"none")
	queue_redraw()


func set_disabled(value: bool) -> void:
	if value == disabled:
		return
	disabled = value
	_tint()
	queue_redraw()


func _tint() -> void:
	var c := DISABLED if disabled else Color.WHITE
	modulate = c
	if holder != null:
		holder.get_parent().modulate = c


func _show_price(locked: bool) -> void:
	if not locked:
		if price_tag != null:
			price_tag.queue_free()
			price_tag = null
		return
	if price_tag == null:
		price_tag = ZenPriceTag.new(garden.slot_price())
		price_tag.position = position
		_ui.add_child(price_tag)
	price_tag.affordable = garden.can_buy_slot(g, index)
	price_tag.queue_redraw()


## Placeholders for a build with no extracted art: a ring for the pot, the
## plant's name, and the need as a word.
func _draw() -> void:
	if holder == null and String(slot.get("holder", "none")) != "none":
		var colour := Color(0.62, 0.34, 0.18) if slot["holder"] == "pot" else Color(0.75, 0.2, 0.2)
		draw_circle(Vector2(0, -20), 90.0, colour)
		draw_circle(Vector2(0, -30), 70.0, Color(0.33, 0.2, 0.12))
	if hovered and selection == null:
		draw_arc(Vector2.ZERO, 130.0, 0.0, TAU, 32, Color(1, 0.9, 0.2), 8.0)
	var font := ThemeDB.fallback_font
	if shown_plant != &"" and plant_art == null and (shown_stage > 0 or sprout == null):
		var label := ZenPlantArt.display_name(shown_plant) if shown_stage > 0 else "sprout"
		draw_string(font, Vector2(-FALLBACK_RADIUS * 2, -60), label,
				HORIZONTAL_ALIGNMENT_CENTER, FALLBACK_RADIUS * 4, 34)
	if shown_need != ZenGarden.Need.NONE and need_art == null:
		draw_string(font, Vector2(-FALLBACK_RADIUS, -140),
				String(ZenGarden.NEED_NAMES[shown_need]),
				HORIZONTAL_ALIGNMENT_CENTER, FALLBACK_RADIUS * 2, 40, Color(0.6, 0.9, 1))
