extends Node2D
## Headless end-to-end checks. Run with:
##   godot --headless tests/gameplay_test.tscn
##
## Time is scaled up so that real plant intervals (a peashooter fires every
## 1.35s) resolve in a short run without faking any game logic.

const TIME_SCALE := 25.0

var _failures: Array[String] = []
var _checks := 0
## Sections that announced themselves, and the ones that ran to completion.
## A GDScript runtime error aborts the calling function without failing the
## run, so a section that starts and never finishes has to be caught here.
var _sections_started: Array[String] = []
var _sections_finished: Array[String] = []


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	await get_tree().process_frame
	await _run()
	Engine.time_scale = 1.0
	_report()


func _run() -> void:
	# Saves live in user:// and outlast a run. Left in place, a level that
	# resumes a previous run's state makes later checks meaningless.
	_clear_all_saves()
	_test_all_scripts_compile()
	_test_data_loaded()
	_test_inheritance_and_tags()
	_test_tag_inversion()
	await _test_peashooter_kills_zombie()
	await _test_sunflower_produces_sun()
	await _test_sun_value_and_hover()
	await _test_spawn_spacing()
	await _test_armor_absorbs_damage()
	await _test_level_runner_spawns_waves()
	_test_entity_taxonomy()
	await _test_allegiance()
	_test_zombie_seed_packets()
	_test_plantable_lanes()
	_test_tutorial_levels_playable()
	await _test_seed_cooldowns()
	await _test_armor_visual_state()
	await _test_armed_mine_is_not_food()
	await _test_sun_expires()
	await _test_mowers()
	await _test_plant_food()
	await _test_input_actions()
	_test_shovel()
	await _test_conveyor_belt()
	_test_audio()
	await _test_objectives()
	await _test_overhaul_scale_mod()
	_test_plant_behaviour_coverage()
	await _test_new_plant_behaviours()
	await _test_reactive_plants()
	await _test_lawn_support_plants()
	await _test_shooting_plants()
	await _test_defence_plants()
	await _test_zombie_status_effects()
	_test_zombie_behaviour_coverage()
	_test_zombie_archetypes()
	await _test_zombie_behaviours()
	await _test_zombie_resistances()
	await _test_zomboss()
	await _test_plant_stun()
	await _test_art()
	await _test_scenery_art()
	_test_zombie_sun_costs()
	await _test_level_save_state()
	_test_simplified_level_schema()
	_test_terrain_rules()
	await _test_grid_items()
	await _test_level_set_up()
	await _test_seed_chooser()
	await _test_lawn_components()
	await _test_level_features()
	await _test_wave_events()
	await _test_working_tiles()
	await _test_star_challenges()
	await _test_natural_win_condition()
	await _test_campaign_progression()
	await _test_rewards()
	_test_settings()
	_test_world_unlocks()
	await _test_menu_flow()
	_test_modding()


# --- checks --------------------------------------------------------------

## Marks a test section as begun. Pair every call with `end_section`.
func section(name: String) -> void:
	print("\n[%s]" % name)
	_sections_started.append(name)


func end_section() -> void:
	if not _sections_started.is_empty():
		_sections_finished.append(_sections_started[-1])


func check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s%s" % [label, ("  (%s)" % detail) if detail else ""])


func check_eq(label: String, actual, expected) -> void:
	check(label, actual == expected, "got %s, expected %s" % [str(actual), str(expected)])


# --- tests ---------------------------------------------------------------

## Loads every GDScript in the project. The gameplay tests only touch the
## classes they use, so a parse error in a scene script - main.gd especially -
## would otherwise slip through to runtime.
func _test_all_scripts_compile() -> void:
	print("\n[scripts]")
	var bad: Array[String] = []
	var count := 0
	for path in _gd_files("res://"):
		count += 1
		var res = load(path)
		if not (res is GDScript):
			bad.append(path)
	check("every .gd compiles", bad.is_empty(),
			"failed: %s" % str(bad) if not bad.is_empty() else "")
	print("        (%d scripts checked)" % count)


## Every .gd under `root`, skipping Godot's own metadata directory.
func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				pass
			elif dir.current_is_dir():
				pending.append(dir_path.path_join(name))
			elif name.ends_with(".gd"):
				out.append(dir_path.path_join(name))
			name = dir.get_next()
		dir.list_dir_end()
	return out


func _test_data_loaded() -> void:
	print("\n[data]")
	check("zombies loaded", Data.zombies.size() > 400)
	check("plants loaded", Data.plants.size() > 200)
	check("levels loaded", Data.levels.size() >= 4)
	check("no load errors", Data.errors().is_empty(), str(Data.errors()))
	check("peashooter exists", Data.plant(&"peashooter") != null)
	check("tutorial zombie exists", Data.zombie(&"tutorial") != null)


func _test_inheritance_and_tags() -> void:
	print("\n[inheritance]")
	# tutorial_armor1 is untouched by any pack, so it shows base values.
	var z := Data.zombie(&"tutorial_armor1")
	check_eq("extends archetype", z.extends_id, &"normal")
	check_eq("toughness from data", z.stat(&"toughness"), 190)
	check("inherited archetype tags", z.has_tag(&"swallowable"))

	var p := Data.plant(&"peashooter")
	check("peashooter has shooter component", p.components_of(&"shooter").size() == 1)
	check_eq("shoot interval", p.components_of(&"shooter")[0].cfg(&"interval"), 1.35)


func _test_tag_inversion() -> void:
	print("\n[tag inversion]")
	# The whole point of the inversion: a gargantuar is NOT swallowable, and we
	# can find that out without any plant-specific field on the zombie.
	var garg := Data.zombie(&"beach_gargantuar")
	check("gargantuar not swallowable", garg != null and not garg.has_tag(&"swallowable"))
	check("basic zombie is swallowable", Data.zombie(&"tutorial_armor1").has_tag(&"swallowable"))

	var swallowable := Data.query(&"zombie", [&"swallowable"])
	var immune := Data.query(&"zombie", [], [&"swallowable"])
	check("query splits the roster", swallowable.size() > 0 and immune.size() > 0,
			"%d swallowable / %d immune" % [swallowable.size(), immune.size()])


func _test_peashooter_kills_zombie() -> void:
	print("\n[combat]")
	var board := _make_board()
	var plant := board.place_plant(&"peashooter", 2, 1)
	check("peashooter placed", plant != null)
	var zombie := board.spawn_zombie(&"tutorial", 2)
	check("zombie spawned", zombie != null)
	var expected_hp: float = float(Data.zombie(&"tutorial").stat(&"toughness"))
	check_eq("zombie health from data", zombie.max_health, expected_hp)

	var start_x: float = zombie.position.x
	# 260 HP / 20 dmg = 13 peas at 1.35s = ~18s of game time.
	await _wait_game_seconds(26.0)

	check("zombie moved toward house", zombie == null or not is_instance_valid(zombie)
			or zombie.position.x < start_x)
	check("zombie died to peas", not is_instance_valid(zombie) or zombie.is_dead,
			"health left %s" % (zombie.health if is_instance_valid(zombie) else "gone"))
	board.queue_free()


func _test_sunflower_produces_sun() -> void:
	print("\n[sun]")
	var board := _make_board()
	var before: int = board.sun
	var sf := board.place_plant(&"sunflower", 1, 1)
	check("sunflower placed", sf != null)

	# first_delay is 5s +/- 5, so 14s covers the worst case. Watch as it
	# happens rather than counting at the end - a sun dropped early would
	# have expired by then and the check would read as a failure.
	var seen := false
	var waited := 0.0
	while waited < 14.0 and not seen:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if board.get_node("Suns").get_child_count() > 0:
			seen = true
	check("sunflower dropped sun", seen, "none seen in %.0fs" % waited)
	board.queue_free()


func _test_sun_value_and_hover() -> void:
	print("\n[sun value + hover]")
	check_eq("sun value is the constant 50", SunToken.VALUE, 50)

	var board := _make_board()
	var before: int = board.sun
	board.drop_sun(board.grid_to_world(2, 3))
	var suns := board.get_node("Suns")
	check_eq("one sun on the board", suns.get_child_count(), 1)

	var token: SunToken = suns.get_child(0)

	# Hover reach: inside the radius counts, well outside does not.
	check("hover hits at the centre", token.contains_point(token.global_position))
	check("hover hits within the radius",
			token.contains_point(token.global_position + Vector2(token.radius * 0.5, 0)))
	check("hover misses well outside",
			not token.contains_point(token.global_position + Vector2(200, 0)))

	token.collect()
	check_eq("not banked until it reaches the counter", board.sun, before)

	# collect() is idempotent, so hover polling every frame during the flight
	# cannot collect the same sun twice.
	token.collect()
	token.collect()

	await _wait_game_seconds(token.fly_time + 0.4)
	check_eq("collecting grants 50 sun exactly once", board.sun, before + 50)
	check("sun token freed after banking", not is_instance_valid(token))
	board.queue_free()


func _test_spawn_spacing() -> void:
	print("\n[spawn spacing]")
	var board := _make_board()
	var runner := LevelRunner.new()
	runner.first_wave_delay = 0.0
	add_child(runner)

	# Four zombies into one lane - the case that used to stack them exactly.
	runner.start({
		"id": "spacing_test",
		"waves": [{"kind": "spawn", "zombies": [
			{"type": "tutorial", "row": 3}, {"type": "tutorial", "row": 3},
			{"type": "tutorial", "row": 3}, {"type": "tutorial", "row": 3}]}],
		"wave_settings": {"count": 1},
	}, board)

	await _wait_game_seconds(0.5)
	var lane := board.zombies_in_row(2)
	check_eq("all four spawned in the lane", lane.size(), 4)

	if lane.size() == 4:
		# zombies_in_row sorts nearest-house first, so walk the gaps.
		var min_gap := INF
		var overlapping := false
		for i in range(1, lane.size()):
			var gap: float = absf(lane[i].position.x - lane[i - 1].position.x)
			min_gap = minf(min_gap, gap)
			if gap < 1.0:
				overlapping = true
		check("no two zombies share a position", not overlapping)
		# spawn_spacing is a floor, not an average - jitter only ever widens.
		var expected: float = runner.spawn_spacing * board.cell_size.x
		check("every gap clears the spacing floor", min_gap >= expected - 0.5,
				"smallest gap %.1fpx, floor %.1fpx" % [min_gap, expected])
		# And that floor has to actually clear a zombie's body.
		var body_width: float = lane[0].body_size.x
		check("spacing floor exceeds zombie width", expected > body_width,
				"%.1fpx spacing vs %.1fpx body" % [expected, body_width])

	runner.queue_free()
	board.queue_free()


func _test_armor_absorbs_damage() -> void:
	print("\n[armor]")
	var board := _make_board()
	var z := board.spawn_zombie(&"tutorial_armor2", 0)
	check("armored zombie spawned", z != null)
	var armor := z.component(&"armor")
	check("armor component attached", armor != null)
	if armor != null:
		check_eq("armor durability from data", armor.durability, 1100.0)
		var body_before: float = z.health
		z.take_damage(500.0)
		check("armor absorbed the hit", z.health == body_before,
				"body went %s -> %s" % [body_before, z.health])
		check_eq("durability reduced", armor.durability, 600.0)
		z.take_damage(600.0)
		check("armor broke, body still full", z.health == body_before)
		z.take_damage(50.0)
		check("damage reaches body once armor is gone", z.health < body_before)
	board.queue_free()


func _test_level_runner_spawns_waves() -> void:
	print("\n[level]")
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)

	var level := Data.level(&"tutorial_1")
	check("tutorial_1 level found", not level.is_empty())
	var seeds: Array = []
	runner.seedbank_ready.connect(func(ids): seeds.assign(ids))
	runner.start(level, board)
	check_eq("seedbank is peashooter only", seeds,
			[{"kind": &"plant", "id": &"peashooter"}])
	check_eq("level has 3 waves", runner.waves.size(), 3)

	await _wait_game_seconds(16.0)
	check("first wave spawned zombies", board.zombie_count() > 0,
			"%d on board" % board.zombie_count())
	runner.queue_free()
	board.queue_free()


func _test_modding() -> void:
	print("\n[modding]")
	var pack_installed := false
	for m in Mods.priority_list():
		if String(m["id"]) == "example_pack":
			pack_installed = true
	check("example_pack is installed", pack_installed)
	if not pack_installed:
		return

	# 1. custom zombie
	var sprinter := Data.zombie(&"sprinter")
	check("mod added a new zombie", sprinter != null)
	if sprinter != null:
		check_eq("custom zombie stats", sprinter.stat(&"speed"), 0.55)
		check("custom tag applied", sprinter.has_tag(&"fast"))
		check("tag removal applied", not sprinter.has_tag(&"swallowable"))
		check("archetype tags still inherited", sprinter.has_tag(&"chompable"))

	# 2. data override of an existing entity
	var tut := Data.zombie(&"tutorial")
	check_eq("mod overrode base zombie stats", tut.stat(&"toughness"), 260)
	check_eq("override came from the pack", tut.source_mod, &"example_pack")

	# 3. custom plant using a mod-supplied behaviour
	var splitpea := Data.plant(&"splitpea_mk2")
	check("mod added a new plant", splitpea != null)
	check("new component type registered", Components.has_type(&"burst_shooter"))
	check_eq("burst_shooter owned by pack", Components.owner_of(&"burst_shooter"), &"example_pack")

	# 4. a pack can be installed but switched off
	check("example_override is installed", Mods.is_installed(&"example_override"))
	check("example_override is disabled", not Mods.is_enabled(&"example_override"))
	check_eq("disabled pack does not override a built-in",
			Components.owner_of(&"sun_producer"), &"base")

	# 5. overriding a BUILT-IN still works, tested directly so the capability
	#    is proven without a pack altering base balance by default.
	var original: GDScript = load("res://core/components/builtin/sun_producer.gd")
	var replacement: GDScript = load("res://mods/example_override/components/sun_producer.gd")
	var announced := [false]
	var on_override := func(type, _old, _new): announced[0] = (type == &"sun_producer")
	Components.type_overridden.connect(on_override)
	Components.register(&"sun_producer", replacement, &"test_override")
	check_eq("a built-in can be replaced", Components.owner_of(&"sun_producer"),
			&"test_override")
	check("the override is announced", announced[0])
	Components.register(&"sun_producer", original, &"base")
	Components.type_overridden.disconnect(on_override)
	check_eq("restored to the built-in", Components.owner_of(&"sun_producer"), &"base")

	# 6. custom level
	var lvl := Data.level(&"example_showdown")
	check("mod added a new level", not lvl.is_empty())
	check_eq("custom level wave count", (lvl.get("waves", []) as Array).size(), 3)

	# 7. the modded plant actually runs the modded component
	var board := _make_board()
	var p := board.place_plant(&"splitpea_mk2", 2, 1)
	check("modded plant spawns", p != null)
	if p != null:
		check("modded plant runs mod component", p.component(&"burst_shooter") != null)
	board.queue_free()


func _test_entity_taxonomy() -> void:
	print("\n[taxonomy]")
	check("graves loaded", Data.graves.size() >= 30, "%d" % Data.graves.size())
	check("objects loaded", Data.objects.size() >= 50, "%d" % Data.objects.size())

	# Graves are destroyable and carry grid-item events.
	var grave := Data.grave(&"gravestone")
	check("a grave has toughness", grave != null and grave.toughness > 0.0)
	var cabinet := Data.grave(&"eightiesarcadecabinet")
	check("a grave can summon", cabinet != null
			and cabinet.component_spec(&"grave_summon") != null)
	# Every component type the data references must actually exist, or the
	# entity spawns with a missing behaviour and only a warning.
	check("grave_summon is implemented", Components.has_type(&"grave_summon"))
	var missing: Array[StringName] = []
	for pool in [Data.zombies, Data.plants, Data.graves, Data.objects]:
		for id in pool:
			for spec in (pool[id] as EntityDef).components:
				if not Components.has_type(spec.type) and not missing.has(spec.type):
					missing.append(spec.type)
	check("no data references an unknown component type", missing.is_empty(),
			str(missing))

	# Evil potions are objects, not plants - PVZGE files them as plants, which
	# would otherwise let them into seed banks and level generation.
	check("potion is not a plant", Data.plant(&"zombiepotion_speed") == null)
	var potion := Data.board_object(&"zombiepotion_speed")
	check("potion is an object", potion != null)
	if potion != null:
		check_eq("potion category", potion.category, ObjectDef.Category.POTION)
	var tile := Data.board_object(&"goldtile")
	check("tiles are objects", tile != null)
	if tile != null:
		check_eq("tile category", tile.category, ObjectDef.Category.TILE)


func _test_allegiance() -> void:
	print("\n[allegiance]")
	var board := _make_board()
	var hostile := board.spawn_zombie(&"tutorial", 2)
	var charmed := board.spawn_zombie(&"tutorial", 2)
	check("both zombies spawned", hostile != null and charmed != null)

	check("zombies start hostile", not hostile.is_charmed())
	check_eq("hostile walks toward the house", hostile.direction(), -1)

	charmed.charm()
	check("charmed zombie reports charmed", charmed.is_charmed())
	check_eq("charmed walks the other way", charmed.direction(), 1)
	check("charming sets a runtime tag", charmed.has_tag(&"charmed"))

	check_eq("lane still holds both", board.zombies_in_row(2).size(), 2)
	check_eq("only one is hostile", board.hostile_zombies_in_row(2).size(), 1)
	check_eq("only one is charmed", board.charmed_zombies_in_row(2).size(), 1)
	# Win conditions must not wait on the player's own zombies.
	check_eq("charmed excluded from zombie_count", board.zombie_count(), 1)

	# A pea must not hit the player's own zombie. Move the hostile one well
	# clear first, since both spawn on the same line.
	hostile.position.x += 400.0
	var pea := board.spawn_projectile(&"pea", 2, charmed.position - Vector2(40, 0), null)
	check("projectile ignores charmed zombies",
			not pea._check_hit(charmed.position.x - 5.0, charmed.position.x + 5.0))
	check("projectile still hits hostile zombies",
			pea._check_hit(hostile.position.x - 5.0, hostile.position.x + 5.0))
	board.queue_free()


func _test_zombie_seed_packets() -> void:
	print("\n[zombie seed packets]")
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)

	# An I-Zombie style level: the seed bank holds zombies, not plants.
	runner.start({
		"id": "izombie_test",
		"seedbank": {"mode": "chooser", "kind": "zombie",
					 "preset": ["tutorial", "tutorial_armor1"]},
		"waves": [],
	}, board)

	var seeds := runner.seedbank_seeds()
	check_eq("seed bank holds two zombies", seeds.size(), 2)
	if seeds.size() == 2:
		check_eq("seeds are zombie kind", seeds[0]["kind"], &"zombie")
		check_eq("seed id carried", seeds[0]["id"], &"tutorial")

	var placed := board.place_entity(&"zombie", &"tutorial", 1, 4)
	check("a zombie can be placed from a packet", placed is Zombie)
	if placed != null:
		check("placed zombie landed in its lane",
				board.zombies_in_row(1).has(placed))
	# A lane takes any number of zombies, unlike a plant cell.
	check("zombies do not block their cell",
			board.can_place_entity(&"zombie", &"tutorial", 1, 4))
	runner.queue_free()
	board.queue_free()


func _test_plantable_lanes() -> void:
	print("\n[plantable lanes]")
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)
	var level := Data.level(&"tutorial_1")
	runner.start(level, board)

	var rows: Array = level.get("plantable_rows", [])
	check_eq("tutorial 1 restricts planting to one lane", rows.size(), 1)
	check_eq("and that lane is 3", int(rows[0]) if rows.size() > 0 else -1, 3)
	# Level rows are 1-based; the board is 0-based.
	check("lane 3 is plantable", board.is_row_plantable(2))
	check("lane 1 is locked", not board.is_row_plantable(0))
	check("planting is refused in a locked lane",
			board.place_plant(&"peashooter", 0, 1) == null)
	check("planting works in the open lane",
			board.place_plant(&"peashooter", 2, 1) != null)

	# Other levels leave every lane open.
	var board2 := _make_board()
	var runner2 := LevelRunner.new()
	add_child(runner2)
	runner2.start(Data.level(&"tutorial_2"), board2)
	check("tutorial 2 leaves lanes open", board2.is_row_plantable(0))

	runner.queue_free()
	runner2.queue_free()
	board.queue_free()
	board2.queue_free()


