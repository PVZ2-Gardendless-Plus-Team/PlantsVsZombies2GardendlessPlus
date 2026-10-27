extends EntityComponent
## Fires a projectile down the lane whenever a zombie is ahead.
##
## Config: projectile, interval, interval_jitter, projectile_plantfood,
## plantfood_count, and how the shot flies - pierce, returns (a boomerang),
## bounces, knockback_chance, knockback_distance. scared_radius makes it a
## scaredy-shroom: it will not fire, and hides, while a zombie is within that
## many squares in its own or a neighbouring lane.

var interval: float = 1.5
var projectile_id: StringName = &"pea"

## Event names a rig may use to say "the shot leaves now".
const SHOOT_EVENTS: Array[StringName] = [&"Shoot", &"shoot", &"fire"]

var _cooldown: float = 0.0
var _pending: bool = false
var _rig_announces: int = -1
var _burst_remaining: int = 0
var _burst_gap: float = 0.0
var _burst_projectile: StringName = &"pea"


func setup() -> void:
	interval = float(cfg(&"interval", 1.5))
	projectile_id = StringName(cfg(&"projectile", &"pea"))
	# Stagger identical plants so they do not fire in lockstep.
	_cooldown = randf() * interval


func _process(delta: float) -> void:
	if host.is_dead:
		return

	# A plant food burst takes priority over the normal firing rhythm.
	if _burst_remaining > 0:
		_burst_gap -= delta
		if _burst_gap <= 0.0:
			_shape(host.board.spawn_projectile(_burst_projectile, host.row,
					host.launch_point(), host))
			_burst_remaining -= 1
			_burst_gap = 0.04
		return

	if _scared():
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if not _has_target():
		return
	_fire()
	_cooldown = cfg_jittered(&"interval", &"interval_jitter", interval)


## A scaredy-shroom ducks while anything is close, and does not shoot.
func _scared() -> bool:
	var radius := float(cfg(&"scared_radius", 0.0))
	if radius <= 0.0:
		return false
	var close: bool = not host.board.hostile_zombies_near(host.row, host.position.x,
			1, radius).is_empty()
	host.set_runtime_tag(&"hiding", close)
	return close


func _has_target() -> bool:
	var board = host.board
	if board == null:
		return false
	# Gravestones count: a peashooter facing one keeps firing until it breaks.
	for z in board.plant_targets_in_row(host.row):
		if z.position.x > host.position.x:
			return true
	return false


## Firing is the animation's call when the rig has one to make. The
## peashooter's Shoot animation carries a "Shoot" event fifteen frames in,
## which is the frame the pea leaves its mouth - spawning on the frame the
## animation *started* is what made the shot look detached from the plant.
## A rig without the event, or a plant without art, fires immediately.
func _fire() -> void:
	if host.play_art_once(&"attack") and _await_event():
		return
	_launch()


func _await_event() -> bool:
	var art: Armature = host.art
	if art == null or not art.has_animation(art.playing):
		return false
	if not art.event.is_connected(_on_art_event):
		art.event.connect(_on_art_event)
	_pending = true
	return _has_shoot_event(art)


## Whether the current animation will actually announce a shot. Checked once
## per rig, because a plant that waits for an event that never comes never
## fires at all.
func _has_shoot_event(art: Armature) -> bool:
	if _rig_announces == -1:
		_rig_announces = 1 if art.announces(art.playing, SHOOT_EVENTS) else 0
	return _rig_announces == 1


func _on_art_event(name: StringName) -> void:
	if not _pending or not SHOOT_EVENTS.has(name):
		return
	_pending = false
	_launch()


func _launch() -> void:
	_shape(host.board.spawn_projectile(projectile_id, host.row, host.launch_point(), host))
	Audio.play_for(&"plant.shoot", host)


## Gives a shot whatever flight this plant's shots have.
func _shape(shot: Projectile) -> void:
	if shot == null:
		return
	shot.pierce = int(cfg(&"pierce", 1))
	shot.returns = bool(cfg(&"returns", false))
	shot.bounces = bool(cfg(&"bounces", false))
	shot.knockback_chance = float(cfg(&"knockback_chance", 0.0))
	shot.knockback_distance = float(cfg(&"knockback_distance", 0.0))


## Plant food: unload a burst of shots down the lane.
func on_plantfood() -> bool:
	var count := int(cfg(&"plantfood_count", 24))
	var id := StringName(cfg(&"projectile_plantfood", projectile_id))
	_burst_remaining = count
	_burst_projectile = id
	return count > 0
