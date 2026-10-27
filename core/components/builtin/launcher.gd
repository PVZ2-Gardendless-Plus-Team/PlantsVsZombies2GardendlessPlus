extends EntityComponent
## Tap it, then tap a square: it lobs a shot there - banana launcher, missile
## toe, bamboozle. What the shot does on landing is the projectile's own
## SplashDamage, so a banana blows up a row of three and a missile toe also
## freezes the 3x3.
##
## Config: projectile, rest (seconds to reload), ammo (shots before it is
## spent, 0 for unlimited), flight (seconds in the air), plantfood_shots.

var _rest: float = 0.0
var _ammo: int = 0
## Shots in the air: [row, x, seconds left].
var _flying: Array = []


func setup() -> void:
	_ammo = int(cfg(&"ammo", 0))
	host.set_runtime_tag(&"tap_to_fire", true)


func _process(delta: float) -> void:
	if _rest > 0.0:
		_rest -= delta
	for shot in _flying.duplicate():
		shot[2] -= delta
		if shot[2] <= 0.0:
			_flying.erase(shot)
			_land(shot[0], shot[1])


func is_loaded() -> bool:
	return _rest <= 0.0 and (int(cfg(&"ammo", 0)) <= 0 or _ammo > 0)


func on_tapped() -> bool:
	return not host.is_dead and is_loaded()


func fire_at(row: int, col: int) -> bool:
	if not is_loaded():
		return false
	_launch(row, host.board.grid_to_world(row, col).x)
	_rest = scaled(float(cfg(&"rest", 20.0)))
	if int(cfg(&"ammo", 0)) > 0:
		_ammo -= 1
	return true


func _launch(row: int, x: float) -> void:
	host.play_art_once(&"attack")
	Audio.play_for(&"plant.lob", host)
	_flying.append([row, x, float(cfg(&"flight", 1.0))])


func _land(row: int, x: float) -> void:
	if not is_instance_valid(host.board):
		return
	Audio.play(&"plant.explode", Vector2(x, 0))
	host.board.splash_at(row, x, StringName(cfg(&"projectile", &"banana")), host)


## Plant food: reloaded, and a volley on the zombies furthest up the lawn.
func on_plantfood() -> bool:
	_rest = 0.0
	if int(cfg(&"ammo", 0)) > 0:
		_ammo = int(cfg(&"ammo", 0))
	var targets: Array = host.board.all_hostile_zombies()
	targets.reverse()
	for z in targets.slice(0, int(cfg(&"plantfood_shots", 3))):
		_launch(z.row, z.position.x)
	return true