func _test_tutorial_levels_playable() -> void:
	print("\n[tutorial levels]")
	var campaign := Data.campaign(&"tutorial")
	check("tutorial campaign exists", campaign != null)
	if campaign == null:
		return
	check_eq("campaign has four levels", campaign.levels.size(), 4)
	check_eq("in order", campaign.levels,
			[&"tutorial_1", &"tutorial_2", &"tutorial_3", &"tutorial_4"] as Array[StringName])

	# Every level must be loadable, have waves, and reference only content
	# that actually exists - otherwise it stalls partway through.
	var runner := LevelRunner.new()
	add_child(runner)
	for level_id in campaign.levels:
		var level := Data.level(level_id)
		if level.is_empty():
			check("%s exists" % level_id, false)
			continue

		var waves: Array = level.get("waves", [])
		check("%s has waves" % level_id, not waves.is_empty())

		# Seeds resolve.
		var board := _make_board()
		runner.start(level, board)
		var seeds := runner.seedbank_seeds()
		check("%s has a seed bank" % level_id, not seeds.is_empty())
		var bad_seeds: Array = []
		for seed in seeds:
			var def: EntityDef = (Data.zombie(seed["id"]) if seed["kind"] == &"zombie"
					else Data.plant(seed["id"]))
			if def == null:
				bad_seeds.append(seed["id"])
		check("%s seeds all exist" % level_id, bad_seeds.is_empty(), str(bad_seeds))

		# Every seed's behaviour is implemented, or the plant does nothing.
		var inert: Array = []
		for seed in seeds:
			var def := Data.plant(seed["id"])
			if def != null and def.components.is_empty():
				inert.append(seed["id"])
		check("%s seeds all do something" % level_id, inert.is_empty(), str(inert))

		# Wave zombies resolve.
		var bad_zombies: Array = []
		for wave in waves:
			for entry in _wave_zombies(wave):
				var zid := StringName(entry.get("type", &""))
				if Data.zombie(zid) == null and not bad_zombies.has(zid):
					bad_zombies.append(zid)
		check("%s zombies all exist" % level_id, bad_zombies.is_empty(), str(bad_zombies))

		board.queue_free()
	runner.queue_free()


## Zombie entries in a wave, flattening `multi` bundles.
func _wave_zombies(wave: Dictionary) -> Array:
	var out: Array = []
	if wave.get("kind") == "multi":
		for sub in (wave.get("actions", []) as Array):
			if sub is Dictionary:
				out.append_array(_wave_zombies(sub))
	else:
		out.append_array(wave.get("zombies", []))
	return out


## The runner must declare victory on its own once the last wave is spawned
## and the board is clear - not only when something calls _on_won().
func _test_natural_win_condition() -> void:
	print("\n[win condition]")
	var board := _make_board()
	var runner := LevelRunner.new()
	runner.first_wave_delay = 0.0
	add_child(runner)

	var won := [false]
	runner.level_complete.connect(func(): won[0] = true)
	runner.start({
		"id": "win_test",
		"seedbank": {"mode": "chooser", "preset": ["peashooter"]},
		"waves": [{"kind": "spawn", "zombies": [{"type": "tutorial", "row": 3}]}],
		"wave_settings": {"count": 1},
	}, board)

	await _wait_game_seconds(0.5)
	check_eq("the wave spawned", board.zombie_count(), 1)
	check("not won while a zombie lives", not won[0])

	for z in board.zombies_in_row(2):
		z.take_damage(99999.0)
	await _wait_game_seconds(0.5)

	check_eq("board is clear", board.zombie_count(), 0)
	check("runner declares victory", won[0])
	check("runner stops after winning", not runner.running)

	runner.queue_free()
	board.queue_free()


func _test_campaign_progression() -> void:
	print("\n[progression]")
	var campaign := Data.campaign(&"tutorial")
	check_eq("next after 1 is 2", campaign.next_after(&"tutorial_1"), &"tutorial_2")
	check_eq("next after 3 is 4", campaign.next_after(&"tutorial_3"), &"tutorial_4")
	check_eq("nothing after the last", campaign.next_after(&"tutorial_4"), &"")
	check("last level is flagged", campaign.is_last(&"tutorial_4"))
	check("first level is not", not campaign.is_last(&"tutorial_1"))

	# Drive the real entry scene: clearing a level must load the next one.
	var main = load("res://game/main.tscn").instantiate()
	main.level_transition_delay = 0.05
	main.retry_delay = 0.05
	add_child(main)
	await get_tree().process_frame
	check_eq("starts at the first level", main._current_level, &"tutorial_1")

	main._on_won()
	check_eq("a win waits for its prize", main._current_level, &"tutorial_1")
	await _collect_reward(main)
	await _wait_game_seconds(0.4)
	check_eq("clearing a level advances", main._current_level, &"tutorial_2")
	check("board was cleared for the next level", main.board.zombie_count() == 0)

	# Losing repeats the same level rather than advancing.
	main._on_lost()
	await _wait_game_seconds(0.4)
	check_eq("losing retries the same level", main._current_level, &"tutorial_2")

	# Finishing the last level ends the campaign instead of wrapping around.
	main.load_level(&"tutorial_4")
	await get_tree().process_frame
	main._on_won()
	await _collect_reward(main)
	await _wait_game_seconds(0.4)
	check_eq("last level does not advance", main._current_level, &"tutorial_4")
	check_eq("campaign completion is announced", main._status.text,
			campaign.completion_message)
	main.queue_free()


func _test_settings() -> void:
	section("settings")
	var before := {}
	for key in Settings.DEFAULTS:
		before[key] = Settings.get_value(key)

	Settings.set_value(&"music_volume", 0.25)
	check_eq("a value is stored", Settings.get_value(&"music_volume"), 0.25)
	Settings.set_value(&"fullscreen", 1.0)
	check_eq("a slider value cannot retype a toggle",
			typeof(Settings.get_value(&"fullscreen")), TYPE_BOOL)
	Settings.set_value(&"no_such_option", 3)
	check("unknown options are refused", Settings.get_value(&"no_such_option") == null)

	Settings.load_settings()
	check_eq("values survive a reload", Settings.get_value(&"music_volume"), 0.25)
	Settings.reset_to_defaults()
	check_eq("defaults restore", Settings.get_value(&"music_volume"),
			Settings.DEFAULTS[&"music_volume"])

	# The settings file belongs to whoever runs the tests; put it back.
	for key in before:
		Settings.set_value(key, before[key])
	end_section()


func _test_world_unlocks() -> void:
	section("world unlocks")
	var c := CampaignDef.from_dict({"id": "w", "levels": ["a", "b", "c"],
			"order": 3, "unlock_after": "tutorial", "map_color": "#102030",
			"description": "d"})
	check_eq("order is read", c.order, 3)
	check_eq("unlock_after is read", c.unlock_after, &"tutorial")
	check_eq("map colour is read", c.map_color, Color.html("#102030"))

	var done := {}
	var cleared := func(id: StringName) -> bool: return done.has(id)
	check("the first level is always open", c.is_level_unlocked(&"a", cleared))
	check("the second waits for the first", not c.is_level_unlocked(&"b", cleared))
	check_eq("next to play is the first", c.next_unplayed(cleared), &"a")
	done[&"a"] = true
	check("clearing opens the next", c.is_level_unlocked(&"b", cleared))
	check("but not the one after", not c.is_level_unlocked(&"c", cleared))
	check_eq("next to play moves on", c.next_unplayed(cleared), &"b")
	check("not complete yet", not c.is_complete(cleared))
	done[&"b"] = true
	done[&"c"] = true
	check("complete once all are cleared", c.is_complete(cleared))
	check("unknown levels are never open", not c.is_level_unlocked(&"z", cleared))

	var worlds := Data.world_campaigns()
	check("the tutorial is on the map", worlds.any(
			func(w: CampaignDef) -> bool: return w.id == &"tutorial"))
	for i in range(1, worlds.size()):
		check("worlds are in map order", worlds[i - 1].order <= worlds[i].order)

	Saves.reset_progress()
	var tutorial := Data.campaign(&"tutorial")
	check("the tutorial world starts open", WorldMap.is_world_open(tutorial))
	var neon := Data.campaign(&"neon")
	if neon != null:
		check("a gated world starts locked", not WorldMap.is_world_open(neon))
		for level_id in tutorial.levels:
			Saves.mark_cleared(level_id)
		check("finishing its gate opens it", WorldMap.is_world_open(neon))
		Saves.reset_progress()
	end_section()


