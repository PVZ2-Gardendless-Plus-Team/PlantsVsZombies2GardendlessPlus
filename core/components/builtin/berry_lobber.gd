extends EntityComponent
## Grows a berry through three sizes; tap it to lob the berry at the first
## zombie in its lane - strawburst. The bigger the berry, the harder it hits,
## and the two bigger ones hit the 3x3 around where they land. Then it rests
## and grows a new one.
##
## Config: grow_times (rest before the first size, then each next size),
## projectiles (per size), plantfood_damage.

## -1 while resting, then 0, 1, 2 as the berry grows.
var stage: int = -1
var _grow: float = 0.0


func setup() -> void:
	host.set_runtime_tag(&"tap_to_fire", true)
	_grow = _grow_time(0)


func _grow_time(index: int) -> float:
	var times: Array = cfg(&"grow_times", [7.5, 10.0, 15.0])
	return scaled(float(times[index])) if index < times.size() else INF


func _process(delta: float) -> void:
	if host.is_dead or stage >= 2:
		return
	_grow -= delta
	if _grow > 0.0:
		return
	stage += 1
	_grow = _grow_time(stage + 1)


func on_tapped() -> bool:
	if host.is_dead or stage < 0:
		return false
	var target: Character = null
	for t in host.board.plant_targets_in_row(host.row):
		if t.position.x > host.position.x:
			target = t
			break
	if target == null:
		return false
	var shots: Array = cfg(&"projectiles", ["strawburst0", "strawburst1", "strawburst2"])
	host.play_art_once(&"attack")
	Audio.play_for(&"plant.lob", host)
	host.board.splash_at(host.row, target.position.x, StringName(shots[stage]), host)
	stage = -1
	_grow = _grow_time(0)
	return true


## Plant food: the biggest berry at once.
func on_plantfood() -> bool:
	if stage >= 2:
		return false
	stage = 2
	return true
