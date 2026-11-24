extends Minigame
## Neon Mixtape Tour's rhythm level: a phat beet stands in every row of one
## column, and zombies glide in to the music, each due at the beets on a
## beat. Tapping a beet smashes the zombie in front of it; let one slip past
## and it walks on to the house. The song is the level: it is won once every
## zombie has come and gone.
##
## Config (RhythmGameProperties): bpm, beat_start_time, beats_per_bar,
## target_column, music_name, time_offset, zombies [{type, row, arrive_time,
## time_before_arrive}]. Times are seconds into the song.

const BEET := &"phatbeet_rhythm"

## Seconds into the song, offset as the level says.
var song_time: float = 0.0
## Zombies yet to come, soonest first.
var _queue: Array = []
## Gliding zombies: [zombie, x0, xt, arrive_time, time_before_arrive]
var _gliding: Array = []
var _lead_in: float = 0.0
var _clock: float = 0.0
var _music_started: bool = false
var _leaked: bool = false


func setup() -> void:
	var column := target_column()
	for row in board.rows:
		if board.plant_at(row, column) == null:
			board.place_preset_plant(BEET, row, column)
	_queue = (cfg(&"zombies", []) as Array).duplicate()
	_queue.sort_custom(func(a, b): return _due(a) < _due(b))
	# The song starts late enough for the first zombie to glide all the way.
	var earliest := 0.0
	for z in _queue:
		earliest = minf(earliest, _due(z))
	_lead_in = -earliest


func target_column() -> int:
	return clampi(int(cfg(&"target_column", 2)), 0, board.cols - 1)


static func _due(entry: Dictionary) -> float:
	return float(entry.get("arrive_time", 0)) - float(entry.get("time_before_arrive", 2))


func tick(delta: float) -> void:
	if not started:
		return
	_clock += delta
	if not _music_started and _clock >= _lead_in:
		_music_started = true
		Audio.play_music(StringName(cfg(&"music_name", "")))
	song_time = _clock - _lead_in + float(cfg(&"time_offset", 0.0))
	while not _queue.is_empty() and song_time >= _due(_queue[0]):
		_launch(_queue.pop_front())
	var target_x: float = board.grid_to_world(0, target_column()).x
	for g in _gliding.duplicate():
		var z: Zombie = g[0]
		if not is_instance_valid(z) or z.is_dead:
			_gliding.erase(g)
			continue
		# Straight on at one pace: due at the beets on its beat, and past
		# them after if nothing stops it.
		var t: float = (song_time - g[3] + g[4]) / maxf(g[4], 0.01)
		z.position.x = lerpf(g[1], target_x, t)
		z.col = board.world_to_col(z.position.x)
		if z.position.x < board.house_x():
			_leaked = true
			_gliding.erase(g)
	notify_progress()


func _launch(entry: Dictionary) -> void:
	var row := clampi(int(entry.get("row", 0)), 0, board.rows - 1)
	var x0: float = board.spawn_x()
	var z = board.spawn_zombie_at(StringName(entry.get("type", "")), row, x0)
	if z == null:
		return
	z.movement_claimed = true
	z.peaceful = true
	_gliding.append([z, x0, 0.0, float(entry.get("arrive_time", 0)),
			float(entry.get("time_before_arrive", 2))])


## How many zombies are still to come or on the lawn.
func remaining() -> int:
	return _queue.size() + _gliding.size()


func holds_waves() -> bool:
	return true


func skips_seed_chooser() -> bool:
	return true


func drops_sky_sun() -> bool:
	return false


func allows_shovel() -> bool:
	return false


func allows_plant_food() -> bool:
	return false


func is_met() -> bool:
	return started and remaining() == 0 and not _leaked


func is_failed() -> bool:
	return _leaked


func start_word() -> String:
	return tr("MUSIC!")


func describe() -> String:
	var total := (cfg(&"zombies", []) as Array).size()
	return tr("Zombies %d / %d") % [total - remaining(), total] if total > 0 else ""


func save_state() -> Dictionary:
	return {"clock": _clock}


func load_state(state: Dictionary) -> void:
	# The song cannot pick up halfway, so a saved rhythm level starts over.
	_clock = 0.0
	notify_progress()