## Drives the real shell: title -> map -> level -> pause -> map.
func _test_menu_flow() -> void:
	section("menu flow")
	_clear_all_saves()
	for action in ["Pause"]:
		check("action '%s' exists" % action, InputMap.has_action(action))

	var app: App = load("res://game/app.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	check("the app opens on the title", app.screen is MainMenu)
	check("no Continue without a save",
			app.screen.find_child("Continue", true, false) == null)

	app.show_world_map()
	await get_tree().process_frame
	var map := app.screen as WorldMap
	check("the map is shown", map != null)
	if map == null:
		app.queue_free()
		end_section()
		return
	check_eq("it opens on the tutorial", map.current_world().id, &"tutorial")
	check_eq("the first level is selected", map.selected_level(), &"tutorial_1")
	check("level 1 is open", not map.level_button(&"tutorial_1").disabled)
	check("level 2 is locked", map.level_button(&"tutorial_2").disabled)

	# Clearing a level opens the next one on the map.
	Saves.mark_cleared(&"tutorial_1")
	app.show_world_map(&"tutorial")
	await get_tree().process_frame
	map = app.screen
	check("clearing level 1 opens level 2", not map.level_button(&"tutorial_2").disabled)
	check_eq("and selects it", map.selected_level(), &"tutorial_2")
	check_eq("the cleared level is marked",
			map.level_button(&"tutorial_1").get_meta(&"state"), &"cleared")

	map._on_play()
	await get_tree().process_frame
	await get_tree().process_frame
	var level = app.screen
	check("choosing a level plays it", level != null and level.has_signal("exit_requested"))
	check_eq("the chosen level runs", level._current_level, &"tutorial_2")
	check("the level returns to the map", level.return_to_map)

	# Escape drops a held seed before it pauses.
	level.board.selected_seed = {"kind": &"plant", "id": &"peashooter", "slot": 0}
	var esc := InputEventAction.new()
	esc.action = &"Pause"
	esc.pressed = true
	level._unhandled_input(esc)
	check("escape drops the held seed", level.board.selected_seed.is_empty())
	check("without pausing", not get_tree().paused)
	level._unhandled_input(esc)
	check("escape with empty hands pauses", get_tree().paused)
	check("the pause menu is open", level.pause_menu.is_open())
	level.pause_menu.close()
	check("resume unpauses", not get_tree().paused)

	# Leaving mid-level saves it, and the map and title offer to resume.
	level.pause_menu.open()
	level.pause_menu._on_exit(&"map")
	await get_tree().process_frame
	await get_tree().process_frame
	check("leaving unpauses", not get_tree().paused)
	check("leaving returns to the map", app.screen is WorldMap)
	check("leaving saves the run", Saves.has_save(&"tutorial_2"))
	map = app.screen
	check_eq("the map marks it in progress",
			map.level_button(&"tutorial_2").get_meta(&"state"), &"saved")
	check_eq("and offers to resume", map._play.text, "Resume")
	check_eq("the title offers to continue it", MainMenu.latest_save(), &"tutorial_2")

	# Winning goes back to the map with the next level open.
	map._on_play()
	await get_tree().process_frame
	await get_tree().process_frame
	level = app.screen
	level.level_transition_delay = 0.05
	level._on_won()
	check("no pausing during the result", not level.can_pause())
	await _collect_reward(level)
	await _wait_game_seconds(0.4)
	check("a win goes back to the map", app.screen is WorldMap)
	check("the won level is cleared", Saves.is_cleared(&"tutorial_2"))
	check("and its save retired", not Saves.has_save(&"tutorial_2"))
	map = app.screen
	check("level 3 is now open", not map.level_button(&"tutorial_3").disabled)

	app.queue_free()
	await get_tree().process_frame
	_clear_all_saves()
	end_section()


func _test_seed_cooldowns() -> void:
	print("\n[seed cooldowns]")
	var bank := SeedBank.new()
	add_child(bank)
	bank.setup([{"kind": &"plant", "id": &"peashooter"},
				{"kind": &"plant", "id": &"sunflower"},
				{"kind": &"plant", "id": &"wallnut"}])
	check_eq("bank has three packets", bank.size(), 3)

	# cooldown_from is the share of the recharge a packet starts with:
	# peashooter 1.0 (ready), sunflower 0.0 (empty), wallnut 0.75.
	check("peashooter starts ready", bank.is_recharged(0))
	check("sunflower starts recharging", not bank.is_recharged(1))
	check("wallnut starts part-charged", not bank.is_recharged(2))
	check_eq("wallnut starts at 75%", snappedf(bank.packet(2).fraction(), 0.01), 0.75)
	check_eq("cost read from the plant", bank.packet(0).cost, 100)

	# Using a packet empties it.
	bank.spend(0)
	check("spending empties the packet", not bank.is_recharged(0))
	check_eq("and it starts from zero", bank.packet(0).fraction(), 0.0)

	# Sun alone is not enough while a packet is still charging.
	check("recharging packet is unusable", not bank.can_use(0, 9999))
	check("affordability is separate", bank.can_afford(0, 9999))

	await _wait_game_seconds(6.0)
	check("peashooter recharged after its cooldown", bank.is_recharged(0))
	check("and is now usable", bank.can_use(0, 9999))
	check("still unusable without sun", not bank.can_use(0, 0))

	# The half-time module halves every recharge.
	var fast := SeedBank.new()
	add_child(fast)
	fast.setup([{"kind": &"plant", "id": &"wallnut"}], true)
	check_eq("half-time halves the recharge", fast.packet(0).recharge,
			float(Data.plant(&"wallnut").cooldown) * 0.5)

	bank.queue_free()
	fast.queue_free()


func _test_armor_visual_state() -> void:
	print("\n[armor state]")
	var board := _make_board()
	var plain := board.spawn_zombie(&"tutorial", 0)
	var armored := board.spawn_zombie(&"tutorial_armor2", 1)

	check("plain zombie has no armor component", plain.component(&"armor") == null)
	check("plain zombie is not tagged armored", not plain.has_tag(&"armored"))

	var armor := armored.component(&"armor")
	check("armored zombie has armor", armor != null)
	if armor != null:
		check("armor starts intact", armor.is_intact())
		check("armored zombie is tagged", armored.has_tag(&"armored"))
		check_eq("armor starts full", armor.fraction(), 1.0)

		armored.take_damage(550.0)
		check("armor is worn but intact", armor.is_intact())
		check_eq("wear is reflected", snappedf(armor.fraction(), 0.01), 0.5)

		armored.take_damage(600.0)
		check("armor breaks", not armor.is_intact())
		check("armored tag cleared on break", not armored.has_tag(&"armored"))
	board.queue_free()


func _test_armed_mine_is_not_food() -> void:
	print("\n[potato mine]")
	var board := _make_board()
	var mine := board.place_plant(&"potatomine", 2, 3)
	check("potato mine placed", mine != null)
	var fuse := mine.component(&"explosive")
	check("mine has an explosive component", fuse != null)

	# While arming it is ordinary food.
	check("arming mine is edible", not mine.has_tag(&"uneatable"))
	check("arming mine is tagged arming", mine.has_tag(&"arming"))
	var zombie := board.spawn_zombie(&"tutorial", 2)
	check("zombie would eat an arming mine", zombie._can_eat(mine))
	if mine.art != null:
		check_eq("a fresh mine sprouts unarmed", mine.art.playing, &"Spawn_Baby")
		await _wait_game_seconds(1.5)
		check_eq("then rests underground", mine.art.playing, &"Idle_Baby")

	# Once armed it detonates on contact instead of being chewed.
	await _wait_game_seconds(float(Data.plant(&"potatomine").stat(&"charge_time", 14.0)) + 2.0)
	check("mine finished arming", not mine.has_tag(&"arming"))
	check("armed mine is uneatable", mine.has_tag(&"uneatable"))
	check("zombie ignores an armed mine as food", not zombie._can_eat(mine))
	if mine.art != null:
		check_eq("an armed mine idles armed", mine.art.playing, &"Idle")
	board.queue_free()


func _test_sun_expires() -> void:
	print("\n[sun expiry]")
	var board := _make_board()
	board.drop_sun(board.grid_to_world(2, 3))
	var suns := board.get_node("Suns")
	check_eq("sun on the board", suns.get_child_count(), 1)

	var token: SunToken = suns.get_child(0)
	var life: float = token.lifetime
	await _wait_game_seconds(life * 0.5)
	check("still there halfway through its life", is_instance_valid(token))

	await _wait_game_seconds(life * 0.6 + 1.0)
	check("uncollected sun despawns", not is_instance_valid(token))
	check_eq("and leaves nothing behind", suns.get_child_count(), 0)
	board.queue_free()


func _test_mowers() -> void:
	print("\n[mowers]")
	var board := _make_board()
	board.mowers_enabled = true
	board.setup_mowers()
	check_eq("one mower per lane", board.get_node("Mowers").get_child_count(), board.rows)
	check("lane starts protected", board.has_mower(2))

	var lost := [false]
	board.level_lost.connect(func(): lost[0] = true)
	var fired := [-1]
	board.mower_triggered.connect(func(row): fired[0] = row)

	# A zombie reaching the house should set the mower off, not end the level.
	var z := board.spawn_zombie(&"tutorial", 2)
	z.position.x = board.house_x() + 4.0
	await _wait_game_seconds(1.0)
	check_eq("the lane's mower fired", fired[0], 2)
	check("level not lost while a mower remains", not lost[0])

	# It should clear the lane on its way out.
	await _wait_game_seconds(3.0)
	check("mower destroyed the zombie", not is_instance_valid(z) or z.is_dead)
	check("lane is no longer protected", not board.has_mower(2))
	check("other lanes still are", board.has_mower(0))

	# The next zombie through a spent lane ends the level.
	var z2 := board.spawn_zombie(&"tutorial", 2)
	z2.position.x = board.house_x() + 4.0
	await _wait_game_seconds(1.0)
	check("spent lane loses the level", lost[0])
	board.queue_free()


func _test_plant_food() -> void:
	print("\n[plant food]")
	var board := _make_board()
	check_eq("starts with none", board.plant_food, 0)

	# A carrier drops food where it dies.
	var carrier := board.spawn_zombie(&"tutorial", 1)
	check("tutorial zombie may carry food", carrier.has_tag(&"plantfood_carrier"))
	carrier.set_runtime_tag(&"carrying_plantfood", true)
	carrier.take_damage(99999.0)
	await get_tree().process_frame

	var dropped: PlantFoodToken = null
	for c in board.get_node("Suns").get_children():
		if c is PlantFoodToken:
			dropped = c
	check("carrier dropped plant food", dropped != null)
	if dropped != null:
		dropped.collect()
		await _wait_game_seconds(dropped.fly_time + 0.4)
		check_eq("collecting banks one food", board.plant_food, 1)

	# Feeding a shooter should unload a burst.
	var shooter := board.place_plant(&"peashooter", 2, 1)
	board.spawn_zombie(&"tutorial", 2)
	var before := board.get_node("Projectiles").get_child_count()
	check("feeding a plant works", board.feed_plant(2, 1))
	check_eq("food was spent", board.plant_food, 0)
	await _wait_game_seconds(1.5)
	check("plant food fired a burst",
			board.get_node("Projectiles").get_child_count() > before + 3,
			"%d projectiles" % board.get_node("Projectiles").get_child_count())

	# Feeding with nothing in the bank does nothing.
	check("cannot feed without food", not board.feed_plant(2, 1))
	# Feeding an empty cell does nothing either.
	board.add_plant_food(1)
	check("cannot feed an empty cell", not board.feed_plant(4, 8))
	check_eq("and the food is kept", board.plant_food, 1)

	# Sunflower produces a handful at once.
	var sf := board.place_plant(&"sunflower", 3, 1)
	var suns_before := board.get_node("Suns").get_child_count()
	check("feeding a sunflower works", board.feed_plant(3, 1))
	check("sunflower dropped several suns",
			board.get_node("Suns").get_child_count() >= suns_before + 3)
	board.queue_free()


func _test_input_actions() -> void:
	print("\n[input actions]")
	# The project's InputMap owns these, so they can be rebound - including to
	# a controller - without touching code.
	for action in ["Slot 1", "Slot 4", "Plant Food", "Shovel", "Fast Forward",
			"Previous Slot", "Next Slot"]:
		check("action '%s' exists" % action, InputMap.has_action(action))

	var main = load("res://game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	# Conveyor levels have extra slots with their own bindings from 5 on.
	main._conveyor_level = false
	check_eq("slot 5 uses the normal binding", main._slot_action(4), &"Slot 5")
	main._conveyor_level = true
	check_eq("slot 5 uses the conveyor binding", main._slot_action(4),
			&"Slot 5 (Convayor)")
	check_eq("slot 1 is shared", main._slot_action(0), &"Slot 1")
	main.queue_free()


func _test_shovel() -> void:
	print("\n[shovel]")
	var board := _make_board()
	check("plant placed", board.place_plant(&"peashooter", 2, 3) != null)
	check("cell is occupied", board.plant_at(2, 3) != null)
	check("shovel digs it up", board.dig_up(2, 3))
	check("cell is free again", board.plant_at(2, 3) == null)
	check("can replant there", board.can_place_entity(&"plant", &"peashooter", 2, 3))
	check("digging an empty cell does nothing", not board.dig_up(2, 3))

	# Digging with the shovel puts it back down, as in PVZGE.
	board.place_plant(&"peashooter", 2, 3)
	board.shovel_active = true
	board.click(board.grid_to_world(2, 4))
	check("a click on an empty cell keeps the shovel", board.shovel_active)
	board.click(board.grid_to_world(2, 3))
	check("the shovel digs the plant up", board.plant_at(2, 3) == null)
	check("and goes back once it has", not board.shovel_active)
	board.queue_free()


func _test_conveyor_belt() -> void:
	print("\n[conveyor]")
	var level := Data.level(&"conveyor_demo")
	check("conveyor demo level exists", not level.is_empty())
	if level.is_empty():
		return

	var belt := ConveyorSeedBank.new()
	add_child(belt)
	belt.setup_conveyor(level.get("seedbank", {}))
	check_eq("pool built from the level", belt.pool.size(), 4)
	check_eq("belt starts empty", belt.size(), 0)

	# The belt refills fast when empty and slows as it fills.
	check_eq("empty belt uses the shortest delay", belt.current_drop_delay(), 3.0)

	await _wait_game_seconds(4.0)
	check("a packet arrived", belt.size() > 0, "%d on the belt" % belt.size())

	# Packets are free and immediately usable - nothing to pay or wait for.
	check("belt packet is ready at once", belt.is_recharged(0))
	check_eq("belt packets are free", belt.cost_of(0), 0)
	check("affordable with no sun", belt.can_afford(0, 0))
	check("usable with no sun", belt.can_use(0, 0))

	# Placing takes it off the belt rather than recharging it.
	var before := belt.size()
	var taken: StringName = belt.packet(0).id
	belt.consume(0)
	check_eq("placing removes the packet", belt.size(), before - 1)
	if belt.size() > 0:
		check("the queue shifted up", belt.packet(0) != null)

	await _wait_game_seconds(20.0)
	check("belt keeps delivering", belt.size() >= 3, "%d on the belt" % belt.size())
	check("delay grows as the belt fills", belt.current_drop_delay() > 3.0)

	# Per-plant limits are respected.
	var counts := {}
	for i in belt.size():
		var id: StringName = belt.packet(i).id
		counts[id] = int(counts.get(id, 0)) + 1
	check("sunflower respects its max of 2", int(counts.get(&"sunflower", 0)) <= 2)
	check("wallnut respects its max of 2", int(counts.get(&"wallnut", 0)) <= 2)

	# Capacity caps growth. A belt built with a small capacity never exceeds
	# it, however long it runs.
	var small := ConveyorSeedBank.new()
	small.capacity = 3
	add_child(small)
	small.setup_conveyor(level.get("seedbank", {}))
	await _wait_game_seconds(40.0)
	check_eq("belt fills to capacity", small.size(), 3)
	check("and never past it", small.size() <= small.capacity)
	small.queue_free()

	# Wave actions can change what the belt delivers mid-level.
	belt.remove_from_pool([&"peashooter"])
	check_eq("removing takes it out of the pool", belt._pool_index(&"peashooter"), -1)
	belt.add_to_pool([{"type": "bonkchoy", "weight": 100, "max": 1}])
	check("adding puts it in the pool", belt._pool_index(&"bonkchoy") >= 0)

	belt.queue_free()

	# The runner reports the mode so the HUD can pick the right bank.
	var runner := LevelRunner.new()
	add_child(runner)
	var board := _make_board()
	runner.start(level, board)
	check("runner reports a conveyor level", runner.is_conveyor())
	runner.start(Data.level(&"tutorial_1"), board)
	check("and a chooser level is not", not runner.is_conveyor())
	runner.queue_free()
	board.queue_free()


func _test_audio() -> void:
	print("\n[audio]")
	check("a backend is selected", Audio.backend != null)
	check("backend has a name", Audio.backend.backend_name() != "")
	# FMOD is not installed here, so its backend must decline rather than be
	# picked and then fail at every call.
	var fmod: AudioBackend = load("res://core/audio/backends/fmod_backend.gd").new()
	check("fmod backend declines when absent", not fmod.is_available())
	check_eq("so a fallback was chosen", Audio.backend.backend_name() != "fmod", true)

	check("catalog loaded", Audio.catalog.size() > 20, "%d" % Audio.catalog.size())
	check("no catalog errors", Audio.catalog.errors.is_empty(),
			str(Audio.catalog.errors))

	# Core events the game actually raises.
	for id in [&"plant.place", &"sun.collect", &"zombie.die", &"mower.trigger",
			&"plant.food", &"level.win", &"level.lose"]:
		check("event '%s' exists" % id, Audio.has_event(id))

	# A mod can add an event, and replace one by reusing its id.
	check("mod added an event", Audio.has_event(&"example.burst"))
	var replaced := Audio.catalog.get_event(&"plant.shoot")
	check_eq("mod replaced a core event", replaced.source_mod, &"example_pack")
	check_eq("with its own path", replaced.fmod_path, "event:/ExamplePack/ReplacedShoot")

	# An unknown event must be survivable - a missing sound is not a crash.
	Audio.play(&"definitely.not.an.event")
	Audio.play_music(&"definitely.not.music")
	check("unknown events are harmless", true)

	# Every id the game raises must be in the catalog, or it is silent for a
	# reason nobody notices until playtest.
	var raised: Array[StringName] = []
	for path in _gd_files("res://core") + _gd_files("res://game"):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		for m in RegEx.create_from_string("Audio\\.play(?:_music|_variant|_for|_extra)?\\(&\"([a-z0-9._]+)\"") \
				.search_all(text):
			var id := StringName(m.get_string(1))
			if not raised.has(id):
				raised.append(id)
	var missing: Array[StringName] = []
	for id in raised:
		if not Audio.has_event(id):
			missing.append(id)
	check("every raised event is in the catalog", missing.is_empty(), str(missing))
	print("        (%d distinct events raised by the game)" % raised.size())

	# Wave cues are picked by a function, so the scan above cannot see them.
	var cues := [LevelRunner.wave_sound(0, 5, false), LevelRunner.wave_sound(2, 5, false),
			LevelRunner.wave_sound(2, 5, true), LevelRunner.wave_sound(4, 5, true)]
	check_eq("wave cues follow PVZGE", cues,
			[&"wave.first", &"", &"wave.huge", &"wave.final"])
	for id in cues:
		if id != &"":
			check("wave cue '%s' exists" % id, Audio.has_event(id))

	# A variant overrides its cue only where the catalog has one.
	check("a plant's own shoot sound exists", Audio.has_event(&"plant.shoot.cactus"))
	check("mowers have per-world variants", Audio.has_event(&"mower.trigger.mower_egypt"))
	check("the coin bag has its own landing", Audio.has_event(&"reward.land.coinbag"))
	check("sunflower makes sun with a sound", Audio.has_event(&"plant.produce"))
	check("peas splat when they hit", Audio.has_event(&"projectile.hit"))
	Audio.play_variant(&"plant.shoot", &"not_a_plant")
	Audio.play_extra(&"plant.food", &"not_a_plant")
	check("an unknown variant falls back quietly", not Audio._missing_reported.has(&"plant.shoot.not_a_plant"))

	_test_audio_streams()
	_test_fmod_backend()


## The Godot fallback's clips come from the generated streams.json.
func _test_audio_streams() -> void:
	var groans := Audio.catalog.get_event(&"zombie.spawn")
	check("generated streams fill the catalog", groans.streams.size() > 1,
			str(groans.streams))
	check("streams point into the Music submodule",
			groans.streams[0].begins_with("res://Music/Assets/"))
	check("a lawn's music loops", Audio.catalog.get_event(&"music.lawn.tutorial").loop)
	check("a victory cue does not", not Audio.catalog.get_event(&"music.victory.egypt").loop)
	# A pack that replaces an event replaced its sound: the base clip must not
	# come back under it.
	check("a replaced event keeps none of the base streams",
			Audio.catalog.get_event(&"plant.shoot").streams.is_empty())
	for world in ["beach", "cowboy", "dark", "dino", "egypt", "eighties", "future",
			"iceage", "kongfu", "lostcity", "modern", "pirate", "sky", "tutorial"]:
		check("world '%s' has lawn music" % world,
				Audio.has_event(StringName("music.lawn." + world)))

	var godot: AudioBackend = load("res://core/audio/backends/godot_backend.gd").new()
	godot.setup(Audio.catalog)
	if DirAccess.dir_exists_absolute("res://Music/Assets"):
		check("godot backend can play a groan", godot.can_play(groans))
	# Music is .gdignored, so the clips are decoded from disk, not imported.
	var groan_path: String = groans.streams[0]
	var groan_bytes := FileAccess.get_file_as_bytes(groan_path)
	if groan_bytes.size() > 200:
		check("godot backend decodes a groan from disk", godot._stream_for(groans) != null)
	elif FileAccess.file_exists(groan_path):
		check("an LFS pointer decodes to nothing", godot._stream_for(groans) == null)
	check("godot backend cannot play what has no clips",
			not godot.can_play(AudioEvent.from_dict({"id": "x.none"})))
	godot.shutdown()


## Drives the FMOD backend against a stand-in for FmodServer, so the calls it
## makes are checked without FMOD installed.
func _test_fmod_backend() -> void:
	var server := FakeFmodServer.new()
	var fmod: AudioBackend = load("res://core/audio/backends/fmod_backend.gd").new()
	fmod.attach(server)
	var shoot := AudioEvent.from_dict({"id": "t.shoot", "fmod": "event:/SFX/Plants/Shoot"})
	var lawn := AudioEvent.from_dict({"id": "t.lawn", "fmod": "event:/Music/InGame/Egypt",
			"music": true})
	var lose := AudioEvent.from_dict({"id": "t.lose", "fmod": "event:/Music/InGame/Lose/Egypt",
			"music": true})

	fmod.play(shoot, Vector2(10, 20))
	check_eq("an effect is a one-shot, position or not", server.one_shots,
			["event:/SFX/Plants/Shoot"])

	fmod.set_parameter(&"state", 1.0)
	fmod.play_music(lawn)
	check_eq("music is a held instance", server.instances.size(), 1)
	var music: FakeFmodEvent = server.instances[0]
	check("and it is started", music.started)
	check_eq("with parameters set before it started", music.parameters.get("state"), 1.0)
	fmod.play_music(lawn)
	check_eq("the same cue again does not restart it", server.instances.size(), 1)
	fmod.set_parameter(&"state", 3.0)
	check_eq("a parameter reaches the playing music", music.parameters.get("state"), 3.0)
	check_eq("and is set globally too", server.globals.get("state"), 3.0)

	fmod.play_music(lose)
	check("a new cue stops the old one", music.stopped and music.released)
	fmod.stop_music()
	check("stop_music stops what is playing", server.instances[1].stopped)

	fmod.set_bus_volume(&"Music", 0.5)
	check_eq("a bus is reached by path", server.buses.get("bus:/Music").volume, 0.5)
	fmod.shutdown()


class FakeFmodServer extends RefCounted:
	var one_shots: Array = []
	var instances: Array = []
	var globals: Dictionary = {}
	var buses: Dictionary = {}

	func load_bank(_path: String, _flags: int) -> Object:
		return null

	func play_one_shot(path: String) -> void:
		one_shots.append(path)

	func create_event_instance(path: String) -> Object:
		var e := FakeFmodEvent.new()
		e.path = path
		instances.append(e)
		return e

	func set_global_parameter_by_name(name: String, value: float) -> void:
		globals[name] = value

	func check_bus_path(_path: String) -> bool:
		return true

	func get_bus(path: String) -> Object:
		if not buses.has(path):
			buses[path] = FakeFmodBus.new()
		return buses[path]

	func update() -> void:
		pass


class FakeFmodEvent extends RefCounted:
	var path: String
	var started := false
	var stopped := false
	var released := false
	var parameters: Dictionary = {}

	func is_valid() -> bool:
		return not released

	func start() -> void:
		started = true

	func stop(_mode: int) -> void:
		stopped = true

	func release() -> void:
		released = true

	func set_parameter_by_name(name: String, value: float) -> void:
		parameters[name] = value


class FakeFmodBus extends RefCounted:
	var volume: float = 1.0


## Objectives are the level's win/lose rules. The default keeps old levels
## working; the rest are selectable from data.
func _test_objectives() -> void:
	section("objectives")
	for t in [&"survive_waves", &"protect_plants", &"no_plant_loss",
			&"sun_produced", &"kill_count"]:
		check("built-in objective '%s'" % t, Components.has_objective(t))
	check_eq("built-ins are owned by base",
			Components.objective_owner_of(&"survive_waves"), &"base")

	# A level that lists none still gets the default goal.
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)
	runner.start(Data.level(&"tutorial_1"), board)
	check_eq("default objective applied", runner.objectives.size(), 1)
	check_eq("and it is survive_waves", runner.objectives[0].name, "survive_waves")

	# A level can ask for several; all must be met.
	runner.start({
		"id": "obj_test",
		"seedbank": {"mode": "chooser", "preset": ["peashooter"]},
		"objectives": [{"type": "kill_count", "count": 2},
					   {"type": "no_plant_loss", "allowed": 0}],
		"waves": [],
	}, board)
	check_eq("level objectives built", runner.objectives.size(), 2)
	var kills: Objective = runner.objectives[0]
	check("kill_count starts unmet", not kills.is_met())
	check("it reports progress", kills.describe().contains("0 / 2"))

	# Killing zombies drives it through the board's signals, not polling.
	for i in 2:
		var z := board.spawn_zombie(&"tutorial", i)
		z.take_damage(99999.0)
	await get_tree().process_frame
	check("kill_count met after two kills", kills.is_met(), kills.describe())

	# A broken objective fails the level.
	var guard: Objective = runner.objectives[1]
	var plant := board.place_plant(&"peashooter", 2, 1)
	check("plant placed for the guard objective", plant != null)
	plant.take_damage(99999.0)
	await get_tree().process_frame
	check("no_plant_loss failed", guard.is_failed(), guard.describe())
	end_section()
	runner.queue_free()
	board.queue_free()


## The bar an overhaul-scale mod has to clear: a new world with its own lawn,
## roster and music; new entities on a new archetype; new gimmicks; a new
## objective keyed off a tag the pack invented; and its own campaign.
func _test_overhaul_scale_mod() -> void:
	section("overhaul-scale mod")
	check("overhaul_demo is enabled", Mods.is_enabled(&"overhaul_demo"))

	# 1. a new world
	var lawn := Data.lawn(&"NeonStage")
	check("mod added a lawn", not lawn.is_empty())
	check_eq("with its own music track", lawn.get("music"), "Neon")
	var roster: Dictionary = lawn.get("zombie_roster", {})
	check("and its own zombie roster", roster.has("basic"))
	check("its music event exists", Audio.has_event(&"music.lawn.neon"))

	# 2. a new archetype, and entities inheriting from it
	var drone := Data.zombie(&"neon_drone")
	check("mod added a zombie", drone != null)
	check("on a mod-defined archetype", drone != null and drone.has_tag(&"synthetic"))
	check("archetype tags inherited", drone != null and drone.has_tag(&"chompable"))
	check("base-only tags absent", drone != null and not drone.has_tag(&"swallowable"))

	# A mod zombie extending another mod zombie.
	var warden := Data.zombie(&"neon_warden")
	check_eq("mod zombie extends a mod zombie", warden.extends_id, &"neon_drone")
	check("inherited the archetype through the chain", warden.has_tag(&"synthetic"))
	check_eq("overrode a stat", warden.toughness, 400.0)
	check_eq("kept an inherited stat", warden.speed, 0.3)
	check("added its own tag", warden.has_tag(&"shielded"))

	# 3. new gimmick components, registered and running
	check("gimmick registered", Components.has_type(&"pulse_aura"))
	check_eq("owned by the pack", Components.owner_of(&"pulse_aura"), &"overhaul_demo")

	var board := _make_board()
	var victim := board.place_plant(&"peashooter", 2, 2)
	var pulser := board.spawn_zombie(&"neon_warden", 2)
	pulser.position.x = victim.position.x + 20.0
	check("gimmick attached to the zombie", pulser.component(&"pulse_aura") != null)
	var hp_before: float = victim.health
	await _wait_game_seconds(4.0)
	# The aura can finish the plant off, which counts as damage either way.
	var hp_after: float = victim.health if is_instance_valid(victim) else 0.0
	check("gimmick damaged a plant without eating it", hp_after < hp_before,
			"%.0f -> %.0f" % [hp_before, hp_after])

	# The other gimmick slows zombies, and must not leave them slowed when it dies.
	var slower := board.place_plant(&"dampener", 4, 3)
	check("mod plant placed", slower != null)
	var runner_zombie := board.spawn_zombie(&"neon_drone", 4)
	runner_zombie.position.x = slower.position.x + 40.0
	var base_speed: float = runner_zombie.speed
	await _wait_game_seconds(0.5)
	check("gimmick slowed the zombie", runner_zombie.speed < base_speed,
			"%.3f -> %.3f" % [base_speed, runner_zombie.speed])
	check("and tagged it", runner_zombie.has_tag(&"dampened"))
	slower.take_damage(99999.0)
	await _wait_game_seconds(0.5)
	check("speed restored when the plant died",
			is_equal_approx(runner_zombie.speed, base_speed),
			"%.3f vs %.3f" % [runner_zombie.speed, base_speed])

	# 4. a new objective type, keyed off the pack's own tag
	check("mod objective registered", Components.has_objective(&"no_synthetic_escape"))
	check_eq("owned by the pack",
			Components.objective_owner_of(&"no_synthetic_escape"), &"overhaul_demo")

	var level := Data.level(&"neon_1")
	check("mod level exists", not level.is_empty())
	var runner := LevelRunner.new()
	add_child(runner)
	runner.start(level, board)
	check_eq("level uses three objectives", runner.objectives.size(), 3)

	var custom: Objective = null
	for o in runner.objectives:
		if o.name == "no_synthetic_escape":
			custom = o
	check("the custom objective is live", custom != null)
	if custom != null:
		check("it starts met", custom.is_met())
		# A synthetic zombie reaching the house must break it.
		var escapee := board.spawn_zombie(&"neon_drone", 2)
		board.zombie_reached_house.emit(escapee)
		check("broken when a synthetic gets through", custom.is_failed(),
				custom.describe())

	# 5. its own campaign
	var campaign := Data.campaign(&"neon")
	check("mod added a campaign", campaign != null)
	if campaign != null:
		check_eq("with its level", campaign.first_level(), &"neon_1")
		check("base campaign untouched", Data.campaign(&"tutorial") != null)

	end_section()
	runner.queue_free()
	board.queue_free()


## Levels carry explicit options now, not a bag of PopCap module-name strings
## the runner has to pattern-match.
func _test_simplified_level_schema() -> void:
	section("level schema")
	var level := Data.level(&"tutorial_1")
	check("no feature string bag", not level.has("features"))
	check("mowers is an explicit flag", level.get("mowers") == true)
	check("sun rate is explicit", (level.get("sun", {}) as Dictionary).has("interval"))
	check_eq("and readable", (level.get("sun", {}) as Dictionary).get("interval"), 5.0)
	check("recharge is explicit", level.has("seed_recharge"))
	check("one name field, not three", level.has("name") and not level.has("comment"))
	check("narrative hooks kept separately", level.has("scripts"))
	check("pacing renamed from wave_settings", level.has("wave_pacing"))
	check("and drops the count that duplicated waves",
			not (level.get("wave_pacing", {}) as Dictionary).has("count"))

	# The runner reads the fields rather than matching strings.
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)
	runner.start(level, board)
	check("runner sees mowers", runner.has_mowers())
	check_eq("runner reads the recharge scale", runner.seed_recharge_scale(), 0.5)
	check("mowers actually installed", board.has_mower(2))

	runner.start(Data.level(&"tutorial_2"), board)
	check_eq("a different level, a different sun rate", runner._sun_cycle(), 10.0)
	end_section()
	runner.queue_free()
	board.queue_free()


## Big Wave Beach water and Sky's open air are the same rule: a cell that
## wants something before a plant can go in it.
func _test_terrain_rules() -> void:
	section("terrain")
	check("water terrain exists", Data.board_object(&"water") != null)
	check("sky gap terrain exists", Data.board_object(&"sky_gap") != null)
	check_eq("water asks for an aquatic plant",
			Data.board_object(&"water").requires_tag, &"aquatic")
	check("deep water refuses everything",
			Data.board_object(&"deep_water").blocks_planting)
	check("lilypad is aquatic", Data.plant(&"lilypad").has_tag(&"aquatic"))
	check("and provides what water wants",
			Data.plant(&"lilypad").has_tag(&"provides:aquatic"))

	var board := _make_board()
	# Ordinary ground takes anything.
	check("plain ground accepts a peashooter",
			board.can_place_entity(&"plant", &"peashooter", 2, 1))

	board.set_terrain(2, 4, &"water")
	check_eq("terrain recorded", board.terrain_at(2, 4), &"water")
	check("water refuses a land plant",
			not board.can_place_entity(&"plant", &"peashooter", 2, 4))
	check("and says why", board.placement_refusal(&"plant", &"peashooter", 2, 4)
			.contains("aquatic"))
	check("water accepts an aquatic plant",
			board.can_place_entity(&"plant", &"lilypad", 2, 4))

	# A lily pad makes the cell viable for a land plant - the carrier rule.
	check("lilypad placed on water", board.place_plant(&"lilypad", 2, 4) != null)
	check_eq("cell now satisfies water", board.cell_provides(2, 4), &"aquatic")

	# Sky uses the identical mechanism with a different tag.
	board.set_terrain(3, 6, &"sky_gap")
	check("sky gap refuses a land plant",
			not board.can_place_entity(&"plant", &"peashooter", 3, 6))
	check("for the same reason, a missing tag",
			board.placement_refusal(&"plant", &"peashooter", 3, 6).contains("airborne"))
	board.set_terrain(4, 6, &"deep_water")
	check("blocking terrain refuses even the right plant",
			not board.can_place_entity(&"plant", &"lilypad", 4, 6))

	# Zombies walk over terrain regardless.
	check("zombies ignore terrain", board.can_place_entity(&"zombie", &"tutorial", 2, 4))
	end_section()
	board.queue_free()


