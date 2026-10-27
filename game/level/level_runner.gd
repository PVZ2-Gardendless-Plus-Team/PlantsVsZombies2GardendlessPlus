class_name LevelRunner
extends Node
## Plays a level from its native definition.
##
## Reads the clean level schema produced by tools/import_levels.py: a `waves`
## list where each entry is either a spawn action or a `multi` bundle of
## actions. Wave pacing follows `wave_settings`, and the level is won once the
## last wave is cleared.
##
## Before the first wave the lawn is set up from the level: `initial` plants,
## grid items and zombies, the plants a protect-the-plant objective guards,
## and `gravestones`. Cells there are 0-based, as PopCap's GridX/GridY are.

signal wave_started(index: int, total: int)
signal level_complete
## An objective was broken. Distinct from the board's own loss, so a HUD can
## say which rule failed.
signal level_failed(objective: Objective)
signal objectives_changed(objectives: Array)
## Emits the seed bank contents as an Array of {kind, id} dictionaries.
signal seedbank_ready(seeds: Array)

@export_group("Pacing")
## Seconds before the first wave arrives.
@export var first_wave_delay: float = 12.0
## Seconds between waves when the player has not cleared the board.
@export var wave_gap: float = 18.0
## A wave also starts early once the board has been cleared down to this share
## of the wave's original health, matching PvZ2's "next wave health" pacing.
@export_range(0.0, 1.0) var clear_fraction: float = 0.45

## PvZ2's music escalates through four stages across a level.
const MUSIC_STAGES := 4
## The Studio parameter the lawn music follows: 0 is Choose Your Seeds, 1-3
## are the first three phases, and anything past them is the final phase.
## It is a preset parameter, local to each music event, not a global one.
const MUSIC_PARAMETER := &"state"

@export_group("Spawning")
## Cells of guaranteed separation between zombies entering the same lane.
## Without this a wave's zombies stack on the spawn line exactly.
@export var spawn_spacing: float = 0.7
## Extra random spread added on top of the spacing, in cells. Accumulated
## rather than applied independently, so jitter can only widen a gap - never
## narrow one below `spawn_spacing`.
@export var spawn_jitter: float = 0.5

@export_group("Grid items")
## Used when a level asks for gravestones but neither it nor its world names
## which kind.
@export var fallback_gravestone: StringName = &"gravestone"
## What a level's "icecubed" zombies and plants are frozen inside.
@export var zombie_ice_block: StringName = &"zombietarget_iceblock"
@export var plant_ice_block: StringName = &"planttarget_iceblock"

@export_group("Sun")
## Seconds between sun falling from the sky.
@export var sun_interval: float = 10.0
## Used instead when the level lists the FastSunDropper feature, which the
## early tutorial levels rely on to keep the player supplied.
@export var fast_sun_interval: float = 5.0

var board: Board
var level: Dictionary = {}
## Set by the host scene so conveyor wave actions can reach the belt.
var seed_bank: SeedBank = null

var waves: Array = []
var wave_index: int = -1
var running: bool = false

var _timer: float = 0.0
var _wave_spawned_health: float = 0.0
var _finished_spawning: bool = false
var _sun_timer: float = 0.0
## Last value pushed to the music `stage` parameter, so it is only set on change.
var _music_stage: int = -1

## The level's win/lose rules. Every one must be met to win; any failure loses.
var objectives: Array[Objective] = []
## Tides, rails, power tiles, potions and the special wave events.
var features: LevelFeatures = null


