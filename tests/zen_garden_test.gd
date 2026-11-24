extends Node
## Headless checks for the Zen Garden. Run with:
##   godot --headless tests/zen_garden_test.tscn
##
## The garden's clock is swapped for one the test moves by hand, so a day of
## growing takes no time at all. Wipes saved progress, as the gameplay suite
## does.

var _failures: Array[String] = []
var _checks := 0
var _now: int = 1_000_000


func _ready() -> void:
	await get_tree().process_frame
	Saves.reset_progress()
	_test_config()
	_test_plant_data()
	_test_fits()
	_test_growth_cycle()
	_test_floating_plant()
	_test_slots_and_tools()
	_test_weights()
	await _test_screen()
	Saves.reset_progress()
	print("\n" + "=".repeat(52))
	if _failures.is_empty():
		print("ALL %d ZEN GARDEN CHECKS PASSED" % _checks)
	else:
		print("%d of %d ZEN GARDEN CHECKS FAILED:" % [_failures.size(), _checks])
		for f in _failures:
			print("  - " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("  ok    " if ok else "  FAIL  ") + label + ("" if ok or detail == "" else "  (%s)" % detail))
	if not ok:
		_failures.append(label + ("" if detail == "" else " - " + detail))


func _garden() -> ZenGarden:
	var z := ZenGarden.new()
	z.clock = func() -> int: return _now
	z.rng.seed = 7
	return z


func _advance(z: ZenGarden, ms: int) -> void:
	_now += ms
	z.tick()


func _test_config() -> void:
	print("\n[gardens]")
	var z := _garden()
	check("four gardens, as PVZGE has", z.garden_count() == 4)
	check("main and night have 48 pots", z.slots(0).size() == 48 and z.slots(3).size() == 48)
	check("mushroom has 24 slots, beach 14", z.slots(1).size() == 24 and z.slots(2).size() == 14)
	var open := 0
	for i in z.slots(0).size():
		if z.is_unlocked(0, i):
			open += 1
	check("eight pots in the main garden come unlocked", open == 8, str(open))
	check("the night garden starts locked", not z.is_unlocked(3, 0))
	check("a day to grow fully", z.full_time() == 24 * 3600 * 1000)


func _test_plant_data() -> void:
	print("\n[plant data]")
	check("lily pad floats", Data.plant(&"lilypad").zen_place == &"float")
	check("cactus wants bare ground", Data.plant(&"cactus").zen_place == &"solid")
	check("peashooter grows in dirt", Data.plant(&"peashooter").zen_place == &"dirt")
	check("tangle kelp sits 40 up", is_equal_approx(Data.plant(&"tanglekelp").zen_height, 40.0))
	check("imitater has fixed odds of 1", Data.plant(&"imitater").zen_weight == 1)
	check("an unweighted plant leaves the odds alone", Data.plant(&"peashooter").zen_weight == -1)


func _slot_with(z: ZenGarden, g: int, ground: String, holder: String = "") -> int:
	for i in z.slots(g).size():
		var s: Dictionary = z.slots(g)[i]
		if s["ground"] == ground and (holder == "" or s["holder"] == holder):
			return i
	return -1


func _test_fits() -> void:
	print("\n[what grows where]")
	var z := _garden()
	var water := _slot_with(z, 2, "any", "floater")
	var deck := _slot_with(z, 2, "deck")
	var grass := _slot_with(z, 1, "grass")
	check("a floater takes a lily pad", z.fits(2, water, &"lilypad"))
	check("a deck refuses a lily pad", not z.fits(2, deck, &"lilypad"))
	check("a deck takes a peashooter", z.fits(2, deck, &"peashooter"))
	check("grass refuses a cactus", not z.fits(1, grass, &"cactus"))
	check("a pot takes anything that grows", z.fits(0, 0, &"cactus") and z.fits(0, 0, &"lilypad"))


func _plant(z: ZenGarden, g: int, slot: int, id: StringName) -> Dictionary:
	z.plants().append(z.new_plant(id, g, slot))
	z.save()
	return z.plant_at(g, slot)


## Waters until the plant moves on to its feed; returns how many pours it took.
func _water_out(z: ZenGarden, g: int, slot: int) -> int:
	var pours := 0
	for i in 10:
		_advance(z, 11 * 1000)
		var p := z.plant_at(g, slot)
		if z.need(p) != ZenGarden.Need.WATER:
			break
		z.tend(g, slot)
		pours += 1
	return pours


