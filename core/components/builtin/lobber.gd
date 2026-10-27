extends EntityComponent
## Lobs an arcing projectile over obstacles at anything in its lane.
##
## Config: projectile, interval, interval_jitter, projectile_plantfood.

var interval: float = 2.7
var projectile_id: StringName = &"cabbage"

var _cooldown: float = 0.0


func setup() -> void:
	interval = float(cfg(&"interval", 2.7))
	projectile_id = StringName(cfg(&"projectile", &"cabbage"))
	_cooldown = randf() * interval


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	# A lobber ignores cover, so any zombie in the lane is a valid target.
	if host.board.hostile_zombies_in_row(host.row).is_empty():
		return
	host.board.spawn_projectile(projectile_id, host.row, host.launch_point(), host)
	host.play_art_once(&"attack")
	Audio.play_for(&"plant.lob", host)
	_cooldown = cfg_jittered(&"interval", &"interval_jitter", interval)


## Plant food: rain a volley over the lane.
func on_plantfood() -> bool:
	var count := int(cfg(&"plantfood_count", 12))
	var id := StringName(cfg(&"projectile_plantfood", projectile_id))
	for i in count:
		host.board.spawn_projectile(id, host.row, host.launch_point(), host)
	return count > 0