func start(level_def: Dictionary, target_board: Board) -> void:
	level = level_def
	board = target_board
	waves = level.get("waves", [])
	wave_index = -1
	# A level that has the player pick seeds waits for them: no waves, no sun
	# and no objective ticking until `begin()`.
	running = not needs_seed_choice()
	_finished_spawning = false
	_timer = first_wave_delay
	_sun_timer = _sun_cycle()

	# Level rows are 1-based, matching the wave data; the board is 0-based.
	var open_rows: Array[int] = []
	for r in (level.get("plantable_rows", []) as Array):
		open_rows.append(int(r) - 1)
	board.plantable_rows = open_rows

	# Any *Mowers feature gives the lane a mower; which one is cosmetic.
	board.mowers_enabled = has_mowers()
	board.setup_mowers()
	board.setup_lawn(lawn_data(), self)
	board.queue_redraw()

	var pacing: Dictionary = level.get("wave_pacing", {})
	if pacing.has("first_delay"):
		_timer = float(pacing["first_delay"])

	if features == null:
		features = LevelFeatures.new()
		features.name = "Features"
		add_child(features)
		features.zombie_spawned.connect(func(z): _wave_spawned_health += z.max_health)
	# Rails and tide before anything is planted, so plants land on carts and
	# know whether they are standing in water.
	features.start(level, board, lawn_data())

	# Before objectives, so a protect-the-plant goal finds what it guards.
	_place_initial()
	_build_objectives()
	_music_stage = -1
	Audio.play_music(music_event())
	_update_music_stage()
	Audio.play(&"level.ready")
	seedbank_ready.emit(seedbank_seeds())


## Starts a level that was waiting on the seed chooser.
func begin() -> void:
	running = true


## True when the player picks this level's plants before it starts.
func needs_seed_choice() -> bool:
	return SeedChooserRules.level_uses_chooser(level)


## What the player may place, as {kind, id} entries.
##
## Entries are plants unless told otherwise. A level whose seedbank sets
## `"kind": "zombie"` hands the player zombies instead, which is how an
## I-Zombie style level works; individual entries may override it too.
func seedbank_seeds() -> Array:
	var sb: Dictionary = level.get("seedbank", {})
	var default_kind := StringName(sb.get("kind", &"plant"))
	var source: Array = sb.get("plants", []) if String(sb.get("mode", "chooser")) == "conveyor" \
			else sb.get("preset", [])

	var out: Array = []
	for entry in source:
		if entry is String:
			out.append({"kind": default_kind, "id": StringName(entry)})
		elif entry is Dictionary and entry.has("type"):
			out.append({
				"kind": StringName(entry.get("kind", default_kind)),
				"id": StringName(entry["type"]),
			})
	return out


## Whether this level parks lawn mowers. An explicit field, rather than a
## string match against someone else's module names.
func has_mowers() -> bool:
	return bool(level.get("mowers", false))


## How much to scale seed recharge by; 1.0 unless the level shortens it.
func seed_recharge_scale() -> float:
	return float(level.get("seed_recharge", 1.0))


## Narrative and tutorial hooks this level asks for, by name.
func scripts() -> Array:
	return level.get("scripts", [])


## Music for this level.
##
## A level names a stage, the stage's lawn names a music track, and the audio
## catalog maps that track to an event. Adding a world is then data only.
func music_event() -> StringName:
	return music_cue(&"lawn")


## A world's cue of one kind - lawn, lose, victory, leave - falling back to
## Front Lawn's and then to nothing.
##
## Winning and losing are MUSIC in the source game, not sound effects: VIC_,
## LOSE_ and LEAVE_ sit in PVZGE's music enum alongside the stage loops. They
## are routed as music here for the same reason, so a world can score its own
## ending.
func music_cue(kind: StringName) -> StringName:
	var track := music_track().to_lower()
	for id in [StringName("music.%s.%s" % [kind, track]),
			StringName("music.%s.tutorial" % kind)]:
		if Audio.has_event(id):
			return id
	return &""


## This level's stage data.
func lawn_data() -> Dictionary:
	return Data.lawn(StringName(level.get("stage", "")))


## The PVZGE track name for this level's stage, e.g. "Tutorial", "Egypt".
func music_track() -> String:
	var lawn := lawn_data()
	return lawn.get("music", "Tutorial") if not lawn.is_empty() else "Tutorial"


