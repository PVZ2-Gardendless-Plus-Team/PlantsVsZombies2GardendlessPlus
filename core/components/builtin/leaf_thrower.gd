extends EntityComponent
## Slaps zombies that come close with its leaves - nightshade. Each leaf
## thrown is gone until it regrows, and it only regrows while the plant is
## shadow powered; powered, it also hurls them the length of the lane.
##
## Config: projectile, projectile_plantfood, ammo, regrow, reach,
## powered_reach, powered_damage_scale, interval, interval_jitter,
## plantfood_volley.

var _ammo: int = 3
var _regrow: float = 0.0
var _cooldown: float = 0.0


func setup() -> void:
	_ammo = int(cfg(&"ammo", 3))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	var powered: bool = host.has_tag(&"shadow_powered")
	if _ammo < int(cfg(&"ammo", 3)) and powered:
		_regrow -= delta
		if _regrow <= 0.0:
			_ammo += 1
			_regrow = scaled(float(cfg(&"regrow", 5.0)))
	_cooldown -= delta
	if _cooldown > 0.0 or _ammo <= 0:
		return
	var reach: float = float(cfg(&"powered_reach" if powered else &"reach", 1.5)) \
			* host.board.cell_size.x
	for t in host.board.plant_targets_in_row(host.row):
		var ahead: float = t.position.x - host.position.x
		if ahead >= 0.0 and ahead <= reach:
			_throw(StringName(cfg(&"projectile", &"nightshade")),
					float(cfg(&"powered_damage_scale", 0.5)) if powered else 1.0)
			_ammo -= 1
			_cooldown = cfg_jittered(&"interval", &"interval_jitter", 2.7)
			return


func _throw(id: StringName, damage_scale: float = 1.0) -> void:
	var shot: Projectile = host.board.spawn_projectile(id, host.row, host.launch_point(), host)
	if shot != null:
		shot.damage *= damage_scale
	host.play_art_once(&"attack")
	Audio.play_for(&"plant.shoot", host)


## Plant food: every leaf back, and a volley of big ones down the lane.
func on_plantfood() -> bool:
	_ammo = int(cfg(&"ammo", 3))
	for i in int(cfg(&"plantfood_volley", 3)):
		_throw(StringName(cfg(&"projectile_plantfood", &"nightshade_pf")))
	return true
