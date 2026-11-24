extends Objective
## Lose no plants at all, or at most a few.
##
## Config: allowed - how many losses are tolerated (0 by default).

var allowed: int = 0

var _lost: int = 0


func setup() -> void:
	allowed = int(cfg(&"allowed", 0))


func on_plant_died(_plant: Node) -> void:
	_lost += 1
	notify_progress()
	if _lost > allowed:
		fail()


func save_state() -> Dictionary:
	return {
		"lost": _lost,
		"failed": failed,
	}


func load_state(state: Dictionary) -> void:
	_lost = int(state.get("lost", _lost))
	failed = bool(state.get("failed", false))
	notify_progress()


func is_met() -> bool:
	return _lost <= allowed


func describe() -> String:
	return tr("Plants lost: %d / %d allowed") % [_lost, allowed]
