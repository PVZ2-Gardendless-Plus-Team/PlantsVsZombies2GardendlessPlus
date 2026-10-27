extends EntityComponent
## Rolls bulbs down its lane that glance off zombies into the next lane over
## and keep going - bowling bulb. It holds three, rolled in order and
## reloaded one at a time, and bigger bulbs hit harder.
##
## Config: projectiles (one per bulb, rolled in this order), reload, pierce,
## projectile_plantfood.

var _loaded: Array[bool] = []
var _reload: float = 0.0
var _cooldown: float = 0.0


func setup() -> void:
	for i in (cfg(&"projectiles", ["bowling0", "bowling1", "bowling2"]) as Array).size():
		_loaded.append(true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _loaded.has(false):
		_reload -= delta
		if _reload <= 0.0:
			_loaded[_loaded.find(false)] = true
			_reload = scaled(float(cfg(&"reload", 4.0)))
	_cooldown -= delta
	if _cooldown > 0.0 or not _loaded.has(true):
		return
	for t in host.board.plant_targets_in_row(host.row):
		if t.position.x > host.position.x:
			var slot := _loaded.find(true)
			_loaded[slot] = false
			_roll(StringName(cfg(&"projectiles", ["bowling0"])[slot]))
			_cooldown = scaled(0.6)
			if _reload <= 0.0:
				_reload = scaled(float(cfg(&"reload", 4.0)))
			return


func _roll(id: StringName) -> void:
	var ball: Projectile = host.board.spawn_projectile(id, host.row, host.launch_point(), host)
	if ball != null:
		ball.bounces = true
		ball.pierce = int(cfg(&"pierce", 3))
	host.play_art_once(&"attack")
	Audio.play_for(&"plant.shoot", host)


## Plant food: one huge bulb that does not stop for anything.
func on_plantfood() -> bool:
	var ball: Projectile = host.board.spawn_projectile(
			StringName(cfg(&"projectile_plantfood", &"bowling_pf")), host.row,
			host.launch_point(), host)
	if ball != null:
		ball.pierce = 999
	return true