## The level's opening dialogue as {speaker_name, box, lines}, or empty.
## Resolved through the speaker registry, so who talks is data.
func dialogue() -> Dictionary:
	var spec: Dictionary = level.get("dialogue", {})
	if spec.is_empty():
		return {}
	var who := Data.speaker(StringName(spec.get("speaker", &"")))
	return {
		"speaker": who.get("name", String(spec.get("speaker", "?"))),
		"portrait": who.get("portrait", ""),
		"box": who.get("dialogue_box", "standard"),
		"lines": spec.get("lines", []),
	}


## What this world is called. A pack renaming a world sets `display_name` on
## the lawn, which is how Aerial Fortress becomes Assault Airspace without the
## stage id - and every level referencing it - having to change.
func world_name() -> String:
	var lawn := lawn_data()
	var shown: String = lawn.get("display_name", "")
	if shown != "":
		return shown
	# Fall back to the stage id, minus the "Stage" suffix.
	return String(level.get("stage", "")).trim_suffix("Stage")


## PvZ2 escalates its music in four phases as a level progresses. FMOD drives
## that from a parameter rather than by swapping tracks, so the intro/loop
## structure survives the transition.
##
## Zero-based here; `_update_music_stage` turns it into the Studio value,
## which starts at 1 because 0 belongs to the seed chooser. The sound design
## owns that contract, not this code.
func music_stage() -> int:
	if waves.is_empty():
		return 0
	var progress := float(maxi(wave_index, 0)) / float(waves.size())
	return clampi(int(progress * MUSIC_STAGES), 0, MUSIC_STAGES - 1)


func _update_music_stage() -> void:
	var stage := music_stage()
	if stage != _music_stage:
		_music_stage = stage
		Audio.set_parameter(MUSIC_PARAMETER, float(stage + 1))


## Builds the level's objectives. A level that lists none gets the default
## goal - outlast the waves - so existing levels keep working.
func _build_objectives() -> void:
	for o in objectives:
		o.queue_free()
	objectives.clear()
	# Placement rules belong to the objectives that added them.
	board.placement_checks.clear()

	var specs: Array = level.get("objectives", [])
	if specs.is_empty():
		specs = [{"type": "survive_waves"}]
	for spec in specs:
		if not (spec is Dictionary):
			continue
		var obj := Components.create_objective(spec, self, board)
		if obj == null:
			continue
		add_child(obj)
		objectives.append(obj)
		obj.progress_changed.connect(func(_o): objectives_changed.emit(objectives))
		obj.setup()

	_connect_board_events()
	objectives_changed.emit(objectives)


## Forwards board events to the objectives, so they never poll.
func _connect_board_events() -> void:
	for pair in [["zombie_died", "on_zombie_died"],
			["plant_died", "on_plant_died"],
			["sun_collected", "on_sun_collected"],
			["zombie_reached_house", "on_zombie_reached_house"]]:
		var sig: StringName = pair[0]
		var hook: StringName = pair[1]
		var fn := Callable(self, "_fanout").bind(hook)
		if not board.is_connected(sig, fn):
			board.connect(sig, fn)


func _fanout(arg: Variant, hook: StringName) -> void:
	for o in objectives:
		o.call(hook, arg)


## Where the level has got to: wave progress, pacing timers and each
## objective's own state.
func snapshot() -> Dictionary:
	var objective_state: Array = []
	for o in objectives:
		objective_state.append({"type": o.name, "state": o.save_state()})
	return {
		"level_id": String(level.get("id", &"")),
		"wave_index": wave_index,
		"finished_spawning": _finished_spawning,
		"wave_timer": _timer,
		"sun_timer": _sun_timer,
		"wave_spawned_health": _wave_spawned_health,
		"objectives": objective_state,
	}


