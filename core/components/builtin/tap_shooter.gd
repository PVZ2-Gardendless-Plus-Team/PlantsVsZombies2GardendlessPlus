extends EntityComponent
## Fires only when tapped, then rests before it can fire again - the coconut
## cannon. The shot rolls down the lane and bursts on the first zombie.
##
## Config: projectile, projectile_plantfood, rest (seconds between shots).

var _rest: float = 0.0


func setup() -> void:
	host.set_runtime_tag(&"tap_to_fire", true)


func _process(delta: float) -> void:
	if _rest > 0.0:
		_rest -= delta


func is_loaded() -> bool:
	return _rest <= 0.0


func on_tapped() -> bool:
	if host.is_dead or not is_loaded():
		return false
	fire(StringName(cfg(&"projectile", &"coconut")))
	return true


func fire(projectile: StringName) -> void:
	_rest = scaled(float(cfg(&"rest", 15.0)))
	host.play_art_once(&"attack")
	Audio.play_for(&"plant.shoot", host)
	var shot: Projectile = host.board.spawn_projectile(projectile, host.row,
			host.launch_point(), host)
	var def := Data.projectile(projectile)
	if shot != null and def != null \
			and not (def.extra.get("SplashDamage", []) as Array).is_empty():
		shot.explodes = true


## Plant food: reloaded, and a giant shot at once.
func on_plantfood() -> bool:
	_rest = 0.0
	fire(StringName(cfg(&"projectile_plantfood", cfg(&"projectile", &"coconut"))))
	return true