## A world can bring its own mechanics: passive fire, a triggerable ability,
## and its own lose condition in place of mowers.
func _test_lawn_components() -> void:
	section("lawn components")
	for t in [&"auto_turret", &"cannon_ability", &"house_health", &"terrain_layout"]:
		check("built-in lawn component '%s'" % t, Components.has_lawn_component(t))

	var lawn := Data.lawn(&"AerialStage")
	check("mod added the world", not lawn.is_empty())
	check_eq("and renamed it", lawn.get("display_name"), "Assault Airspace")

	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)
	runner.start(Data.level(&"airspace_1"), board)

	# A rename must not require touching the levels that reference the stage.
	check_eq("the runner reports the new name", runner.world_name(), "Assault Airspace")
	check_eq("base worlds keep their own name",
			LevelRunner.new().world_name(), "")

	check_eq("world installed its components", board.lawn_components.size(), 4)
	check("no mowers on this world", not board.has_mower(2))
	check("terrain painted by the world", board.terrain_at(2, 7) == &"sky_gap")

	# The passive half: the base chips away without the player doing anything.
	var z := board.spawn_zombie(&"neon_drone", 2)
	var hp: float = z.health
	await _wait_game_seconds(3.0)
	check("base fire damaged a zombie on its own",
			not is_instance_valid(z) or z.health < hp)

	# The ability half: charged, triggerable, then on cooldown.
	var abilities := board.lawn_abilities()
	check_eq("one triggerable ability", abilities.size(), 1)
	var cannon: LawnComponent = abilities[0]
	check("starts charged", cannon.can_activate())
	check("HUD text says so", cannon.describe().contains("ready"))

	# The cannon hits a band around the nearest zombie, not a chosen one, so
	# assert on the board's total health rather than one victim.
	board.spawn_zombie(&"neon_warden", 3)
	var before := _total_hostile_health(board)
	check("ability fired", board.activate_lawn_ability(0))
	await get_tree().process_frame
	check("and damaged the board", _total_hostile_health(board) < before,
			"%.0f -> %.0f" % [before, _total_hostile_health(board)])
	check("now on cooldown", not cannon.can_activate())
	check("cooldown is reported", cannon.cooldown_fraction() > 0.9)
	check("a second trigger is refused", not board.activate_lawn_ability(0))

	# The lose condition: house health instead of mowers.
	var house: LawnComponent = null
	for c in board.lawn_components:
		if c.name == "house_health":
			house = c
	check("world brought its own threshold rule", house != null)
	if house != null:
		var full: float = house.health
		var lost := [false]
		board.level_lost.connect(func(): lost[0] = true)
		var leaker := board.spawn_zombie(&"neon_drone", 1)
		board._on_zombie_reached_house(leaker)
		check("house took damage instead of losing", house.health < full)
		check("and the level is not over", not lost[0])
		check("the zombie was consumed", not is_instance_valid(leaker) or leaker.is_dead)

		# Drain it and the level ends.
		house.health = 1.0
		var finisher := board.spawn_zombie(&"neon_drone", 1)
		board._on_zombie_reached_house(finisher)
		check("level lost once the house is gone", lost[0])

	# Dialogue speakers are data, so a world can use the boss box without Zomboss.
	var talk := runner.dialogue()
	check("level has dialogue", not talk.is_empty())
	check_eq("with a custom speaker", talk.get("speaker"), "Commander Vex")
	check_eq("reusing the boss box", talk.get("box"), "boss")
	check_eq("base speakers still there", Data.speaker(&"zomboss").get("name"),
			"Dr. Zomboss")
	end_section()
	runner.queue_free()
	board.queue_free()


## Combined health of every hostile zombie, for area-effect assertions.
func _total_hostile_health(board: Board) -> float:
	var total := 0.0
	for row in board.rows:
		for z in board.hostile_zombies_in_row(row):
			total += z.health
	return total


## Behaviour is derived from the fields a plant carries, not its Family, so
## most of the roster should now do something. This guards against a change
## that silently drops plants back to inert.
func _test_plant_behaviour_coverage() -> void:
	section("plant coverage")
	var total := Data.plants.size()
	var with_behaviour := 0
	var unimplemented: Array[StringName] = []
	for id in Data.plants:
		var def: PlantDef = Data.plants[id]
		if def.components.is_empty():
			continue
		var any := false
		for spec in def.components:
			if Components.has_type(spec.type):
				any = true
			elif not unimplemented.has(spec.type):
				unimplemented.append(spec.type)
		if any:
			with_behaviour += 1
	check("every declared behaviour is implemented", unimplemented.is_empty(),
			str(unimplemented))
	check("most plants do something", with_behaviour >= 150,
			"%d of %d" % [with_behaviour, total])
	print("        (%d of %d plants have a working behaviour)"
			% [with_behaviour, total])

	# Family is a tag now, not the thing that picks behaviour.
	var shadow := Data.query(&"plant", [&"family:shadow"])
	var kinds := {}
	for def in shadow:
		for spec in def.components:
			kinds[spec.type] = true
	check("one family spans several behaviours", kinds.size() > 1,
			"shadow -> %s" % str(kinds.keys()))
	end_section()


func _test_new_plant_behaviours() -> void:
	section("new plant behaviours")
	var board := _make_board()

	# freeze_burst: holds a zombie in place and is spent doing it.
	var ice := board.place_plant(&"iceberglettuce", 2, 3)
	if ice == null:
		ice = board.place_plant(&"chillypepper", 2, 3)
	check("a freeze plant placed", ice != null)
	if ice != null:
		check("it is a freeze_burst", ice.component(&"freeze_burst") != null)
		var victim := board.spawn_zombie(&"tutorial", 2)
		victim.position.x = ice.position.x + 30.0
		await _wait_game_seconds(0.6)
		# The plant kills itself doing this, so validity is checked first -
		# reading a freed node is a crash, not an error.
		check("zombie was frozen or chilled", not is_instance_valid(victim)
				or victim.has_tag(&"frozen") or victim.has_tag(&"slowed"))
		check("the plant is spent",
				not is_instance_valid(ice) or ice.is_dead)

	# instant_damage: goes off once, kills itself doing it.
	var bomb := board.place_plant(&"jalapeno", 3, 3)
	check("an instant plant placed", bomb != null)
	if bomb != null:
		var target := board.spawn_zombie(&"tutorial", 3)
		target.position.x = bomb.position.x + 20.0
		var hp: float = target.health
		await _wait_game_seconds(1.5)
		check("it damaged what was near it",
				not is_instance_valid(target) or target.health < hp)
		check("and was spent", not is_instance_valid(bomb) or bomb.is_dead)

	# tile_placer: the lasting effect is the terrain, not the plant.
	# tile_placer frees itself in setup, so only the terrain is checked.
	board.place_plant(&"goldleaf", 4, 5)
	await _wait_game_seconds(0.3)
	check("it left terrain behind", board.terrain_at(4, 5) != &"")
	board.queue_free()

	# wind_burst only takes zombies the wind can carry.
	var board2 := _make_board()
	var light := board2.spawn_zombie(&"tutorial", 1)
	var heavy := board2.spawn_zombie(&"beach_gargantuar", 2)
	# PVZGE tags gargantuars carriable too, so weight is what separates them.
	check("light zombie is carriable", light.has_tag(&"carriable"))
	check("gargantuar is also tagged carriable", heavy.has_tag(&"carriable"))
	check("but it is far heavier",
			float(heavy.def.stat(&"weight")) > float(light.def.stat(&"weight")),
			"%s vs %s" % [heavy.def.stat(&"weight"), light.def.stat(&"weight")])
	var blover := board2.place_plant(&"blover", 0, 1)
	check("blover placed", blover != null)
	if blover != null:
		await _wait_game_seconds(0.5)
		check("the carriable zombie was blown away",
				not is_instance_valid(light) or light.is_dead)
		check("the gargantuar was too heavy to lift",
				is_instance_valid(heavy) and not heavy.is_dead)
	board2.queue_free()
	end_section()



## Plants that react to a zombie reaching them, eating them or just being on
## the lawn - the squash, chomper and friends that used to stand idle.
func _test_reactive_plants() -> void:
	section("reactive plants")
	var board := _make_board()

	# Squash leaps on the first zombie in reach and is spent doing it.
	var squash := board.place_plant(&"squash", 0, 2)
	check("squash has a behaviour", squash.component(&"squash") != null)
	var squashed := board.spawn_zombie_at(&"tutorial", 0, squash.position.x + 70.0)
	await _wait_game_seconds(1.5)
	check("squash flattened the zombie", not is_instance_valid(squashed) or squashed.is_dead)
	check("and was spent", not is_instance_valid(squash) or squash.is_dead)

	# Chomper swallows what it can and bites what it cannot.
	var chomper := board.place_plant(&"chomper", 1, 2)
	var meal := board.spawn_zombie_at(&"tutorial", 1, chomper.position.x + 60.0)
	meal.speed = 0.0
	await _wait_game_seconds(1.5)
	check("chomper swallowed the zombie", not is_instance_valid(meal) or meal.is_dead)
	check("and is chewing", chomper.has_tag(&"chewing"))
	board.queue_free()

	var board2 := _make_board()
	var chomper2 := board2.place_plant(&"chomper", 1, 2)
	var giant := board2.spawn_zombie_at(&"tutorial_gargantuar", 1, chomper2.position.x + 60.0)
	giant.speed = 0.0
	var giant_hp: float = giant.health
	await _wait_game_seconds(1.5)
	check("a gargantuar is bitten, not swallowed",
			is_instance_valid(giant) and not giant.is_dead and giant.health < giant_hp)
	board2.queue_free()

	# Tangle kelp drags its zombie under; grimrose reaches down the lane.
	var board3 := _make_board()
	board3.set_terrain(2, 3, &"water")
	var kelp := board3.place_plant(&"tanglekelp", 2, 3)
	check("tangle kelp goes in water", kelp != null)
	var swimmer := board3.spawn_zombie_at(&"tutorial", 2, kelp.position.x + 20.0)
	var rose := board3.place_plant(&"grimrose", 3, 0)
	var far := board3.spawn_zombie_at(&"tutorial", 3, board3.grid_to_world(3, 7).x)
	await _wait_game_seconds(2.0)
	check("kelp dragged the zombie under", not is_instance_valid(swimmer) or swimmer.is_dead)
	check("and was spent", not is_instance_valid(kelp) or kelp.is_dead)
	check("grimrose reached down the lane", not is_instance_valid(far) or far.is_dead)
	check("and was spent", not is_instance_valid(rose) or rose.is_dead)
	board3.queue_free()

	# Plants that answer being eaten.
	var board4 := _make_board()
	var hypno := board4.place_plant(&"hypnoshroom", 0, 3)
	var hypno_eater := board4.spawn_zombie_at(&"tutorial", 0, hypno.position.x + 5.0)
	var shadow := board4.place_plant(&"shadowshroom", 1, 3)
	var shadow_eater := board4.spawn_zombie_at(&"tutorial", 1, shadow.position.x + 5.0)
	var bean := board4.place_plant(&"sunbean", 2, 3)
	var bean_eater := board4.spawn_zombie_at(&"tutorial", 2, bean.position.x + 5.0)
	var moon := board4.place_plant(&"moonbean", 3, 3)
	board4.spawn_zombie_at(&"tutorial", 3, moon.position.x + 5.0)
	await _wait_game_seconds(2.5)
	check("hypno-shroom turned its eater", is_instance_valid(hypno_eater)
			and hypno_eater.is_charmed())
	check("shadow-shroom poisoned its eater", not is_instance_valid(shadow_eater)
			or shadow_eater.is_poisoned() or shadow_eater.is_dead)
	check("sun bean infected its eater", is_instance_valid(bean_eater)
			and bean_eater.component(&"sun_infection") != null)
	if is_instance_valid(bean_eater):
		var before := _sun_tokens(board4)
		bean_eater.max_health = 2000.0
		bean_eater.health = 2000.0
		bean_eater.take_damage(600.0)
		check("an infected zombie sheds sun when hurt", _sun_tokens(board4) > before)
	var bombs: Array = board4._suns.get_children().filter(func(n): return n is SunBomb)
	check("moon bean left a sun bomb", bombs.size() == 1)
	if bombs.size() == 1:
		var bomb: SunBomb = bombs[0]
		var victim := board4.spawn_zombie_at(&"tutorial", 3, bomb.position.x)
		bomb.collect()
		check("collecting the sun bomb sets it off", victim.is_dead)
	board4.queue_free()

	var board5 := _make_board()
	var chili := board5.place_plant(&"chilibean", 2, 3)
	var chili_eater := board5.spawn_zombie_at(&"tutorial", 2, chili.position.x + 5.0)
	var queued := board5.spawn_zombie_at(&"tutorial", 2, chili.position.x + 150.0)
	queued.speed = 0.0
	await _wait_game_seconds(7.0)
	check("chili bean's eater is gone", not is_instance_valid(chili_eater) or chili_eater.is_dead)
	check("and its gas stunned the zombie behind", is_instance_valid(queued) and queued.is_stunned())
	board5.queue_free()

	# Lane clearers and one-shots.
	var board6 := _make_board()
	var lane_a := board6.spawn_zombie_at(&"tutorial", 0, board6.grid_to_world(0, 6).x)
	board6.place_plant(&"cranjelly", 0, 1)
	var pushed := board6.spawn_zombie_at(&"tutorial", 1, board6.grid_to_world(1, 4).x)
	var pushed_x: float = pushed.position.x
	board6.place_plant(&"hurrikale", 1, 1)
	var warped := board6.spawn_zombie_at(&"tutorial", 2, board6.grid_to_world(2, 2).x)
	warped.take_damage(100.0)
	board6.place_plant(&"thymewarp", 4, 0)
	await _wait_game_seconds(0.2)
	check("thyme warp sent the zombie back", warped.position.x >= board6.spawn_x() - board6.cell_size.x * 0.5)
	check("at full health", is_equal_approx(warped.health, warped.max_health))
	var sun_before := _sun_tokens(board6)
	board6.place_plant(&"goldbloom", 3, 0)
	await _wait_game_seconds(0.2)
	check("gold bloom burst out sun", _sun_tokens(board6) > sun_before)
	var food_before: int = board6._suns.get_children().filter(
			func(n): return n is PlantFoodToken).size()
	board6.place_plant(&"powerlily", 3, 1)
	await _wait_game_seconds(0.2)
	check("power lily made plant food", board6._suns.get_children().filter(
			func(n): return n is PlantFoodToken).size() > food_before)
	await _wait_game_seconds(2.0)
	check("cran-jelly crushed the lane", not is_instance_valid(lane_a) or lane_a.is_dead)
	check("hurrikale blew its lane back", is_instance_valid(pushed)
			and pushed.position.x > pushed_x + board6.cell_size.x)
	board6.queue_free()

	# Proximity plants.
	var board7 := _make_board()
	var spring := board7.place_plant(&"springbean", 0, 3)
	var bounced := board7.spawn_zombie_at(&"tutorial", 0, spring.position.x + 10.0)
	var bounced_x: float = bounced.position.x
	var stallia := board7.place_plant(&"stallia", 1, 3)
	var sniffed := board7.spawn_zombie_at(&"tutorial", 1, stallia.position.x + 5.0)
	var violet := board7.place_plant(&"shrinkingviolet", 2, 3)
	var shrunk := board7.spawn_zombie_at(&"tutorial", 2, violet.position.x + 5.0)
	var sage := board7.place_plant(&"solarsage", 3, 3)
	var convert := board7.spawn_zombie_at(&"tutorial", 3, sage.position.x + 5.0)
	await _wait_game_seconds(2.0)
	check("spring bean bounced its zombie back",
			bounced.position.x > bounced_x + board7.cell_size.x * 0.5)
	check("stallia's perfume slowed the zombie", sniffed.has_tag(&"slowed"))
	check("and stallia was spent", not is_instance_valid(stallia) or stallia.is_dead)
	check("shrinking violet shrank the zombie", shrunk.component(&"shrunk") != null)
	var shrunk_hp: float = shrunk.health
	shrunk.take_damage(10.0)
	check("a shrunk zombie takes double damage",
			is_equal_approx(shrunk_hp - shrunk.health, 20.0))
	check("solar sage converted the zombie", convert.is_charmed() and convert.peaceful
			and convert.component(&"sun_trail") != null)
	board7.queue_free()

	# Plants that bide their time.
	var board8 := _make_board()
	var stalker := board8.place_plant(&"celerystalker", 0, 4)
	check("celery stalker starts hidden", stalker.has_tag(&"hidden"))
	var passer := board8.spawn_zombie_at(&"tutorial", 0, stalker.position.x - 60.0)
	passer.speed = 0.0
	var pepper := board8.place_plant(&"ghostpepper", 1, 4)
	var haunted := board8.spawn_zombie_at(&"tutorial", 1, pepper.position.x + 100.0)
	haunted.speed = 0.0
	var haunted_hp: float = haunted.health
	var berry := board8.place_plant(&"electricblueberry", 2, 0)
	var struck := board8.spawn_zombie_at(&"tutorial", 2, board8.grid_to_world(2, 7).x)
	struck.speed = 0.0
	await _wait_game_seconds(1.0)
	check("celery stalker popped up behind the zombie", not stalker.has_tag(&"hidden"))
	check("and hit it", passer.health < passer.max_health)
	check("ghost pepper haunted the zombie", not is_instance_valid(haunted)
			or haunted.health < haunted_hp)
	await _wait_game_seconds(11.0)
	check("ghost pepper burnt out", not is_instance_valid(pepper) or pepper.is_dead)
	check("electric blueberry struck", not is_instance_valid(struck) or struck.is_dead)
	check("and survived it", is_instance_valid(berry) and not berry.is_dead)
	board8.queue_free()

	# Toadstool swallows, then pays out the meal as sun.
	var board9 := _make_board()
	var toad := board9.place_plant(&"toadstool", 0, 1)
	var snack := board9.spawn_zombie_at(&"tutorial", 0, toad.position.x + 200.0)
	snack.speed = 0.0
	await _wait_game_seconds(1.5)
	check("toadstool's tongue reached the zombie", not is_instance_valid(snack) or snack.is_dead)
	var toad_sun := _sun_tokens(board9)
	await _wait_game_seconds(31.0)
	check("and turned it into sun", _sun_tokens(board9) > toad_sun)
	board9.queue_free()
	end_section()


## Plants that change what the lawn allows: carriers, plants that go onto
## gravestones, and plants that copy or bring back other plants.
func _test_lawn_support_plants() -> void:
	section("lawn support plants")
	var board := _make_board()

	# A lily pad carries a land plant on water; zombies eat the top one first.
	board.set_terrain(1, 4, &"water")
	var pad := board.place_plant(&"lilypad", 1, 4)
	check("lily pad floats", pad != null)
	check("a land plant can stand on it",
			board.can_place_entity(&"plant", &"peashooter", 1, 4))
	var rider := board.place_plant(&"peashooter", 1, 4)
	check("and does", rider != null)
	check_eq("the cell's plant is the rider", board.plant_at(1, 4), rider)
	check_eq("with the pad under it", board.carrier_at(1, 4), pad)
	check("a second pad is refused", not board.can_place_entity(&"plant", &"lilypad", 1, 4))
	check("both are on the lane", board.plants_in_row(1).size() == 2)
	rider.die()
	await get_tree().process_frame
	check_eq("with the rider gone the pad is what zombies meet",
			board.plant_at(1, 4), pad)
	check("and the water is still covered", board.cell_provides(1, 4) == &"aquatic")
	check("so another land plant can go on", board.can_place_entity(&"plant", &"wallnut", 1, 4))
	pad.die()
	await get_tree().process_frame
	check("losing the pad uncovers the water",
			not board.can_place_entity(&"plant", &"peashooter", 1, 4))

	# A flower pot does the same in the sky.
	board.set_terrain(2, 5, &"sky_gap")
	check("a flower pot can go over a gap",
			board.place_plant(&"floawerPot", 2, 5) != null)
	check("and carries a land plant", board.place_plant(&"peashooter", 2, 5) != null)

	# Grave buster only goes onto a stone, and eats it.
	check("grave buster needs a grave",
			not board.can_place_entity(&"plant", &"gravebuster", 3, 6))
	board.place_object(&"gravestone", 3, 6)
	check("a grave refuses ordinary plants",
			not board.can_place_entity(&"plant", &"peashooter", 3, 6))
	check("but takes a grave buster", board.can_place_entity(&"plant", &"gravebuster", 3, 6))
	var buster := board.place_plant(&"gravebuster", 3, 6)
	await _wait_game_seconds(5.0)
	check("the grave is gone", board.object_at(3, 6) == null)
	check("and so is the buster", not is_instance_valid(buster) or buster.is_dead)
	board.queue_free()

	# Hot potato melts a frozen plant free.
	var board2 := _make_board()
	var frozen := board2.place_plant(&"peashooter", 2, 2)
	board2.encase_in_block(frozen, &"planttarget_iceblock")
	check("the plant is frozen", frozen.is_encased())
	check("hot potato can go onto the ice",
			board2.can_place_entity(&"plant", &"hotpotato", 2, 2))
	board2.place_plant(&"hotpotato", 2, 2)
	check_eq("without taking the frozen plant's place", board2.plant_at(2, 2), frozen)
	await _wait_game_seconds(3.5)
	check("the block melted", board2.object_at(2, 2) == null)
	check("and the plant is free", not frozen.is_encased())

	# Intensive carrot brings back the last plant to die in its cell.
	var lost := board2.place_plant(&"wallnut", 0, 3)
	lost.die()
	await get_tree().process_frame
	check_eq("the cell remembers what died", board2.last_dead_plant(0, 3), &"wallnut")
	board2.place_plant(&"intensivecarrot", 0, 3)
	await get_tree().process_frame
	await get_tree().process_frame
	var back := board2.plant_at(0, 3)
	check("the carrot brought it back", back != null and back.entity_id() == &"wallnut")
	if back != null:
		check("at half health", back.health < back.max_health)

	# Imitater becomes another plant.
	var copy := board2.place_entity(&"plant", &"imitater", 4, 1, &"sunflower")
	check("imitater planted", copy != null)
	await _wait_game_seconds(1.5)
	var grown := board2.plant_at(4, 1)
	check("and turned into its plant", grown != null and grown.entity_id() == &"sunflower")
	var random_copy := board2.place_plant(&"imitater", 4, 3)
	await _wait_game_seconds(1.5)
	var random_grown := board2.plant_at(4, 3)
	check("an imitater with no packet picks a plant", random_grown != null
			and random_grown.entity_id() != &"imitater")
	check("the imitater's own death is not remembered",
			board2.last_dead_plant(4, 1) != &"imitater")
	board2.queue_free()

	# Umbrella leaf bounces a thrown imp; lights light the lawn.
	var board3 := _make_board()
	board3.place_plant(&"umbrellaleaf", 2, 2)
	check("an umbrella shelters its 3x3", board3.is_sheltered(1, 3)
			and not board3.is_sheltered(2, 5))
	board3.place_plant(&"plantern", 0, 6)
	check("a plantern lights the squares round it", board3.is_lit(1, 7)
			and not board3.is_lit(3, 7))
	var giant := board3.spawn_zombie_at(&"tutorial_gargantuar", 2, board3.grid_to_world(2, 5).x)
	giant.speed = 0.0
	var imp_thrower = giant.component(&"imp_thrower")
	check("the gargantuar throws imps", imp_thrower != null)
	if imp_thrower != null:
		imp_thrower._throw()
		var landed: Array = board3.hostile_zombies_in_row(2).filter(
				func(z): return z != giant)
		check("its imp was bounced back up the lane", landed.size() == 1
				and landed[0].position.x >= board3.spawn_x() - 1.0)
	check("resistant radish stands as a wall",
			board3.place_plant(&"turnip", 4, 4).has_tag(&"blocker"))
	board3.queue_free()
	end_section()


