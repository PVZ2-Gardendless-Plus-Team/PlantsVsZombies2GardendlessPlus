extends LawnComponent
## The house has hit points instead of lawn mowers.
##
## This is how Sky works: nothing saves a lane, but a zombie getting through
## chips the base rather than ending the run outright, and the level is lost
## only when that health is gone. Because it is a lawn component, the world
## declares it in data and the board needs no special case.
##
## Config: max_health, damage_per_zombie (fixed cost), use_zombie_weight
## (scale the cost by how heavy the zombie is instead).

signal health_changed(current: float, maximum: float)
signal house_destroyed

var max_health: float = 1000.0
var damage_per_zombie: float = 100.0
var use_zombie_weight: bool = false

var health: float = 1000.0


func setup() -> void:
	max_health = maxf(float(cfg(&"max_health", 1000.0)), 1.0)
	damage_per_zombie = float(cfg(&"damage_per_zombie", 100.0))
	use_zombie_weight = bool(cfg(&"use_zombie_weight", false))
	health = max_health
	notify_state()


## Consumes the zombie and bills the house for it.
func handle_zombie_at_house(zombie: Node) -> bool:
	var cost := damage_per_zombie
	if use_zombie_weight and zombie.def != null:
		# Heavier zombies hurt more, so a gargantuar is not one chip.
		cost = maxf(float(zombie.def.stat(&"weight", 1000.0)) * 0.1, 1.0)

	health = maxf(0.0, health - cost)
	health_changed.emit(health, max_health)
	notify_state()
	Audio.play(&"lawn.house.hit", zombie.position)

	# The zombie is spent either way; it does not stand on the threshold.
	zombie.die()

	if health <= 0.0:
		house_destroyed.emit()
		board.level_lost.emit()
	return true


func save_state() -> Dictionary:
	return {"health": health}


func load_state(state: Dictionary) -> void:
	health = clampf(float(state.get("health", max_health)), 0.0, max_health)
	health_changed.emit(health, max_health)
	notify_state()


func health_fraction() -> float:
	return clampf(health / max_health, 0.0, 1.0)


func describe() -> String:
	return tr("Base integrity: %d%%") % int(round(health_fraction() * 100.0))
