extends EntityComponent
## Fires forward at what is ahead and backward, twice as hard, at what has
## got behind it - split pea.
##
## Config: projectile, interval, interval_jitter, rear_count (shots per
## volley backward), plantfood_count, plantfood_count_rear.

var _front: float = 0.0
var _rear: float = 0.0
var _burst_front: int = 0
var _burst_rear: int = 0
var _burst_gap: float = 0.0


func setup() -> void:
	_front = randf() * float(cfg(&"interval", 1.35))
	_rear = _front


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _burst_front > 0 or _burst_rear > 0:
		_burst_gap -= delta
		if _burst_gap <= 0.0:
			_burst_gap = 0.04
			if _burst_front > 0:
				_burst_front -= 1
				_fire(1)
			if _burst_rear > 0:
				_burst_rear -= 1
				_fire(-1)
		return
	_front -= delta
	_rear -= delta
	if _front <= 0.0 and _has_target(1):
		_fire(1)
		_front = cfg_jittered(&"interval", &"interval_jitter", 1.35)
	if _rear <= 0.0 and _has_target(-1):
		for i in int(cfg(&"rear_count", 2)):
			_fire(-1, i * 10.0)
		_rear = cfg_jittered(&"interval", &"interval_jitter", 1.35)


func _has_target(side: int) -> bool:
	for t in host.board.plant_targets_in_row(host.row):
		if (t.position.x - host.position.x) * side > 0.0:
			return true
	return false


func _fire(side: int, offset: float = 0.0) -> void:
	var at: Vector2 = host.launch_point(side) - Vector2(side * offset, 0)
	host.board.spawn_projectile(StringName(cfg(&"projectile", &"pea")), host.row,
			at, host, side)
	host.play_art_once(&"attack")
	Audio.play_for(&"plant.shoot", host)


func on_plantfood() -> bool:
	_burst_front = int(cfg(&"plantfood_count", 60))
	_burst_rear = int(cfg(&"plantfood_count_rear", 90))
	return true