## Shooters with a twist, and plants the player taps to fire.
func _test_shooting_plants() -> void:
	section("shooting plants")
	var board := _make_board()

	# Split pea fires both ways; its rear shots never hit its own side.
	var split := board.place_plant(&"splitpea", 0, 4)
	var behind := board.spawn_zombie_at(&"tutorial", 0, board.grid_to_world(0, 1).x)
	behind.speed = 0.0
	var behind_hp: float = behind.health
	var neighbour := board.place_plant(&"wallnut", 0, 2)
	await _wait_game_seconds(2.0)
	check("split pea shot the zombie behind it", behind.health < behind_hp)
	check("over the wall-nut without hurting it", is_equal_approx(neighbour.health,
			neighbour.max_health))
	check("split pea is still standing", is_instance_valid(split))

	# Bloomerang's boomerang passes through and comes back.
	board.place_plant(&"bloomerang", 1, 0)
	var first := board.spawn_zombie_at(&"tutorial", 1, board.grid_to_world(1, 4).x)
	var second := board.spawn_zombie_at(&"tutorial", 1, board.grid_to_world(1, 5).x)
	first.speed = 0.0
	second.speed = 0.0
	await _wait_game_seconds(7.0)
	check("the boomerang hit both zombies", first.health < first.max_health
			and second.health < second.max_health)
	check("each of them twice", first.max_health - first.health >= 40.0,
			"took %.0f" % (first.max_health - first.health))

	# Scaredy-shroom hides when a zombie is close.
	var scaredy := board.place_plant(&"scaredyshroom", 2, 3)
	board.spawn_zombie_at(&"tutorial", 2, scaredy.position.x + 40.0).speed = 0.0
	await _wait_game_seconds(0.5)
	check("scaredy-shroom hides from a close zombie", scaredy.has_tag(&"hiding"))
	board.queue_free()

	# Red stinger: strong near the house, a wall far from it.
	var board2 := _make_board()
	var near := board2.place_plant(&"redstinger", 0, 1)
	var far := board2.place_plant(&"redstinger", 1, 7)
	near.take_damage(30.0)
	far.take_damage(30.0)
	check("near the house it takes full damage",
			is_equal_approx(near.max_health - near.health, 30.0))
	check("far from it, a fifth", is_equal_approx(far.max_health - far.health, 6.0))
	var target := board2.spawn_zombie_at(&"tutorial", 0, board2.grid_to_world(0, 6).x)
	target.speed = 0.0
	await _wait_game_seconds(2.5)
	check("a near red stinger shoots", target.health < target.max_health)

	# Gloom-shroom hurts the 3x3; powered, it powers its shadow neighbours.
	var gloom := board2.place_plant(&"gloomshroom", 3, 4)
	var gloomed := board2.spawn_zombie_at(&"tutorial", 4, gloom.position.x + 60.0)
	gloomed.speed = 0.0
	var leafy := board2.place_plant(&"nightshade", 3, 5)
	gloom.add_timed_tag(&"shadow_powered", 10.0)
	await _wait_game_seconds(2.0)
	check("gloom-shroom hurt the zombie in the next lane",
			gloomed.health < gloomed.max_health or gloomed.is_dead)
	check("and passed its shadow power on", leafy.has_tag(&"shadow_powered"))
	board2.queue_free()

	# Nightshade slaps what comes near, and runs out of leaves.
	var board3 := _make_board()
	var shade := board3.place_plant(&"nightshade", 0, 2)
	var slapped := board3.spawn_zombie_at(&"tutorial", 0, shade.position.x + 80.0)
	slapped.speed = 0.0
	slapped.max_health = 5000.0
	slapped.health = 5000.0
	await _wait_game_seconds(12.0)
	check("nightshade slapped the zombie", slapped.health < 5000.0)
	check_eq("and used up its leaves", shade.component(&"leaf_thrower")._ammo, 0)
	board3.queue_free()

	# Tap-to-fire: arm the launcher, pick a square.
	var board4 := _make_board()
	var banana := board4.place_plant(&"banana", 2, 0)
	var victim := board4.spawn_zombie_at(&"tutorial", 3, board4.grid_to_world(3, 6).x)
	victim.speed = 0.0
	check("tapping the launcher arms it", board4.tap_plant(2, 0))
	check("and it waits for a square", board4.aiming == banana.component(&"launcher"))
	check("the banana is away", board4.aim_at(3, 6))
	check("it cannot fire again straight away", not board4.tap_plant(2, 0))
	await _wait_game_seconds(1.5)
	check("the banana blew the zombie up", not is_instance_valid(victim) or victim.is_dead)

	var toe := board4.place_plant(&"missiletoe", 1, 0)
	var chilled := board4.spawn_zombie_at(&"tutorial_gargantuar", 1, board4.grid_to_world(1, 5).x)
	board4.tap_plant(1, 0)
	board4.aim_at(1, 5)
	await _wait_game_seconds(1.5)
	check("missile toe froze its target", is_instance_valid(chilled)
			and (chilled.has_tag(&"frozen") or chilled.has_tag(&"slowed")))
	check("missile toe is reloading", not toe.component(&"launcher").is_loaded())

	var berry := board4.place_plant(&"strawburst", 4, 0)
	var berried := board4.spawn_zombie_at(&"tutorial", 4, board4.grid_to_world(4, 7).x)
	berried.speed = 0.0
	check("a strawburst with no berry yet does nothing", not board4.tap_plant(4, 0))
	await _wait_game_seconds(8.0)
	check("after a while it has grown one", berry.component(&"berry_lobber").stage >= 0)
	check("tapping it lobs the berry", board4.tap_plant(4, 0))
	check("which hit the zombie", not is_instance_valid(berried)
			or berried.health < berried.max_health or berried.is_dead)

	board4.place_plant(&"phatbeet_rhythm", 0, 3)
	var beaten := board4.spawn_zombie_at(&"tutorial", 0, board4.grid_to_world(0, 4).x)
	beaten.speed = 0.0
	check("tapping the phat beet smashes the zombie in front", board4.tap_plant(0, 3)
			and beaten.is_dead)
	board4.queue_free()

	# Bowling bulb glances into the next lane.
	var board5 := _make_board()
	board5.place_plant(&"bowlingbulb", 2, 0)
	var pin := board5.spawn_zombie_at(&"tutorial", 2, board5.grid_to_world(2, 4).x)
	pin.speed = 0.0
	await _wait_game_seconds(1.5)
	check("the bulb hit the zombie", pin.health < pin.max_health)
	board5.queue_free()
	end_section()


func _test_defence_plants() -> void:
	section("defence plants")
	var board := _make_board()

	# Aloe heals the plant in front of it.
	board.place_plant(&"aloe", 0, 1)
	var patient := board.place_plant(&"wallnut", 0, 2)
	patient.take_damage(300.0)
	await _wait_game_seconds(1.2)
	check("aloe healed the wall-nut in front of it", patient.max_health - patient.health < 300.0)

	# Peach heals the 3x3 on a timer.
	var peach := board.place_plant(&"peach", 2, 4)
	peach.component(&"healer")._timer = 0.0
	var hurt := board.place_plant(&"wallnut", 3, 5)
	hurt.take_damage(200.0)
	await _wait_game_seconds(0.2)
	check("peach healed its neighbour", is_equal_approx(hurt.max_health - hurt.health, 50.0),
			"missing %.0f" % (hurt.max_health - hurt.health))

	# Lychee hits back every 100 health it loses.
	var lychee := board.place_plant(&"lychee", 4, 3)
	var biter := board.spawn_zombie_at(&"tutorial", 4, lychee.position.x + 20.0)
	biter.speed = 0.0
	lychee.take_damage(250.0, biter)
	check_eq("lychee struck back twice", biter.max_health - biter.health, 40.0)
	board.queue_free()

	# Infi-nut lies flat when eaten down and grows back.
	var board2 := _make_board()
	var infi := board2.place_plant(&"holonut", 0, 3)
	infi.take_damage(infi.max_health + 10.0)
	check("infi-nut survives being eaten down", not infi.is_dead)
	check("but lies flat, uneatable", infi.has_tag(&"uneatable"))
	infi.component(&"regrower")._downed_left = 0.1
	await _wait_game_seconds(0.3)
	check("and springs back at full health", not infi.has_tag(&"uneatable")
			and is_equal_approx(infi.health, infi.max_health))

	# Murkadamia's jelly soaks and reflects while shadow powered.
	var murk := board2.place_plant(&"murkadamia", 1, 3)
	var eater := board2.spawn_zombie_at(&"tutorial", 1, murk.position.x + 20.0)
	eater.speed = 0.0
	eater.max_health = 2000.0
	eater.health = 2000.0
	murk.add_timed_tag(&"shadow_powered", 10.0)
	murk.take_damage(400.0, eater)
	check("murkadamia's jelly took the bite", is_equal_approx(murk.health, murk.max_health))
	check_eq("and threw a quarter back", eater.max_health - eater.health, 100.0)

	# Sweet potato lures a zombie in the next lane into its own.
	var potato := board2.place_plant(&"sweetpotato", 3, 4)
	var lured := board2.spawn_zombie_at(&"tutorial", 4, potato.position.x + 80.0)
	lured.speed = 0.0
	await _wait_game_seconds(0.2)
	check_eq("sweet potato pulled the zombie into its lane", lured.row, 3)
	board2.queue_free()

	# Gumnut glues the zombie that walks up to it.
	var board3 := _make_board()
	var gum := board3.place_plant(&"gumnut", 0, 3)
	var chewer := board3.spawn_zombie_at(&"tutorial", 0, gum.position.x + 50.0)
	chewer.speed = 0.0
	await _wait_game_seconds(0.2)
	check("gumnut is spent", not is_instance_valid(gum) or gum.is_dead)
	check("and the zombie is gummed", chewer.has_tag(&"gummed"))
	var stuck_x := chewer.position.x
	chewer.speed = 0.5
	await _wait_game_seconds(1.0)
	check("a gummed zombie stays put", is_equal_approx(chewer.position.x, stuck_x))

	# Chard guard throws a zombie back down the lane.
	var chard := board3.place_plant(&"chardguard", 1, 2)
	var thrown := board3.spawn_zombie_at(&"tutorial", 1, chard.position.x + 40.0)
	thrown.speed = 0.0
	var thrown_x := thrown.position.x
	await _wait_game_seconds(0.2)
	check("chard guard threw the zombie back", thrown.position.x > thrown_x + 100.0)
	check_eq("and used a fling", chard.component(&"bouncer").uses, 2)

	# Vamporcini drains its neighbours and grows on it.
	var vamp := board3.place_plant(&"vamporcini", 3, 4)
	var drained := board3.spawn_zombie_at(&"tutorial", 3, vamp.position.x + 60.0)
	drained.speed = 0.0
	drained.max_health = 2000.0
	drained.health = 2000.0
	var vamp_max := vamp.max_health
	await _wait_game_seconds(1.0)
	check("vamporcini drained the zombie", drained.health < 2000.0)
	check("and grew tougher", vamp.max_health > vamp_max)
	board3.queue_free()

	# Buttercup butters whatever eats it.
	var board4 := _make_board()
	var cup := board4.place_plant(&"buttercup", 0, 3)
	var muncher := board4.spawn_zombie_at(&"tutorial", 0, cup.position.x)
	muncher.max_health = 2000.0
	muncher.health = 2000.0
	await _wait_game_seconds(0.5)
	check("buttercup stunned its eater", muncher.is_stunned())
	check("and stung it", muncher.health <= 1900.0)

	# Noctarine's cloud stings and fades.
	var cloud := board4.place_plant(&"noctarine", 2, 4)
	var stung := board4.spawn_zombie_at(&"tutorial", 3, cloud.position.x + 40.0)
	stung.speed = 0.0
	await _wait_game_seconds(0.3)
	check("noctarine's cloud stung the next lane", stung.health < stung.max_health)
	cloud.component(&"gas_cloud")._age = 100.0
	await _wait_game_seconds(0.1)
	check("and fades", not is_instance_valid(cloud) or cloud.is_dead)

	# Zoybean pod grows charmed zombies.
	var pod := board4.place_plant(&"zoybeanpod", 4, 1)
	pod.component(&"zoy_grower")._timer = 0.0
	await _wait_game_seconds(0.1)
	check("zoybean pod grew a zombie on our side",
			not board4.charmed_zombies_in_row(4).is_empty())

	# Magnet-shroom pulls a bucket off.
	var magnet := board4.place_plant(&"magnetshroom", 1, 3)
	var bucket := board4.spawn_zombie_at(&"tutorial_armor2", 1, magnet.position.x + 120.0)
	bucket.speed = 0.0
	check("the bucket is metal", bucket.has_tag(&"metal"))
	await _wait_game_seconds(0.2)
	check("magnet-shroom took it", not bucket.has_tag(&"metal"))
	check("and is resting", magnet.component(&"magnet")._rest_left > 0.0)
	board4.queue_free()
	end_section()


## Behaviour comes from the fields a zombie carries, the same inversion the
## plants went through. ZombieSort would have been the obvious discriminator
## and the useless one: it separates Normal from Gargantuar and says nothing
## about what either does.
func _test_zombie_behaviour_coverage() -> void:
	section("zombie coverage")
	# Hitboxes are data, not behaviour; a zombie with only those still just
	# walks and bites.
	var hitboxes: Array[StringName] = [&"attack_rect", &"hit_rect"]
	var with_behaviour := 0
	var unimplemented: Array[StringName] = []
	var kinds := {}
	for id in Data.zombies:
		var def: ZombieDef = Data.zombies[id]
		var any := false
		for spec in def.components:
			if hitboxes.has(spec.type):
				continue
			if Components.has_type(spec.type):
				any = true
				kinds[spec.type] = int(kinds.get(spec.type, 0)) + 1
			elif not unimplemented.has(spec.type):
				unimplemented.append(spec.type)
		if any:
			with_behaviour += 1
	check("every declared zombie behaviour is implemented",
			unimplemented.is_empty(), str(unimplemented))
	check("a good share of the roster does something",
			with_behaviour >= 240, "%d of %d" % [with_behaviour, Data.zombies.size()])
	print("        (%d of %d zombies have a working behaviour: %s)"
			% [with_behaviour, Data.zombies.size(), str(kinds)])
	end_section()


## Every world's gargantuar is the same zombie with one twist, so the shared
## part belongs in the archetype and each entry should carry only its
## difference. This checks the inheritance actually delivers the shared part.
func _test_zombie_archetypes() -> void:
	section("zombie archetypes")
	var garg: ZombieDef = Data.zombie(&"beach_gargantuar")
	check("a world gargantuar loaded", garg != null)
	check_eq("it inherits the archetype", garg.extends_id, &"gargantuar")
	check_eq("including toughness it never states", garg.toughness, 3600.0)
	var smash: ComponentSpec = garg.component_spec(&"smasher")
	check("and the shared smasher", smash != null)
	if smash != null:
		check_eq("at archetype damage", float(smash.config.get(&"damage", 0.0)), 1500.0)
	var throw: ComponentSpec = garg.component_spec(&"imp_thrower")
	check("while stating its own imp", throw != null)
	if throw != null:
		check_eq("which is this world's", StringName(throw.config.get(&"imp", &"")),
				&"beach_imp")

	# The file itself has to stay small, or the archetype is decoration.
	var raw := FileAccess.get_file_as_string("res://data/native/zombies/beach_gargantuar.json")
	check("its file stays a delta", raw.length() < 400, "%d bytes" % raw.length())

	# Kung-Fu is the real overhaul of the gargantuar, so it must be able to
	# drop what the archetype gave it.
	var statue: ZombieDef = Data.zombie(&"kongfu_bronze_statue")
	check("the bronze statue loaded", statue != null)
	check("it opts out of smashing", statue.component_spec(&"smasher") == null)
	check("summons instead", statue.component_spec(&"summoner") != null)
	check("and is temporary", statue.component_spec(&"lifespan") != null)
	check_eq("with its own toughness", statue.toughness, 9000.0)

	# Two of one component type is meaningful: a poncho zombie wears a plate
	# over a poncho and both have to be chewed through.
	var poncho: ZombieDef = Data.zombie(&"easter_poncho")
	check("the poncho zombie loaded", poncho != null)
	check_eq("it keeps both armor pools",
			poncho.components_of(&"armor").size(), 2)
	end_section()


func _test_zombie_behaviours() -> void:
	section("zombie behaviours")
	var board := _make_board()

	# A smasher stops at a plant and flattens it, rather than nibbling.
	var wall: Plant = board.place_plant(&"wallnut", 1, 2)
	check("a wall-nut placed", wall != null)
	var garg: Zombie = board.spawn_zombie(&"beach_gargantuar", 1)
	check("a gargantuar spawned", garg != null)
	check("its attack is claimed by a component", garg.attack_claimed)
	if wall != null and garg != null:
		var wall_hp: float = wall.health
		garg.position.x = wall.position.x
		garg.col = wall.col
		await _wait_game_seconds(1.2)
		check("the wall-nut was smashed, not eaten",
				not is_instance_valid(wall) or wall.health < wall_hp)

	# Worn down to half, a gargantuar throws its imp over the defences.
	var thrower: Zombie = board.spawn_zombie(&"beach_gargantuar", 2)
	var before := board.zombie_count()
	thrower.take_damage(thrower.max_health * 0.6, null)
	await get_tree().process_frame
	check("an imp was thrown at half health", board.zombie_count() > before,
			"%d -> %d" % [before, board.zombie_count()])

	# A camel lets its mummy out when it dies.
	var camel: Zombie = board.spawn_zombie(&"camel_onehump", 3)
	check("a camel spawned", camel != null)
	var riders := board.zombie_count()
	camel.die()
	await get_tree().process_frame
	check("the rider got out", board.zombie_count() >= riders,
			"%d -> %d" % [riders, board.zombie_count()])
	board.queue_free()

	# An escort arrives as several bodies from one spawn, and the members must
	# not bring escorts of their own.
	var board2 := _make_board()
	var lead: Zombie = board2.spawn_zombie(&"camel_onehump", 0)
	check("a train leader spawned", lead != null)
	check("it brought company", board2.zombies_in_row(0).size() > 1,
			"%d in the lane" % board2.zombies_in_row(0).size())
	check("the train is finite", board2.zombie_count() < 20,
			"%d zombies" % board2.zombie_count())
	for z: Zombie in board2.zombies_in_row(0):
		if z != lead:
			check("members are marked as escorting", z.has_tag(&"escorting"))
			break
	board2.queue_free()

	# Losing the last of its armor enrages a newspaper zombie.
	var board3 := _make_board()
	var news: Zombie = board3.spawn_zombie(&"modern_newspaper", 2)
	check("a newspaper zombie spawned", news != null)
	var paced: float = news.speed
	check("it starts calm", not news.has_tag(&"enraged"))
	# Exactly the paper's worth of damage: the armor absorbs all of it, so
	# nothing reaches the body and no damage signal fires. It must still rage.
	news.take_damage(800.0, null)
	await get_tree().process_frame
	check("it survived losing the paper", not news.is_dead)
	check_eq("which took no health", news.health, news.max_health)
	check("and is enraged anyway", news.has_tag(&"enraged"))
	check("moving faster than before", news.speed > paced,
			"%f -> %f" % [paced, news.speed])
	board3.queue_free()
	end_section()