## Resumes from a snapshot. `start()` must have run first, so the level's
## waves, objectives and seed bank already exist; this moves them forward.
func apply_snapshot(state: Dictionary) -> void:
	wave_index = int(state.get("wave_index", -1))
	_finished_spawning = bool(state.get("finished_spawning", false))
	_timer = float(state.get("wave_timer", first_wave_delay))
	_sun_timer = float(state.get("sun_timer", _sun_cycle()))
	_wave_spawned_health = float(state.get("wave_spawned_health", 0.0))

	# Objectives are matched by type, so a level whose goals changed between
	# save and load restores whichever ones it still has.
	for entry in (state.get("objectives", []) as Array):
		if not (entry is Dictionary):
			continue
		for o in objectives:
			if o.name == String(entry.get("type", "")):
				o.load_state(entry.get("state", {}))
				break

	_music_stage = -1
	_update_music_stage()
	objectives_changed.emit(objectives)


## Progress lines for the HUD, one per objective that reports any.
func objective_lines() -> Array[String]:
	var out: Array[String] = []
	for o in objectives:
		var text := o.describe()
		if text != "":
			out.append(("[x] " if o.is_met() else ("[!] " if o.is_failed() else "")) + text)
	return out


## True when this level's seeds arrive on a conveyor belt rather than from a
## fixed set of chooser slots.
func is_conveyor() -> bool:
	return String((level.get("seedbank", {}) as Dictionary)
			.get("mode", "chooser")) == "conveyor"


## Sun rate for this level, from its own `sun` block.
func _sun_cycle() -> float:
	var sun: Dictionary = level.get("sun", {})
	return float(sun.get("interval", sun_interval))


## True once every wave has been sent and nothing a wave started - a storm
## still blowing in, an open portal - is left to arrive.
func all_waves_spawned() -> bool:
	return _finished_spawning and (features == null or features.pending() == 0)


## Halts the level without clearing the board, so a result can be shown.
func stop() -> void:
	running = false


func _process(delta: float) -> void:
	if not running or board == null:
		return

	_sun_timer -= delta
	if _sun_timer <= 0.0:
		board.drop_sun_from_sky()
		_sun_timer = _sun_cycle()
	features.tick(delta)

	# Objectives own the outcome: all met wins, any broken loses.
	for o in objectives:
		if o.is_failed():
			running = false
			level_failed.emit(o)
			return
	if not objectives.is_empty():
		var all_met := true
		for o in objectives:
			if not o.is_met():
				all_met = false
				break
		if all_met:
			running = false
			level_complete.emit()
			return
	if _finished_spawning:
		return

	_timer -= delta
	if _timer <= 0.0 or _board_mostly_cleared():
		_advance_wave()


## True when enough of the current wave's health has been destroyed that the
## next wave should come early.
func _board_mostly_cleared() -> bool:
	if wave_index < 0 or _wave_spawned_health <= 0.0:
		return false
	return _remaining_health() <= _wave_spawned_health * clear_fraction


func _remaining_health() -> float:
	var total := 0.0
	for r in board.rows:
		for z in board.hostile_zombies_in_row(r):
			total += z.health
	return total


func _advance_wave() -> void:
	wave_index += 1
	if wave_index >= waves.size():
		_finished_spawning = true
		for o in objectives:
			o.on_all_waves_spawned()
		return

	_wave_spawned_health = 0.0
	_run_action(waves[wave_index])
	wave_started.emit(wave_index + 1, waves.size())
	_update_music_stage()
	for o in objectives:
		o.on_wave_started(wave_index + 1, waves.size())
	var settings_flag: int = int((level.get("wave_pacing", {}) as Dictionary)
			.get("flag_interval", 0))
	var is_flag := settings_flag > 0 and (wave_index + 1) % settings_flag == 0
	var cue := wave_sound(wave_index, waves.size(), is_flag)
	if cue != &"":
		Audio.play(cue)

	var pacing: Dictionary = level.get("wave_pacing", {})
	_timer = float(pacing.get("gap", wave_gap))


