extends LawnComponent
## A world ability the player triggers: the base fires a cannon shot that
## damages everything in a band of the board.
##
## Deliberately an ability rather than a cheat - it has a cooldown and is
## surfaced in the HUD, so it is part of how the world plays.
##
## Config: damage, cooldown (seconds), radius (cells around the impact),
## ready_at_start (whether it can fire immediately).

var damage: float = 800.0
var cooldown: float = 30.0
var radius: float = 1.5

var _charge: float = 0.0


func setup() -> void:
	is_ability = true
	damage = float(cfg(&"damage", 800.0))
	cooldown = maxf(float(cfg(&"cooldown", 30.0)), 0.1)
	radius = float(cfg(&"radius", 1.5))
	_charge = cooldown if bool(cfg(&"ready_at_start", true)) else 0.0


func _process(delta: float) -> void:
	if _charge >= cooldown:
		return
	_charge = minf(_charge + delta, cooldown)
	if _charge >= cooldown:
		notify_state()


func can_activate() -> bool:
	return _charge >= cooldown


func activate() -> bool:
	if not can_activate():
		return false
	var target := nearest_hostile()
	if target == null:
		return false      # nothing to shoot; keep the charge

	# A band centred on the target, so it hits a cluster rather than one zombie.
	var reach: float = radius * board.cell_size.x
	for z in all_hostiles():
		if absf(z.position.x - target.position.x) <= reach:
			z.take_damage(damage, self)
	_charge = 0.0
	notify_state()
	Audio.play(&"lawn.cannon", target.position)
	return true


func save_state() -> Dictionary:
	return {"charge": _charge}


func load_state(state: Dictionary) -> void:
	_charge = clampf(float(state.get("charge", cooldown)), 0.0, cooldown)
	notify_state()


func cooldown_fraction() -> float:
	return 1.0 - clampf(_charge / cooldown, 0.0, 1.0)


func describe() -> String:
	if can_activate():
		return tr("Cannon ready")
	return tr("Cannon %d%%") % int(round((_charge / cooldown) * 100.0))