func _test_growth_cycle() -> void:
	print("\n[growing]")
	Saves.reset_progress()
	var z := _garden()
	_plant(z, 0, 0, &"peashooter")
	_advance(z, 1)
	var p := z.plant_at(0, 0)
	check("a new sprout wants water", z.need(p) == ZenGarden.Need.WATER)
	var pours := _water_out(z, 0, 0)
	# PVZGE counts waterLeftTime down from 3 and asks again until it is
	# below zero.
	check("it takes four pours, as PVZGE's", pours == 4, str(pours))
	p = z.plant_at(0, 0)
	check("then fertilizer", z.need(p) == ZenGarden.Need.FERTILIZER)
	var coins := Saves.currency(&"coins")
	var r := z.tend(0, 0)
	check("feeding grows it to stage 1", r.get("grew_to") == 1 and z.stage(p) == 1)
	check("and pays five silver coins", r["drops"].size() == 5 and r["drops"][0]["value"] == 10)
	check("drops are banked by the screen, not the rules", Saves.currency(&"coins") == coins)
	check("it is growing again", not z.is_stuck(p))
	_advance(z, z.full_time() / 4 + 1000)
	p = z.plant_at(0, 0)
	check("six hours on it stops at the next stage", z.is_stuck(p) and z.stage(p) == 1)
	check("and wants water", z.need(p) == ZenGarden.Need.WATER)
	_water_out(z, 0, 0)
	r = z.tend(0, 0)
	check("stage 2 pays gold", r.get("grew_to") == 2 and r["drops"][0]["value"] == 50)
	_advance(z, z.full_time() / 4 + 1000)
	_water_out(z, 0, 0)
	r = z.tend(0, 0)
	check("stage 3 pays a gem", r.get("grew_to") == 3 and r["drops"][0]["kind"] == &"gems")
	_advance(z, z.full_time() / 4 + 1000)
	_water_out(z, 0, 0)
	p = z.plant_at(0, 0)
	var feed := z.need(p)
	check("a grown plant wants music or pesticide",
			feed == ZenGarden.Need.JUKEBOX or feed == ZenGarden.Need.PESTICIDE, str(feed))
	z.tend(0, 0)
	check("shoveling a grown plant banks a boost", z.shovel(0, 0) and Saves.plant_boosts(&"peashooter") == 1)
	check("the pot is empty again", z.plant_at(0, 0).is_empty())
	var again := ZenGarden.new()
	check("progress is saved", again.plants().is_empty())


func _test_floating_plant() -> void:
	print("\n[floating plants]")
	Saves.reset_progress()
	var z := _garden()
	var water := _slot_with(z, 2, "any", "floater")
	_plant(z, 2, water, &"lilypad")
	_advance(z, 1)
	check("a lily pad skips the watering", z.need(z.plant_at(2, water)) == ZenGarden.Need.FERTILIZER)


func _test_slots_and_tools() -> void:
	print("\n[slots and tools]")
	Saves.reset_progress()
	var z := _garden()
	check("a locked pot cannot be bought without coins", not z.buy_slot(0, 20))
	Saves.add_currency(&"coins", 5000)
	check("4000 coins buys it", z.buy_slot(0, 20) and z.is_unlocked(0, 20)
			and Saves.currency(&"coins") == 1000)
	check("no sprout, no planting", z.plant_sprout(0, 0) == &"")
	Saves.add_currency(&"sprouts", 2)
	var planted := z.plant_sprout(0, 0)
	check("a sprout grows into an owned plant", planted != &"" and Saves.is_plant_unlocked(planted), str(planted))
	check("and is spent", z.sprouts() == 1)
	check("a sprout cannot be lifted", not z.can_lift(0, 0))
	var p := z.plant_at(0, 0)
	p["grown"] = z.full_time() / 4 + 5
	p["stuck"] = false
	check("the glove moves a grown plant", z.move(0, 0, 1) and z.plant_at(0, 1) == p)
	check("not onto a locked pot", not z.move(0, 1, 30))
	check("the wheelbarrow picks it up", z.load_cart(0, 1) and z.plant_at(0, 1).is_empty())
	check("and holds one plant", not z.cart().is_empty())
	var bed := _slot_with(z, 1, "grass")
	Saves.add_currency(&"coins", 4000)
	z.buy_slot(1, bed)
	check("and sets it down in another garden", z.unload_cart(1, bed) and z.cart().is_empty()
			and StringName(z.plant_at(1, bed)["plant"]) == StringName(p["plant"]))


func _test_weights() -> void:
	print("\n[sprout odds]")
	Saves.reset_progress()
	var z := _garden()
	check("a plant you have none of is 8", z.sprout_weight(&"peashooter") == 8)
	_plant(z, 0, 0, &"peashooter")
	check("one is 32", z.sprout_weight(&"peashooter") == 32)
	_plant(z, 0, 1, &"peashooter")
	check("two is 128", z.sprout_weight(&"peashooter") == 128)
	_plant(z, 0, 2, &"peashooter")
	check("three or more is 1", z.sprout_weight(&"peashooter") == 1)
	check("fixed odds win", z.sprout_weight(&"imitater") == 1)


func _test_screen() -> void:
	print("\n[screen]")
	Saves.reset_progress()
	Saves.add_currency(&"sprouts", 3)
	var screen := ZenGardenScreen.new()
	add_child(screen)
	await get_tree().process_frame
	check("the screen opens on the main garden", screen.garden_index == 0
			and screen.slot_view(47) != null)
	screen.click_slot(0)
	check("clicking an empty pot plants a sprout", not screen.model.plant_at(0, 0).is_empty())
	screen.show_garden(1)
	check("next garden switches", screen.garden_index == 1
			and screen.slot_view(23) != null and screen.slot_view(24) == null)
	screen.show_garden(4)
	check("and wraps around", screen.garden_index == 0)
	var view := screen.slot_view(0)
	var at := screen.get_global_transform().affine_inverse() * view.global_position
	check("a click finds the slot under it", screen.slot_at(at) == 0, str(screen.slot_at(at)))
	screen.queue_free()
	await get_tree().process_frame
