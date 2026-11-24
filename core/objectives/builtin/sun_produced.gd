extends Objective
## Collect a total amount of sun over the level.
##
## Config: amount - the sun to reach.

var amount: int = 1000

var _collected: int = 0


func setup() -> void:
	amount = int(cfg(&"amount", 1000))


func on_sun_collected(value: int) -> void:
	_collected += value
	notify_progress()


func save_state() -> Dictionary:
	return {
		"collected": _collected,
		"failed": failed,
	}


func load_state(state: Dictionary) -> void:
	_collected = int(state.get("collected", _collected))
	failed = bool(state.get("failed", false))
	notify_progress()


func is_met() -> bool:
	return _collected >= amount


func describe() -> String:
	return tr("Sun produced: %d / %d") % [_collected, amount]