## Resistances are the other half of what separates one world's zombies from
## another's, and they are stats rather than components.
func _test_zombie_resistances() -> void:
	section("zombie resistance")
	var board := _make_board()

	var plain: Zombie = board.spawn_zombie(&"tutorial", 0)
	plain.apply_stun(2.0)
	check("an ordinary zombie can be stunned", plain.is_stunned())

	# Every zombie carrying ChiliStunDurationMult reads 0: a mech does not stop.
	var mech: ZombieDef = Data.zombie(&"football_mech")
	check("a stun-proof zombie exists", mech != null)
	check_eq("its stun scale is zero", mech.stun_scale, 0.0)
	var proof: Zombie = board.spawn_zombie(&"football_mech", 1)
	proof.apply_stun(2.0)
	check("so stunning it does nothing", not proof.is_stunned())
	check("and it says why", proof.has_tag(&"stun_immune"))

	# Ice chills a troglobite instead of holding it.
	var trog: Zombie = board.spawn_zombie(&"iceage_troglobite", 2)
	check("a chill-only zombie spawned", trog != null)
	check("it is tagged chill_only", trog.has_tag(&"chill_only"))
	trog.apply_freeze(2.0)
	check("freezing only slows it", not trog.is_stunned())
	check("but it is slowed", trog.has_tag(&"slowed"))
	check("and never frozen solid", not trog.has_tag(&"frozen"))

	# A ducky-tube zombie swims faster than it walks.
	var duck: Zombie = board.spawn_zombie(&"duckytube", 3)
	var on_land: float = duck.current_speed()
	board.set_terrain(3, duck.col, &"water")
	check("water speeds it up", duck.current_speed() > on_land,
			"%f -> %f" % [on_land, duck.current_speed()])
	var walker: Zombie = board.spawn_zombie(&"tutorial", 4)
	board.set_terrain(4, walker.col, &"water")
	check_eq("an ordinary zombie is unaffected by it",
			walker.current_speed(), walker.speed)
	board.queue_free()
	end_section()



## Zomboss is the one zombie whose whole fight is in the data: staged health
## pools and a weighted action list per stage. This checks the stages are read
## and that exhausting one advances rather than kills.
func _test_zomboss() -> void:
	section("zomboss")
	var def: ZombieDef = Data.zombie(&"zombossmech_egypt")
	check("a boss loaded", def != null)
	var spec: ComponentSpec = def.component_spec(&"zomboss")
	check("it has a zomboss component", spec != null)
	if spec == null:
		end_section()
		return
	var stages: Array = spec.config.get(&"stages", [])
	check_eq("with three stages", stages.size(), 3)
	var first: Dictionary = stages[0]
	check_eq("the first stage's health", float(first.get("health", 0.0)), 4000.0)
	var actions: Array = first.get("actions", [])
	check_eq("and four actions", actions.size(), 4)
	var names: Array = []
	for a: Dictionary in actions:
		names.append(a.get("action"))
	check("summon is one of them", names.has("summon"), str(names))
	# A point budget on a non-summon action is PopCap's default, not meaning.
	for a: Dictionary in actions:
		if a.get("action") != "summon":
			check("'%s' carries no point budget" % a.get("action"),
					not a.has("points"))
			break

	var board := _make_board()
	var boss: Zombie = board.spawn_zombie(&"zombossmech_egypt", 2)
	check("the boss spawned", boss != null)
	var zomboss: EntityComponent = boss.component(&"zomboss")
	check("its component is live", zomboss != null)
	check_eq("health comes from the stage, not toughness", boss.max_health, 4000.0)
	check("it moves itself", boss.movement_claimed)
	check("and does not bite", boss.attack_claimed)

	# It must stay put rather than walking into the house.
	var start_x: float = boss.position.x
	await _wait_game_seconds(0.4)
	check("it holds its ground instead of walking in",
			absf(boss.position.x - start_x) < board.cell_size.x * 3.0,
			"moved %f" % (boss.position.x - start_x))

	# Exhausting a stage advances instead of killing.
	boss.take_damage(99999.0, null)
	check("stage one did not kill it", not boss.is_dead)
	check_eq("it advanced", zomboss.stage_index, 1)
	check_eq("to the next pool", boss.max_health, 8000.0)
	boss.take_damage(99999.0, null)
	check_eq("and again", zomboss.stage_index, 2)
	check("still alive", not boss.is_dead)
	boss.take_damage(99999.0, null)
	check("the last stage kills it", boss.is_dead)
	board.queue_free()

	# Every boss in the data is flatly immune to a plant's stun, so the
	# stagger its stage describes has to be earned another way: by hurting it
	# hard and fast. Once reeling it takes the stage's damage multiplier.
	var board2 := _make_board()
	var b2: Zombie = board2.spawn_zombie(&"zombossmech_egypt", 2)
	var boss2: EntityComponent = b2.component(&"zomboss")
	check_eq("a plant cannot stun a boss", b2.def.stun_scale, 0.0)
	b2.apply_stun(5.0)
	check("so stunning it does nothing", not b2.is_stunned())
	check("a chip of damage does not stagger it", not boss2.is_staggered())
	b2.take_damage(10.0, null)
	check("still steady", not boss2.is_staggered())
	# 8% of a 4000 pool is 320, so this burst earns a stagger.
	b2.take_damage(400.0, null)
	check("a burst staggers it", boss2.is_staggered())
	var hp: float = b2.health
	b2.take_damage(100.0, null)
	check("and it takes the stage multiplier while reeling",
			b2.health < hp - 100.0, "lost %f for 100" % (hp - b2.health))
	board2.queue_free()

	# The boss summons from its own list, and its summons do not summon.
	var board3 := _make_board()
	var b3: Zombie = board3.spawn_zombie(&"zombossmech_egypt", 2)
	var before := board3.zombie_count()
	var summon: EntityComponent = b3.component(&"zomboss")
	summon._action = {"action": "summon", "zombies": ["mummy"],
			"points": 600, "points_max": 600}
	summon._summon()
	check("it called zombies onto the lawn", board3.zombie_count() > before,
			"%d -> %d" % [before, board3.zombie_count()])
	check("within the point budget", board3.zombie_count() - before <= 6,
			"%d summoned" % (board3.zombie_count() - before))
	board3.queue_free()
	end_section()


## A roar stuns every plant, and a plant has nothing to stop walking - so a
## stun has to reach its components instead. It does that through the same
## scaling a buff uses, which is why no component had to change.
func _test_plant_stun() -> void:
	section("plant stun")
	var board := _make_board()
	var pea: Plant = board.place_plant(&"peashooter", 2, 1)
	check("a peashooter placed", pea != null)
	check("it starts unsuppressed", not pea.is_stunned())
	check_eq("at full pace", pea.suppression, 1.0)
	pea.apply_stun(2.0)
	check("stunned", pea.is_stunned())
	check("and tagged", pea.has_tag(&"suppressed"))
	check("its pace collapsed", pea.suppression < 0.2,
			"suppression %f" % pea.suppression)

	# Suppression reaches a component's timers without the component knowing.
	var shooter: EntityComponent = pea.component(&"shooter")
	check("the shooter exists", shooter != null)
	if shooter != null:
		check("so its interval stretched", shooter.scaled(1.0) > 5.0,
				"scaled(1.0) = %f" % shooter.scaled(1.0))

	# A boss roar hits every plant on the board, not just one lane.
	var far: Plant = board.place_plant(&"sunflower", 0, 5)
	var boss: Zombie = board.spawn_zombie(&"kongfu_boss_chi", 3)
	var roar: EntityComponent = boss.component(&"zomboss")
	check("the kung-fu boss roars", roar != null)
	if roar != null and far != null:
		roar._roar()
		check("a plant in another lane was stunned", far.is_stunned())
	board.queue_free()
	end_section()



## Extracted art is optional - it lives in the private `art` submodule - so this
## checks it loads and drives when present, and that nothing breaks when not.
func _test_art() -> void:
	section("art")
	if not Art.is_available():
		check("no art extracted, placeholders stand in", true,
				"check out the art submodule to exercise this")
		end_section()
		return

	var board := _make_board()
	var pea: Plant = board.place_plant(&"peashooter", 2, 1)
	check("a peashooter placed", pea != null)
	check("it got its artwork", pea != null and pea.art != null)
	if pea != null and pea.art != null:
		check("which has bones and sprites",
				pea.art.get_child_count() > 0)
		check("and the idle animation is running",
				pea.art.playing != &"", String(pea.art.playing))
		check("it knows its rig's animations",
				pea.art.has_animation(&"Shoot"), str(pea.art.animation_names()))

	var z: Zombie = board.spawn_zombie(&"tutorial", 2)
	check("a zombie spawned with art", z.art != null)
	if z.art != null:
		check_eq("walking on spawn", z.art.playing, &"Walk")
		# The rig is drawn walking toward the house already, so a hostile
		# zombie is NOT mirrored; a charmed one is.
		check("a hostile zombie is not mirrored", z.art.facing == 1)
		# A hand hidden at rest stays hidden until an animation shows it.
		var spare: Node2D = z.art.get_node_or_null(^"hand_side_HAND")
		check("the spare eating hand starts invisible",
				spare != null and spare.modulate.a < 0.01)
		await get_tree().process_frame
		var stride := z.art.ground_speed(&"Walk")
		check("the walk plays at the pace the zombie moves",
				stride > 0.0 and is_equal_approx(z.art.speed_scale(),
						z.current_speed() * z._entering_scale() * board.cell_size.x / stride),
				"%.3f" % z.art.speed_scale())
		z.apply_stun(0.5)
		await get_tree().process_frame
		check_eq("and stops dead when stunned", z.art.speed_scale(), 0.0)
		await _wait_game_seconds(0.6)
		z.charm()
		check("a charmed one is", z.art.facing == -1)
		z.set_allegiance(Zombie.Allegiance.HOSTILE)
		# Eating is a different animation, and it must not restart every frame.
		z.target = pea
		await _wait_game_seconds(0.2)
		check_eq("and eating once it reaches a plant", z.art.playing, &"Eat")

	# Drawn as PVZGE draws them: one scale for every character, so the art's
	# own proportions decide who is bigger, and feet on the lane's floor.
	var sunny: Plant = board.place_plant(&"sunflower", 3, 1)
	if pea != null and pea.art != null and sunny != null and sunny.art != null:
		check("a peashooter and a sunflower share one scale",
				is_equal_approx(pea.art.scale.y, sunny.art.scale.y))
		check("and stand on the lane's floor, below the cell's centre",
				pea.art.position.y > 0.0 and is_equal_approx(pea.art.position.y, sunny.art.position.y))
		if z.art != null:
			check("zombies are drawn at the plants' scale",
					is_equal_approx(absf(z.art.scale.y), pea.art.scale.y))
	check("zombies come on from past the screen's right edge",
			board.spawn_x() >= board.lawn_right_x() + board.cell_size.x * 2.5)
	var cone: Zombie = board.spawn_zombie(&"tutorial_armor1", 0)
	if cone.art != null and cone.art.socket(&"armor") != null:
		check("a cone zombie wears its cone's rig", cone.has_armor_art())
		cone.component(&"armor").strip()
		await get_tree().process_frame
		check("which comes off with the armor", not cone.has_armor_art())
	check("a zombie off the lawn hurries on", cone._entering_scale() > 1.0)

	# Acting changes what a plant is doing, and it goes back to idling after.
	# The component says what happened; it never names an animation.
	if pea != null and pea.art != null and pea.art.has_animation(&"Shoot"):
		var idle_name: StringName = Art.animation_for(&"plant", &"peashooter", &"idle")
		board.spawn_zombie(&"tutorial", 2)
		await _wait_game_seconds(2.0)
		check("firing changed the animation or returned to idle",
				pea.art.playing == &"Shoot" or pea.art.playing == idle_name,
				String(pea.art.playing))

	# Animations are Godot resources now, not a hand-rolled sampler.
	var rig := Art.set_for(&"zombies_BasicZOMBIE")
	var library := rig.animations(&"BasicZombie")
	check("animations baked into a Godot library",
			library.get_animation_list().size() > 0,
			str(library.get_animation_list()))
	var walk: Animation = library.get_animation(&"Walk")
	check("with real tracks and keys", walk != null and walk.get_track_count() > 0)
	if walk != null:
		check("and a length from the source frame rate",
				absf(walk.length - 3.0) < 0.1, "%f" % walk.length)
	check("baking happens once per rig",
			rig.animations(&"BasicZombie") == library)

	# The rig's limbs are posed by IK, and its slots animate as well as move.
	var baker := rig.rig(&"BasicZombie")
	check_eq("the zombie's legs and arms are IK chains", baker.iks.size(), 4)
	if walk != null:
		check("a walk says how fast it was drawn to travel",
				float(walk.get_meta(&"ground_speed", 0.0)) > 10.0)
		check("and keys which foot picture shows",
				walk.find_track(NodePath("foot_there/0:visible"), Animation.TYPE_VALUE) >= 0)
	var eat: Animation = library.get_animation(&"Eat")
	if walk != null and eat != null:
		# Every animation keys every moving part, so none inherits the pose
		# the last one left behind - eating arms carried into the walk.
		check("walk keys the same parts eating moves",
				walk.find_track(NodePath("hand_here_HAND:position"), Animation.TYPE_VALUE) >= 0
				and eat.find_track(NodePath("hand_here_HAND:position"), Animation.TYPE_VALUE) >= 0)
		check("and fades the eating hands in and out",
				eat.find_track(NodePath("hand_side_HAND:modulate"), Animation.TYPE_VALUE) >= 0)
	var turns := baker._rotation_timeline([
		{"duration": 5, "rotate": 170.0}, {"duration": 0, "rotate": -170.0}])
	check_eq("a key past the seam turns the short way",
			float(turns[1]["value"]), 190.0)
	var spun := baker._rotation_timeline([
		{"duration": 5, "rotate": 0.0, "clockwise": 1}, {"duration": 0, "rotate": -10.0}])
	check_eq("unless the rig says to go round the long way",
			float(spun[1]["value"]), 350.0)

	# A rig says when it acts, and where from.
	if pea != null and pea.art != null:
		check("and its Shoot animation announces the shot",
				pea.art.announces(&"Shoot", [&"Shoot"]))
		# PVZGE's PeaSpawnPoint: ahead of the stem and up at the mouth, which
		# at the shared character scale is about 34 x 41 px off the feet.
		var feet := pea.position + pea.art.position
		var spout := pea.launch_point() - feet
		check("the pea leaves from the peashooter's mouth",
				absf(spout.x - 66.538 * pea.art.scale.x) < 0.5
				and absf(spout.y + 79.306 * pea.art.scale.y) < 0.5,
				"%.1f,%.1f" % [spout.x, spout.y])
		var shot := board.spawn_projectile(&"pea", pea.row, pea.launch_point(), pea)
		check_eq("and appears exactly there", shot.position, pea.launch_point())
		shot.queue_free()
	var bare: Plant = board.place_plant(&"sunflower", 0, 8)
	if bare != null:
		check_eq("a plant without a spawn point fires from just ahead of it",
				bare.launch_point(), bare.position + Vector2(24, -12))

	# Losing a limb: the whole arm comes off, the stump underneath shows.
	var hurt: Zombie = board.spawn_zombie(&"tutorial", 4)
	if hurt.art != null:
		var before := hurt.art.slot_names().size()
		hurt.take_damage(hurt.max_health * 0.75, null)
		await get_tree().process_frame
		check("the arm came off", hurt.art.slot_names().size() < before,
				"%d -> %d slots" % [before, hurt.art.slot_names().size()])

	# The lawn reads front to back, and a zombie covers the plant it eats.
	check("a front row draws over a back row",
			board.lane_z(4, Board.LAYER_PLANT) > board.lane_z(0, Board.LAYER_ZOMBIE))
	check("and within a row the zombie is in front",
			board.lane_z(2, Board.LAYER_ZOMBIE) > board.lane_z(2, Board.LAYER_PLANT))
	check("while sun sits above the lot",
			Board.LAYER_COLLECTABLE > board.lane_z(board.rows, Board.LAYER_PROJECTILE))
	var scattered: Zombie = board.spawn_zombie(&"tutorial", 1)
	check("zombies stand off the lane's centre line",
			absf(scattered.lane_offset) > 0.0,
			"%.2f" % scattered.lane_offset)

	# A shared bundle is parsed once however many entities use it.
	var first := Art.set_for(&"zombies_BasicZOMBIE")
	var second := Art.set_for(&"zombies_BasicZOMBIE")
	check("bundles are shared, not reloaded", first == second)
	check("armors read the same rig as the zombie",
			first != null and first.has_armature(&"Cone")
			and first.has_armature(&"BasicZombie"))
	board.queue_free()
	end_section()


func _test_scenery_art() -> void:
	section("scenery art")
	# Without art the lawn must still be playable, drawing its placeholder.
	var bare := _make_board()
	check("an unknown stage builds no scenery",
			not bare.scenery.show_stage(&"NoSuchStage", bare, 5))
	check("so the placeholder lawn still draws", not bare.scenery.has_art())
	bare.queue_free()
	if not Art.is_available() or Art.set_for(&"lawns_TutorialLAWN") == null:
		check("no lawn art extracted, placeholders stand in", true,
				"run tools/extract_prefabs.py lawns/ and tools/extract_rigs.py")
		end_section()
		return

	var board := _make_board()
	board.plantable_rows = [2]
	board.mowers_enabled = true
	board.setup_mowers()
	var runner := LevelRunner.new()
	runner.level = {"stage": "TutorialStage"}
	board.setup_lawn({}, runner)
	runner.free()
	check("the tutorial stage gets its lawn", board.scenery.has_art())
	check("which says which lanes are sodded", board.scenery.shows_open_rows())
	check_eq("one sodded lane picks the one-row lawn",
			board.scenery.sod_animation, &"row1")
	var mower := board.mower_in_row(0)
	check("the mowers get their world's art", mower != null and mower.art != null)

	# The mower revs in place before it drives, as PVZGE's does.
	var start_x := mower.position.x
	mower.trigger()
	await _wait_game_seconds(0.05)
	check("it revs in place first", is_equal_approx(mower.position.x, start_x))
	await _wait_game_seconds(1.0)
	check("then drives off", mower == null or not is_instance_valid(mower)
			or mower.position.x > start_x + 40.0)

	var sun := SunToken.new()
	board.add_child(sun)
	check("sun has its art", sun.art != null)

	# A sunflower's sun leaves its head on the Produce event and lands at
	# its feet, as PVZGE's SunProducePoint does.
	var sf := board.place_plant(&"sunflower", 2, 2)
	check("a sunflower has its art", sf != null and sf.art != null)
	if sf != null and sf.art != null:
		var suns := board.get_node("Suns")
		var before := suns.get_child_count()
		var producer: EntityComponent = null
		for c in sf._components:
			if c.get_script().resource_path.ends_with("sun_producer.gd"):
				producer = c
		check("the sunflower has a sun producer", producer != null)
		if producer != null:
			producer.set(&"_timer", 0.0)
			await get_tree().process_frame
			check("no sun before the Produce event", suns.get_child_count() == before)
			# The event is 23 frames in; the flight takes under a second.
			await _wait_game_seconds(2.2)
			var popped: SunToken = null
			for t in suns.get_children():
				if t is SunToken and t != sun:
					popped = t
			check("then one appears", popped != null)
			if popped != null:
				var feet: float = sf.position.y + sf.art.position.y
				check("it lands at the sunflower's feet",
						is_equal_approx(popped.position.y, feet),
						"%.1f vs %.1f" % [popped.position.y, feet])
				check("near the sunflower",
						absf(popped.position.x - sf.position.x) < board.cell_size.x,
						"%.1f vs %.1f" % [popped.position.x, sf.position.x])
	board.queue_free()
	end_section()


