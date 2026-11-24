extends Objective
## Spend no more than a set amount of sun over the level.
##
## Config: max - the sun that may be spent.

var maximum: int = 1000

var _spent: int = 0


func setup() -> void:
	maximum = int(cfg(&"max", 1000))
	board.sun_spent.connect(_on_sun_spent)


func _on_sun_spent(amount: int) -> void:
	_spent += amount
	if _spent > maximum:
		fail()
	notify_progress()


func save_state() -> Dictionary:
	return {"spent": _spent, "failed": failed}


func load_state(state: Dictionary) -> void:
	_spent = int(state.get("spent", _spent))
	failed = bool(state.get("failed", false))
	notify_progress()


func describe() -> String:
	return tr("Sun spent: %d / %d") % [_spent, maximum]
