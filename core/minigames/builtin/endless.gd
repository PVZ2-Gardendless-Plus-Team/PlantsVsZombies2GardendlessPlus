extends Minigame
## The Endless Zones (PVZGE's Danger Rooms): waves that never run out. The
## zone is played in levels of a few flags each; every level is worth more
## wave points than the last, and the run ends only when the zombies get in.
## The longest run in each zone is kept.
##
## Waves are built the way PVZGE's jittered wave generator does: a budget of
## points per wave, spent on zombies from the zone's pool by their wave_cost,
## with the must-contain zombies always among them and every flag wave worth
## two and a half times as much.
##
## Config (DangerRoomModuleProperties or DangerRoomMiniGameModuleProperties,
## with their level designers folded in): max_flag_wave (flags per level),
## level_designers [{type: jittered_wave_generator, starting_points,
## base_point_increment_per_wave, base_point_increment_per_level,
## must_contain_zombie, zombie_pool}].

const WAVES_PER_FLAG := 5
## Seconds between waves, and before the first one of each level.
const WAVE_GAP := 22.0
const FIRST_WAVE_DELAY := 15.0
## A wave comes early once the lawn is down to this share of its health.
const CLEAR_FRACTION := 0.35

var level_number: int = 1
var wave: int = 0
var _timer: float = FIRST_WAVE_DELAY
var _wave_health: float = 0.0
var _between_levels: bool = false
var _generator: Dictionary = {}


func setup() -> void:
	for d in (cfg(&"level_designers", []) as Array):
		if d is Dictionary and String(d.get("type", "")) == "jittered_wave_generator":
			_generator = d
			break
	if _generator.is_empty():
		push_warning("Endless: no wave generator in %s" % runner.level.get("id", "?"))


func waves_per_level() -> int:
	return maxi(int(cfg(&"max_flag_wave", 2)), 1) * WAVES_PER_FLAG


## The zone's key for its best streak.
func best_key() -> StringName:
	return StringName("endless:%s" % runner.level.get("id", ""))


func tick(delta: float) -> void:
	if not started or _generator.is_empty():
		return
	if _between_levels:
		# The next level starts once the last one's zombies are all gone.
		if board.zombie_count() == 0:
			_between_levels = false
			level_number += 1
			wave = 0
			_timer = FIRST_WAVE_DELAY
			Saves.record_best(best_key(), level_number - 1)
			notify_progress()
		return
	_timer -= delta
	if _timer <= 0.0 or (wave > 0 and _lawn_health() <= _wave_health * CLEAR_FRACTION):
		_send_wave()


func _send_wave() -> void:
	wave += 1
	_timer = WAVE_GAP
	var points := wave_points(level_number, wave)
	_wave_health = 0.0
	for id in pick_zombies(points):
		var z = board.spawn_zombie(id, randi() % board.rows, randf() * 0.8)
		if z != null:
			_wave_health += z.max_health
	if wave % WAVES_PER_FLAG == 0:
		Audio.play(&"wave.huge")
	elif wave == 1:
		Audio.play(&"wave.first")
	if wave >= waves_per_level():
		_between_levels = true
	notify_progress()


## The budget for one wave: the zone's starting points, raised for every
## level and every wave into it, and multiplied on a flag wave.
func wave_points(level: int, index: int) -> float:
	var points := float(_generator.get("starting_points", 100)) \
			+ float(_generator.get("base_point_increment_per_level", 5)) * (level - 1) * waves_per_level() \
			+ float(_generator.get("base_point_increment_per_wave", 30)) * (index - 1)
	if index % WAVES_PER_FLAG == 0:
		points *= 2.5
	return points


## Zombies for a budget: one of each must-contain zombie that fits, then
## random picks from the pool until nothing affordable is left.
func pick_zombies(points: float) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in (_generator.get("must_contain_zombie", []) as Array):
		var cost := _cost(StringName(id))
		if cost <= points:
			out.append(StringName(id))
			points -= cost
	var pool: Array = (_generator.get("zombie_pool", []) as Array) \
			+ (_generator.get("must_contain_zombie", []) as Array)
	var guard := 0
	while guard < 200:
		guard += 1
		var affordable := pool.filter(func(id): return _cost(StringName(id)) <= points)
		if affordable.is_empty():
			break
		var id := StringName(affordable.pick_random())
		out.append(id)
		points -= _cost(id)
	return out


func _cost(id: StringName) -> float:
	var def := Data.zombie(id)
	if def == null:
		return INF
	return maxf(float(def.stat(&"wave_cost", 100)), 1.0)


func _lawn_health() -> float:
	var total := 0.0
	for row in board.rows:
		for z in board.hostile_zombies_in_row(row):
			total += z.health
	return total


# --- rules ----------------------------------------------------------------

## The zone sends its own waves, forever.
func holds_waves() -> bool:
	return true


func is_met() -> bool:
	return false


func describe() -> String:
	var text := tr("Level %d") % level_number
	if wave > 0:
		text += "  " + tr("Wave %d / %d") % [wave, waves_per_level()]
	var best := Saves.best(best_key())
	if best > 0:
		text += "  " + tr("Best %d") % best
	return text


func save_state() -> Dictionary:
	return {"level": level_number, "wave": wave, "between": _between_levels,
			"timer": _timer}


func load_state(state: Dictionary) -> void:
	level_number = int(state.get("level", 1))
	wave = int(state.get("wave", 0))
	_between_levels = bool(state.get("between", false))
	_timer = float(state.get("timer", FIRST_WAVE_DELAY))
	notify_progress()