func _test_zombie_status_effects() -> void:
	section("zombie status")
	var board := _make_board()
	var z := board.spawn_zombie(&"tutorial", 2)
	var base: float = z.speed
	var start_x: float = z.position.x

	z.apply_stun(1.0)
	check("stunned zombie reports it", z.is_stunned())
	check("and is tagged", z.has_tag(&"stunned"))
	await _wait_game_seconds(0.3)
	check("a stunned zombie does not move",
			is_equal_approx(z.position.x, start_x),
			"%.2f vs %.2f" % [z.position.x, start_x])

	await _wait_game_seconds(1.2)
	check("the stun wears off", not z.is_stunned())
	await _wait_game_seconds(0.3)
	check("and it moves again", z.position.x < start_x)

	z.apply_slow(0.5, 1.0)
	check_eq("slow halves the speed", z.speed, base * 0.5)
	check("and is tagged", z.has_tag(&"slowed"))
	# Re-applying must not stack into a standstill.
	z.apply_slow(0.5, 1.0)
	check_eq("re-applying does not compound", z.speed, base * 0.5)
	await _wait_game_seconds(1.4)
	check_eq("speed is restored exactly", z.speed, base)
	check("and the tag cleared", not z.has_tag(&"slowed"))

	# A buff speeds a plant's components up without them knowing about buffs.
	var plant := board.place_plant(&"peashooter", 3, 1)
	var shooter := plant.component(&"shooter")
	check("plant has a shooter", shooter != null)
	check_eq("unbuffed rate is 1", plant.attack_rate, 1.0)
	var before := shooter.scaled(2.0)
	plant.apply_buff(2.0, 1.0, 5.0)
	check("plant reports buffed", plant.is_buffed())
	check_eq("intervals halve under a 2x buff", shooter.scaled(2.0), before * 0.5)
	board.queue_free()
	end_section()


## I-Zombie needs a cost per zombie. PopCap's data has none, so it is derived
## from wave cost - and must at least order sensibly.
func _test_zombie_sun_costs() -> void:
	section("zombie sun costs")
	# Including mod-authored zombies, which never state a cost.
	var free: Array[StringName] = []
	for id in Data.zombies:
		if (Data.zombies[id] as ZombieDef).placement_cost() <= 0:
			free.append(id)
	check("no zombie is free to place", free.is_empty(),
			"%d free: %s" % [free.size(), str(free.slice(0, 5))])

	var basic := Data.zombie(&"tutorial")
	var cone := Data.zombie(&"tutorial_armor1")
	var bucket := Data.zombie(&"tutorial_armor2")
	var garg := Data.zombie(&"tutorial_gargantuar")
	check("basic is the cheapest of the four",
			basic.placement_cost() <= cone.placement_cost())
	check("armour costs more than none",
			cone.placement_cost() < bucket.placement_cost(),
			"%d vs %d" % [cone.placement_cost(), bucket.placement_cost()])
	check("a gargantuar costs most",
			garg.placement_cost() > bucket.placement_cost(),
			"%d vs %d" % [garg.placement_cost(), bucket.placement_cost()])

	# A mod zombie that states no cost is still priced.
	var modded := Data.zombie(&"neon_colossus")
	if modded != null:
		check("a mod zombie is priced too", modded.placement_cost() > 0,
				"%d" % modded.placement_cost())

	# The board prices a zombie seed from the zombie, not the plant table.
	var board := _make_board()
	check_eq("board reads the zombie's cost",
			board.seed_cost(&"zombie", &"tutorial"), basic.placement_cost())
	board.queue_free()
	end_section()


## Every level keeps its own slot, so several can be part-played at once.
func _test_level_save_state() -> void:
	section("level save state")
	Saves.clear_save(&"tutorial_2")
	Saves.clear_save(&"tutorial_3")
	check("no save to begin with", not Saves.has_save(&"tutorial_2"))

	var board := _make_board()
	var runner := LevelRunner.new()
	runner.first_wave_delay = 0.0
	add_child(runner)
	var bank := SeedBank.new()
	add_child(bank)
	board.seed_bank = bank

	runner.start(Data.level(&"tutorial_2"), board)
	bank.setup(runner.seedbank_seeds())

	# Build a state worth remembering.
	board.place_plant(&"peashooter", 2, 1)
	board.place_plant(&"sunflower", 3, 2)
	board.add_sun(175)
	board.add_plant_food(2)
	bank.spend(0)
	await _wait_game_seconds(1.0)
	var zombies := board.zombie_count()

	var sun: int = board.sun
	var food: int = board.plant_food
	var wave: int = runner.wave_index
	var charge: float = bank.packet(0).charge

	check("saved", Saves.save_level(runner, board, bank))
	check("slot exists", Saves.has_save(&"tutorial_2"))

	# Now wreck it, so a successful restore cannot be a coincidence.
	board.reset()
	runner.start(Data.level(&"tutorial_2"), board)
	bank.setup(runner.seedbank_seeds())
	check_eq("board really was cleared", board.plant_at(2, 1), null)
	check("sun really was reset", board.sun != sun)

	# And restore.
	var data := Saves.load_save(&"tutorial_2")
	check("save loads back", not data.is_empty())
	check("restored", Saves.restore(data, runner, board, bank))

	check_eq("sun came back", board.sun, sun)
	check_eq("plant food came back", board.plant_food, food)
	check("the peashooter is back", board.plant_at(2, 1) != null)
	check("the sunflower is back", board.plant_at(3, 2) != null)
	check_eq("wave progress came back", runner.wave_index, wave)
	# Charge is a float, so compare approximately.
	check("packet charge came back",
			is_equal_approx(bank.packet(0).charge, charge),
			"%f vs %f" % [bank.packet(0).charge, charge])
	check_eq("the zombies came back", board.zombie_count(), zombies)

	# Slots are per level.
	runner.start(Data.level(&"tutorial_3"), board)
	Saves.save_level(runner, board, bank)
	check("a second level has its own slot", Saves.has_save(&"tutorial_3"))
	check("the first is untouched", Saves.has_save(&"tutorial_2"))
	check("both are listed", Saves.saved_levels().size() >= 2)

	# Clearing a level retires its slot.
	Saves.mark_cleared(&"tutorial_2")
	check("clearing a level marks it", Saves.is_cleared(&"tutorial_2"))
	check("and retires its save", not Saves.has_save(&"tutorial_2"))
	check("without touching the other", Saves.has_save(&"tutorial_3"))

	Saves.clear_save(&"tutorial_3")
	runner.queue_free()
	bank.queue_free()
	board.queue_free()
	end_section()


## Wipes every save slot so the run starts from nothing.
func _clear_all_saves() -> void:
	var cleared := Saves.saved_levels()
	for level_id in cleared:
		Saves.clear_save(level_id)
	Saves.reset_progress()
	if not cleared.is_empty():
		print("        (cleared %d save slot(s) from a previous run)"
				% cleared.size())


# --- helpers -------------------------------------------------------------

## Gravestones, tiles and ice blocks standing in cells.
func _test_grid_items() -> void:
	section("grid items")
	var board := _make_board()

	var grave = board.place_object(&"gravestone_egypt", 2, 6)
	check("a gravestone is placed", grave is Grave)
	check("it is found in its cell", board.object_at(2, 6) == grave)
	check("one item per cell", board.place_object(&"gravestone", 2, 6) == null)
	check("a gravestone blocks planting",
			board.placement_refusal(&"plant", &"peashooter", 2, 6) != "")
	check("zombies may still drop there",
			board.can_place_entity(&"zombie", &"tutorial", 2, 6))

	var puddle = board.place_object(&"potholepuddle", 1, 4)
	check("a tile is placed as a grid object",
			puddle is GridObject and not (puddle is Grave))
	check("a puddle placed as an object carries its terrain rule",
			board.placement_refusal(&"plant", &"peashooter", 1, 4) != "")
	check("a plant-named grid item is planted instead",
			board.place_object(&"lilypad", 0, 3) is Plant)

	# A peashooter facing a gravestone fires at it until it breaks.
	var shooter := board.place_plant(&"peashooter", 2, 1)
	var full: float = grave.health
	await _wait_game_seconds(6.0)
	check("peas hit the gravestone", not is_instance_valid(grave) or grave.health < full,
			"%s of %s" % [grave.health if is_instance_valid(grave) else 0.0, full])
	if is_instance_valid(grave):
		grave.take_damage(99999.0)
	await get_tree().process_frame
	check("a broken gravestone leaves its cell", board.object_at(2, 6) == null)
	check("and the cell is plantable again",
			board.placement_refusal(&"plant", &"peashooter", 2, 6) == "")
	board.dig_up(shooter.row, shooter.col)

	# A gravestone that pays out sun when broken.
	var paying = board.place_object(&"gravestoneSunOnDestruction", 4, 5)
	var suns_before := _sun_tokens(board)
	paying.take_damage(99999.0)
	await get_tree().process_frame
	check("a sun gravestone drops sun", _sun_tokens(board) > suns_before)

	# A zombie frozen in ice holds still until the block is broken.
	var frozen := board.spawn_zombie_at(&"iceage_imp", 3, board.grid_to_world(3, 5).x)
	frozen.col = 5
	check("the zombie is encased", board.encase_in_block(frozen, &"zombietarget_iceblock"))
	var held_x := frozen.position.x
	await _wait_game_seconds(2.0)
	check_eq("an encased zombie does not walk", frozen.position.x, held_x)
	board.object_at(3, 5).take_damage(99999.0)
	await _wait_game_seconds(2.0)
	check("breaking the block frees it",
			not frozen.is_encased() and frozen.position.x < held_x)

	# A frozen plant does nothing, and is neither food nor a pea target.
	var iced := board.place_preset_plant(&"peashooter", 0, 1)
	board.encase_in_block(iced, &"planttarget_iceblock")
	check("a plant can be encased", iced.is_encased())
	check("its block is not a target for plants",
			not board.plant_targets_in_row(0).has(board.object_at(0, 1)))

	# Saving keeps the items, their health and who is frozen.
	var snap := board.snapshot()
	board.apply_snapshot(snap)
	await get_tree().process_frame
	check("objects survive a save", board.object_at(1, 4) != null)
	check("an encased plant stays encased",
			board.plant_at(0, 1) != null and board.plant_at(0, 1).is_encased())
	board.queue_free()
	end_section()



## Starts a bare level on a fresh board, with waves held off so the test
## drives everything itself.
func _start_feature_level(extra: Dictionary) -> Array:
	var board := _make_board()
	var runner := LevelRunner.new()
	runner.first_wave_delay = 9999.0
	add_child(runner)
	var level := {"id": "feature_test", "stage": "",
			"seedbank": {"mode": "chooser", "preset": ["peashooter"]}, "waves": []}
	level.merge(extra, true)
	runner.start(level, board)
	return [board, runner]


func _finish_feature_level(pair: Array) -> void:
	pair[1].queue_free()
	pair[0].queue_free()


## Tides, rail carts and power tiles, as a level sets them up.
func _test_level_features() -> void:
	section("level features")

	# The tide floods from the right. A plant the water reaches drowns unless
	# it can stand in water; when the tide goes out the ground is dry again.
	var pair := _start_feature_level({"tide": {"water_from": 7}})
	var board: Board = pair[0]
	var runner: LevelRunner = pair[1]
	check_eq("the tide floods its columns", board.terrain_at(2, 7), &"water")
	check_eq("and leaves the rest dry", board.terrain_at(2, 6), &"")
	check("a land plant cannot go in the water",
			board.placement_refusal(&"plant", &"peashooter", 2, 8) != "")
	var dry := board.place_plant(&"peashooter", 1, 5)
	var pad := board.place_plant(&"lilypad", 3, 5)
	runner._run_action({"kind": "tide", "water_from": 4})
	await get_tree().process_frame
	check("a rising tide drowns a land plant", not is_instance_valid(dry) or dry.is_dead)
	check("but not an aquatic one", is_instance_valid(pad) and not pad.is_dead)
	runner._run_action({"kind": "tide", "water_from": 9})
	check_eq("a falling tide dries the lawn", board.terrain_at(2, 7), &"")
	_finish_feature_level(pair)

	# Rails: plants only go on carts, and carts roll along their rail.
	pair = _start_feature_level({"railcarts": {
		"rails": [{"col": 4, "row_start": 0, "row_end": 4}],
		"carts": [{"col": 4, "row": 1}, {"col": 4, "row": 4}]}})
	board = pair[0]
	check("rail is laid", board.is_rail(2, 4))
	check("a cart stands on it", board.railcart_at(1, 4) != null)
	check("bare rail cannot be planted",
			board.placement_refusal(&"plant", &"peashooter", 2, 4) != "")
	check("a cart can", board.placement_refusal(&"plant", &"peashooter", 1, 4) == "")
	var rider := board.place_plant(&"peashooter", 1, 4)
	check("a cart rolls along its rail", board.move_railcart(1, 4, 3))
	check("and takes its plant with it", board.plant_at(3, 4) == rider and rider.row == 3)
	check("the cell it left is bare rail again", board.railcart_at(1, 4) == null)
	check("carts cannot pass each other", not board.move_railcart(3, 4, 4))
	check("or leave the rail", not board.move_railcart(3, 4, 5))
	# The same moves from the mouse: pick the cart up, then put it down.
	check("clicking a cart picks it up", board._handle_cart_click(3, 4))
	board._handle_cart_click(0, 4)
	check("clicking its rail sets it down there", board.plant_at(0, 4) == rider)
	var snap := board.snapshot()
	board.apply_snapshot(snap)
	check("rails survive a save", board.is_rail(2, 4) and board.railcart_at(0, 4) != null)
	_finish_feature_level(pair)

	# Power tiles: plant food on one reaches the others of its group.
	pair = _start_feature_level({"power_tiles": [
		{"group": "alpha", "row": 0, "col": 2, "delay": 0.2},
		{"group": "alpha", "row": 4, "col": 6, "delay": 0.2},
		{"group": "beta", "row": 2, "col": 2, "delay": 0.2}]})
	board = pair[0]
	check_eq("tiles know their group", board.power_tile_group(4, 6), "alpha")
	board.place_plant(&"sunflower", 0, 2)
	board.place_plant(&"sunflower", 4, 6)
	board.place_plant(&"sunflower", 2, 2)
	board.add_plant_food(1)
	var before := _sun_tokens(board)
	board.feed_plant(0, 2)
	var fed_one := _sun_tokens(board) - before
	await _wait_game_seconds(1.0)
	var fed_all := _sun_tokens(board) - before
	check("feeding one powered plant feeds its group", fed_all >= fed_one * 2,
			"%d suns from one, %d in all" % [fed_one, fed_all])
	check("but not another group", fed_all < fed_one * 3)
	_finish_feature_level(pair)
	end_section()


func _zombies_on(board: Board) -> Array:
	var out: Array = []
	for r in board.rows:
		out.append_array(board.hostile_zombies_in_row(r))
	return out


## Storms, raiding parties, low tide, frost wind, portals and dinosaurs.
func _test_wave_events() -> void:
	section("wave events")
	var pair := _start_feature_level({})
	var board: Board = pair[0]
	var runner: LevelRunner = pair[1]

	runner._run_action({"kind": "storm", "zombies": ["tutorial", "tutorial"],
		"col_start": 5, "col_end": 7, "row_start": 0, "row_end": 4,
		"group_size": 1, "group_interval": 0.2})
	check_eq("a storm holds its zombies back at first", _zombies_on(board).size(), 0)
	await _wait_game_seconds(0.6)
	var stormed := _zombies_on(board)
	check_eq("then blows them in", stormed.size(), 2)
	check("already partway up the lawn",
			stormed.all(func(z): return z.col >= 4 and z.col <= 7))
	check("spread over the quietest lanes", stormed.size() == 2 and stormed[0].row != stormed[1].row)
	for z in stormed:
		z.queue_free()
	await get_tree().process_frame

	runner._run_action({"kind": "raiding_party", "type": "tutorial", "count": 3,
		"group_size": 2, "group_interval": 0.1})
	runner._run_action({"kind": "low_tide", "type": "tutorial", "count": 2,
		"group_size": 2, "group_interval": 0.1, "delay": 0.1,
		"col_start": 4, "col_end": 6})
	await _wait_game_seconds(0.8)
	check_eq("a raiding party and a low tide bring their zombies",
			_zombies_on(board).size(), 5)
	check("waiting events keep the level going", runner.features.pending() == 0)
	for z in _zombies_on(board):
		z.queue_free()
	await get_tree().process_frame

	# Frost wind: one blast chills, the second freezes.
	var plant := board.place_plant(&"peashooter", 2, 3)
	runner._run_action({"kind": "frost_wind", "winds": [{"row": 2, "direction": "right"}]})
	await _wait_game_seconds(2.0)
	check("one gust chills a plant", board.chill_at(2, 3) > 0.0 and not plant.is_encased())
	runner._run_action({"kind": "frost_wind", "winds": [{"row": 2, "direction": "left"}]})
	await _wait_game_seconds(2.0)
	check("a second freezes it solid", plant.is_encased())

	# A portal lets its zombies through one at a time, then closes.
	var spare := board.place_plant(&"peashooter", 1, 6)
	runner._run_action({"kind": "portal", "row": 1, "col": 6, "portal": {
		"first": {"min": 0.1, "max": 0.1}, "interval": {"min": 0.2, "max": 0.2},
		"zombies": [{"type": "tutorial", "weight": 1}, {"type": "tutorial_armor1", "weight": 1}]}})
	check("a portal opens on its cell", board.object_at(1, 6) != null)
	check("pushing out the plant there", board.plant_at(1, 6) == null)
	check("an open portal holds the level open", runner.features.pending() > 0)
	await _wait_game_seconds(2.0)
	var arrivals := board.hostile_zombies_in_row(1)
	check_eq("each of its zombies comes through once", arrivals.size(), 2)
	check("and the portal closes", board.object_at(1, 6) == null)
	runner._run_action({"kind": "portal", "row": 3, "col": 7, "portal": "egypt"})
	var shared := board.object_at(3, 7)
	check("a shared portal type is found by name",
			shared != null and shared.component(&"portal").remaining() > 0)
	for z in _zombies_on(board):
		z.queue_free()
	if shared != null:
		shared.die()
	await get_tree().process_frame

	# Dinosaurs throw zombies toward the house.
	var kicked := board.spawn_zombie_at(&"tutorial", 0, board.grid_to_world(0, 7).x)
	var start_x := kicked.position.x
	var raptor := board.spawn_dino(&"raptor", 0)
	check("a raptor is called in", raptor is Dino)
	# It walks on from off-screen, where zombies come from too.
	await _wait_game_seconds(5.5)
	check("it kicks a zombie forward", kicked.position.x < start_x - board.cell_size.x * 2.0,
			"%.0f -> %.0f" % [start_x, kicked.position.x])

	var carried := board.spawn_zombie_at(&"tutorial", 4, board.grid_to_world(4, 7).x)
	board.spawn_dino(&"ptero", 4)
	await _wait_game_seconds(5.5)
	check("a pterodactyl carries one to the front", carried.col <= 1, "col %d" % carried.col)

	var flung := board.spawn_zombie_at(&"tutorial", 2, board.grid_to_world(2, 7).x)
	board.spawn_dino(&"ankylo", 2)
	await _wait_game_seconds(3.0)
	check("an ankylosaurus flings one forward", flung.col <= 3, "col %d" % flung.col)

	var tossed := board.spawn_zombie_at(&"tutorial", 3, board.grid_to_world(3, 7).x)
	board.spawn_dino(&"stego", 3)
	await _wait_game_seconds(3.0)
	check("a stegosaurus tosses one up the lawn", tossed.col <= 4 and not tossed.is_encased(),
			"col %d" % tossed.col)

	runner._run_action({"kind": "dino", "dino": "tyranno", "row": 1, "delay": 0.2})
	await _wait_game_seconds(0.5)
	check("a dino wave can arrive late", board.find_children("*", "Dino", true, false).any(
			func(d): return d.behaviour == &"roar"))
	_finish_feature_level(pair)
	end_section()


## Puddles and potions, which act on the zombies that walk into them.
func _test_working_tiles() -> void:
	section("working tiles")
	var board := _make_board()

	var jelly := board.place_object(&"goopuddle_eternal", 1, 5)
	check("a goo puddle has a behaviour", jelly.component(&"tile_liquid") != null)
	var z := board.spawn_zombie_at(&"tutorial", 1, board.grid_to_world(1, 5).x)
	z.movement_claimed = true
	var full := z.health
	await _wait_game_seconds(1.5)
	check("it hurts a zombie standing in it", z.health < full)
	z.queue_free()

	board.place_object(&"butter", 2, 5)
	var buttered := board.spawn_zombie_at(&"tutorial", 2, board.grid_to_world(2, 5).x)
	await get_tree().process_frame
	await get_tree().process_frame
	check("butter stops a zombie", buttered.is_stunned())
	check("and is used up", board.object_at(2, 5) == null)
	buttered.queue_free()

	var potion := board.place_object(&"zombiepotion_speed", 3, 5)
	check("a potion is an object", potion != null and potion.category() == ObjectDef.Category.POTION)
	var drinker := board.spawn_zombie_at(&"tutorial", 3, board.grid_to_world(3, 5).x)
	var pace := drinker.speed
	await get_tree().process_frame
	await get_tree().process_frame
	check("a zombie drinks a potion it walks into", board.object_at(3, 5) == null)
	check("a speed potion speeds it up", drinker.speed > pace)
	board.place_object(&"zombiepotion_toughness", 4, 5)
	var brute := board.spawn_zombie_at(&"tutorial", 4, board.grid_to_world(4, 5).x)
	var hp := brute.max_health
	await get_tree().process_frame
	await get_tree().process_frame
	check("a toughness potion toughens it", brute.max_health > hp and board.object_at(4, 5) == null)

	# A level with potions sets some out and tops them up over time.
	board.queue_free()
	var pair := _start_feature_level({"potions": {"initial": 3, "max": 4,
			"interval": {"min": 0.2, "max": 0.2}, "types": ["zombiepotion_speed"]}})
	check_eq("a potion level starts with its potions", pair[1].features._potion_count(), 3)
	await _wait_game_seconds(1.0)
	check_eq("and refills them up to its cap", pair[1].features._potion_count(), 4)
	_finish_feature_level(pair)
	end_section()


