extends LawnComponent
## The lawn itself shoots: a steady trickle of damage at whatever is closest,
## with no input from the player.
##
## This is the passive half of an Aerial Fortress style world - the base
## defends itself a little, which changes pacing without replacing plants.
##
## Config: interval (seconds), damage, targets (how many to hit per shot).

var interval: float = 2.0
var damage: float = 10.0
var targets: int = 1

var _timer: float = 0.0


func setup() -> void:
	interval = float(cfg(&"interval", 2.0))
	damage = float(cfg(&"damage", 10.0))
	targets = maxi(int(cfg(&"targets", 1)), 1)
	_timer = interval


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval

	# Nearest first, so the trickle goes where the threat is.
	var hostiles := all_hostiles()
	if hostiles.is_empty():
		return
	hostiles.sort_custom(func(a, b): return a.position.x < b.position.x)
	var hit := 0
	for z in hostiles:
		if hit >= targets:
			break
		z.take_damage(damage, self)
		hit += 1
	if hit > 0:
		Audio.play(&"lawn.turret")


func describe() -> String:
	return tr("Base fire: %.0f dmg / %.1fs") % [damage, interval]
