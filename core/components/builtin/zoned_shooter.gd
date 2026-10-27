extends EntityComponent
## A shooter that changes with where it stands - red stinger. The lawn is cut
## into thirds from the house: in the nearest third it fires full-strength
## shots and takes full damage, in the middle third weaker shots and a third
## of the damage, and in the far third it does not fire at all but shrugs off
## most of what hits it.
##
## Config: projectiles (per zone, "" for none), damage_taken (per zone),
## interval, interval_jitter, plantfood_dps, plantfood_duration.

var _cooldown: float = 0.0
var _ray_left: float = 0.0


func setup() -> void:
	_cooldown = randf() * float(cfg(&"interval", 1.75))


func zone() -> int:
	return clampi(int(host.col / 3), 0, 2)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _ray_left > 0.0:
		_ray_left -= delta
		for t in host.board.plant_targets_in_row(host.row):
			if t.position.x > host.position.x:
				t.take_damage(float(cfg(&"plantfood_dps", 200.0)) * delta, host)
		return
	var shot := _projectile()
	if shot == &"":
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	for t in host.board.plant_targets_in_row(host.row):
		if t.position.x > host.position.x:
			host.board.spawn_projectile(shot, host.row, host.launch_point(), host)
			host.play_art_once(&"attack")
			Audio.play_for(&"plant.shoot", host)
			_cooldown = cfg_jittered(&"interval", &"interval_jitter", 1.75)
			return


func _projectile() -> StringName:
	var list: Array = cfg(&"projectiles", ["redstinger", "redstinger_weak", ""])
	return StringName(list[zone()]) if zone() < list.size() else &""


## Incoming damage scaled by the zone it stands in.
func absorb_damage(amount: float) -> float:
	var list: Array = cfg(&"damage_taken", [1.0, 0.3333333, 0.2])
	return amount * (float(list[zone()]) if zone() < list.size() else 1.0)


## Plant food: a ray burning down the whole lane for a while.
func on_plantfood() -> bool:
	_ray_left = float(cfg(&"plantfood_duration", 5.0))
	return true