## The cue a wave starts with, as PVZGE plays them: the awooga as the first
## zombies come, the final-wave sting for the last, a huge wave for a flag.
## Any other wave arrives in silence, so this returns no cue for it.
static func wave_sound(index: int, count: int, is_flag: bool) -> StringName:
	if index == count - 1 and count > 1:
		return &"wave.final"
	if is_flag:
		return &"wave.huge"
	if index == 0:
		return &"wave.first"
	return &""


func _run_action(action: Dictionary) -> void:
	match String(action.get("kind", "")):
		"spawn":
			# Track the last offset used in each lane, so each zombie starts
			# a guaranteed distance behind the one before it.
			var per_lane := {}
			var spawned: Array[Zombie] = []
			for z in (action.get("zombies", []) as Array):
				var made := _spawn_one(z, per_lane)
				if made != null:
					spawned.append(made)
			_assign_plant_food(spawned, int(action.get("plantfood", 0)))
		"conveyor":
			# Mid-level changes to what the belt can deliver.
			if seed_bank is ConveyorSeedBank:
				seed_bank.add_to_pool(action.get("add", []))
				seed_bank.remove_from_pool(action.get("remove", []))
		"multi":
			for sub in (action.get("actions", []) as Array):
				if sub is Dictionary:
					_run_action(sub)
		"gravestones":
			_raise_gravestones(action)
		_:
			# Unmodelled action kinds are skipped rather than fatal, so a level
			# using a feature we have not built yet still plays.
			features.run(action)


# --- lawn set-up ----------------------------------------------------------

## Everything the level has standing on the lawn before the first wave.
func _place_initial() -> void:
	var init: Dictionary = level.get("initial", {})
	# Items first: a lily pad or puddle decides what the plants can stand on.
	for e in (init.get("grid_items", []) as Array):
		if e is Dictionary:
			board.place_object(_cell_type(e), int(e.get("row", 0)), int(e.get("col", 0)))

	var plants: Array = (init.get("plants", []) as Array).duplicate()
	for spec in (level.get("objectives", []) as Array):
		if spec is Dictionary and String(spec.get("type", "")) == "protect_plants":
			plants.append_array(spec.get("plants", []))
	for e in plants:
		if not (e is Dictionary):
			continue
		var p := board.place_preset_plant(_cell_type(e),
				int(e.get("row", 0)), int(e.get("col", 0)))
		if p == null:
			continue
		if String(e.get("condition", "")) == "icecubed":
			board.encase_in_block(p, plant_ice_block)
		elif bool(e.get("plantfood", false)):
			p.apply_plant_food()

	for e in (init.get("zombies", []) as Array):
		if not (e is Dictionary):
			continue
		var row := int(e.get("row", 0))
		var col := int(e.get("col", board.cols - 1))
		var z := board.spawn_zombie_at(_cell_type(e), row, board.grid_to_world(row, col).x)
		if z != null and String(e.get("condition", "")) == "icecubed":
			z.col = col
			board.encase_in_block(z, zombie_ice_block)

	_place_starting_gravestones(level.get("gravestones", {}))


## A placement names its contents as `type`; older conversions used the
## source's own key.
func _cell_type(entry: Dictionary) -> StringName:
	for key in ["type", "typename", "planttype"]:
		if entry.get(key):
			return StringName(entry[key])
	return &""