## Star challenges, converted to objectives.
func _test_star_challenges() -> void:
	section("star challenges")
	for t in [&"zombie_distance", &"sun_used", &"simultaneous_plants", &"kill_in_time",
			&"sun_holdout", &"save_mowers", &"no_plant_zone"]:
		check("objective '%s' exists" % t, Components.has_objective(t))

	var pair := _start_feature_level({"objectives": [
		{"type": "survive_waves"},
		{"type": "zombie_distance", "distance": 4},
		{"type": "sun_used", "max": 150},
		{"type": "simultaneous_plants", "max": 2},
		{"type": "no_plant_zone", "cells": [{"row": 0, "col": 0}, {"row": 1, "col": 0}]},
		{"type": "save_mowers"},
		{"type": "kill_in_time", "count": 2, "seconds": 5},
		{"type": "sun_holdout", "seconds": 1}]})
	var board: Board = pair[0]
	var runner: LevelRunner = pair[1]
	var by := {}
	for o in runner.objectives:
		by[o.name] = o
	check_eq("every challenge becomes an objective", runner.objectives.size(), 8)

	check("mold makes its cells unplantable",
			board.placement_refusal(&"plant", &"peashooter", 0, 0) != "")
	board.place_plant(&"peashooter", 2, 2)
	board.place_plant(&"peashooter", 3, 2)
	check("a plant cap refuses one plant too many",
			board.placement_refusal(&"plant", &"peashooter", 4, 2) != "")

	await _wait_game_seconds(1.2)
	check("holding out without spending sun is met", by["sun_holdout"].is_met())
	board.add_sun(500)
	board.spend_sun(100)
	check("spending within the limit is fine", not by["sun_used"].is_failed())
	board.spend_sun(100)
	check("spending past it fails", by["sun_used"].is_failed())

	for i in 2:
		board.spawn_zombie_at(&"tutorial", i, board.grid_to_world(i, 8).x).die()
	check("quick kills meet the kill challenge", by["kill_in_time"].is_met())

	var walker := board.spawn_zombie_at(&"tutorial", 4, board.grid_to_world(4, 4).x)
	await get_tree().process_frame
	check("a zombie short of the flowers is fine", not by["zombie_distance"].is_failed())
	board.move_zombie(walker, 4, board.grid_to_world(4, 2).x)
	await get_tree().process_frame
	check("one past them fails", by["zombie_distance"].is_failed())

	board.mower_triggered.emit(0)
	check("losing a mower fails save-the-mowers", by["save_mowers"].is_failed())
	_finish_feature_level(pair)

	# A kill challenge never met is failed once the level is otherwise won.
	pair = _start_feature_level({"objectives": [{"type": "survive_waves"},
			{"type": "kill_in_time", "count": 5, "seconds": 1}]})
	runner = pair[1]
	runner.first_wave_delay = 0.0
	runner._timer = 0.0
	await _wait_game_seconds(0.5)
	check("an unmet challenge fails at the end", runner.objectives[1].is_failed())
	_finish_feature_level(pair)
	end_section()

func _sun_tokens(board: Board) -> int:
	var n := 0
	for child in board.find_children("*", "SunToken", true, false):
		if not child.is_queued_for_deletion():
			n += 1
	return n


## A level's own start-up content: pre-placed plants, items and zombies, the
## plants a protect-the-plant goal guards, gravestones, and a gravestone wave.
func _test_level_set_up() -> void:
	section("level set-up")
	var board := _make_board()
	var runner := LevelRunner.new()
	runner.first_wave_delay = 0.5
	add_child(runner)
	var level := {
		"id": "set_up_test", "stage": "EgyptStage",
		"seedbank": {"mode": "chooser", "preset": ["peashooter"]},
		"initial": {
			"grid_items": [{"type": "slider_up", "row": 4, "col": 2}],
			"plants": [
				{"type": "wallnut", "row": 1, "col": 3},
				{"type": "peashooter", "row": 0, "col": 0, "condition": "icecubed"},
			],
			"zombies": [{"type": "iceage_imp", "row": 3, "col": 6,
					"condition": "icecubed"}],
		},
		"objectives": [{"type": "survive_waves"},
				{"type": "protect_plants", "must_protect": 1,
				"plants": [{"type": "sunflower", "row": 2, "col": 0}]}],
		"gravestones": {"count": 3, "col_start": 4, "col_end": 7,
				"forced": [{"row": 0, "col": 8}]},
		"waves": [{"kind": "gravestones",
				"pool": [{"type": "gravestone_dark", "count": 2}],
				"positions": [{"row": 1, "col": 3}, {"row": 4, "col": 8}]}],
	}
	runner.start(level, board)

	check("a slider tile is laid", board.object_at(4, 2) != null)
	check("a plant starts on the lawn", board.plant_at(1, 3) != null)
	check("a frozen plant starts in ice",
			board.plant_at(0, 0) != null and board.plant_at(0, 0).is_encased())
	check("a frozen zombie starts in ice", board.object_at(3, 6) != null
			and board.zombie_count() == 1)
	check("the protected plant is planted for its objective",
			board.plant_at(2, 0) != null)
	var forced = board.object_at(0, 8)
	check("a forced gravestone uses the world's own kind",
			forced is Grave and forced.entity_id() == &"gravestone_egypt")
	var scattered := 0
	for r in board.rows:
		for c in range(4, 8):
			var o = board.object_at(r, c)
			if o is Grave and String(o.entity_id()).begins_with("gravestone"):
				scattered += 1
	check_eq("the counted gravestones land in their columns", scattered, 3)

	await _wait_game_seconds(1.5)
	check("a gravestone wave knocks out the plant in its way",
			board.object_at(1, 3) is Grave and board.plant_at(1, 3) == null)
	check("and raises the rest", board.object_at(4, 8) is Grave)
	runner.queue_free()
	board.queue_free()
	end_section()


func _test_seed_chooser() -> void:
	section("seed chooser")
	# These checks are about the chooser's rules, not about which plants the
	# player has won; `_test_rewards` covers that.
	Settings.set_value(&"unlock_all_plants", true)
	var board := _make_board()

	# Plain chooser: every plant on the default list, base slot count.
	var plain := {"seedbank": {"mode": "chooser", "selection": "chooser"}}
	check("a chooser level asks for a pick", SeedChooserRules.level_uses_chooser(plain))
	check("a preset level does not", not SeedChooserRules.level_uses_chooser(
			{"seedbank": {"mode": "chooser", "selection": "preset", "preset": ["peashooter"]}}))
	var rules := SeedChooserRules.from_level(plain, board)
	check_eq("the default list leads with Sunflower", rules.candidates[0], &"sunflower")
	check_eq("six slots by default", rules.slots, 6)
	check("sun producers are allowed by default", rules.can_pick(&"sunflower"))
	check("water-only plants need water", not rules.can_pick(&"tanglekelp"))
	check("amphibious ones do not", rules.can_pick(&"guacodile"))
	check("pack plants are offered too", rules.candidates.has(&"splitpea_mk2"),
			"example_pack's plant")

	# Bans, the sun producer rule, locked presets and the slot override.
	var strict := {"seedbank": {"mode": "chooser", "selection": "chooser",
			"preset": ["wallnut"], "blacklist": ["peashooter"], "slots": 3}}
	rules = SeedChooserRules.from_level(strict, board)
	check("a blacklisted plant is refused", not rules.can_pick(&"peashooter"))
	check("any blacklist bans sun producers", not rules.can_pick(&"twinsunflower"))
	check("other plants still go", rules.can_pick(&"cabbagepult"))
	check_eq("the preset plant is locked in", rules.locked, [&"wallnut"] as Array[StringName])
	check_eq("the level's slot override", rules.slots, 3)
	check("a short hand cannot start", not rules.can_start([&"wallnut"]))
	check("a full hand can", rules.can_start([&"wallnut", &"cabbagepult", &"bonkchoy"]))

	# An include list narrows the offer and caps the slots.
	var narrow := {"seedbank": {"mode": "chooser", "selection": "chooser",
			"include": ["peashooter", "sunflower", "lilypad"],
			"exclude_sun_producers": "true"}}
	rules = SeedChooserRules.from_level(narrow, board)
	check_eq("only the included plants", rules.candidates.size(), 3)
	check_eq("slots shrink to what can be picked", rules.slots, 1)
	board.set_terrain(2, 4, &"water")
	rules = SeedChooserRules.from_level(narrow, board)
	check("water on the lawn lets aquatic plants in", rules.can_pick(&"lilypad"))
	board.set_terrain(2, 4, &"")

	# A challenging deck may start with fewer plants than there are slots.
	var decked := {"seedbank": {"mode": "chooser", "selection": "chooser",
			"decks": {"challenging": [{"name": "Two", "plants": ["peashooter", "wallnut"]}],
					"challenging_locked": true,
					"recommended": [{"name": "Hidden", "plants": ["sunflower"]}]}}}
	rules = SeedChooserRules.from_level(decked, board)
	check_eq("a locked challenge hides the recommended decks", rules.decks.size(), 1)
	check("the deck's exact hand can start", rules.can_start([&"wallnut", &"peashooter"]))
	check_eq("a deck fills the hand", rules.deck_picks(rules.decks[0]),
			[&"peashooter", &"wallnut"] as Array[StringName])

	# The Imitater copies the plant before it, unless that plant is a mint.
	rules = SeedChooserRules.from_level(plain, board)
	check("the Imitater can copy a Peashooter", rules.can_imitate(&"peashooter"))
	check("but not a mint", not rules.can_imitate(&"wintermint"))
	check("and needs something to copy", not rules.can_imitate(&""))
	check_eq("an Imitater becomes a second packet of what it copies",
			rules.seeds_for([&"peashooter", &"imitater", &"wallnut"]),
			[&"peashooter", &"peashooter", &"wallnut"] as Array[StringName])
	check_eq("a deck keeps its Imitater in place",
			rules.deck_picks({"plants": ["sunflower", "imitater", "wallnut"]}),
			[&"sunflower", &"imitater", &"wallnut"] as Array[StringName])
	board.queue_free()

	# In the game: the level waits for the chooser, then plays the picks.
	Saves.clear_save(&"chooser_demo")
	var main = load("res://game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.load_level(&"chooser_demo")
	var chooser: SeedChooser = main._chooser
	check("the chooser opens", chooser != null and chooser.visible)
	if chooser == null:
		main.queue_free()
		Settings.set_value(&"unlock_all_plants", false)
		end_section()
		return
	check("the level holds until the player is ready", not main.runner.running)
	check("the lawn is still while choosing",
			main.board.process_mode == Node.PROCESS_MODE_DISABLED)
	check_eq("the preset plant starts in the hand", chooser.chosen[0], &"wallnut")
	check("the locked plant cannot be put back", not chooser.unpick(&"wallnut"))
	check("a banned plant cannot be picked", not chooser.pick(&"cherry_bomb"))
	check("nor can a sun producer", not chooser.pick(&"sunflower"))
	chooser.clear_hand()
	check("Let's Rock waits for a full hand", not chooser.lets_rock())
	for id in [&"peashooter", &"cabbagepult", &"potatomine"]:
		chooser.pick(id)
	check("a fifth plant does not fit", not chooser.pick(&"bonkchoy"))
	check("Let's Rock with a full hand", chooser.lets_rock())
	check("the level is under way", main.runner.running)
	check("the lawn moves again", main.board.process_mode == Node.PROCESS_MODE_INHERIT)
	var bank_ids: Array = []
	for slot in main.seed_bank.size():
		bank_ids.append(main.seed_bank.packet(slot).id)
	check_eq("the bank holds the picks in order", bank_ids,
			[&"wallnut", &"peashooter", &"cabbagepult", &"potatomine"])
	check_eq("the picks are remembered", Saves.last_seed_choice(),
			["wallnut", "peashooter", "cabbagepult", "potatomine"])

	# An Imitater goes after a plant, and leaves with it.
	chooser.open(SeedChooserRules.from_level(plain, main.board))
	check("an Imitater cannot lead the hand", not chooser.pick(&"imitater"))
	chooser.pick(&"peashooter")
	check("an Imitater can follow a plant", chooser.pick(&"imitater"))
	check("removing the plant takes its Imitater too",
			chooser.unpick(&"peashooter") and not chooser.chosen.has(&"imitater"))
	main.load_level(&"chooser_demo")
	chooser.clear_hand()
	for id in [&"peashooter", &"imitater", &"cabbagepult"]:
		chooser.pick(id)
	check("Let's Rock with an Imitater", chooser.lets_rock())
	var imitated: Array = []
	for slot in main.seed_bank.size():
		imitated.append(main.seed_bank.packet(slot).id)
	check_eq("the Imitater's slot is a second Peashooter", imitated,
			[&"wallnut", &"peashooter", &"peashooter", &"cabbagepult"])
	main.seed_bank.spend(2)
	var saved: Array = main.seed_bank.snapshot()
	main.seed_bank.setup([{"kind": &"plant", "id": &"wallnut"},
			{"kind": &"plant", "id": &"peashooter"},
			{"kind": &"plant", "id": &"peashooter"},
			{"kind": &"plant", "id": &"cabbagepult"}])
	main.seed_bank.apply_snapshot(saved)
	check("a resumed copy keeps its own recharge",
			main.seed_bank.is_recharged(1) != main.seed_bank.is_recharged(2)
			or main.seed_bank.packet(2).charge < main.seed_bank.packet(1).charge)
	Saves.clear_save(&"chooser_demo")
	main.load_level(&"chooser_demo")
	chooser.clear_hand()
	for id in [&"peashooter", &"cabbagepult", &"potatomine"]:
		chooser.pick(id)
	chooser.lets_rock()

	# Resuming keeps the hand rather than asking again.
	Saves.save_level(main.runner, main.board, main.seed_bank)
	main.load_level(&"chooser_demo")
	check("a resumed level skips the chooser", not chooser.visible and main.runner.running)
	check_eq("and keeps its hand", main.seed_bank.size(), 4)
	Saves.clear_save(&"chooser_demo")

	# A fresh start offers the last picks again.
	main.load_level(&"chooser_demo")
	check_eq("the last hand is offered again", chooser.chosen.size(), 4)
	check("and can start straight away", chooser.can_start())
	Saves.clear_save(&"chooser_demo")
	main.queue_free()
	Settings.set_value(&"unlock_all_plants", false)
	end_section()


func _test_rewards() -> void:
	section("rewards")
	_clear_all_saves()

	# What a level drops: its own prize the first time, a coin bag after.
	var first := LevelReward.for_level(Data.level(&"tutorial_1"), true)
	check_eq("tutorial 1 gives a plant", first.type, &"unlock_plant")
	check_eq("the Sunflower", first.param, &"sunflower")
	check("which gets the award screen", first.is_award())
	var replay := LevelReward.for_level(Data.level(&"tutorial_1"), false)
	check_eq("a replay drops a coin bag", replay.type, LevelReward.COIN_BAG)
	check_eq("of five silver coins", replay.amount, 50)
	check("which pays out on the lawn", not replay.is_award())
	check_eq("tutorial 4 gives a trophy",
			LevelReward.for_level(Data.level(&"tutorial_4"), true).param, &"sauce")
	check_eq("an unmodelled prize falls back to a coin bag",
			LevelReward.from_value({"type": "pinata", "param": "spine_egypt"}).type,
			LevelReward.COIN_BAG)
	check_eq("so does PopCap's none",
			LevelReward.from_value({"type": "none", "param": "none"}).type,
			LevelReward.COIN_BAG)
	check_eq("and a plant that does not exist",
			LevelReward.from_value({"type": "unlock_plant", "param": "nope"}).type,
			LevelReward.COIN_BAG)
	check_eq("a coins prize is a bag of that much",
			LevelReward.from_value({"type": "coins", "amount": 120}).amount, 120)

	# Owning plants.
	check("the base plants start unlocked", Saves.is_plant_unlocked(&"peashooter")
			and Saves.is_plant_unlocked(&"potatomine"))
	check("others have to be won", not Saves.is_plant_unlocked(&"cabbagepult"))
	check("a pack's own plant starts unlocked", Saves.is_plant_unlocked(&"splitpea_mk2"))
	check("unlocking a plant", Saves.unlock_plant(&"cabbagepult")
			and Saves.is_plant_unlocked(&"cabbagepult"))
	check("is only news once", not Saves.unlock_plant(&"cabbagepult"))
	check("it is new until seen", Saves.is_plant_new(&"cabbagepult"))
	Saves.mark_plants_seen([&"cabbagepult"])
	check("then it is not", not Saves.is_plant_new(&"cabbagepult"))
	Settings.set_value(&"unlock_all_plants", true)
	check("the testing switch opens everything", Saves.is_plant_unlocked(&"bonkchoy"))
	Settings.set_value(&"unlock_all_plants", false)

	# The chooser only offers what the player owns.
	var board := _make_board()
	var plain := {"seedbank": {"mode": "chooser", "selection": "chooser"}}
	var rules := SeedChooserRules.from_level(plain, board)
	check("a won plant is offered", rules.can_pick(&"cabbagepult"))
	check("an unwon one is not", not rules.candidates.has(&"bonkchoy"))
	var listed := {"seedbank": {"mode": "chooser", "selection": "chooser",
			"include": ["peashooter", "bonkchoy"]}}
	rules = SeedChooserRules.from_level(listed, board)
	check("an include list still shows it", rules.candidates.has(&"bonkchoy"))
	check_eq("refused", rules.refusal(&"bonkchoy"), "not unlocked yet")
	listed["seedbank"]["unlock_all"] = true
	rules = SeedChooserRules.from_level(listed, board)
	check("unless the level unlocks all", rules.can_pick(&"bonkchoy"))
	var preset := {"seedbank": {"mode": "chooser", "selection": "chooser",
			"preset": ["bonkchoy"]}}
	rules = SeedChooserRules.from_level(preset, board)
	check("a level's preset plant goes in regardless", rules.can_pick(&"bonkchoy"))
	board.queue_free()

	# In the game: the prize drops, is granted at once, and is shown off.
	var demo: Dictionary = Data.level(&"tutorial_1").duplicate(true)
	demo["id"] = "reward_demo"
	demo["reward"] = {"type": "unlock_plant", "param": "bonkchoy"}
	demo["unlocks_features"] = ["almanac"]
	Data.levels[&"reward_demo"] = demo
	var main = load("res://game/main.tscn").instantiate()
	main.level_transition_delay = 0.05
	add_child(main)
	await get_tree().process_frame
	main.load_level(&"reward_demo")
	await get_tree().process_frame
	main._on_won()
	var drop: RewardDrop = main._reward_drop
	check("a won level drops its prize", drop != null and is_instance_valid(drop))
	check("granted as it drops", Saves.is_plant_unlocked(&"bonkchoy"))
	check("the level's features open", Saves.has_feature(&"almanac"))
	check("and the level is cleared", Saves.is_cleared(&"reward_demo"))
	check("the prize leaps to the lawn", drop != null and drop.is_leaping())
	await _wait_game_seconds(drop.leap_time + 0.2 if drop != null else 0.1)
	check("and waits there", is_instance_valid(drop) and not drop.is_collected())
	check("the level holds until it is picked up",
			main._current_level == &"reward_demo" and not main._award.visible)
	if is_instance_valid(drop):
		drop.collect()
	await _wait_game_seconds(drop.present_time + 0.3)
	check("a new plant gets the award screen", main._award.visible)
	check_eq("saying so", main._award._title.text, "You got a new plant!")
	main._award._on_continue()
	check("continuing dismisses it", not main._award.visible)

	# Winning again pays a coin bag into the wallet.
	var before := Saves.currency(&"coins")
	main.load_level(&"reward_demo")
	await get_tree().process_frame
	main._on_won()
	drop = main._reward_drop
	check_eq("a replay drops a coin bag", drop.reward.type, LevelReward.COIN_BAG)
	check("the coin counter shows", main._coin_counter.visible)
	drop.collect()
	await _wait_game_seconds(3.0)
	check_eq("its coins are banked", Saves.currency(&"coins") - before, 50)
	check("without an award screen", not main._award.visible)
	main.queue_free()
	Data.levels.erase(&"reward_demo")
	_clear_all_saves()
	end_section()


## Picks up a won level's prize and clicks past its award screen, the way a
## player ends a level.
func _collect_reward(main) -> void:
	await get_tree().process_frame
	var drop: RewardDrop = main._reward_drop
	if drop == null or not is_instance_valid(drop):
		return
	drop.collect()
	await _wait_game_seconds(drop.present_time + 0.3)
	if main._award.visible:
		main._award._on_continue()


func _make_board() -> Board:
	var b := Board.new()
	add_child(b)
	return b


## Waits for `seconds` of in-game time, which passes TIME_SCALE times faster.
func _wait_game_seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame


func _report() -> void:
	# A section that began and never ended means its function died partway.
	for name in _sections_started:
		if not _sections_finished.has(name):
			_failures.append("section '%s' did not run to completion "
					% name + "(a runtime error aborted it)")
			_checks += 1

	print("\n" + "=".repeat(52))
	if _failures.is_empty():
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d of %d CHECKS FAILED:" % [_failures.size(), _checks])
		for f in _failures:
			print("   - %s" % f)
	print("=".repeat(52))
	get_tree().quit(0 if _failures.is_empty() else 1)
