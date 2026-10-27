extends EntityComponent
## Fires on its own clock rather than when something is in front of it, and
## can hit any lane - caulipower and friends.
##
## Config: projectile, detect_interval, cooldown_min, cooldown_max.

var projectile_id: StringName = &"pea"
var cooldown_min: float = 10.0
var cooldown_max: float = 12.0

var _timer: float = 0.0


func setup() -> void:
	projectile_id = StringName(cfg(&"projectile", &"pea"))
	cooldown_min = float(cfg(&"cooldown_min", cfg(&"detect_interval", 10.0)))
	cooldown_max = float(cfg(&"cooldown_max", cooldown_min + 2.0))
	_timer = randf_range(cooldown_min, cooldown_max)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(cooldown_min, cooldown_max)

	# Picks whichever lane has something in it, not just its own.
	var rows: Array[int] = []
	for row in host.board.rows:
		if not host.board.hostile_zombies_in_row(row).is_empty():
			rows.append(row)
	if rows.is_empty():
		return
	var row: int = rows[randi() % rows.size()]
	host.board.spawn_projectile(projectile_id, row, host.launch_point(), host)
	Audio.play_for(&"plant.shoot", host)