## Gravestones present from the start: every `forced` cell, plus `count` more
## scattered over the allowed columns and rows.
func _place_starting_gravestones(g: Dictionary) -> void:
	if g.is_empty():
		return
	var types: Array = g.get("types", [])
	for e in (g.get("forced", []) as Array):
		if e is Dictionary:
			var kind := _cell_type(e)
			board.place_object(kind if kind != &"" else _pick_gravestone(types),
					int(e.get("row", 0)), int(e.get("col", 0)))

	var count := int(g.get("count", 0))
	if count <= 0:
		return
	var cells: Array[Vector2i] = []
	for r in range(int(g.get("row_start", 0)), int(g.get("row_end", board.rows - 1)) + 1):
		for c in range(int(g.get("col_start", 0)), int(g.get("col_end", board.cols - 1)) + 1):
			if board.in_bounds(r, c):
				cells.append(Vector2i(c, r))
	cells.shuffle()
	for cell in cells:
		if count <= 0:
			break
		if board.plant_at(cell.y, cell.x) != null:
			continue
		if board.place_object(_pick_gravestone(types), cell.y, cell.x) != null:
			count -= 1


## A wave that raises gravestones mid-level. Each pool entry places `count`
## of its kind into the shuffled candidate positions. Plants standing where a
## stone rises are knocked out of the ground unless `displace_plants` is false,
## in which case those cells are passed over.
func _raise_gravestones(action: Dictionary) -> void:
	var displace := bool(action.get("displace_plants", true))
	var positions: Array = (action.get("positions", []) as Array).duplicate()
	positions.shuffle()
	var next := 0
	for entry in (action.get("pool", []) as Array):
		if not (entry is Dictionary):
			continue
		var kind := StringName(entry["type"]) if entry.get("type") else _pick_gravestone([])
		var left := int(entry.get("count", 1))
		while left > 0 and next < positions.size():
			var pos: Dictionary = positions[next]
			next += 1
			# A position with no column or row is anywhere on the lawn.
			var col := int(pos["col"]) if pos.get("col") != null else randi() % board.cols
			var row := int(pos["row"]) if pos.get("row") != null else randi() % board.rows
			if not board.in_bounds(row, col) or board.object_at(row, col) != null:
				continue
			if board.plant_at(row, col) != null:
				if not displace:
					continue
				board.dig_up(row, col)
			if board.place_object(kind, row, col) != null:
				left -= 1


## One of the given kinds, else one of the world's own gravestones.
func _pick_gravestone(types: Array) -> StringName:
	if not types.is_empty():
		return StringName(types.pick_random())
	var world: Array = lawn_data().get("gravestones", [])
	if not world.is_empty():
		return StringName(world.pick_random())
	return fallback_gravestone


## Marks some of a wave's zombies as carrying plant food, which they drop when
## killed. Only zombies whose data allows it are eligible - the rest are
## skipped rather than forced.
func _assign_plant_food(spawned: Array[Zombie], count: int) -> void:
	if count <= 0:
		return
	var eligible: Array[Zombie] = []
	for z in spawned:
		if z.has_tag(&"plantfood_carrier"):
			eligible.append(z)
	eligible.shuffle()
	for i in mini(count, eligible.size()):
		eligible[i].set_runtime_tag(&"carrying_plantfood", true)


func _spawn_one(entry: Dictionary, per_lane: Dictionary) -> Zombie:
	var id := StringName(entry.get("type", &""))
	if id == &"":
		return null
	# PopCap rows are 1-based; an absent row means "anywhere".
	var row: int = int(entry.get("row", 0)) - 1
	if not entry.has("row"):
		row = randi() % board.rows
	row = clampi(row, 0, board.rows - 1)

	# Offsets accumulate down the lane: each zombie sits at least
	# `spawn_spacing` behind the previous one, plus a random extra.
	var offset: float = randf() * spawn_jitter
	if per_lane.has(row):
		offset = float(per_lane[row]) + spawn_spacing + randf() * spawn_jitter
	per_lane[row] = offset

	var z := board.spawn_zombie(id, row, offset)
	if z != null:
		_wave_spawned_health += z.max_health
	return z


func wave_label() -> String:
	if _finished_spawning:
		return "Final wave"
	return "Wave %d / %d" % [maxi(wave_index + 1, 0), waves.size()]
